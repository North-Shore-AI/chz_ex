defmodule ChzEx.Blueprint do
  @moduledoc """
  Blueprint for lazy configuration construction.
  """

  import Kernel, except: [apply: 2, apply: 3]

  alias ChzEx.{ArgumentMap, Cast, Error, Lazy, Parser, Schema}
  alias ChzEx.Blueprint.{Castable, Reference}
  alias ChzEx.Factory.Standard, as: StandardFactory

  defstruct [
    :target,
    :entrypoint_repr,
    arg_map: %ArgumentMap{}
  ]

  @type t :: %__MODULE__{
          target: module(),
          entrypoint_repr: String.t(),
          arg_map: ArgumentMap.t()
        }

  @doc """
  Create a new blueprint for a target module.
  """
  def new(target) when is_atom(target) do
    if Schema.chz?(target) do
      %__MODULE__{
        target: target,
        entrypoint_repr: inspect(target),
        arg_map: ArgumentMap.new()
      }
    else
      raise ArgumentError, "#{inspect(target)} is not a ChzEx schema"
    end
  end

  @doc """
  Apply arguments to the blueprint.
  """
  def apply(%__MODULE__{} = bp, args, opts \\ []) when is_map(args) do
    layer_name = Keyword.get(opts, :layer_name)
    subpath = Keyword.get(opts, :subpath)
    strict = Keyword.get(opts, :strict, false)

    args = apply_subpath(args, subpath)
    bp = %{bp | arg_map: ArgumentMap.add_layer(bp.arg_map, args, layer_name)}

    maybe_check_strict(bp, strict)
  end

  defp apply_subpath(args, nil), do: args

  defp apply_subpath(args, subpath) do
    args
    |> Enum.map(fn {k, v} -> {join_path(subpath, k), v} end)
    |> Map.new()
  end

  defp maybe_check_strict(bp, false), do: bp

  defp maybe_check_strict(bp, true) do
    with {:ok, state} <- make_lazy(bp),
         :ok <- check_extraneous(bp.arg_map, state) do
      bp
    else
      {:error, %Error{} = err} -> raise err
    end
  end

  @doc """
  Apply arguments from argv.
  """
  def apply_from_argv(%__MODULE__{} = bp, argv, opts \\ []) do
    allow_hyphens = Keyword.get(opts, :allow_hyphens, false)
    strict = Keyword.get(opts, :strict, false)

    case Parser.parse(argv, allow_hyphens: allow_hyphens) do
      {:ok, args} ->
        help = Parser.help_requested?(args)
        args = Map.delete(args, :__help__)

        try do
          bp =
            apply(bp, args,
              layer_name: Keyword.get(opts, :layer_name, "command line"),
              strict: strict
            )

          if help do
            raise ChzEx.HelpError, message: get_help(bp)
          end

          {:ok, bp}
        rescue
          err in [Error] -> {:error, err}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Construct the final value.
  """
  def make(%__MODULE__{} = bp) do
    with {:ok, state} <- make_lazy(bp),
         :ok <- check_extraneous(bp.arg_map, state),
         :ok <- Lazy.check_reference_targets(state.value_mapping, Map.keys(state.value_mapping)) do
      if state.missing_params != [] do
        {:error, %Error{type: :missing_required, path: hd(state.missing_params)}}
      else
        try do
          struct = Lazy.evaluate(state.value_mapping)

          with {:ok, validated} <- validate_struct(struct) do
            {:ok, apply_mungers(validated)}
          end
        rescue
          err in [Error] ->
            {:error, err}

          e in RuntimeError ->
            message = Exception.message(e)
            cycle = String.replace_prefix(message, "Detected cyclic reference: ", "")
            {:error, %Error{type: :cycle, message: cycle}}
        end
      end
    else
      {:error, %Error{} = err} -> {:error, err}
      {:error, _} = err -> err
    end
  end

  @doc """
  Make from argv, suitable for CLI entrypoints.
  """
  def make_from_argv(%__MODULE__{} = bp, argv \\ nil, opts \\ []) do
    argv = argv || System.argv()

    case apply_from_argv(bp, argv, opts) do
      {:ok, bp} -> make(bp)
      {:error, _} = err -> err
    end
  end

  @doc """
  Generate help text.
  """
  def get_help(%__MODULE__{} = bp, _opts \\ []) do
    {:ok, state} = make_lazy(bp)

    # Build warning for missing required params
    warning =
      if state.missing_params != [] do
        missing = state.missing_params |> Enum.sort() |> Enum.join(", ")
        "WARNING: Missing required arguments for parameter(s): #{missing}\n\n"
      else
        ""
      end

    header = "Entry point: #{bp.entrypoint_repr}\n\n"

    params =
      state.all_params
      |> Enum.sort_by(fn {path, _field} -> path end)
      |> Enum.map_join("\n", fn {path, field} ->
        found = ArgumentMap.get_kv(bp.arg_map, path)
        raw_value = if found, do: found.value, else: nil
        value_str = format_param_value(raw_value, field)
        type_str = type_to_string(field.type)
        doc = field.doc || ""
        "#{path}  #{type_str}  #{value_str}  #{doc}"
      end)

    warning <> header <> "Arguments:\n" <> params
  end

  defp format_param_value(nil, field) do
    if ChzEx.Field.has_default?(field) do
      inspect(ChzEx.Field.get_default(field))
    else
      "-"
    end
  end

  defp format_param_value(%Reference{} = ref, _field), do: "@=" <> ref.ref
  defp format_param_value(%Castable{value: val}, _field), do: inspect(val)
  defp format_param_value(%ChzEx.Blueprint.Computed{}, _field), do: "f(...)"
  defp format_param_value(other, _field), do: inspect(other)

  defp type_to_string(type), do: ChzEx.Type.type_repr(type)

  defp make_lazy(%__MODULE__{} = bp) do
    arg_map = ArgumentMap.consolidate(bp.arg_map)

    state = %{
      arg_map: arg_map,
      all_params: %{},
      used_args: MapSet.new(),
      missing_params: [],
      value_mapping: %{}
    }

    state = construct_schema(bp.target, "", state)
    {:ok, state}
  rescue
    err in [Error] -> {:error, err}
  end

  defp construct_schema(module, path, state) do
    fields = module.__chz_fields__()

    state =
      Enum.reduce(fields, state, fn {name, field}, st ->
        param_path = join_path(path, Atom.to_string(name))
        construct_field(field, param_path, st)
      end)

    kwargs =
      Enum.map(fields, fn {name, _field} ->
        param_path = join_path(path, Atom.to_string(name))
        {name, %Lazy.ParamRef{ref: param_path}}
      end)
      |> Map.new()

    thunk = %Lazy.Thunk{
      fn: fn resolved_kwargs -> struct!(module, resolved_kwargs) end,
      kwargs: kwargs
    }

    put_value(state, path, thunk)
  end

  defp construct_field(field, path, state) do
    state = record_param(state, path, field)
    found = ArgumentMap.get_kv(state.arg_map, path)
    subpaths = ArgumentMap.subpaths(state.arg_map, path, strict: true)

    case {field.embed_type, field.type} do
      {:one, _} ->
        construct_embed_one(field, path, found, subpaths, state)

      {:many, _} ->
        construct_embed_many(field, path, found, subpaths, state)

      {_, {:map_schema, schema_fields}} ->
        construct_map_schema(field, path, schema_fields, found, subpaths, state)

      {_, {:tuple, types}} when is_list(types) ->
        construct_hetero_tuple(field, path, types, found, subpaths, state)

      _ ->
        construct_scalar(field, path, found, state)
    end
  end

  defp construct_scalar(field, path, found, state) do
    cond do
      found != nil ->
        construct_scalar_from_found(field, path, found, state)

      ChzEx.Field.has_default?(field) ->
        put_value(state, path, %Lazy.Value{value: ChzEx.Field.get_default(field)})

      field.munger != nil ->
        put_value(state, path, %Lazy.Value{value: nil})

      true ->
        state = mark_missing(state, path)
        put_value(state, path, %Lazy.Value{value: nil})
    end
  end

  defp construct_scalar_from_found(field, path, found, state) do
    state = mark_used(state, found)
    {evaluatable, state} = resolve_scalar_value(field, path, found.value, state)
    put_value(state, path, evaluatable)
  end

  defp resolve_scalar_value(field, path, %Reference{ref: ref}, state) when ref == path do
    if ChzEx.Field.has_default?(field) do
      {%Lazy.Value{value: ChzEx.Field.get_default(field)}, state}
    else
      {%Lazy.Value{value: nil}, mark_missing(state, path)}
    end
  end

  defp resolve_scalar_value(_field, _path, %Reference{ref: ref}, state) do
    {%Lazy.ParamRef{ref: ref}, state}
  end

  defp resolve_scalar_value(field, path, %Castable{value: str}, state) do
    {cast_value(field, path, str), state}
  end

  defp resolve_scalar_value(_field, _path, %ChzEx.Blueprint.Computed{} = computed, state) do
    kwargs = build_computed_kwargs(computed.sources)
    {%Lazy.Thunk{fn: computed.compute, kwargs: kwargs}, state}
  end

  defp resolve_scalar_value(_field, _path, value, state) do
    {%Lazy.Value{value: value}, state}
  end

  defp build_computed_kwargs(sources) do
    Map.new(sources, fn {key, %Reference{ref: ref}} ->
      key = if is_binary(key), do: String.to_atom(key), else: key
      {key, %Lazy.ParamRef{ref: ref}}
    end)
  end

  # Map schema construction - expands map fields as individual parameters
  defp construct_map_schema(_field, path, schema_fields, found, _subpaths, state) do
    # If a complete map value was provided directly, use it
    if found != nil and not special_arg?(found.value) do
      state = mark_used(state, found)
      put_value(state, path, %Lazy.Value{value: found.value})
    else
      expand_map_schema_fields(path, schema_fields, state)
    end
  end

  defp expand_map_schema_fields(path, schema_fields, state) do
    {kwargs, state} =
      Enum.reduce(schema_fields, {%{}, state}, fn {name, field_spec}, {acc, st} ->
        process_schema_field_entry(path, name, field_spec, acc, st)
      end)

    thunk = %Lazy.Thunk{
      fn: fn resolved -> Map.new(resolved) end,
      kwargs: kwargs
    }

    put_value(state, path, thunk)
  end

  defp process_schema_field_entry(path, name, field_spec, acc, st) do
    {type, required} = ChzEx.Type.normalize_map_schema_field(field_spec)
    param_path = join_path(path, Atom.to_string(name))

    virtual_field = %ChzEx.Field{
      name: name,
      type: type,
      raw_type: type,
      default: nil,
      default_factory: nil,
      doc: nil,
      validators: [],
      munger: nil,
      meta_factory: nil,
      polymorphic: false,
      blueprint_cast: nil,
      blueprint_unspecified: nil,
      namespace: nil,
      embed_type: nil,
      repr: true,
      metadata: %{}
    }

    st = record_param(st, param_path, virtual_field)
    found_field = ArgumentMap.get_kv(st.arg_map, param_path)

    st = process_map_schema_field(virtual_field, param_path, found_field, required, st)
    include_in_kwargs? = found_field != nil or required == :required

    if include_in_kwargs? do
      {Map.put(acc, name, %Lazy.ParamRef{ref: param_path}), st}
    else
      {acc, st}
    end
  end

  # Heterogeneous tuple construction - each position has a specific type
  defp construct_hetero_tuple(_field, path, types, found, _subpaths, state) do
    # If a complete tuple value was provided directly, use it
    if found != nil and not special_arg?(found.value) do
      state = mark_used(state, found)
      put_value(state, path, %Lazy.Value{value: found.value})
    else
      # Expand each position as a separate parameter
      indices = 0..(length(types) - 1)

      {kwargs, state} =
        Enum.zip(indices, types)
        |> Enum.reduce({%{}, state}, fn {idx, type}, {acc, st} ->
          param_path = join_path(path, Integer.to_string(idx))

          # Create a virtual field for this tuple position
          virtual_field = %ChzEx.Field{
            name: String.to_atom("elem_#{idx}"),
            type: type,
            raw_type: type,
            default: nil,
            default_factory: nil,
            doc: nil,
            validators: [],
            munger: nil,
            meta_factory: nil,
            polymorphic: false,
            blueprint_cast: nil,
            blueprint_unspecified: nil,
            namespace: nil,
            embed_type: nil,
            repr: true,
            metadata: %{}
          }

          st = record_param(st, param_path, virtual_field)
          found_elem = ArgumentMap.get_kv(st.arg_map, param_path)

          st = process_tuple_element(virtual_field, param_path, found_elem, st)
          {Map.put(acc, idx, %Lazy.ParamRef{ref: param_path}), st}
        end)

      # Build a thunk that constructs the final tuple
      thunk = %Lazy.Thunk{
        fn: fn resolved ->
          indices
          |> Enum.map(&Map.fetch!(resolved, &1))
          |> List.to_tuple()
        end,
        kwargs: kwargs
      }

      put_value(state, path, thunk)
    end
  end

  # Helper for map schema field processing - reduces nesting depth
  defp process_map_schema_field(virtual_field, param_path, found_field, required, st) do
    cond do
      found_field != nil ->
        st = mark_used(st, found_field)
        {evaluatable, st} = resolve_scalar_value(virtual_field, param_path, found_field.value, st)
        put_value(st, param_path, evaluatable)

      required == :optional ->
        st

      true ->
        st = mark_missing(st, param_path)
        put_value(st, param_path, %Lazy.Value{value: nil})
    end
  end

  # Helper for tuple element processing - reduces nesting depth
  defp process_tuple_element(virtual_field, param_path, found_elem, st) do
    if found_elem != nil do
      st = mark_used(st, found_elem)
      {evaluatable, st} = resolve_scalar_value(virtual_field, param_path, found_elem.value, st)
      put_value(st, param_path, evaluatable)
    else
      st = mark_missing(st, param_path)
      put_value(st, param_path, %Lazy.Value{value: nil})
    end
  end

  defp construct_embed_one(field, path, found, subpaths, state) do
    if field.polymorphic do
      construct_polymorphic(field, path, found, subpaths, state)
    else
      construct_embed_one_standard(field, path, found, subpaths, state)
    end
  end

  defp construct_embed_one_standard(field, path, found, subpaths, state) do
    subpaths_present = subpaths != [] or nested_args_present?(field.type, path, state.arg_map)

    cond do
      found != nil and subpaths == [] and not special_arg?(found.value) ->
        state = mark_used(state, found)
        put_value(state, path, %Lazy.Value{value: found.value})

      subpaths_present ->
        construct_schema(field.type, path, state)

      has_all_defaults?(field.type) ->
        construct_schema(field.type, path, state)

      ChzEx.Field.has_default?(field) ->
        put_value(state, path, %Lazy.Value{value: ChzEx.Field.get_default(field)})

      true ->
        state = mark_missing(state, path)
        put_value(state, path, %Lazy.Value{value: nil})
    end
  end

  defp construct_polymorphic(field, path, found, subpaths, state) do
    subpaths_present = subpaths != [] or nested_args_present?(field.type, path, state.arg_map)

    factory =
      resolve_factory(field, found, subpaths_present)

    case factory do
      {:ok, factory_module} ->
        state = if found != nil, do: mark_used(state, found), else: state
        construct_schema(factory_module, path, state)

      {:error, reason} ->
        raise %Error{type: :invalid_value, path: path, message: reason}
    end
  end

  defp resolve_factory(field, found, subpaths_present) do
    factory = meta_factory_for_field(field)
    factory_module = factory.__struct__

    cond do
      found != nil ->
        case found.value do
          %Castable{value: value} -> factory_module.from_string(factory, value)
          module when is_atom(module) -> {:ok, module}
          _ -> {:error, "Invalid factory for #{path_label(field)}"}
        end

      subpaths_present ->
        default = factory_module.unspecified_factory(factory)

        if default,
          do: {:ok, default},
          else: {:error, "No default factory for #{path_label(field)}"}

      true ->
        default = factory_module.unspecified_factory(factory)

        if default,
          do: {:ok, default},
          else: {:error, "No default factory for #{path_label(field)}"}
    end
  end

  @doc false
  def meta_factory_for_field(%ChzEx.Field{} = field) do
    case field.meta_factory do
      nil ->
        StandardFactory.new(
          annotation: field.type,
          unspecified: field.blueprint_unspecified,
          namespace: field.namespace
        )

      %_{} = meta_factory ->
        meta_factory

      module when is_atom(module) ->
        if function_exported?(module, :new, 1) do
          module.new(
            annotation: field.type,
            unspecified: field.blueprint_unspecified,
            namespace: field.namespace
          )
        else
          raise %Error{
            type: :invalid_value,
            path: Atom.to_string(field.name),
            message: "Invalid meta_factory"
          }
        end
    end
  end

  defp path_label(field) do
    Atom.to_string(field.name)
  end

  defp construct_embed_many(field, path, found, subpaths, state) do
    if field.polymorphic do
      construct_embed_many_polymorphic(field, path, found, subpaths, state)
    else
      cond do
        usable_found?(found, subpaths) ->
          state = mark_used(state, found)
          put_value(state, path, %Lazy.Value{value: found.value})

        subpaths != [] ->
          {thunk, state} = build_embed_many_from_subpaths(field.type, path, subpaths, state)
          put_value(state, path, thunk)

        ChzEx.Field.has_default?(field) ->
          put_value(state, path, %Lazy.Value{value: ChzEx.Field.get_default(field)})

        true ->
          state = mark_missing(state, path)
          put_value(state, path, %Lazy.Value{value: []})
      end
    end
  end

  defp construct_embed_many_polymorphic(field, path, found, subpaths, state) do
    cond do
      usable_found?(found, subpaths) ->
        state = mark_used(state, found)
        put_value(state, path, %Lazy.Value{value: found.value})

      subpaths != [] ->
        {thunk, state} = build_polymorphic_many(field, path, subpaths, state)
        put_value(state, path, thunk)

      ChzEx.Field.has_default?(field) ->
        put_value(state, path, %Lazy.Value{value: ChzEx.Field.get_default(field)})

      true ->
        state = mark_missing(state, path)
        put_value(state, path, %Lazy.Value{value: []})
    end
  end

  defp usable_found?(found, subpaths) do
    found != nil and subpaths == [] and not special_arg?(found.value)
  end

  defp build_embed_many_from_subpaths(type, path, subpaths, state) do
    indices = extract_indices(subpaths)

    {kwargs, state} =
      Enum.reduce(indices, {%{}, state}, fn index, {acc, st} ->
        {param_ref, st} = build_embed_many_index(type, path, index, st)
        {Map.put(acc, index, param_ref), st}
      end)

    {build_index_thunk(indices, kwargs), state}
  end

  defp build_embed_many_index(type, path, index, state) do
    index_path = join_path(path, index)
    state = construct_schema(type, index_path, state)
    {%Lazy.ParamRef{ref: index_path}, state}
  end

  defp build_polymorphic_many(field, path, subpaths, state) do
    indices = extract_indices(subpaths)

    {kwargs, state} =
      Enum.reduce(indices, {%{}, state}, fn index, {acc, st} ->
        {param_ref, st} = build_polymorphic_index(field, path, index, st)
        {Map.put(acc, index, param_ref), st}
      end)

    {build_index_thunk(indices, kwargs), state}
  end

  defp build_polymorphic_index(field, path, index, state) do
    index_path = join_path(path, index)
    found_index = ArgumentMap.get_kv(state.arg_map, index_path)

    subpaths_present =
      ArgumentMap.subpaths(state.arg_map, index_path, strict: true) != [] or
        nested_args_present?(field.type, index_path, state.arg_map)

    case resolve_factory(field, found_index, subpaths_present) do
      {:ok, factory_module} ->
        state = if found_index != nil, do: mark_used(state, found_index), else: state
        state = construct_schema(factory_module, index_path, state)
        {%Lazy.ParamRef{ref: index_path}, state}

      {:error, reason} ->
        raise %Error{type: :invalid_value, path: index_path, message: reason}
    end
  end

  defp build_index_thunk(indices, kwargs) do
    %Lazy.Thunk{
      fn: fn resolved ->
        Enum.map(indices, fn index -> Map.fetch!(resolved, index) end)
      end,
      kwargs: kwargs
    }
  end

  defp extract_indices(subpaths) do
    subpaths
    |> Enum.map(&String.split(&1, "."))
    |> Enum.map(&List.first/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp cast_value(field, path, str) do
    case Cast.try_cast(str, field.type) do
      {:ok, value} ->
        %Lazy.Value{value: value}

      {:error, reason} ->
        raise %Error{type: :cast_error, path: path, message: reason}
    end
  end

  defp special_arg?(%Castable{}), do: true
  defp special_arg?(%Reference{}), do: true
  defp special_arg?(_), do: false

  defp has_all_defaults?(module) when is_atom(module) do
    if Schema.chz?(module) do
      module.__chz_fields__()
      |> Enum.all?(fn {_name, field} -> not ChzEx.Field.required?(field) end)
    else
      false
    end
  end

  defp nested_args_present?(module, path, arg_map) do
    if Schema.chz?(module) do
      module
      |> collect_param_paths(path)
      |> Enum.any?(fn param_path -> ArgumentMap.get_kv(arg_map, param_path) != nil end)
    else
      false
    end
  end

  defp collect_param_paths(module, prefix) do
    module.__chz_fields__()
    |> Enum.flat_map(fn {name, field} ->
      path = join_path(prefix, Atom.to_string(name))

      nested =
        if field.embed_type == :one and Schema.chz?(field.type) do
          collect_param_paths(field.type, path)
        else
          []
        end

      [path | nested]
    end)
  end

  defp record_param(state, path, field) do
    %{state | all_params: Map.put(state.all_params, path, field)}
  end

  defp put_value(state, path, evaluatable) do
    %{state | value_mapping: Map.put(state.value_mapping, path, evaluatable)}
  end

  defp mark_used(state, found) do
    %{state | used_args: MapSet.put(state.used_args, {found.key, found.layer_index})}
  end

  defp mark_missing(state, path) do
    %{state | missing_params: [path | state.missing_params]}
  end

  defp join_path("", child), do: child

  defp join_path(parent, child) do
    if String.starts_with?(child, ".") or child == "" do
      parent <> child
    else
      parent <> "." <> child
    end
  end

  defp check_extraneous(arg_map, state) do
    param_paths = Map.keys(state.all_params)

    arg_map.layers
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {layer, idx}, :ok ->
      check_layer_extraneous(layer, idx, state.used_args, param_paths)
    end)
  end

  defp check_layer_extraneous(layer, idx, used_args, param_paths) do
    result =
      Enum.reduce_while(layer.args, :ok, fn {key, _value}, :ok ->
        check_arg_extraneous(key, idx, used_args, param_paths)
      end)

    case result do
      :ok -> {:cont, :ok}
      {:error, _} = err -> {:halt, err}
    end
  end

  defp check_arg_extraneous(key, idx, used_args, param_paths) do
    cond do
      MapSet.member?(used_args, {key, idx}) -> {:cont, :ok}
      not extraneous_key?(key, param_paths) -> {:cont, :ok}
      true -> {:halt, {:error, extraneous_error(key, param_paths)}}
    end
  end

  defp extraneous_error(key, param_paths) do
    suggestions = suggestions_for(key, param_paths)
    message = extraneous_message(key, suggestions, param_paths)

    %Error{
      type: :extraneous,
      path: key,
      suggestions: suggestions,
      message: message
    }
  end

  defp extraneous_message(key, suggestions, param_paths) do
    base = "Unknown argument: #{key}"
    ancestor = closest_valid_ancestor(key, param_paths)

    hints =
      []
      |> add_hint(suggestions != [], "Did you mean: #{Enum.join(suggestions, ", ")}?")
      |> add_hint(ancestor != nil, "Closest valid ancestor: #{ancestor}")
      |> add_hint(String.starts_with?(key, "-"), "Did you mean to use allow_hyphens: true?")

    if hints == [] do
      base
    else
      Enum.join([base | hints], "\n")
    end
  end

  defp extraneous_key?(key, param_paths) do
    if String.contains?(key, "...") do
      regex = ChzEx.Wildcard.to_regex(key)
      not Enum.any?(param_paths, &Regex.match?(regex, &1))
    else
      key not in param_paths
    end
  end

  defp suggestions_for(key, param_paths) do
    param_paths
    |> Enum.map(fn path -> {path, ChzEx.Wildcard.approximate(key, path)} end)
    |> Enum.filter(fn {_path, {score, _}} -> score > 0.1 end)
    |> Enum.sort_by(fn {_path, {score, _}} -> -score end)
    |> Enum.take(3)
    |> Enum.map(fn {_path, {_score, suggestion}} -> suggestion end)
  end

  defp closest_valid_ancestor(key, param_paths) do
    parts = String.split(key, ".", trim: true)

    if length(parts) < 2, do: nil, else: find_ancestor(parts, param_paths)
  end

  defp find_ancestor(parts, param_paths) do
    param_set = MapSet.new(param_paths)

    (length(parts) - 1)..1
    |> Enum.find_value(fn idx ->
      parent = parts |> Enum.take(idx) |> Enum.join(".")
      if MapSet.member?(param_set, parent), do: parent, else: nil
    end)
  end

  defp add_hint(hints, true, message), do: hints ++ [message]
  defp add_hint(hints, false, _message), do: hints

  defp validate_struct(struct) do
    module = struct.__struct__

    params = ChzEx.asdict(struct)
    changeset = module.changeset(struct(module), params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, validated} ->
        polymorphic_fields =
          module.__chz_fields__()
          |> Enum.filter(fn {_name, field} -> field.polymorphic end)
          |> Enum.map(fn {name, _field} -> name end)

        validated =
          Enum.reduce(polymorphic_fields, validated, fn name, acc ->
            Map.put(acc, name, Map.get(struct, name))
          end)

        validate_nested(validated)

      {:error, changeset} ->
        {field, {msg, opts}} = hd(changeset.errors)
        message = format_error(msg, opts)
        {:error, %Error{type: :validation_error, path: Atom.to_string(field), message: message}}
    end
  end

  defp validate_nested(struct) do
    fields = struct.__struct__.__chz_fields__()

    Enum.reduce_while(fields, {:ok, struct}, fn {name, _field}, {:ok, acc} ->
      value = Map.get(acc, name)

      case validate_value(value) do
        {:ok, new_value} ->
          {:cont, {:ok, Map.put(acc, name, new_value)}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp validate_value(value) when is_struct(value) do
    if Schema.chz?(value), do: validate_struct(value), else: {:ok, value}
  end

  defp validate_value(value) when is_list(value), do: validate_list(value)
  defp validate_value(value), do: {:ok, value}

  defp validate_list(list) do
    result =
      Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
        case validate_value(item) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case result do
      {:ok, validated_list} -> {:ok, Enum.reverse(validated_list)}
      {:error, _} = err -> err
    end
  end

  defp format_error(message, opts) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      atom_key =
        try do
          String.to_existing_atom(key)
        rescue
          ArgumentError -> nil
        end

      opts
      |> Keyword.get(atom_key, key)
      |> to_string()
    end)
  end

  defp apply_mungers(struct) do
    fields = struct.__struct__.__chz_fields__()

    Enum.reduce(fields, struct, fn {name, field}, acc ->
      value = Map.get(acc, name) |> apply_mungers_to_value()
      acc = Map.put(acc, name, value)

      case field.munger do
        nil -> acc
        munger -> Map.put(acc, name, munger.(value, acc))
      end
    end)
  end

  defp apply_mungers_to_value(value) do
    cond do
      Schema.chz?(value) -> apply_mungers(value)
      is_list(value) -> Enum.map(value, &apply_mungers_to_value/1)
      true -> value
    end
  end
end
