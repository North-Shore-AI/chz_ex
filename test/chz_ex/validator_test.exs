defmodule ChzEx.ValidatorTest do
  use ExUnit.Case, async: true

  defmodule ValidationSchema do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer)
      field(:pattern, :string, default: "^[0-9]+$")
    end
  end

  describe "typecheck/2" do
    test "passes for correct type" do
      struct = %ValidationSchema{value: 10}
      assert :ok = ChzEx.Validator.typecheck(struct, :value)
    end

    test "fails for wrong type" do
      struct = %ValidationSchema{value: "bad"}
      assert {:error, _} = ChzEx.Validator.typecheck(struct, :value)
    end
  end

  describe "gt/1" do
    test "passes when greater" do
      struct = %ValidationSchema{value: 10}
      assert :ok = ChzEx.Validator.gt(5).(struct, :value)
    end

    test "fails when not greater" do
      struct = %ValidationSchema{value: 1}
      assert {:error, _} = ChzEx.Validator.gt(5).(struct, :value)
    end
  end

  describe "lt/1, ge/1, le/1" do
    test "comparison validators work" do
      struct = %ValidationSchema{value: 10}
      assert :ok = ChzEx.Validator.lt(11).(struct, :value)
      assert :ok = ChzEx.Validator.ge(10).(struct, :value)
      assert :ok = ChzEx.Validator.le(10).(struct, :value)

      assert {:error, _} = ChzEx.Validator.lt(5).(struct, :value)
      assert {:error, _} = ChzEx.Validator.ge(11).(struct, :value)
      assert {:error, _} = ChzEx.Validator.le(9).(struct, :value)
    end
  end

  describe "valid_regex/2" do
    test "passes for valid regex" do
      struct = %ValidationSchema{pattern: "^[0-9]+$"}
      assert :ok = ChzEx.Validator.valid_regex(struct, :pattern)
    end

    test "fails for invalid regex" do
      struct = %ValidationSchema{pattern: "("}
      assert {:error, _} = ChzEx.Validator.valid_regex(struct, :pattern)
    end
  end

  describe "for_all_fields/1" do
    test "applies validator to all fields" do
      struct = %ValidationSchema{value: 10}

      validator =
        ChzEx.Validator.for_all_fields(fn _struct, _field ->
          :ok
        end)

      assert :ok = validator.(struct)
    end
  end
end
