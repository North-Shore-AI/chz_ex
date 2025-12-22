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

  @doc """
  Prefix all keys in a layer with a subpath.
  """
  def nest_subpath(layer, nil), do: layer

  def nest_subpath(layer, subpath) when is_binary(subpath) do
    args = prefix_keys(layer.args, subpath)
    qualified = prefix_keys(layer.qualified, subpath)
    wildcard = prefix_keys(layer.wildcard, subpath)

    patterns =
      wildcard
      |> Enum.map(fn {k, _} -> {k, Wildcard.to_regex(k)} end)
      |> Map.new()

    %{layer | args: args, qualified: qualified, wildcard: wildcard, patterns: patterns}
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

  defp prefix_keys(map, subpath) do
    Map.new(map, fn {k, v} -> {join_arg_path(subpath, k), v} end)
  end

  defp join_arg_path("", child), do: child

  defp join_arg_path(parent, child) do
    if String.starts_with?(child, ".") or child == "" do
      parent <> child
    else
      parent <> "." <> child
    end
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
    lookup = Map.get(map.consolidated_qualified, key)

    if ignore_wildcards and lookup != nil do
      build_result(map, key, lookup)
    else
      get_kv_with_wildcards(map, key, lookup)
    end
  end

  defp get_kv_with_wildcards(map, key, lookup) do
    lookup_idx = if lookup, do: elem(lookup, 1), else: -1

    wildcard_match =
      Enum.find(map.consolidated_wildcard, fn {_k, pattern, _v, idx} ->
        idx > lookup_idx and Regex.match?(pattern, key)
      end)

    cond do
      wildcard_match != nil ->
        {wk, _pattern, value, idx} = wildcard_match
        layer = Enum.at(map.layers, idx)
        %{key: wk, value: value, layer_index: idx, layer_name: layer.name}

      lookup != nil ->
        build_result(map, key, lookup)

      true ->
        nil
    end
  end

  defp build_result(map, key, {value, idx}) do
    layer = Enum.at(map.layers, idx)
    %{key: key, value: value, layer_index: idx, layer_name: layer.name}
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
    qualified_subpaths = get_qualified_subpaths(map, path, strict)
    wildcard_subpaths = get_wildcard_subpaths(map, path, strict)
    Enum.uniq(qualified_subpaths ++ wildcard_subpaths)
  end

  defp get_qualified_subpaths(map, path, strict) do
    path_dot = path <> "."

    map.consolidated_qualified_sorted
    |> Enum.filter(&qualified_path_matches?(&1, path, path_dot, strict))
    |> Enum.map(&extract_subpath(&1, path, path_dot))
  end

  defp qualified_path_matches?(k, path, _path_dot, false) when k == path, do: true
  defp qualified_path_matches?(k, "", _path_dot, _strict) when k != "", do: true
  defp qualified_path_matches?(k, _path, path_dot, _strict), do: String.starts_with?(k, path_dot)

  defp extract_subpath(k, path, _path_dot) when k == path, do: ""
  defp extract_subpath(k, "", _path_dot), do: k
  defp extract_subpath(k, _path, path_dot), do: String.replace_prefix(k, path_dot, "")

  defp get_wildcard_subpaths(map, path, strict) do
    Enum.flat_map(map.consolidated_wildcard, fn {wk, pattern, _v, _idx} ->
      wildcard_subpath(wk, pattern, path, strict)
    end)
  end

  defp wildcard_subpath(wk, _pattern, "", _strict), do: [wk]

  defp wildcard_subpath(wk, pattern, path, false) do
    if Regex.match?(pattern, path), do: [""], else: find_wildcard_suffix(wk, path)
  end

  defp wildcard_subpath(wk, _pattern, path, true), do: find_wildcard_suffix(wk, path)

  defp find_wildcard_suffix(wildcard_key, path) do
    literal = path |> String.split(".") |> List.last()

    case :binary.match(wildcard_key, literal) do
      :nomatch -> []
      {pos, len} -> extract_wildcard_suffix(wildcard_key, path, literal, pos, len)
    end
  end

  defp extract_wildcard_suffix(wildcard_key, path, literal, pos, len) do
    prefix = String.slice(wildcard_key, 0, pos + len)
    suffix = String.slice(wildcard_key, pos + len, String.length(wildcard_key))

    if String.ends_with?(prefix, literal) and Regex.match?(Wildcard.to_regex(prefix), path) do
      normalized_suffix = normalize_suffix(suffix)
      if normalized_suffix == "", do: [""], else: [normalized_suffix]
    else
      []
    end
  end

  defp normalize_suffix(suffix) do
    cond do
      String.starts_with?(suffix, "...") -> suffix
      String.starts_with?(suffix, ".") -> String.slice(suffix, 1..-1//1)
      true -> suffix
    end
  end
end
