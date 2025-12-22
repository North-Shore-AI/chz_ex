defmodule ChzEx.Cast do
  @moduledoc """
  Type-aware casting from strings for CLI parsing.
  """

  alias ChzEx.Type

  @doc """
  Attempt to cast a string to a target type.
  """
  def try_cast(value, type) when is_binary(value) do
    do_cast(value, type)
  end

  defp do_cast(value, :string), do: {:ok, value}

  defp do_cast(value, :integer) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Cannot cast #{inspect(value)} to integer"}
    end
  end

  defp do_cast(value, :float) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "Cannot cast #{inspect(value)} to float"}
    end
  end

  defp do_cast(value, :boolean) do
    cond do
      value in ~w(true True t 1) -> {:ok, true}
      value in ~w(false False f 0) -> {:ok, false}
      true -> {:error, "Cannot cast #{inspect(value)} to boolean"}
    end
  end

  defp do_cast(value, nil) when value in ["nil", "None"], do: {:ok, nil}

  defp do_cast(value, {:union, types}) do
    types
    |> Type.normalize_union()
    |> sort_union_types()
    |> Enum.reduce_while(
      {:error, "Cannot cast #{inspect(value)} to #{Type.type_repr({:union, types})}"},
      fn type, _acc ->
        case do_cast(value, type) do
          {:ok, casted} ->
            {:halt, {:ok, casted}}

          {:error, _} ->
            {:cont,
             {:error, "Cannot cast #{inspect(value)} to #{Type.type_repr({:union, types})}"}}
        end
      end
    )
  end

  defp do_cast(value, {:literal, literals}) when is_list(literals) do
    case cast_literal(value, literals) do
      {:ok, literal} ->
        {:ok, literal}

      :error ->
        {:error, "Cannot cast #{inspect(value)} to #{Type.type_repr({:literal, literals})}"}
    end
  end

  defp do_cast(value, {:enum, values}) when is_list(values) do
    case cast_literal(value, values) do
      {:ok, enum_value} -> {:ok, enum_value}
      :error -> {:error, "Invalid enum value #{inspect(value)}"}
    end
  end

  defp do_cast(value, {:function, arity}) when is_integer(arity) do
    with {:ok, {module, fun, arity}} <- parse_function_ref(value, arity),
         true <- function_exported?(module, fun, arity) do
      {:ok, Function.capture(module, fun, arity)}
    else
      false -> {:error, "Function #{value} with arity #{arity} is not available"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_cast(value, :function) do
    with {:ok, {module, fun, arity}} <- parse_function_ref(value, nil),
         true <- function_exported?(module, fun, arity) do
      {:ok, Function.capture(module, fun, arity)}
    else
      false -> {:error, "Function #{value} is not available"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_cast(value, :path), do: {:ok, Path.expand(value)}

  defp do_cast(value, :binary), do: decode_binary(value)
  defp do_cast(value, :bytes), do: decode_binary(value)

  defp do_cast(value, {:mapset, inner_type}) do
    case do_cast(value, {:array, inner_type}) do
      {:ok, list} -> {:ok, MapSet.new(list)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_cast(value, MapSet), do: {:ok, MapSet.new(String.split(value, ",", trim: true))}

  defp do_cast(value, DateTime) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, "Cannot cast #{inspect(value)} to DateTime"}
    end
  end

  defp do_cast(value, Date) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "Cannot cast #{inspect(value)} to Date"}
    end
  end

  defp do_cast(value, Time) do
    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> {:error, "Cannot cast #{inspect(value)} to Time"}
    end
  end

  defp do_cast(value, {:array, inner_type}) do
    values = String.split(value, ",", trim: true)
    results = Enum.map(values, &do_cast(&1, inner_type))

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, v} -> v end)}
    else
      {:error, "Cannot cast #{inspect(value)} to array of #{inspect(inner_type)}"}
    end
  end

  defp do_cast("", {:map, _key_type, _value_type}), do: {:ok, %{}}

  defp do_cast(value, {:map, key_type, value_type}) do
    pairs = String.split(value, ",", trim: true)
    parsed = Enum.map(pairs, &parse_map_pair(&1, key_type, value_type))
    build_map_from_parsed(parsed, value)
  end

  defp do_cast(value, module) when is_atom(module) do
    cond do
      function_exported?(module, :__chz_enum_values__, 0) ->
        do_cast(value, {:enum, module.__chz_enum_values__()})

      function_exported?(module, :__chz_cast__, 1) ->
        module.__chz_cast__(value)

      true ->
        {:error, "Cannot cast #{inspect(value)} to #{inspect(module)}"}
    end
  end

  defp do_cast(value, _type) do
    {:error, "Cannot cast #{inspect(value)}"}
  end

  defp parse_map_pair(pair, key_type, value_type) do
    case String.split(pair, ":", parts: 2) do
      [k, v] -> {do_cast(k, key_type), do_cast(v, value_type)}
      _ -> {:error, :invalid_pair}
    end
  end

  defp build_map_from_parsed(parsed, value) do
    if Enum.all?(parsed, &match?({{:ok, _}, {:ok, _}}, &1)) do
      map = Map.new(parsed, fn {{:ok, k}, {:ok, v}} -> {k, v} end)
      {:ok, map}
    else
      {:error, "Cannot cast #{inspect(value)} to map"}
    end
  end

  defp decode_binary(value) do
    hex = String.trim_leading(value, "0x")

    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:ok, value}
    end
  end

  defp cast_literal(value, literals) do
    Enum.reduce_while(literals, :error, fn literal, _acc ->
      case cast_literal_value(value, literal) do
        {:ok, match} -> {:halt, {:ok, match}}
        :error -> {:cont, :error}
      end
    end)
  end

  defp cast_literal_value(value, literal) when is_binary(literal) do
    if value == literal, do: {:ok, literal}, else: :error
  end

  defp cast_literal_value(value, literal) when is_integer(literal) do
    case Integer.parse(value) do
      {parsed, ""} when parsed == literal -> {:ok, literal}
      _ -> :error
    end
  end

  defp cast_literal_value(value, literal) when is_float(literal) do
    case Float.parse(value) do
      {parsed, ""} when parsed == literal -> {:ok, literal}
      _ -> :error
    end
  end

  defp cast_literal_value(value, literal) when is_boolean(literal) do
    case do_cast(value, :boolean) do
      {:ok, parsed} when parsed == literal -> {:ok, literal}
      _ -> :error
    end
  end

  defp cast_literal_value(value, literal) when is_atom(literal) do
    if value == Atom.to_string(literal), do: {:ok, literal}, else: :error
  end

  defp cast_literal_value(value, nil) when value in ["nil", "None", "null", "NULL"],
    do: {:ok, nil}

  defp cast_literal_value(_value, _literal), do: :error

  defp sort_union_types(types) do
    types
    |> Enum.with_index()
    |> Enum.sort_by(fn {type, index} -> {union_priority(type), index} end)
    |> Enum.map(fn {type, _index} -> type end)
  end

  defp union_priority({:literal, _}), do: -2
  defp union_priority(nil), do: -1
  defp union_priority(:string), do: 1
  defp union_priority(_), do: 0

  defp parse_function_ref(value, default_arity) do
    {mod_fun, arity} =
      case String.split(value, "/", parts: 2) do
        [mod_fun, arity_str] ->
          case Integer.parse(arity_str) do
            {int, ""} -> {mod_fun, int}
            _ -> {mod_fun, default_arity}
          end

        [mod_fun] ->
          {mod_fun, default_arity}
      end

    with {:ok, {module_str, fun_str}} <- split_module_function(mod_fun),
         {:ok, module} <- to_existing_module(module_str),
         {:ok, fun} <- to_existing_function(fun_str),
         {:ok, arity} <- resolve_arity(module, fun, arity) do
      {:ok, {module, fun, arity}}
    end
  end

  defp split_module_function(mod_fun) do
    cond do
      String.contains?(mod_fun, ":") ->
        case String.split(mod_fun, ":", parts: 2) do
          [module_str, fun_str] -> {:ok, {module_str, fun_str}}
          _ -> {:error, "Invalid function reference: #{mod_fun}"}
        end

      String.contains?(mod_fun, ".") ->
        parts = String.split(mod_fun, ".")
        {module_parts, [fun_str]} = Enum.split(parts, length(parts) - 1)
        {:ok, {Enum.join(module_parts, "."), fun_str}}

      true ->
        {:error, "Invalid function reference: #{mod_fun}"}
    end
  end

  defp to_existing_module(module_str) do
    module_name =
      if String.starts_with?(module_str, "Elixir.") do
        module_str
      else
        "Elixir." <> module_str
      end

    try do
      {:ok, String.to_existing_atom(module_name)}
    rescue
      ArgumentError -> {:error, "Unknown module: #{module_str}"}
    end
  end

  defp to_existing_function(fun_str) do
    {:ok, String.to_existing_atom(fun_str)}
  rescue
    ArgumentError -> {:error, "Unknown function: #{fun_str}"}
  end

  defp resolve_arity(_module, _fun, nil), do: {:error, "Function arity is required"}

  defp resolve_arity(module, fun, arity) when is_integer(arity) do
    if function_exported?(module, fun, arity) do
      {:ok, arity}
    else
      {:error, "Function #{inspect(module)}.#{fun}/#{arity} is not available"}
    end
  end
end
