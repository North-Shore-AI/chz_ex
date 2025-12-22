defmodule ChzEx.IntegrationTest do
  use ExUnit.Case, async: false

  defmodule ModelConfig do
    use ChzEx.Schema

    chz_schema do
      field(:hidden_dim, :integer, default: 768)
      field(:num_layers, :integer, default: 12)
    end
  end

  defmodule Config do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      field(:seed, :integer, default: 42)
      embeds_one(:model, ModelConfig)
    end
  end

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
    end
  end

  defmodule SGD do
    use ChzEx.Schema

    chz_schema do
      field(:lr, :float, default: 0.01)
      field(:momentum, :float, default: 0.9)
    end
  end

  defmodule PolyConfig do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)

      embeds_one(:optimizer, BaseOptimizer,
        polymorphic: true,
        namespace: :integration_optimizers,
        blueprint_unspecified: Adam
      )
    end
  end

  defmodule ValidatedConfig do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer,
        validator: [
          ChzEx.Validator.gt(0),
          ChzEx.Validator.lt(100)
        ]
      )
    end
  end

  defmodule MungedConfig do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      field(:display_name, :string, munger: ChzEx.Munger.attr_if_none(:name))
    end
  end

  setup do
    start_supervised!(ChzEx.Registry)
    ChzEx.Registry.register(:integration_optimizers, "adam", Adam)
    ChzEx.Registry.register(:integration_optimizers, "sgd", SGD)
    :ok
  end

  describe "full pipeline" do
    test "basic CLI parsing" do
      {:ok, config} = ChzEx.entrypoint(Config, ["name=test", "model.hidden_dim=256"])

      assert config.name == "test"
      assert config.seed == 42
      assert config.model.hidden_dim == 256
      assert config.model.num_layers == 12
    end

    test "nested structs" do
      {:ok, config} =
        ChzEx.entrypoint(Config, [
          "name=test",
          "model.hidden_dim=128",
          "model.num_layers=4"
        ])

      assert config.model.hidden_dim == 128
      assert config.model.num_layers == 4
    end

    test "polymorphic construction" do
      {:ok, config} =
        ChzEx.entrypoint(PolyConfig, [
          "name=test",
          "optimizer=sgd",
          "optimizer.momentum=0.99"
        ])

      assert config.optimizer.__struct__ == SGD
      assert config.optimizer.momentum == 0.99
    end

    test "wildcards" do
      {:ok, config} = ChzEx.entrypoint(Config, ["name=test", "...num_layers=6"])
      assert config.model.num_layers == 6
    end

    test "references" do
      defmodule RefConfig do
        use ChzEx.Schema

        chz_schema do
          field(:base, :integer, default: 5)
          field(:value, :integer)
        end
      end

      {:ok, config} =
        ChzEx.entrypoint(RefConfig, [
          "value@=base"
        ])

      assert config.value == 5
    end

    test "validation" do
      assert {:error, %ChzEx.Error{type: :validation_error}} =
               ChzEx.entrypoint(ValidatedConfig, ["value=200"])
    end

    test "mungers" do
      {:ok, config} = ChzEx.entrypoint(MungedConfig, ["name=exp"])
      assert config.display_name == "exp"
    end

    test "error messages with suggestions" do
      assert {:error, %ChzEx.Error{type: :extraneous, suggestions: suggestions}} =
               ChzEx.entrypoint(Config, ["name=test", "model.hidden_dims=256"])

      assert "model.hidden_dim" in suggestions
    end

    test "help generation" do
      help = ChzEx.Blueprint.new(Config) |> ChzEx.Blueprint.get_help()

      assert help =~ "name"
      assert help =~ "model.hidden_dim"
    end
  end
end
