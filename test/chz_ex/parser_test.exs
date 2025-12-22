defmodule ChzEx.ParserTest do
  use ExUnit.Case, async: true

  alias ChzEx.Blueprint.{Castable, Reference}
  alias ChzEx.Parser

  describe "parse/1" do
    test "parses key=value" do
      assert {:ok, %{"name" => %Castable{value: "test"}}} = Parser.parse(["name=test"])
    end

    test "parses multiple arguments" do
      assert {:ok, result} = Parser.parse(["a=1", "b=2"])
      assert result["a"] == %Castable{value: "1"}
      assert result["b"] == %Castable{value: "2"}
    end

    test "parses dotted paths" do
      assert {:ok, %{"model.layers" => %Castable{value: "12"}}} =
               Parser.parse(["model.layers=12"])
    end

    test "handles equals in value" do
      assert {:ok, %{"expr" => %Castable{value: "a=b"}}} = Parser.parse(["expr=a=b"])
    end

    test "errors on missing equals" do
      assert {:error, _} = Parser.parse(["noequals"])
    end

    test "detects --help flag" do
      assert {:ok, args} = Parser.parse(["--help"])
      assert Parser.help_requested?(args)
    end

    test "supports allow_hyphens option" do
      assert {:ok, %{"name" => %Castable{value: "test"}}} =
               Parser.parse(["--name=test"], allow_hyphens: true)
    end
  end

  describe "parse_arg/1" do
    test "returns Castable for normal values" do
      assert {:ok, "a", %Castable{value: "1"}} = Parser.parse_arg("a=1")
    end

    test "returns Reference for @= syntax" do
      assert {:ok, "a", %Reference{ref: "b"}} = Parser.parse_arg("a@=b")
    end
  end

  describe "help_requested?/1" do
    test "detects --help" do
      assert Parser.help_requested?(["--help"])
    end

    test "detects -h" do
      assert Parser.help_requested?(["-h"])
    end

    test "detects help" do
      assert Parser.help_requested?(["help"])
    end
  end
end
