defmodule ChzEx.Traverse do
  @moduledoc """
  Traversal utilities for ChzEx structs.
  """

  alias ChzEx.Schema

  @doc """
  Stream `{path, value}` pairs for all nested values in a ChzEx struct.
  """
  @spec traverse(any(), String.t()) :: Enumerable.t()
  def traverse(struct, path \\ "") do
    Stream.unfold([{path, struct}], fn
      [] ->
        nil

      [{current_path, value} | rest] ->
        next = child_entries(value, current_path) ++ rest
        {{current_path, value}, next}
    end)
  end

  defp child_entries(value, path) do
    cond do
      Schema.chz?(value) ->
        value.__struct__.__chz_fields__()
        |> Enum.map(fn {name, _field} ->
          field_path = join_path(path, Atom.to_string(name))
          {field_path, Map.get(value, name)}
        end)

      is_map(value) ->
        Enum.map(value, fn {key, val} ->
          {join_path(path, to_path_segment(key)), val}
        end)

      is_list(value) ->
        value
        |> Enum.with_index()
        |> Enum.map(fn {val, index} ->
          {join_path(path, Integer.to_string(index)), val}
        end)

      is_tuple(value) ->
        value
        |> Tuple.to_list()
        |> Enum.with_index()
        |> Enum.map(fn {val, index} ->
          {join_path(path, Integer.to_string(index)), val}
        end)

      true ->
        []
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
