defmodule ChzEx.ErrorTest do
  use ExUnit.Case, async: true

  alias ChzEx.Error

  describe "error formatting" do
    test "formats missing_required error" do
      error = %Error{type: :missing_required, path: "name"}
      assert Error.format(error) == "Missing required argument: name"
    end

    test "formats extraneous error with suggestions" do
      error = %Error{type: :extraneous, path: "bad", suggestions: ["good"]}
      assert Error.format(error) =~ "Unknown argument: bad"
      assert Error.format(error) =~ "Did you mean: good"
    end

    test "formats validation_error" do
      error = %Error{type: :validation_error, path: "value", message: "too high"}
      assert Error.format(error) == "Validation error for value: too high"
    end

    test "formats cast_error" do
      error = %Error{type: :cast_error, path: "count", message: "invalid"}
      assert Error.format(error) == "Could not cast count: invalid"
    end

    test "formats cycle error" do
      error = %Error{type: :cycle, path: "a", message: "a -> b -> a"}
      assert Error.format(error) == "Detected cyclic reference: a -> b -> a"
    end
  end
end
