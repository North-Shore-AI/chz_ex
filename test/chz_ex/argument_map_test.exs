defmodule ChzEx.ArgumentMapTest do
  use ExUnit.Case, async: true

  alias ChzEx.ArgumentMap

  describe "add_layer/3" do
    test "adds layer with args" do
      map = ArgumentMap.new() |> ArgumentMap.add_layer(%{"a" => 1})

      assert length(map.layers) == 1
      assert map.layers |> hd() |> Map.get(:args) == %{"a" => 1}
    end

    test "stores layer name" do
      map = ArgumentMap.new() |> ArgumentMap.add_layer(%{"a" => 1}, "layer1")

      assert map.layers |> hd() |> Map.get(:name) == "layer1"
    end
  end

  describe "consolidate/1" do
    test "consolidates qualified keys" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"a" => 1})
        |> ArgumentMap.consolidate()

      assert map.consolidated_qualified["a"] == {1, 0}
    end

    test "consolidates wildcard patterns" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"...a" => 1})
        |> ArgumentMap.consolidate()

      assert [{pattern, _regex, 1, 0}] = map.consolidated_wildcard
      assert pattern == "...a"
    end

    test "is idempotent" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"a" => 1})
        |> ArgumentMap.consolidate()
        |> ArgumentMap.consolidate()

      assert map.consolidated
      assert map.consolidated_qualified["a"] == {1, 0}
    end
  end

  describe "get_kv/2" do
    test "finds exact match" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"a" => 1}, "first")
        |> ArgumentMap.consolidate()

      result = ArgumentMap.get_kv(map, "a")
      assert result.value == 1
      assert result.layer_name == "first"
    end

    test "finds wildcard match" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"...a" => 2}, "wild")
        |> ArgumentMap.consolidate()

      result = ArgumentMap.get_kv(map, "x.a")
      assert result.value == 2
      assert result.key == "...a"
    end

    test "later layer overrides earlier" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"a" => 1}, "first")
        |> ArgumentMap.add_layer(%{"a" => 2}, "second")
        |> ArgumentMap.consolidate()

      result = ArgumentMap.get_kv(map, "a")
      assert result.value == 2
      assert result.layer_name == "second"
    end

    test "returns nil when not found" do
      map = ArgumentMap.new() |> ArgumentMap.add_layer(%{"a" => 1}) |> ArgumentMap.consolidate()

      assert ArgumentMap.get_kv(map, "missing") == nil
    end

    test "includes layer info in result" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"a" => 1}, "layer1")
        |> ArgumentMap.consolidate()

      result = ArgumentMap.get_kv(map, "a")
      assert result.layer_index == 0
      assert result.layer_name == "layer1"
    end
  end

  describe "subpaths/2" do
    test "finds qualified subpaths" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{
          "model.hidden" => 768,
          "model.layers" => 12,
          "data.path" => "/tmp"
        })
        |> ArgumentMap.consolidate()

      subpaths = ArgumentMap.subpaths(map, "model")
      assert "hidden" in subpaths
      assert "layers" in subpaths
      refute "path" in subpaths
    end

    test "finds wildcard subpaths" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"model...dim" => 1})
        |> ArgumentMap.consolidate()

      subpaths = ArgumentMap.subpaths(map, "model")
      assert "...dim" in subpaths
    end

    test "respects strict option" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"model" => 1, "model.hidden" => 2})
        |> ArgumentMap.consolidate()

      assert "" in ArgumentMap.subpaths(map, "model")
      refute "" in ArgumentMap.subpaths(map, "model", strict: true)
    end
  end

  describe "nest_subpath/2" do
    test "prefixes layer keys" do
      map =
        ArgumentMap.new()
        |> ArgumentMap.add_layer(%{"a" => 1, "...b" => 2})

      layer = hd(map.layers)
      nested = ArgumentMap.nest_subpath(layer, "root")

      assert nested.args["root.a"] == 1
      assert nested.args["root...b"] == 2
    end
  end
end
