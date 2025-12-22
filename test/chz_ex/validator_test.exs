defmodule ChzEx.ValidatorTest do
  use ExUnit.Case, async: true

  defmodule ValidationSchema do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer)
      field(:pattern, :string, default: "^[0-9]+$")
      field(:name, :string)
      field(:enabled, :boolean, default: false)
    end
  end

  defmodule RangeConfig do
    use ChzEx.Schema
    import ChzEx.Validate

    chz_schema do
      field(:min, :integer)
      field(:max, :integer)
    end

    validate :check_range do
      if struct.min > struct.max do
        {:error, :min, "must be <= max"}
      else
        :ok
      end
    end
  end

  defmodule ConsistencyChild do
    use ChzEx.Schema

    chz_schema do
      field(:seed, :integer)
    end
  end

  defmodule ConsistencyRoot do
    use ChzEx.Schema

    chz_schema do
      field(:seed, :integer)
      embeds_many(:children, ConsistencyChild)
    end
  end

  defmodule OverrideBase do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer, default: 1)
    end
  end

  defmodule OverrideChild do
    use ChzEx.Schema

    chz_parent(OverrideBase)

    chz_schema do
      field(:value, :integer, default: 2, validator: ChzEx.Validator.override?())
    end
  end

  defmodule OverrideChildBad do
    use ChzEx.Schema

    chz_parent(OverrideBase)

    chz_schema do
      field(:value, :string, default: "oops", validator: ChzEx.Validator.override?())
    end
  end

  defmodule OverrideChildMixin do
    use ChzEx.Schema
    use ChzEx.Validator.IsOverrideMixin

    chz_parent(OverrideBase)

    chz_schema do
      field(:value, :integer, default: 2)
    end
  end

  defmodule OverrideChildMixinBad do
    use ChzEx.Schema
    use ChzEx.Validator.IsOverrideMixin

    chz_parent(OverrideBase)

    chz_schema do
      field(:value, :string, default: "oops")
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

  describe "instancecheck/2 and instance_of/1" do
    test "validates instances against type specs" do
      struct = %ValidationSchema{value: 10}
      assert :ok = ChzEx.Validator.instancecheck(struct, :value)
      assert :ok = ChzEx.Validator.instance_of(:integer).(struct, :value)

      struct = %ValidationSchema{value: "bad"}
      assert {:error, _} = ChzEx.Validator.instancecheck(struct, :value)
      assert {:error, _} = ChzEx.Validator.instance_of(:integer).(struct, :value)
    end
  end

  describe "const_default/2" do
    test "passes when value matches default" do
      struct = %ValidationSchema{pattern: "^[0-9]+$"}
      assert :ok = ChzEx.Validator.const_default(struct, :pattern)
    end

    test "fails when value differs from default" do
      struct = %ValidationSchema{pattern: "abc"}
      assert {:error, _} = ChzEx.Validator.const_default(struct, :pattern)
    end
  end

  describe "in_range/2" do
    test "enforces inclusive bounds" do
      struct = %ValidationSchema{value: 5}
      assert :ok = ChzEx.Validator.in_range(0, 10).(struct, :value)

      struct = %ValidationSchema{value: -1}
      assert {:error, _} = ChzEx.Validator.in_range(0, 10).(struct, :value)
    end
  end

  describe "one_of/1" do
    test "allows only listed values" do
      struct = %ValidationSchema{value: 10}
      assert :ok = ChzEx.Validator.one_of([5, 10]).(struct, :value)

      struct = %ValidationSchema{value: 7}
      assert {:error, _} = ChzEx.Validator.one_of([5, 10]).(struct, :value)
    end
  end

  describe "matches/1" do
    test "validates regex matches" do
      struct = %ValidationSchema{name: "alpha"}
      assert :ok = ChzEx.Validator.matches(~r/^a/).(struct, :name)
      assert {:error, _} = ChzEx.Validator.matches(~r/^z/).(struct, :name)
    end
  end

  describe "not_empty/0" do
    test "rejects empty values" do
      struct = %ValidationSchema{name: ""}
      assert {:error, _} = ChzEx.Validator.not_empty().(struct, :name)

      struct = %ValidationSchema{name: "ok"}
      assert :ok = ChzEx.Validator.not_empty().(struct, :name)
    end
  end

  describe "all/1 and any/1" do
    test "combines validators" do
      struct = %ValidationSchema{value: 5}

      assert :ok =
               ChzEx.Validator.all([ChzEx.Validator.gt(0), ChzEx.Validator.lt(10)]).(
                 struct,
                 :value
               )

      assert {:error, _} =
               ChzEx.Validator.all([ChzEx.Validator.gt(0), ChzEx.Validator.lt(3)]).(
                 struct,
                 :value
               )

      assert :ok =
               ChzEx.Validator.any([ChzEx.Validator.lt(0), ChzEx.Validator.gt(3)]).(
                 struct,
                 :value
               )

      assert {:error, _} =
               ChzEx.Validator.any([ChzEx.Validator.lt(0), ChzEx.Validator.gt(10)]).(
                 struct,
                 :value
               )
    end
  end

  describe "when_field/3" do
    test "applies validator conditionally" do
      validator = ChzEx.Validator.when_field(:enabled, true, ChzEx.Validator.not_empty())

      struct = %ValidationSchema{enabled: true, name: ""}
      assert {:error, _} = validator.(struct, :name)

      struct = %ValidationSchema{enabled: false, name: ""}
      assert :ok = validator.(struct, :name)
    end
  end

  describe "check_field_consistency_in_tree/3" do
    test "detects mismatched values in nested configs" do
      config = %ConsistencyRoot{
        seed: 1,
        children: [%ConsistencyChild{seed: 1}, %ConsistencyChild{seed: 1}]
      }

      assert :ok = ChzEx.Validator.check_field_consistency_in_tree(config, [:seed])

      bad = %ConsistencyRoot{
        seed: 1,
        children: [%ConsistencyChild{seed: 2}]
      }

      assert {:error, msg} = ChzEx.Validator.check_field_consistency_in_tree(bad, [:seed])
      assert String.contains?(msg, "seed")
    end
  end

  describe "validate macro" do
    test "registers class-level validators" do
      changeset = RangeConfig.changeset(%RangeConfig{}, %{min: 5, max: 3})
      assert {"must be <= max", _} = changeset.errors[:min]
    end
  end

  describe "override?/1 and IsOverrideMixin" do
    test "accepts valid overrides" do
      changeset = OverrideChild.changeset(%OverrideChild{}, %{})
      assert changeset.valid?

      changeset = OverrideChildMixin.changeset(%OverrideChildMixin{}, %{})
      assert changeset.valid?
    end

    test "rejects invalid overrides" do
      changeset = OverrideChildBad.changeset(%OverrideChildBad{}, %{})
      assert {msg, _} = changeset.errors[:value]
      assert String.contains?(msg, "must be an instance of")

      changeset = OverrideChildMixinBad.changeset(%OverrideChildMixinBad{}, %{})
      assert {msg, _} = changeset.errors[:value]
      assert String.contains?(msg, "must be an instance of")
    end
  end
end
