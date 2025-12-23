# credo:disable-for-this-file Credo.Check.Readability.PredicateFunctionNames
defmodule ChzEx.Type do
  @moduledoc """
  Runtime type helpers and human-readable type formatting.
  """

  @type t ::
          atom()
          | nil
          | {:array, t()}
          | {:map, t(), t()}
          | {:map_schema, map()}
          | {:mapset, t()}
          | {:tuple, [t()]}
          | {:union, [t()]}
          | {:literal, [term()]}
          | {:enum, [term()]}
          | {:function, non_neg_integer()}

  @doc """
  Wrap a type in an optional union with nil.
  """
  @spec make_optional(t()) :: t()
  def make_optional(type) do
    if optional?(type) do
      type
    else
      {:union, normalize_union([type, nil])}
    end
  end

  @doc """
  Return true if the type allows nil.
  """
  @spec optional?(t()) :: boolean()
  def optional?(nil), do: true

  def optional?({:union, types}) do
    normalize_union(types) |> Enum.any?(&(&1 == nil))
  end

  def optional?(_type), do: false

  @doc """
  Returns a human-readable representation for a type.
  """
  @spec type_repr(t()) :: String.t()
  def type_repr({:union, types}) do
    normalize_union(types)
    |> Enum.map_join(" | ", &type_repr/1)
  end

  def type_repr({:array, inner}), do: "[#{type_repr(inner)}]"

  def type_repr({:map, key, value}) do
    "%{#{type_repr(key)} => #{type_repr(value)}}"
  end

  def type_repr({:map_schema, fields}) when is_map(fields) do
    fields_str =
      fields
      |> Enum.sort_by(fn {k, _} -> Atom.to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{map_schema_field_repr(v)}" end)

    "%{#{fields_str}}"
  end

  def type_repr({:mapset, inner}), do: "MapSet[#{type_repr(inner)}]"

  def type_repr({:tuple, types}) when is_list(types) do
    types_str = Enum.map_join(types, ", ", &type_repr/1)
    "{#{types_str}}"
  end

  def type_repr({:literal, values}) do
    "literal[" <> Enum.map_join(values, ", ", &inspect/1) <> "]"
  end

  def type_repr({:enum, values}) do
    "enum[" <> Enum.map_join(values, ", ", &inspect/1) <> "]"
  end

  def type_repr({:function, arity}) when is_integer(arity) do
    "function/#{arity}"
  end

  def type_repr(:function), do: "function"
  def type_repr(:path), do: "path"

  def type_repr(type) when is_atom(type) do
    atom_string = Atom.to_string(type)
    String.replace_prefix(atom_string, "Elixir.", "")
  end

  def type_repr(type), do: inspect(type)

  @doc """
  Runtime type checking.
  """
  @spec is_instance?(term(), t()) :: boolean()
  def is_instance?(value, {:union, types}) do
    normalize_union(types)
    |> Enum.any?(&is_instance?(value, &1))
  end

  def is_instance?(nil, nil), do: true
  def is_instance?(_value, nil), do: false

  def is_instance?(_value, :any), do: true
  def is_instance?(_value, :term), do: true

  def is_instance?(value, :string), do: is_binary(value)
  def is_instance?(value, :integer), do: is_integer(value)
  def is_instance?(value, :float), do: is_float(value) or is_integer(value)
  def is_instance?(value, :boolean), do: is_boolean(value)
  def is_instance?(value, :binary), do: is_binary(value)
  def is_instance?(value, :atom), do: is_atom(value)
  def is_instance?(value, :map), do: is_map(value)
  def is_instance?(value, :path), do: is_binary(value)

  def is_instance?(value, {:array, inner}) when is_list(value) do
    Enum.all?(value, &is_instance?(&1, inner))
  end

  def is_instance?(_value, {:array, _inner}), do: false

  def is_instance?(value, {:map, key_type, value_type}) when is_map(value) do
    Enum.all?(value, fn {k, v} ->
      is_instance?(k, key_type) and is_instance?(v, value_type)
    end)
  end

  def is_instance?(_value, {:map, _key_type, _value_type}), do: false

  def is_instance?(%MapSet{} = value, {:mapset, inner}) do
    Enum.all?(value, &is_instance?(&1, inner))
  end

  def is_instance?(_value, {:mapset, _inner}), do: false

  def is_instance?(value, {:tuple, types}) when is_tuple(value) and is_list(types) do
    tuple_list = Tuple.to_list(value)

    length(tuple_list) == length(types) and
      Enum.zip(tuple_list, types)
      |> Enum.all?(fn {v, t} -> is_instance?(v, t) end)
  end

  def is_instance?(_value, {:tuple, _types}), do: false

  def is_instance?(value, {:literal, values}), do: value in values
  def is_instance?(value, {:enum, values}), do: value in values

  def is_instance?(value, {:function, arity}) when is_integer(arity),
    do: is_function(value, arity)

  def is_instance?(value, :function), do: is_function(value)

  def is_instance?(value, module) when is_atom(module) do
    cond do
      function_exported?(module, :__chz_enum_values__, 0) ->
        value in module.__chz_enum_values__()

      Code.ensure_loaded?(module) and function_exported?(module, :__struct__, 0) ->
        is_struct(value, module)

      true ->
        false
    end
  end

  def is_instance?(value, {:map_schema, fields}) when is_map(value) and is_map(fields) do
    Enum.all?(fields, fn {key, field_spec} ->
      {type, required} = normalize_map_schema_field(field_spec)

      case Map.fetch(value, key) do
        {:ok, field_value} -> is_instance?(field_value, type)
        :error -> required == :optional
      end
    end)
  end

  def is_instance?(_value, {:map_schema, _fields}), do: false

  @doc false
  @spec normalize_union([t()]) :: [t()]
  def normalize_union(types) when is_list(types) do
    types
    |> Enum.flat_map(fn
      {:union, inner} -> normalize_union(inner)
      type -> [type]
    end)
    |> Enum.uniq()
  end

  @doc """
  Normalize a map_schema field spec to {type, :required | :optional}.
  """
  @spec normalize_map_schema_field(t() | {t(), :required | :optional}) ::
          {t(), :required | :optional}
  def normalize_map_schema_field({type, :required}), do: {type, :required}
  def normalize_map_schema_field({type, :optional}), do: {type, :optional}
  def normalize_map_schema_field(type), do: {type, :required}

  defp map_schema_field_repr({type, :optional}), do: "#{type_repr(type)}?"
  defp map_schema_field_repr({type, :required}), do: type_repr(type)
  defp map_schema_field_repr(type), do: type_repr(type)
end
