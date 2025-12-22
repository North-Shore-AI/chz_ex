defmodule ChzEx.Blueprint.Serialize do
  @moduledoc """
  Convert a blueprint back into CLI-style argv arguments.
  """

  alias ChzEx.Blueprint
  alias ChzEx.Blueprint.{Castable, Computed, Reference}
  alias ChzEx.{Schema, Type, Wildcard}

  @doc """
  Serialize a blueprint into a list of `key=value` CLI arguments.
  """
  @spec to_argv(Blueprint.t()) :: [String.t()]
  def to_argv(%Blueprint{} = bp) do
    bp.arg_map.layers
    |> collapse_layers()
    |> Enum.flat_map(fn {key, value} ->
      field = field_for_key(bp.target, key)
      arg_to_string(key, value, field)
    end)
  end

  defp collapse_layers(layers) do
    {ordered, _keys} =
      Enum.reduce(layers, {[], MapSet.new()}, fn layer, {ordered, keys} ->
        collapse_layer(layer, ordered, keys)
      end)

    ordered
  end

  defp collapse_layer(layer, ordered, keys) do
    {layer_args, keys_to_remove} =
      layer_entries(layer)
      |> Enum.reduce({[], MapSet.new()}, fn {key, value}, {layer_args, keys_to_remove} ->
        keys_to_remove = keys_to_remove_for_entry(key, keys, keys_to_remove)

        {[{key, value} | layer_args], keys_to_remove}
      end)

    layer_args = Enum.reverse(layer_args)
    ordered = Enum.reject(ordered, fn {key, _} -> MapSet.member?(keys_to_remove, key) end)
    keys = MapSet.difference(keys, keys_to_remove)
    ordered = ordered ++ layer_args

    keys =
      Enum.reduce(layer_args, keys, fn {key, _value}, acc ->
        MapSet.put(acc, key)
      end)

    {ordered, keys}
  end

  defp keys_to_remove_for_entry(key, keys, keys_to_remove) do
    if String.contains?(key, "...") do
      collect_matching_keys(keys, Wildcard.to_regex(key), keys_to_remove)
    else
      maybe_track_override(key, keys, keys_to_remove)
    end
  end

  defp collect_matching_keys(keys, regex, keys_to_remove) do
    Enum.reduce(keys, keys_to_remove, &add_if_matches(&1, &2, regex))
  end

  defp add_if_matches(prev_key, acc, regex) do
    if Regex.match?(regex, prev_key), do: MapSet.put(acc, prev_key), else: acc
  end

  defp maybe_track_override(key, keys, keys_to_remove) do
    if MapSet.member?(keys, key) do
      MapSet.put(keys_to_remove, key)
    else
      keys_to_remove
    end
  end

  defp layer_entries(layer) do
    (Map.to_list(layer.qualified) ++ Map.to_list(layer.wildcard))
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp arg_to_string(key, %Castable{value: value}, _field), do: ["#{key}=#{value}"]
  defp arg_to_string(key, %Reference{ref: ref}, _field), do: ["#{key}@=#{ref}"]

  defp arg_to_string(_key, %Computed{}, _field) do
    raise ArgumentError, "Cannot serialize computed values to argv"
  end

  defp arg_to_string(key, value, _field) when is_binary(value), do: ["#{key}=#{value}"]

  defp arg_to_string(key, value, _field)
       when is_integer(value) or is_float(value) or is_boolean(value) or is_nil(value) do
    ["#{key}=#{inspect(value)}"]
  end

  defp arg_to_string(key, value, field) when is_atom(value) do
    cond do
      value in [true, false, nil] ->
        ["#{key}=#{inspect(value)}"]

      module_atom?(value) ->
        case serialize_module(field, value) do
          {:ok, name} -> ["#{key}=#{name}"]
          :error -> ["#{key}=#{Type.type_repr(value)}"]
        end

      true ->
        ["#{key}=#{Atom.to_string(value)}"]
    end
  end

  defp arg_to_string(key, value, _field) when is_function(value) do
    ["#{key}=#{function_ref(value)}"]
  end

  defp arg_to_string(key, value, field) when is_list(value),
    do: arg_to_string_list(key, value, field)

  defp arg_to_string(key, value, field) when is_map(value),
    do: arg_to_string_map(key, value, field)

  defp arg_to_string(key, value, _field) when is_tuple(value) do
    list = Tuple.to_list(value)
    arg_to_string(key, list, nil)
  end

  defp arg_to_string(key, value, _field) do
    raise ArgumentError,
          "Cannot serialize #{inspect(value)} for #{key}"
  end

  defp primitive_value?(value)
       when is_integer(value) or is_float(value) or is_boolean(value) or is_nil(value),
       do: true

  defp primitive_value?(_value), do: false

  defp arg_to_string_list(key, [], _field), do: ["#{key}="]

  defp arg_to_string_list(key, value, _field) do
    cond do
      Enum.all?(value, &is_binary/1) ->
        arg_to_string_binary_list(key, value)

      Enum.all?(value, &primitive_value?/1) ->
        ["#{key}=#{Enum.map_join(value, ",", &inspect/1)}"]

      true ->
        raise ArgumentError, "Cannot serialize list value for #{key}"
    end
  end

  defp arg_to_string_binary_list(key, value) do
    if Enum.all?(value, fn entry -> not String.contains?(entry, ",") end) do
      ["#{key}=#{Enum.join(value, ",")}"]
    else
      value
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, index} ->
        arg_to_string("#{key}.#{index}", entry, nil)
      end)
    end
  end

  defp arg_to_string_map(key, value, _field) do
    Enum.flat_map(value, fn {k, v} ->
      arg_to_string(join_path(key, to_path_segment(k)), v, nil)
    end)
  end

  defp module_atom?(value) when is_atom(value) do
    Code.ensure_loaded?(value) and function_exported?(value, :__info__, 1)
  end

  defp serialize_module(nil, _module), do: :error

  defp serialize_module(field, module) do
    if field.meta_factory != nil or field.polymorphic do
      factory = Blueprint.meta_factory_for_field(field)
      factory_module = factory.__struct__
      factory_module.serialize(factory, module)
    else
      :error
    end
  end

  defp function_ref(fun) do
    info = Function.info(fun)
    module = Keyword.get(info, :module)
    name = Keyword.get(info, :name)
    arity = Keyword.get(info, :arity)

    if is_atom(module) and is_atom(name) and is_integer(arity) do
      "#{Type.type_repr(module)}.#{name}/#{arity}"
    else
      raise ArgumentError, "Cannot serialize function reference #{inspect(fun)}"
    end
  end

  defp field_for_key(target, key) do
    if Schema.chz?(target) do
      segments = String.split(key, ".", trim: true)
      resolve_field(target, segments)
    else
      nil
    end
  end

  defp resolve_field(_module, []), do: nil

  defp resolve_field(module, [segment]) do
    if numeric_segment?(segment), do: nil, else: find_field(module, segment)
  end

  defp resolve_field(module, [segment | rest]) do
    case segment_kind(segment) do
      :numeric ->
        resolve_field(module, rest)

      :wildcard ->
        nil

      :field ->
        resolve_field_in_module(module, segment, rest)
    end
  end

  defp resolve_field_in_module(module, segment, rest) do
    case find_field(module, segment) do
      nil -> nil
      field -> resolve_embedded_field(field, rest)
    end
  end

  defp resolve_embedded_field(field, rest) do
    if field.embed_type in [:one, :many] and Schema.chz?(field.type) do
      resolve_field(field.type, rest)
    else
      nil
    end
  end

  defp find_field(module, segment) do
    module.__chz_fields__()
    |> Enum.find_value(fn {name, field} ->
      if Atom.to_string(name) == segment, do: field, else: nil
    end)
  end

  defp numeric_segment?(segment) do
    case Integer.parse(segment) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp segment_kind(segment) do
    cond do
      numeric_segment?(segment) -> :numeric
      String.contains?(segment, "...") -> :wildcard
      true -> :field
    end
  end

  defp join_path("", child), do: child
  defp join_path(parent, child), do: "#{parent}.#{child}"

  defp to_path_segment(value) when is_binary(value), do: value
  defp to_path_segment(value) when is_atom(value), do: Atom.to_string(value)
  defp to_path_segment(value) when is_integer(value), do: Integer.to_string(value)
  defp to_path_segment(value) when is_float(value), do: Float.to_string(value)
  defp to_path_segment(value), do: inspect(value)
end
