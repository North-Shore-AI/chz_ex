defmodule ChzEx.LazyTest do
  use ExUnit.Case, async: true

  alias ChzEx.Lazy
  alias ChzEx.Lazy.{ParamRef, Thunk, Value}

  describe "evaluate/1" do
    test "evaluates Value" do
      mapping = %{
        "" => %Value{value: 123}
      }

      assert Lazy.evaluate(mapping) == 123
    end

    test "resolves ParamRef" do
      mapping = %{
        "" => %ParamRef{ref: "a"},
        "a" => %Value{value: 42}
      }

      assert Lazy.evaluate(mapping) == 42
    end

    test "evaluates Thunk with resolved kwargs" do
      mapping = %{
        "" => %Thunk{
          fn: fn %{x: x, y: y} -> x + y end,
          kwargs: %{x: %ParamRef{ref: "a"}, y: %ParamRef{ref: "b"}}
        },
        "a" => %Value{value: 1},
        "b" => %Value{value: 2}
      }

      assert Lazy.evaluate(mapping) == 3
    end

    test "caches resolved values" do
      caller = self()

      mapping = %{
        "" => %Thunk{
          fn: fn %{x: x, y: y} -> x + y end,
          kwargs: %{x: %ParamRef{ref: "a"}, y: %ParamRef{ref: "a"}}
        },
        "a" => %Thunk{
          fn: fn _ ->
            send(caller, :called)
            2
          end,
          kwargs: %{}
        }
      }

      assert Lazy.evaluate(mapping) == 4
      assert_receive :called
      refute_receive :called, 10
    end

    test "detects cycles" do
      mapping = %{
        "" => %ParamRef{ref: "a"},
        "a" => %ParamRef{ref: "b"},
        "b" => %ParamRef{ref: "a"}
      }

      assert_raise RuntimeError, ~r/cyclic reference/i, fn ->
        Lazy.evaluate(mapping)
      end
    end

    test "requires root entry" do
      assert_raise ArgumentError, fn ->
        Lazy.evaluate(%{"a" => %Value{value: 1}})
      end
    end
  end

  describe "check_reference_targets/2" do
    test "returns :ok for valid refs" do
      mapping = %{
        "" => %ParamRef{ref: "a"},
        "a" => %Value{value: 1}
      }

      assert :ok = Lazy.check_reference_targets(mapping, ["", "a"])
    end

    test "returns error with suggestions for invalid" do
      mapping = %{
        "" => %ParamRef{ref: "missing"},
        "a" => %Value{value: 1}
      }

      assert {:error, %ChzEx.Error{message: msg}} =
               Lazy.check_reference_targets(mapping, ["", "a"])

      assert msg =~ "missing"
      assert msg =~ "Did you mean"
    end
  end
end
