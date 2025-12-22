defmodule ChzEx.Serialize do
  @moduledoc """
  Serialization helpers for converting configs into blueprint-friendly arguments.
  """

  alias ChzEx.{Field, Schema}

  @doc """
  Flatten a ChzEx struct into dot-delimited blueprint arguments.

  Options:
  - `:skip_defaults` - omit fields whose values match defaults.
  """
  @spec to_blueprint_values(any(), Keyword.t()) :: map()
  def to_blueprint_values(obj, opts \\ []) do
    skip_defaults = Keyword.get(opts, :skip_defaults, false)
    do_to_blueprint_values(obj, "", skip_defaults, %{})
  end

  defp do_to_blueprint_values(obj, path, skip_defaults, acc) do
    case classify_value(obj) do
      :chz ->
        serialize_chz(obj, path, skip_defaults, acc)

      :map ->
        serialize_map(obj, path, skip_defaults, acc)

      :list ->
        serialize_list(obj, path, skip_defaults, acc)

      :value ->
        Map.put(acc, path, obj)
    end
  end

  defp classify_value(obj) do
    cond do
      Schema.chz?(obj) -> :chz
      map_with_chz?(obj) -> :map
      list_with_chz?(obj) -> :list
      true -> :value
    end
  end

  defp serialize_chz(obj, path, skip_defaults, acc) do
    obj.__struct__.__chz_fields__()
    |> Enum.reduce(acc, fn {name, field}, acc ->
      value = Map.get(obj, name)

      if skip_defaults and default_match?(field, value) do
        acc
      else
        param_path = join_path(path, Atom.to_string(name))
        acc = maybe_put_polymorphic(field, value, param_path, acc)
        do_to_blueprint_values(value, param_path, skip_defaults, acc)
      end
    end)
  end

  defp serialize_map(obj, path, skip_defaults, acc) do
    Enum.reduce(obj, acc, fn {key, value}, acc ->
      param_path = join_path(path, to_path_segment(key))
      acc = Map.put(acc, param_path, type_of(value))
      do_to_blueprint_values(value, param_path, skip_defaults, acc)
    end)
  end

  defp serialize_list(obj, path, skip_defaults, acc) do
    obj
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {value, index}, acc ->
      param_path = join_path(path, Integer.to_string(index))
      acc = Map.put(acc, param_path, type_of(value))
      do_to_blueprint_values(value, param_path, skip_defaults, acc)
    end)
  end

  defp maybe_put_polymorphic(field, value, path, acc) do
    if field.meta_factory != nil or field.polymorphic do
      factory = ChzEx.Blueprint.meta_factory_for_field(field)
      factory_module = factory.__struct__
      default = factory_module.unspecified_factory(factory)

      if Schema.chz?(value) and value.__struct__ != default do
        Map.put(acc, path, value.__struct__)
      else
        acc
      end
    else
      acc
    end
  end

  defp default_match?(%Field{} = field, value) do
    if Field.has_default?(field) do
      Field.get_default(field) == value
    else
      false
    end
  end

  defp map_with_chz?(value) when is_map(value) do
    keys = Map.keys(value)
    has_keys = keys != []
    string_keys = Enum.all?(keys, &is_binary/1)
    has_chz = Enum.any?(value, fn {_k, v} -> Schema.chz?(v) end)
    has_keys and string_keys and has_chz
  end

  defp map_with_chz?(_value), do: false

  defp list_with_chz?(value) when is_list(value) do
    Enum.any?(value, &Schema.chz?/1)
  end

  defp list_with_chz?(_value), do: false

  defp type_of(value) do
    if Schema.chz?(value), do: value.__struct__, else: value
  end

  defp join_path("", child), do: child
  defp join_path(parent, child), do: "#{parent}.#{child}"

  defp to_path_segment(value) when is_binary(value), do: value
  defp to_path_segment(value) when is_atom(value), do: Atom.to_string(value)
  defp to_path_segment(value), do: to_string(value)
end
