defmodule ChzEx.FactoryTest do
  use ExUnit.Case, async: false

  alias ChzEx.Factory.Standard

  defmodule SampleConfig do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer, default: 1)
    end
  end

  defmodule QualifiedFactory do
    def make, do: SampleConfig
  end

  setup do
    start_supervised!(ChzEx.Registry)
    :ok
  end

  describe "Standard.unspecified_factory/1" do
    test "returns module for chz annotation" do
      factory = Standard.new(annotation: SampleConfig)
      assert SampleConfig == Standard.unspecified_factory(factory)
    end

    test "returns explicit unspecified" do
      factory = Standard.new(annotation: SampleConfig, unspecified: QualifiedFactory)
      assert QualifiedFactory == Standard.unspecified_factory(factory)
    end

    test "returns nil for non-instantiable" do
      factory = Standard.new(annotation: :integer)
      assert nil == Standard.unspecified_factory(factory)
    end
  end

  describe "Standard.from_string/2" do
    test "resolves short name from registry" do
      :ok = ChzEx.Registry.register(:factories, "sample", SampleConfig)
      factory = Standard.new(annotation: SampleConfig, namespace: :factories)

      assert {:ok, SampleConfig} = Standard.from_string(factory, "sample")
    end

    test "resolves fully qualified module:attr" do
      :ok = ChzEx.Registry.register_module(QualifiedFactory)
      factory = Standard.new(annotation: SampleConfig)

      assert {:ok, SampleConfig} =
               Standard.from_string(factory, "ChzEx.FactoryTest.QualifiedFactory:make")
    end

    test "errors for unknown" do
      factory = Standard.new(annotation: SampleConfig, namespace: :factories)
      assert {:error, _} = Standard.from_string(factory, "missing")
    end
  end

  describe "Standard.perform_cast/2" do
    test "casts to annotation type" do
      factory = Standard.new(annotation: :integer)
      assert {:ok, 3} = Standard.perform_cast(factory, "3")
    end
  end
end
