defmodule ChzEx.FieldTest do
  use ExUnit.Case, async: true

  alias ChzEx.Field

  describe "new/3" do
    test "creates field with name and type" do
      field = Field.new(:name, :string)

      assert field.name == :name
      assert field.type == :string
      assert field.raw_type == :string
    end

    test "sets default value" do
      field = Field.new(:value, :integer, default: 10)

      assert field.default == 10
      assert field.default_factory == nil
    end

    test "sets default_factory" do
      factory = fn -> 42 end
      field = Field.new(:value, :integer, default_factory: factory)

      assert field.default == nil
      assert field.default_factory == factory
    end

    test "rejects both default and default_factory" do
      assert_raise ArgumentError, fn ->
        Field.new(:value, :integer, default: 1, default_factory: fn -> 2 end)
      end
    end

    test "normalizes validators to list" do
      validator = fn _struct, _attr -> :ok end

      field = Field.new(:name, :string, validator: validator)
      assert field.validators == [validator]

      field2 = Field.new(:name, :string, validators: [validator])
      assert field2.validators == [validator]
    end

    test "accepts munger function" do
      munger = fn value, _struct -> value end
      field = Field.new(:name, :string, munger: munger)

      assert field.munger == munger
    end

    test "stores metadata" do
      field = Field.new(:name, :string, metadata: %{source: "test"})

      assert field.metadata == %{source: "test"}
    end
  end

  describe "has_default?/1" do
    test "false when no default" do
      field = Field.new(:name, :string)
      refute Field.has_default?(field)
    end

    test "true with static default" do
      field = Field.new(:name, :string, default: "x")
      assert Field.has_default?(field)
    end

    test "true with default_factory" do
      field = Field.new(:name, :string, default_factory: fn -> "x" end)
      assert Field.has_default?(field)
    end
  end

  describe "get_default/1" do
    test "returns static default" do
      field = Field.new(:name, :string, default: "x")
      assert Field.get_default(field) == "x"
    end

    test "calls default_factory" do
      field = Field.new(:name, :string, default_factory: fn -> "x" end)
      assert Field.get_default(field) == "x"
    end

    test "returns nil when no default" do
      field = Field.new(:name, :string)
      assert Field.get_default(field) == nil
    end
  end

  describe "required?/1" do
    test "true when no default" do
      field = Field.new(:name, :string)
      assert Field.required?(field)
    end

    test "false when has default" do
      field = Field.new(:name, :string, default: "x")
      refute Field.required?(field)
    end
  end
end
