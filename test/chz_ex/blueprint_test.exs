defmodule ChzEx.BlueprintTest do
  use ExUnit.Case, async: true

  alias ChzEx.Blueprint

  defmodule InnerConfig do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer, default: 10, doc: "Inner value")
    end
  end

  defmodule SimpleConfig do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string, doc: "Config name")
      field(:count, :integer, default: 1, doc: "Count")
      field(:enabled, :boolean, default: true, doc: "Enabled flag")
    end
  end

  defmodule NestedConfig do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string, doc: "Config name")
      embeds_one(:inner, InnerConfig, doc: "Inner config")
    end
  end

  describe "new/1" do
    test "creates blueprint for chz module" do
      bp = Blueprint.new(SimpleConfig)
      assert bp.target == SimpleConfig
    end

    test "errors for non-chz module" do
      assert_raise ArgumentError, fn ->
        Blueprint.new(String)
      end
    end
  end

  describe "apply/3" do
    test "adds argument layer" do
      bp =
        Blueprint.new(SimpleConfig)
        |> Blueprint.apply(%{"name" => "test"})

      assert length(bp.arg_map.layers) == 1
    end

    test "supports layer_name option" do
      bp =
        Blueprint.new(SimpleConfig)
        |> Blueprint.apply(%{"name" => "test"}, layer_name: "preset")

      assert hd(bp.arg_map.layers).name == "preset"
    end

    test "supports subpath option" do
      bp =
        Blueprint.new(NestedConfig)
        |> Blueprint.apply(%{"value" => 12}, subpath: "inner")

      assert hd(bp.arg_map.layers).args["inner.value"] == 12
    end

    test "raises on extraneous args when strict" do
      assert_raise ChzEx.Error, fn ->
        Blueprint.new(SimpleConfig)
        |> Blueprint.apply(%{"unknown" => 1}, strict: true)
      end
    end
  end

  describe "apply_from_argv/2" do
    test "parses and applies argv" do
      {:ok, bp} = Blueprint.new(SimpleConfig) |> Blueprint.apply_from_argv(["name=test"])

      assert hd(bp.arg_map.layers).args["name"].value == "test"
    end

    test "raises HelpError on --help" do
      assert_raise ChzEx.HelpError, fn ->
        Blueprint.new(SimpleConfig) |> Blueprint.apply_from_argv(["--help"])
      end
    end

    test "returns error for extraneous args when strict" do
      assert {:error, %ChzEx.Error{type: :extraneous}} =
               Blueprint.new(SimpleConfig)
               |> Blueprint.apply_from_argv(["unknown=1"], strict: true)
    end
  end

  describe "make/1" do
    test "constructs simple struct" do
      {:ok, result} =
        Blueprint.new(SimpleConfig)
        |> Blueprint.apply(%{"name" => "test", "count" => 2})
        |> Blueprint.make()

      assert result.name == "test"
      assert result.count == 2
    end

    test "applies defaults" do
      {:ok, result} =
        Blueprint.new(SimpleConfig)
        |> Blueprint.apply(%{"name" => "test"})
        |> Blueprint.make()

      assert result.count == 1
      assert result.enabled == true
    end

    test "casts string values" do
      {:ok, result} =
        Blueprint.new(SimpleConfig)
        |> Blueprint.apply(%{
          "name" => %ChzEx.Blueprint.Castable{value: "test"},
          "count" => %ChzEx.Blueprint.Castable{value: "3"}
        })
        |> Blueprint.make()

      assert result.count == 3
      assert result.name == "test"
    end

    test "returns error for missing required" do
      assert {:error, %ChzEx.Error{type: :missing_required, path: "name"}} =
               Blueprint.new(SimpleConfig) |> Blueprint.make()
    end

    test "returns error for extraneous args" do
      assert {:error, %ChzEx.Error{type: :extraneous, path: "unknown"}} =
               Blueprint.new(SimpleConfig)
               |> Blueprint.apply(%{"name" => "test", "unknown" => 1})
               |> Blueprint.make()
    end
  end

  describe "make_from_argv/2" do
    test "full pipeline from argv to struct" do
      {:ok, result} =
        Blueprint.new(SimpleConfig) |> Blueprint.make_from_argv(["name=test", "count=2"])

      assert result.name == "test"
      assert result.count == 2
    end
  end

  describe "get_help/2" do
    test "includes all parameters" do
      help = Blueprint.new(NestedConfig) |> Blueprint.get_help()

      assert help =~ "name"
      assert help =~ "inner"
      assert help =~ "inner.value"
    end

    test "shows defaults" do
      help = Blueprint.new(SimpleConfig) |> Blueprint.get_help()

      assert help =~ "1"
      assert help =~ "true"
    end

    test "shows types" do
      help = Blueprint.new(SimpleConfig) |> Blueprint.get_help()

      assert help =~ "string"
      assert help =~ "integer"
      assert help =~ "boolean"
    end

    test "shows doc strings" do
      help = Blueprint.new(SimpleConfig) |> Blueprint.get_help()

      assert help =~ "Config name"
      assert help =~ "Enabled flag"
    end
  end
end
