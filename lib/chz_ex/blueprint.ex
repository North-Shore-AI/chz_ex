defmodule ChzEx.Blueprint do
  @moduledoc """
  Blueprint for lazy configuration construction.
  """

  import Kernel, except: [apply: 2, apply: 3]

  alias ChzEx.{ArgumentMap, Cast, Error, Lazy, Parser, Schema}
  alias ChzEx.Blueprint.{Castable, Reference}

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
    if Schema.is_chz?(target) do
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

    args =
      if subpath do
        args
        |> Enum.map(fn {k, v} -> {"#{subpath}.#{k}", v} end)
        |> Map.new()
      else
        args
      end

    %{bp | arg_map: ArgumentMap.add_layer(bp.arg_map, args, layer_name)}
  end

  @doc """
  Apply arguments from argv.
  """
  def apply_from_argv(%__MODULE__{} = bp, argv, opts \\ []) do
    case Parser.parse(argv) do
      {:ok, args} ->
        help = Parser.help_requested?(args)
        args = Map.delete(args, :__help__)

        bp =
          apply(bp, args, layer_name: Keyword.get(opts, :layer_name, "command line"))

        if help do
          raise ChzEx.HelpException, message: get_help(bp)
        end

        {:ok, bp}

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
         :ok <- Lazy.check_reference_targets(state.value_mapping, Map.keys(state.all_params)) do
      if state.missing_params != [] do
        {:error, %Error{type: :missing_required, path: hd(state.missing_params)}}
      else
        try do
          struct = Lazy.evaluate(state.value_mapping)

          with {:ok, validated} <- validate_struct(struct) do
            {:ok, apply_mungers(validated)}
          end
        rescue
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
  def make_from_argv(%__MODULE__{} = bp, argv \\ nil) do
    argv = argv || System.argv()

    case apply_from_argv(bp, argv) do
      {:ok, bp} -> make(bp)
      {:error, _} = err -> err
    end
  end

  @doc """
  Generate help text.
  """
  def get_help(%__MODULE__{} = bp, _opts \\ []) do
    {:ok, state} = make_lazy(bp)

    header = "Entry point: #{bp.entrypoint_repr}\n\n"

    params =
      state.all_params
      |> Enum.sort_by(fn {path, _field} -> path end)
      |> Enum.map(fn {path, field} ->
        found = ArgumentMap.get_kv(bp.arg_map, path)

        value_str =
          cond do
            found == nil and ChzEx.Field.has_default?(field) ->
              inspect(ChzEx.Field.get_default(field))

            found == nil ->
              "-"

            match?(%Reference{}, found.value) ->
              "@=" <> found.value.ref

            match?(%Castable{}, found.value) ->
              found.value.value |> inspect()

            match?(%ChzEx.Blueprint.Computed{}, found.value) ->
              "f(...)"

            true ->
              inspect(found.value)
          end

        type_str = type_to_string(field.type)
        doc = field.doc || ""
        "#{path}  #{type_str}  #{value_str}  #{doc}"
      end)
      |> Enum.join("\n")

    header <> "Arguments:\n" <> params
  end

  defp type_to_string({:array, inner}), do: "array(#{type_to_string(inner)})"
  defp type_to_string(type) when is_atom(type), do: Atom.to_string(type)
  defp type_to_string(type), do: inspect(type)

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

    case field.embed_type do
      :one ->
        construct_embed_one(field, path, found, subpaths, state)

      :many ->
        construct_embed_many(field, path, found, subpaths, state)

      _ ->
        construct_scalar(field, path, found, state)
    end
  end

  defp construct_scalar(field, path, found, state) do
    cond do
      found != nil ->
        state = mark_used(state, found)
        value = found.value

        {evaluatable, state} =
          case value do
            %Reference{ref: ref} ->
              if ref == path do
                if ChzEx.Field.has_default?(field) do
                  {%Lazy.Value{value: ChzEx.Field.get_default(field)}, state}
                else
                  {%Lazy.Value{value: nil}, mark_missing(state, path)}
                end
              else
                {%Lazy.ParamRef{ref: ref}, state}
              end

            %Castable{value: str} ->
              {cast_value(field, path, str), state}

            %ChzEx.Blueprint.Computed{sources: sources, compute: compute} ->
              kwargs =
                Enum.map(sources, fn {key, %Reference{ref: ref}} ->
                  key =
                    case key do
                      atom when is_atom(atom) -> atom
                      binary when is_binary(binary) -> String.to_atom(binary)
                    end

                  {key, %Lazy.ParamRef{ref: ref}}
                end)
                |> Map.new()

              {%Lazy.Thunk{fn: compute, kwargs: kwargs}, state}

            _ ->
              {%Lazy.Value{value: value}, state}
          end

        put_value(state, path, evaluatable)

      ChzEx.Field.has_default?(field) ->
        put_value(state, path, %Lazy.Value{value: ChzEx.Field.get_default(field)})

      true ->
        if field.munger != nil do
          put_value(state, path, %Lazy.Value{value: nil})
        else
          state = mark_missing(state, path)
          put_value(state, path, %Lazy.Value{value: nil})
        end
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
      found != nil and subpaths == [] and not is_special_arg(found.value) ->
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
    factory =
      ChzEx.Factory.Standard.new(
        annotation: field.type,
        unspecified: field.blueprint_unspecified,
        namespace: field.namespace
      )

    cond do
      found != nil ->
        case found.value do
          %Castable{value: value} -> ChzEx.Factory.Standard.from_string(factory, value)
          module when is_atom(module) -> {:ok, module}
          _ -> {:error, "Invalid factory for #{path_label(field)}"}
        end

      subpaths_present ->
        default = ChzEx.Factory.Standard.unspecified_factory(factory)

        if default,
          do: {:ok, default},
          else: {:error, "No default factory for #{path_label(field)}"}

      true ->
        default = ChzEx.Factory.Standard.unspecified_factory(factory)

        if default,
          do: {:ok, default},
          else: {:error, "No default factory for #{path_label(field)}"}
    end
  end

  defp path_label(field) do
    Atom.to_string(field.name)
  end

  defp construct_embed_many(field, path, found, subpaths, state) do
    cond do
      found != nil and subpaths == [] and not is_special_arg(found.value) ->
        state = mark_used(state, found)
        put_value(state, path, %Lazy.Value{value: found.value})

      subpaths != [] ->
        indices =
          subpaths
          |> Enum.map(&String.split(&1, "."))
          |> Enum.map(&List.first/1)
          |> Enum.filter(&(&1 != nil))
          |> Enum.uniq()
          |> Enum.sort()

        {kwargs, state} =
          Enum.reduce(indices, {%{}, state}, fn index, {acc, st} ->
            st = construct_schema(field.type, join_path(path, index), st)
            {Map.put(acc, index, %Lazy.ParamRef{ref: join_path(path, index)}), st}
          end)

        thunk = %Lazy.Thunk{
          fn: fn resolved ->
            indices
            |> Enum.map(fn index -> Map.fetch!(resolved, index) end)
          end,
          kwargs: kwargs
        }

        put_value(state, path, thunk)

      ChzEx.Field.has_default?(field) ->
        put_value(state, path, %Lazy.Value{value: ChzEx.Field.get_default(field)})

      true ->
        state = mark_missing(state, path)
        put_value(state, path, %Lazy.Value{value: []})
    end
  end

  defp cast_value(field, path, str) do
    case Cast.try_cast(str, field.type) do
      {:ok, value} ->
        %Lazy.Value{value: value}

      {:error, reason} ->
        raise %Error{type: :cast_error, path: path, message: reason}
    end
  end

  defp is_special_arg(%Castable{}), do: true
  defp is_special_arg(%Reference{}), do: true
  defp is_special_arg(_), do: false

  defp has_all_defaults?(module) when is_atom(module) do
    if Schema.is_chz?(module) do
      module.__chz_fields__()
      |> Enum.all?(fn {_name, field} -> not ChzEx.Field.required?(field) end)
    else
      false
    end
  end

  defp nested_args_present?(module, path, arg_map) do
    if Schema.is_chz?(module) do
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
        if field.embed_type == :one and Schema.is_chz?(field.type) do
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
  defp join_path(parent, child), do: "#{parent}.#{child}"

  defp check_extraneous(arg_map, state) do
    param_paths = Map.keys(state.all_params)

    arg_map.layers
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {layer, idx}, :ok ->
      result =
        layer.args
        |> Enum.reduce_while(:ok, fn {key, _value}, :ok ->
          if MapSet.member?(state.used_args, {key, idx}) do
            {:cont, :ok}
          else
            if extraneous_key?(key, param_paths) do
              {:halt,
               {:error,
                %Error{
                  type: :extraneous,
                  path: key,
                  suggestions: suggestions_for(key, param_paths)
                }}}
            else
              {:cont, :ok}
            end
          end
        end)

      case result do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
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

  defp validate_value(value) do
    cond do
      Schema.is_chz?(value) ->
        validate_struct(value)

      is_list(value) ->
        value
        |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
          case validate_value(item) do
            {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
            {:error, _} = err -> {:halt, err}
          end
        end)
        |> case do
          {:ok, list} -> {:ok, Enum.reverse(list)}
          {:error, _} = err -> err
        end

      true ->
        {:ok, value}
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
      Schema.is_chz?(value) -> apply_mungers(value)
      is_list(value) -> Enum.map(value, &apply_mungers_to_value/1)
      true -> value
    end
  end
end
