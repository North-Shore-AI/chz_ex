defmodule ChzEx.Parser do
  @moduledoc """
  Parse CLI arguments into blueprint argument maps.
  """

  alias ChzEx.Blueprint.{Castable, Reference}

  @help_flags ["--help", "-h", "help"]

  @doc """
  Parse a list of "key=value" strings into a map.
  """
  @spec parse([String.t()], Keyword.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(argv, opts \\ []) when is_list(argv) do
    allow_hyphens = Keyword.get(opts, :allow_hyphens, false)

    argv
    |> Enum.reject(&(&1 == "--"))
    |> Enum.reduce_while({:ok, %{}}, fn arg, {:ok, acc} ->
      parse_arg_into_acc(arg, acc, allow_hyphens)
    end)
  end

  defp parse_arg_into_acc(arg, acc, _allow_hyphens) when arg in @help_flags do
    {:cont, {:ok, Map.put(acc, :__help__, true)}}
  end

  defp parse_arg_into_acc(arg, acc, allow_hyphens) do
    case parse_arg(arg, allow_hyphens: allow_hyphens) do
      {:ok, key, value} ->
        {:cont, {:ok, Map.put(acc, key, value)}}

      {:error, _} = err ->
        {:halt, err}
    end
  end

  @doc """
  Parse a single argument string.
  """
  @spec parse_arg(String.t(), Keyword.t()) ::
          {:ok, String.t(), Castable.t() | Reference.t()} | {:error, String.t()}
  def parse_arg(arg, opts \\ []) when is_binary(arg) do
    allow_hyphens = Keyword.get(opts, :allow_hyphens, false)

    case String.split(arg, "=", parts: 2) do
      [key, value] ->
        key = maybe_strip_hyphens(key, allow_hyphens)

        if String.ends_with?(key, "@") do
          ref_key = String.trim_trailing(key, "@")
          {:ok, ref_key, %Reference{ref: value}}
        else
          {:ok, key, %Castable{value: value}}
        end

      [_no_equals] ->
        {:error, "Invalid argument #{inspect(arg)}. Arguments must be in key=value format."}
    end
  end

  @doc """
  Check if help was requested.
  """
  def help_requested?(args) when is_map(args), do: Map.get(args, :__help__, false)
  def help_requested?(argv) when is_list(argv), do: Enum.any?(argv, &(&1 in @help_flags))

  defp maybe_strip_hyphens(key, true), do: String.trim_leading(key, "-")
  defp maybe_strip_hyphens(key, false), do: key
end
