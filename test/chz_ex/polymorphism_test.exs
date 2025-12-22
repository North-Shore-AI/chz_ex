defmodule ChzEx.PolymorphismTest do
  use ExUnit.Case, async: false

  defmodule BaseOptimizer do
    use ChzEx.Schema

    chz_schema do
      field(:lr, :float, default: 0.001)
    end
  end

  defmodule Adam do
    use ChzEx.Schema

    chz_schema do
      field(:lr, :float, default: 0.001)
      field(:beta1, :float, default: 0.9)
      field(:beta2, :float, default: 0.999)
    end
  end

  defmodule SGD do
    use ChzEx.Schema

    chz_schema do
      field(:lr, :float, default: 0.01)
      field(:momentum, :float, default: 0.9)
    end
  end

  defmodule Config do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)

      embeds_one(:optimizer, BaseOptimizer,
        polymorphic: true,
        namespace: :test_optimizers,
        blueprint_unspecified: Adam
      )
    end
  end

  defmodule ListConfig do
    use ChzEx.Schema

    chz_schema do
      embeds_many(:optimizers, BaseOptimizer,
        polymorphic: true,
        namespace: :test_optimizers,
        blueprint_unspecified: Adam
      )
    end
  end

  setup do
    start_supervised!(ChzEx.Registry)
    ChzEx.Registry.register(:test_optimizers, "adam", Adam)
    ChzEx.Registry.register(:test_optimizers, "sgd", SGD)
    :ok
  end

  describe "polymorphic embeds" do
    test "uses default factory when unspecified" do
      {:ok, config} =
        ChzEx.entrypoint(Config, [
          "name=test",
          "optimizer.lr=0.0001"
        ])

      assert config.optimizer.__struct__ == Adam
      assert config.optimizer.lr == 0.0001
      assert config.optimizer.beta1 == 0.9
    end

    test "resolves factory from string" do
      {:ok, config} =
        ChzEx.entrypoint(Config, [
          "name=test",
          "optimizer=sgd",
          "optimizer.momentum=0.99"
        ])

      assert config.optimizer.__struct__ == SGD
      assert config.optimizer.momentum == 0.99
    end

    test "passes subpath args to factory" do
      {:ok, config} =
        ChzEx.entrypoint(Config, [
          "name=test",
          "optimizer=adam",
          "optimizer.beta1=0.95"
        ])

      assert config.optimizer.__struct__ == Adam
      assert config.optimizer.beta1 == 0.95
    end

    test "errors for unknown factory" do
      assert {:error, %ChzEx.Error{type: :invalid_value}} =
               ChzEx.entrypoint(Config, [
                 "name=test",
                 "optimizer=unknown"
               ])
    end

    test "constructs polymorphic lists per index" do
      {:ok, config} =
        ChzEx.entrypoint(ListConfig, [
          "optimizers.0=adam",
          "optimizers.0.lr=0.0002",
          "optimizers.1=sgd",
          "optimizers.1.momentum=0.95"
        ])

      assert [%Adam{}, %SGD{}] = config.optimizers
      assert Enum.at(config.optimizers, 0).lr == 0.0002
      assert Enum.at(config.optimizers, 1).momentum == 0.95
    end
  end
end
