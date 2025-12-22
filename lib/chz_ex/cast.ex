defmodule ChzEx.Cast do
  @moduledoc """
  Type-aware casting from strings for CLI parsing.
  """

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

  defp do_cast(value, {:array, inner_type}) do
    values = String.split(value, ",", trim: true)
    results = Enum.map(values, &do_cast(&1, inner_type))

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, v} -> v end)}
    else
      {:error, "Cannot cast #{inspect(value)} to array of #{inspect(inner_type)}"}
    end
  end

  defp do_cast(value, {:map, key_type, value_type}) do
    if value == "" do
      {:ok, %{}}
    else
      pairs = String.split(value, ",", trim: true)

      parsed =
        Enum.map(pairs, fn pair ->
          case String.split(pair, ":", parts: 2) do
            [k, v] -> {do_cast(k, key_type), do_cast(v, value_type)}
            _ -> {:error, "Cannot cast #{inspect(value)} to map"}
          end
        end)

      if Enum.all?(parsed, &match?({{:ok, _}, {:ok, _}}, &1)) do
        map =
          Enum.map(parsed, fn {{:ok, k}, {:ok, v}} -> {k, v} end)
          |> Map.new()

        {:ok, map}
      else
        {:error, "Cannot cast #{inspect(value)} to map"}
      end
    end
  end

  defp do_cast(value, module) when is_atom(module) do
    if function_exported?(module, :__chz_cast__, 1) do
      module.__chz_cast__(value)
    else
      {:error, "Cannot cast #{inspect(value)} to #{inspect(module)}"}
    end
  end

  defp do_cast(value, _type) do
    {:error, "Cannot cast #{inspect(value)}"}
  end
end
