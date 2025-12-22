defmodule ChzEx.MungerTest do
  use ExUnit.Case, async: true

  describe "if_none/1" do
    test "replaces nil with function result" do
      munger = ChzEx.Munger.if_none(fn struct -> struct.name <> "_suffix" end)
      assert munger.(nil, %{name: "test"}) == "test_suffix"
    end

    test "keeps non-nil value" do
      munger = ChzEx.Munger.if_none(fn _ -> "ignored" end)
      assert munger.("value", %{name: "test"}) == "value"
    end
  end

  describe "attr_if_none/1" do
    test "replaces nil with other attr" do
      munger = ChzEx.Munger.attr_if_none(:name)
      assert munger.(nil, %{name: "test"}) == "test"
    end

    test "keeps non-nil value" do
      munger = ChzEx.Munger.attr_if_none(:name)
      assert munger.("value", %{name: "test"}) == "value"
    end
  end

  describe "from_function/1" do
    test "wraps 2-arity function" do
      fun = fn struct, value -> "#{struct.name}:#{value}" end
      munger = ChzEx.Munger.from_function(fun)

      assert munger.("x", %{name: "test"}) == "test:x"
    end
  end
end
