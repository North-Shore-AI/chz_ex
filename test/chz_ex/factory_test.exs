defmodule ChzEx.FactoryTest do
  use ExUnit.Case, async: false

  alias ChzEx.Factory.{Function, Standard, Subclass}

  defmodule SampleConfig do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer, default: 1)
    end
  end

  defmodule QualifiedFactory do
    def make, do: SampleConfig

    def nested, do: %{inner: SampleConfig}
    def nested_module, do: ChzEx.FactoryTest.QualifiedFactory.Nested
  end

  defmodule QualifiedFactory.Nested do
    def build, do: SampleConfig
  end

  defmodule FunctionProvider do
    def zero, do: SampleConfig
    def double(value), do: value * 2
  end

  defmodule Handler do
    @callback handle() :: atom()
    @callback name() :: String.t()
  end

  defmodule Alpha do
    @behaviour Handler

    def handle, do: :alpha
    def name, do: "alpha"
  end

  defmodule Beta do
    @behaviour Handler

    def handle, do: :beta
    def name, do: "beta"
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

    test "resolves aliases" do
      :ok = ChzEx.Registry.register(:factories, "sample", SampleConfig)

      factory =
        Standard.new(
          annotation: SampleConfig,
          namespace: :factories,
          aliases: %{"alias" => "sample"}
        )

      assert {:ok, SampleConfig} = Standard.from_string(factory, "alias")
    end

    test "resolves nested module attribute paths" do
      :ok = ChzEx.Registry.register_module(QualifiedFactory)
      factory = Standard.new(annotation: SampleConfig)

      assert {:ok, SampleConfig} =
               Standard.from_string(factory, "ChzEx.FactoryTest.QualifiedFactory:nested.inner")

      assert {:ok, SampleConfig} =
               Standard.from_string(
                 factory,
                 "ChzEx.FactoryTest.QualifiedFactory:nested_module.build"
               )
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

  describe "Standard.registered_factories/1" do
    test "returns namespace map including aliases" do
      :ok = ChzEx.Registry.register(:factories, "sample", SampleConfig)

      factory =
        Standard.new(
          annotation: SampleConfig,
          namespace: :factories,
          aliases: %{"alias" => "sample"}
        )

      factories = Standard.registered_factories(factory)
      assert factories["sample"] == SampleConfig
      assert factories["alias"] == SampleConfig
    end
  end

  describe "Standard.serialize/2" do
    test "serializes to a registered name" do
      :ok = ChzEx.Registry.register(:factories, "sample", SampleConfig)
      factory = Standard.new(annotation: SampleConfig, namespace: :factories)

      assert {:ok, "sample"} = Standard.serialize(factory, SampleConfig)
    end
  end

  describe "Subclass meta-factory" do
    test "resolves registered modules by short name" do
      :ok = ChzEx.Registry.register_module(Alpha)
      :ok = ChzEx.Registry.register_module(Beta)

      factory = Subclass.new(annotation: Handler)
      assert {:ok, Alpha} = Subclass.from_string(factory, "Alpha")
      assert {:ok, Beta} = Subclass.from_string(factory, "Beta")
    end

    test "uses discriminator functions" do
      :ok = ChzEx.Registry.register_module(Alpha)
      :ok = ChzEx.Registry.register_module(Beta)

      factory = Subclass.new(annotation: Handler, discriminator: :name)
      assert {:ok, Alpha} = Subclass.from_string(factory, "alpha")
      assert {:ok, Beta} = Subclass.from_string(factory, "beta")
    end
  end

  describe "Function meta-factory" do
    test "resolves functions by module and arity" do
      :ok = ChzEx.Registry.register_module(FunctionProvider)
      factory = Function.new(annotation: :integer)

      assert {:ok, fun} =
               Function.from_string(factory, "ChzEx.FactoryTest.FunctionProvider:double/1")

      assert fun.(3) == 6
    end

    test "resolves functions from default module" do
      factory = Function.new(annotation: :integer, default_module: FunctionProvider)
      assert {:ok, fun} = Function.from_string(factory, "double/1")
      assert fun.(4) == 8
    end
  end
end
