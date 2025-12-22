defmodule ChzEx.Validator do
  @moduledoc """
  Validation functions for ChzEx schemas.
  """

  alias ChzEx.{Schema, Type}

  @doc """
  Type check validator using ChzEx type semantics.
  """
  def typecheck(struct, attr) do
    field = struct.__struct__.__chz_fields__()[attr]
    value = Map.get(struct, attr)
    expected = field.raw_type

    if Type.is_instance?(value, expected) do
      :ok
    else
      {:error, "Expected #{attr} to be #{Type.type_repr(expected)}, got #{inspect(value)}"}
    end
  end

  @doc """
  Instance check validator using the annotated type.
  """
  def instancecheck(struct, attr) do
    field = struct.__struct__.__chz_fields__()[attr]
    value = Map.get(struct, attr)
    expected = field.raw_type

    if Type.is_instance?(value, expected) do
      :ok
    else
      {:error, "Expected #{attr} to be #{Type.type_repr(expected)}, got #{inspect(value)}"}
    end
  end

  @doc """
  Build a validator that checks for instances of the given type.
  """
  def instance_of(type) do
    fn struct, attr ->
      value = Map.get(struct, attr)

      if Type.is_instance?(value, type) do
        :ok
      else
        {:error, "Expected #{attr} to be #{Type.type_repr(type)}, got #{inspect(value)}"}
      end
    end
  end

  @doc "Check value is greater than base."
  def gt(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value > base, do: :ok, else: {:error, "Expected #{attr} to be greater than #{base}"}
    end
  end

  @doc "Check value is less than base."
  def lt(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value < base, do: :ok, else: {:error, "Expected #{attr} to be less than #{base}"}
    end
  end

  @doc "Check value is greater than or equal to base."
  def ge(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value >= base, do: :ok, else: {:error, "Expected #{attr} to be >= #{base}"}
    end
  end

  @doc "Check value is less than or equal to base."
  def le(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value <= base, do: :ok, else: {:error, "Expected #{attr} to be <= #{base}"}
    end
  end

  @doc "Check value is a valid regex."
  def valid_regex(struct, attr) do
    value = Map.get(struct, attr)

    case Regex.compile(value) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Invalid regex in #{attr}: #{inspect(reason)}"}
    end
  end

  @doc "Check value matches the field's default."
  def const_default(struct, attr) do
    field = struct.__struct__.__chz_fields__()[attr]

    cond do
      field.default_factory != nil ->
        {:error, "const_default requires a static default for #{attr}"}

      is_nil(field.default) ->
        {:error, "const_default requires a non-nil default for #{attr}"}

      true ->
        value = Map.get(struct, attr)

        if value == field.default do
          :ok
        else
          {:error,
           "Expected #{attr} to match the default #{inspect(field.default)}, got #{inspect(value)}"}
        end
    end
  end

  @doc "Check value is within an inclusive range."
  def in_range(min, max) do
    fn struct, attr ->
      value = Map.get(struct, attr)

      cond do
        value < min -> {:error, "Expected #{attr} to be >= #{min}"}
        value > max -> {:error, "Expected #{attr} to be <= #{max}"}
        true -> :ok
      end
    end
  end

  @doc "Check value is one of the allowed values."
  def one_of(values) when is_list(values) do
    fn struct, attr ->
      value = Map.get(struct, attr)

      if value in values do
        :ok
      else
        {:error, "Expected #{attr} to be one of #{inspect(values)}"}
      end
    end
  end

  @doc "Check value matches a regex."
  def matches(pattern) do
    regex =
      case pattern do
        %Regex{} = compiled -> compiled
        binary when is_binary(binary) -> Regex.compile!(binary)
      end

    fn struct, attr ->
      value = Map.get(struct, attr)

      if is_binary(value) and Regex.match?(regex, value) do
        :ok
      else
        {:error, "Expected #{attr} to match #{inspect(pattern)}"}
      end
    end
  end

  @doc "Check value is not empty."
  def not_empty do
    fn struct, attr ->
      value = Map.get(struct, attr)

      cond do
        is_nil(value) -> {:error, "#{attr} cannot be nil"}
        is_binary(value) and value == "" -> {:error, "#{attr} cannot be empty"}
        is_list(value) and value == [] -> {:error, "#{attr} cannot be empty"}
        is_map(value) and map_size(value) == 0 -> {:error, "#{attr} cannot be empty"}
        true -> :ok
      end
    end
  end

  @doc "Apply validator to all fields."
  def for_all_fields(validator) do
    fn struct -> validate_all_fields(struct, validator) end
  end

  @doc "Combine validators; all must pass."
  def all(validators) when is_list(validators) do
    fn struct, attr -> apply_all(validators, struct, attr) end
  end

  @doc "Combine validators; any may pass."
  def any(validators) when is_list(validators) do
    fn struct, attr -> apply_any(validators, struct, attr) end
  end

  defp apply_all(validators, struct, attr) do
    Enum.reduce_while(validators, :ok, fn validator, :ok ->
      case validator.(struct, attr) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp apply_any(validators, struct, attr) do
    results = Enum.map(validators, & &1.(struct, attr))

    if Enum.any?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, Enum.join(any_error_messages(results), "; ")}
    end
  end

  defp any_error_messages(results) do
    results
    |> Enum.filter(&match?({:error, _}, &1))
    |> Enum.map(fn {:error, msg} -> msg end)
  end

  @doc "Apply validator when another field satisfies a condition."
  def when_field(field, condition, validator) do
    fn struct, attr ->
      field_value = Map.get(struct, field)

      applies? =
        if is_function(condition, 1) do
          condition.(field_value)
        else
          field_value == condition
        end

      if applies? do
        validator.(struct, attr)
      else
        :ok
      end
    end
  end

  @doc """
  Check that selected fields have consistent values across a nested object tree.
  """
  def check_field_consistency_in_tree(obj, fields, opts \\ []) do
    regex_root = Keyword.get(opts, :regex_root, "")
    regex = Regex.compile!(regex_root)

    fields =
      fields
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    values = collect_field_values(obj, fields, regex, "", %{})

    Enum.find_value(values, :ok, fn {{_group, field}, value_map} ->
      if map_size(value_map) > 1 do
        {:error, consistency_message(field, value_map)}
      else
        false
      end
    end)
  end

  @doc """
  Alias for `check_field_consistency_in_tree/3`.
  """
  def check_field_consistency(obj, fields, opts \\ []) do
    check_field_consistency_in_tree(obj, fields, opts)
  end

  @doc """
  Validator that checks if a field overrides a parent definition.
  """
  def override?, do: override?([])

  def override?(opts) when is_list(opts) do
    fn struct, attr -> override?(struct, attr, opts) end
  end

  def override?(struct, attr), do: override?(struct, attr, [])

  def override?(struct, attr, opts) when is_list(opts) do
    original_defs =
      Keyword.get(opts, :original_defs) || find_original_definitions(struct, opts)

    field_name = normalize_attr(attr, original_defs)
    module = struct.__struct__

    case Map.get(original_defs, field_name) do
      nil ->
        {:error, "Unknown field #{attr} for override check"}

      {original_field, original_module} ->
        check_override_type(struct, field_name, original_field, original_module, module)
    end
  end

  defp check_override_type(struct, field_name, original_field, original_module, module) do
    if original_module == module do
      {:error,
       "Field #{field_name} does not exist in any parent classes of #{Type.type_repr(module)}"}
    else
      value = Map.get(struct, field_name)

      if Type.is_instance?(value, original_field.raw_type) do
        :ok
      else
        {:error,
         "#{Type.type_repr(module)}.#{field_name} must be an instance of " <>
           "#{Type.type_repr(original_field.raw_type)} to match the type on " <>
           "the original definition in #{Type.type_repr(original_module)}"}
      end
    end
  end

  @doc false
  def check_overrides(struct) do
    original_defs = find_original_definitions(struct, [])

    struct.__struct__.__chz_fields__()
    |> Enum.reduce_while(:ok, fn {name, _field}, :ok ->
      case override?(struct, name, original_defs: original_defs) do
        :ok -> {:cont, :ok}
        {:error, msg} -> {:halt, {:error, name, msg}}
      end
    end)
  end

  defp find_original_definitions(struct, opts) do
    module = struct.__struct__
    parents = Keyword.get(opts, :parents) || parents_for(module)
    modules = parents ++ [module]

    Enum.reduce(modules, %{}, fn mod, acc ->
      collect_original_defs(mod, acc)
    end)
  end

  defp collect_original_defs(mod, acc) do
    if Schema.chz?(mod) do
      mod.__chz_fields__()
      |> Enum.reduce(acc, fn {name, field}, acc ->
        Map.put_new(acc, name, {field, mod})
      end)
    else
      acc
    end
  end

  defp parents_for(module) do
    if function_exported?(module, :__chz_parents__, 0) do
      module.__chz_parents__()
    else
      []
    end
  end

  defp normalize_attr(attr, _original_defs) when is_atom(attr), do: attr

  defp normalize_attr(attr, original_defs) when is_binary(attr) do
    Enum.find(Map.keys(original_defs), fn key -> Atom.to_string(key) == attr end)
  end

  defp collect_field_values(obj, fields, regex, obj_path, acc) do
    if Schema.chz?(obj) do
      obj.__struct__.__chz_fields__()
      |> Enum.reduce(acc, fn {name, _field}, acc ->
        value = Map.get(obj, name)
        field_path = join_path(obj_path, Atom.to_string(name))
        field_name = Atom.to_string(name)

        acc = maybe_add_consistency(acc, fields, field_name, value, obj_path, field_path, regex)

        acc
        |> maybe_collect_chz(value, field_path, fields, regex)
      end)
    else
      acc
    end
  end

  defp maybe_collect_chz(acc, value, path, fields, regex) do
    cond do
      Schema.chz?(value) -> collect_field_values(value, fields, regex, path, acc)
      is_map(value) -> collect_map_values(value, path, fields, regex, acc)
      is_list(value) -> collect_list_values(value, path, fields, regex, acc)
      true -> acc
    end
  end

  defp maybe_add_consistency(acc, fields, field_name, value, obj_path, field_path, regex) do
    if MapSet.member?(fields, field_name) do
      case Regex.run(regex, obj_path) do
        [group | _] -> add_consistency_value(acc, group, field_name, value, field_path)
        nil -> acc
      end
    else
      acc
    end
  end

  defp collect_map_values(value, path, fields, regex, acc) do
    Enum.reduce(value, acc, fn {k, v}, acc ->
      if Schema.chz?(v) do
        collect_field_values(v, fields, regex, join_path(path, to_string(k)), acc)
      else
        acc
      end
    end)
  end

  defp collect_list_values(value, path, fields, regex, acc) do
    value
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {v, idx}, acc ->
      if Schema.chz?(v) do
        collect_field_values(v, fields, regex, join_path(path, Integer.to_string(idx)), acc)
      else
        acc
      end
    end)
  end

  defp add_consistency_value(acc, group, field, value, path) do
    Map.update(acc, {group, field}, %{value => [path]}, fn value_map ->
      Map.update(value_map, value, [path], fn paths -> [path | paths] end)
    end)
  end

  defp consistency_message(field, value_map) do
    details =
      Enum.map_join(value_map, "\n", fn {value, paths} ->
        "#{inspect(value)} at #{paths_repr(Enum.reverse(paths))}"
      end)

    "Field #{inspect(field)} has inconsistent values in object tree:\n" <> details
  end

  defp paths_repr(paths) do
    if length(paths) <= 3 do
      Enum.join(paths, ", ")
    else
      Enum.join(Enum.take(paths, 3), ", ") <> ", ... (#{length(paths) - 3} more)"
    end
  end

  defp join_path("", child), do: child
  defp join_path(parent, child), do: "#{parent}.#{child}"

  defp validate_all_fields(struct, validator) do
    struct.__struct__.__chz_fields__()
    |> Enum.reduce_while(:ok, &validate_single_field(&1, &2, struct, validator))
  end

  defp validate_single_field({name, _field}, :ok, struct, validator) do
    case validator.(struct, name) do
      :ok -> {:cont, :ok}
      {:error, msg} -> {:halt, {:error, name, msg}}
    end
  end
end

defmodule ChzEx.Validator.IsOverrideMixin do
  @moduledoc """
  Macro that adds a class-level override checker.
  """

  defmacro __using__(_opts) do
    quote do
      @chz_validate :__chz_check_overrides__

      def __chz_check_overrides__(struct) do
        ChzEx.Validator.check_overrides(struct)
      end
    end
  end
end
