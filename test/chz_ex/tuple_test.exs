defmodule ChzEx.TupleTest do
  use ExUnit.Case, async: true

  alias ChzEx.Blueprint

  defmodule Inner do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer)
    end
  end

  defmodule ConfigWithHeteroTuple do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      # Heterogeneous tuple: specific type at each position
      field(:coords, {:tuple, [:integer, :integer, :string]})
    end
  end

  defmodule ConfigWithNestedHeteroTuple do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      # Tuple containing an embedded schema
      field(:data, {:tuple, [:string, Inner]})
    end
  end

  describe "heterogeneous tuple type" do
    test "type_repr displays tuple with types" do
      type = {:tuple, [:integer, :string, :boolean]}
      assert ChzEx.Type.type_repr(type) == "{integer, string, boolean}"
    end

    test "is_instance? validates heterogeneous tuple" do
      type = {:tuple, [:integer, :string]}

      assert ChzEx.Type.is_instance?({1, "hello"}, type)
      refute ChzEx.Type.is_instance?({1, 2}, type)
      refute ChzEx.Type.is_instance?({1, "hello", "extra"}, type)
      refute ChzEx.Type.is_instance?({1}, type)
    end
  end

  describe "heterogeneous tuple in blueprint" do
    test "expands tuple fields as indexed parameters" do
      help = Blueprint.new(ConfigWithHeteroTuple) |> Blueprint.get_help()

      assert help =~ "coords.0"
      assert help =~ "coords.1"
      assert help =~ "coords.2"
    end

    test "constructs tuple from indexed parameters" do
      {:ok, result} =
        Blueprint.new(ConfigWithHeteroTuple)
        |> Blueprint.apply(%{
          "name" => "test",
          "coords.0" => 10,
          "coords.1" => 20,
          "coords.2" => "north"
        })
        |> Blueprint.make()

      assert result.name == "test"
      assert result.coords == {10, 20, "north"}
    end

    test "casts string values for tuple fields" do
      {:ok, result} =
        Blueprint.new(ConfigWithHeteroTuple)
        |> Blueprint.apply(%{
          "name" => "test",
          "coords.0" => %ChzEx.Blueprint.Castable{value: "10"},
          "coords.1" => %ChzEx.Blueprint.Castable{value: "20"},
          "coords.2" => %ChzEx.Blueprint.Castable{value: "north"}
        })
        |> Blueprint.make()

      assert result.coords == {10, 20, "north"}
    end

    test "returns error for missing tuple element" do
      assert {:error, %ChzEx.Error{type: :missing_required}} =
               Blueprint.new(ConfigWithHeteroTuple)
               |> Blueprint.apply(%{
                 "name" => "test",
                 "coords.0" => 10,
                 "coords.2" => "north"
                 # missing coords.1
               })
               |> Blueprint.make()
    end

    test "can pass complete tuple directly" do
      {:ok, result} =
        Blueprint.new(ConfigWithHeteroTuple)
        |> Blueprint.apply(%{
          "name" => "test",
          "coords" => {1, 2, "x"}
        })
        |> Blueprint.make()

      assert result.coords == {1, 2, "x"}
    end
  end
end
