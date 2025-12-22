defmodule ChzEx.CastTest do
  use ExUnit.Case, async: true

  alias ChzEx.Cast

  describe "try_cast/2" do
    test "casts to :string" do
      assert {:ok, "hello"} = Cast.try_cast("hello", :string)
    end

    test "casts to :integer" do
      assert {:ok, 42} = Cast.try_cast("42", :integer)
    end

    test "casts to :float" do
      assert {:ok, 3.14} = Cast.try_cast("3.14", :float)
    end

    test "casts to :boolean (true/false/t/f/1/0)" do
      assert {:ok, true} = Cast.try_cast("true", :boolean)
      assert {:ok, false} = Cast.try_cast("false", :boolean)
      assert {:ok, true} = Cast.try_cast("t", :boolean)
      assert {:ok, false} = Cast.try_cast("f", :boolean)
      assert {:ok, true} = Cast.try_cast("1", :boolean)
      assert {:ok, false} = Cast.try_cast("0", :boolean)
    end

    test "casts to {:array, type}" do
      assert {:ok, [1, 2, 3]} = Cast.try_cast("1,2,3", {:array, :integer})
    end

    test "casts to {:map, k, v}" do
      assert {:ok, %{"a" => 1, "b" => 2}} = Cast.try_cast("a:1,b:2", {:map, :string, :integer})
    end

    test "returns error for invalid" do
      assert {:error, _} = Cast.try_cast("nope", :integer)
    end
  end
end
