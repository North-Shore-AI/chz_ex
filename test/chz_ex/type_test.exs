defmodule ChzEx.TypeTest do
  use ExUnit.Case, async: true

  alias ChzEx.Type

  describe "make_optional/1 and optional?/1" do
    test "wraps non-optional types" do
      assert Type.make_optional(:integer) == {:union, [:integer, nil]}
      assert Type.optional?({:union, [:integer, nil]})
    end

    test "keeps existing optional types" do
      assert Type.make_optional({:union, [:integer, nil]}) == {:union, [:integer, nil]}
      assert Type.optional?(nil)
    end
  end

  describe "type_repr/1" do
    test "formats primitive and module types" do
      assert Type.type_repr(:integer) == "integer"
      assert Type.type_repr(Date) == "Date"
    end

    test "formats composite types" do
      assert Type.type_repr({:array, :string}) == "[string]"
      assert Type.type_repr({:map, :string, :integer}) == "%{string => integer}"
      assert Type.type_repr({:union, [:integer, :string]}) == "integer | string"
      assert Type.type_repr({:literal, ["a", 1]}) == ~s(literal["a", 1])
      assert Type.type_repr({:function, 2}) == "function/2"
      assert Type.type_repr({:mapset, :integer}) == "MapSet[integer]"
    end
  end

  describe "is_instance?/2" do
    test "handles primitives and unions" do
      assert Type.is_instance?("value", :string)
      assert Type.is_instance?(1, :integer)
      assert Type.is_instance?(1, :float)
      assert Type.is_instance?(true, :boolean)
      refute Type.is_instance?("1", :integer)

      assert Type.is_instance?(nil, {:union, [:integer, nil]})
      assert Type.is_instance?("a", {:union, [:integer, :string]})
      refute Type.is_instance?(:atom, {:union, [:integer, :string]})
    end

    test "handles collections and literals" do
      assert Type.is_instance?([1, 2], {:array, :integer})
      refute Type.is_instance?([1, "2"], {:array, :integer})

      assert Type.is_instance?(%{"a" => 1}, {:map, :string, :integer})
      refute Type.is_instance?(%{a: 1}, {:map, :string, :integer})

      assert Type.is_instance?(MapSet.new([1, 2]), {:mapset, :integer})
      refute Type.is_instance?(MapSet.new(["1"]), {:mapset, :integer})

      assert Type.is_instance?("a", {:literal, ["a", "b"]})
      refute Type.is_instance?("c", {:literal, ["a", "b"]})
    end

    test "handles date/time and functions" do
      assert Type.is_instance?(~D[2024-01-02], Date)
      assert Type.is_instance?(~T[03:04:05], Time)
      assert Type.is_instance?(DateTime.utc_now(), DateTime)

      assert Type.is_instance?("/tmp", :path)

      assert Type.is_instance?(&Kernel.length/1, :function)
      assert Type.is_instance?(&Kernel.length/1, {:function, 1})
      refute Type.is_instance?(&Kernel.length/1, {:function, 2})
    end
  end
end
