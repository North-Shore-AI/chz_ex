defmodule ChzEx.CastTest do
  use ExUnit.Case, async: true

  alias ChzEx.{Cast, Type}

  defmodule EnumStrings do
    def __chz_enum_values__, do: ["foo", "bar"]
  end

  defmodule EnumAtoms do
    def __chz_enum_values__, do: [:foo, :bar]
  end

  describe "try_cast/2" do
    test "casts unions and optionals" do
      assert {:ok, 1} = Cast.try_cast("1", {:union, [:integer, :string]})
      assert {:ok, "abc"} = Cast.try_cast("abc", {:union, [:integer, :string]})
      assert {:ok, nil} = Cast.try_cast("None", Type.make_optional(:integer))
    end

    test "casts date and time types" do
      assert {:ok, %Date{}} = Cast.try_cast("2024-01-02", Date)
      assert {:ok, %Time{}} = Cast.try_cast("03:04:05", Time)
      assert {:ok, %DateTime{}} = Cast.try_cast("2024-01-02T03:04:05Z", DateTime)
    end

    test "casts paths" do
      assert {:ok, expanded} = Cast.try_cast("~/tmp", :path)
      assert expanded == Path.expand("~/tmp")
    end

    test "casts literals and enums" do
      assert {:ok, 1} = Cast.try_cast("1", {:literal, [1, "a"]})
      assert {:ok, "a"} = Cast.try_cast("a", {:literal, [1, "a"]})
      assert {:error, _} = Cast.try_cast("b", {:literal, [1, "a"]})

      assert {:ok, "foo"} = Cast.try_cast("foo", EnumStrings)
      assert {:error, _} = Cast.try_cast("baz", EnumStrings)

      assert {:ok, :foo} = Cast.try_cast("foo", EnumAtoms)
      assert {:error, _} = Cast.try_cast("baz", EnumAtoms)
    end

    test "casts function references" do
      assert {:ok, fun} = Cast.try_cast("String.split/2", {:function, 2})
      assert fun.("a,b", ",") == ["a", "b"]

      assert {:ok, fun2} = Cast.try_cast("String.split", {:function, 2})
      assert fun2.("a,b", ",") == ["a", "b"]
    end

    test "casts binaries and mapsets" do
      assert {:ok, <<10, 11>>} = Cast.try_cast("0A0B", :binary)
      assert {:ok, "raw"} = Cast.try_cast("raw", :binary)

      assert {:ok, set} = Cast.try_cast("1,2,3", {:mapset, :integer})
      assert MapSet.equal?(set, MapSet.new([1, 2, 3]))
    end
  end
end
