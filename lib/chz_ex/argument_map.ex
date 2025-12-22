defmodule ChzEx.ArgumentMap do
  @moduledoc """
  Layered argument storage supporting wildcards.
  """

  alias ChzEx.Wildcard

  defstruct layers: [],
            consolidated: false,
            consolidated_qualified: %{},
            consolidated_qualified_sorted: [],
            consolidated_wildcard: []

  @type layer :: %{
          args: map(),
          name: String.t() | nil,
          qualified: map(),
          wildcard: map(),
          patterns: %{String.t() => Regex.t()}
        }

  @type t :: %__MODULE__{
          layers: [layer()],
          consolidated: boolean(),
          consolidated_qualified: %{String.t() => {any(), non_neg_integer()}},
          consolidated_qualified_sorted: [String.t()],
          consolidated_wildcard: [{String.t(), Regex.t(), any(), non_neg_integer()}]
        }

  @doc """
  Create a new argument map.
  """
  def new, do: %__MODULE__{}

  @doc """
  Add a layer of arguments.
  """
  def add_layer(%__MODULE__{} = map, args, name \\ nil) when is_map(args) do
    layer = build_layer(args, name)
    %{map | layers: map.layers ++ [layer], consolidated: false}
  end

  defp build_layer(args, name) do
    {qualified, wildcard} =
      args
      |> Enum.sort_by(fn {k, _} -> -String.length(k) end)
      |> Enum.split_with(fn {k, _} -> not String.contains?(k, "...") end)

    patterns =
      wildcard
      |> Enum.map(fn {k, _} -> {k, Wildcard.to_regex(k)} end)
      |> Map.new()

    %{
      args: args,
      name: name,
      qualified: Map.new(qualified),
      wildcard: Map.new(wildcard),
      patterns: patterns
    }
  end

  @doc """
  Consolidate layers for efficient lookup.
  """
  def consolidate(%__MODULE__{consolidated: true} = map), do: map

  def consolidate(%__MODULE__{layers: layers} = map) do
    consolidated_qualified =
      layers
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {layer, idx}, acc ->
        Enum.reduce(layer.qualified, acc, fn {k, v}, acc2 ->
          Map.put(acc2, k, {v, idx})
        end)
      end)

    consolidated_wildcard =
      layers
      |> Enum.with_index()
      |> Enum.flat_map(fn {layer, idx} ->
        Enum.map(layer.wildcard, fn {k, v} ->
          {k, layer.patterns[k], v, idx}
        end)
      end)
      |> Enum.reverse()

    %{
      map
      | consolidated: true,
        consolidated_qualified: consolidated_qualified,
        consolidated_qualified_sorted: consolidated_qualified |> Map.keys() |> Enum.sort(),
        consolidated_wildcard: consolidated_wildcard
    }
  end

  @doc """
  Look up a value by exact key, checking wildcards.
  """
  def get_kv(%__MODULE__{consolidated: false} = map, key) do
    map |> consolidate() |> get_kv(key)
  end

  def get_kv(%__MODULE__{} = map, key, opts \\ []) do
    ignore_wildcards = Keyword.get(opts, :ignore_wildcards, false)

    case Map.get(map.consolidated_qualified, key) do
      {value, idx} when ignore_wildcards ->
        layer = Enum.at(map.layers, idx)
        %{key: key, value: value, layer_index: idx, layer_name: layer.name}

      lookup ->
        lookup_idx = if lookup, do: elem(lookup, 1), else: -1

        wildcard_match =
          unless ignore_wildcards do
            Enum.find(map.consolidated_wildcard, fn {_k, pattern, _v, idx} ->
              idx > lookup_idx and Regex.match?(pattern, key)
            end)
          end

        case wildcard_match do
          {wk, _pattern, value, idx} ->
            layer = Enum.at(map.layers, idx)
            %{key: wk, value: value, layer_index: idx, layer_name: layer.name}

          nil when lookup != nil ->
            {value, idx} = lookup
            layer = Enum.at(map.layers, idx)
            %{key: key, value: value, layer_index: idx, layer_name: layer.name}

          nil ->
            nil
        end
    end
  end

  @doc """
  Find subpaths matching a path prefix.
  """
  def subpaths(map, path, opts \\ [])

  def subpaths(%__MODULE__{consolidated: false} = map, path, opts) do
    map |> consolidate() |> subpaths(path, opts)
  end

  def subpaths(%__MODULE__{} = map, path, opts) do
    strict = Keyword.get(opts, :strict, false)
    path_dot = path <> "."

    qualified_subpaths =
      map.consolidated_qualified_sorted
      |> Enum.filter(fn k ->
        cond do
          not strict and k == path -> true
          path == "" and k != "" -> true
          String.starts_with?(k, path_dot) -> true
          true -> false
        end
      end)
      |> Enum.map(fn k ->
        cond do
          k == path -> ""
          path == "" -> k
          true -> String.replace_prefix(k, path_dot, "")
        end
      end)

    wildcard_subpaths =
      map.consolidated_wildcard
      |> Enum.flat_map(fn {wk, pattern, _v, _idx} ->
        cond do
          path == "" ->
            [wk]

          not strict and Regex.match?(pattern, path) ->
            [""]

          true ->
            find_wildcard_suffix(wk, path)
        end
      end)

    (qualified_subpaths ++ wildcard_subpaths) |> Enum.uniq()
  end

  defp find_wildcard_suffix(wildcard_key, path) do
    literal = path |> String.split(".") |> List.last()

    case :binary.match(wildcard_key, literal) do
      :nomatch ->
        []

      {pos, len} ->
        prefix = String.slice(wildcard_key, 0, pos + len)
        suffix = String.slice(wildcard_key, pos + len, String.length(wildcard_key))

        if String.ends_with?(prefix, literal) and Regex.match?(Wildcard.to_regex(prefix), path) do
          suffix =
            cond do
              String.starts_with?(suffix, "...") -> suffix
              String.starts_with?(suffix, ".") -> String.slice(suffix, 1..-1//1)
              true -> suffix
            end

          if suffix == "", do: [""], else: [suffix]
        else
          []
        end
    end
  end
end
