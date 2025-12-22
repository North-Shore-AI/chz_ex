defmodule ChzEx.SerializeTest do
  use ExUnit.Case, async: true

  defmodule Child do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer, default: 1)
    end
  end

  defmodule Parent do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      embeds_one(:child, Child)
    end
  end

  defmodule Handler do
    @callback name() :: String.t()
  end

  defmodule AlphaHandler do
    @behaviour Handler
    use ChzEx.Schema

    chz_schema do
      field(:message, :string, default: "alpha")
    end

    def name, do: "alpha"
  end

  defmodule BetaHandler do
    @behaviour Handler
    use ChzEx.Schema

    chz_schema do
      field(:message, :string, default: "beta")
    end

    def name, do: "beta"
  end

  defmodule PolyConfig do
    use ChzEx.Schema

    alias ChzEx.Factory.Subclass

    chz_schema do
      embeds_one(:handler, AlphaHandler,
        polymorphic: true,
        meta_factory:
          Subclass.new(
            annotation: Handler,
            default: AlphaHandler,
            discriminator: :name
          )
      )
    end
  end

  defmodule ListConfig do
    use ChzEx.Schema

    chz_schema do
      embeds_many(:children, Child)
    end
  end

  describe "to_blueprint_values/2" do
    test "flattens basic struct values" do
      config = %Parent{name: "root", child: %Child{value: 3}}

      assert %{"name" => "root", "child.value" => 3} =
               ChzEx.Serialize.to_blueprint_values(config)
    end

    test "skips defaults when requested" do
      config = %Child{value: 1}
      assert %{} == ChzEx.Serialize.to_blueprint_values(config, skip_defaults: true)
    end

    test "records polymorphic factory modules" do
      config = %PolyConfig{handler: %BetaHandler{message: "hi"}}

      values = ChzEx.Serialize.to_blueprint_values(config)
      assert values["handler"] == BetaHandler
      assert values["handler.message"] == "hi"
    end

    test "handles list of nested structs" do
      config = %ListConfig{children: [%Child{value: 2}, %Child{value: 4}]}

      values = ChzEx.Serialize.to_blueprint_values(config)
      assert values["children.0"] == Child
      assert values["children.0.value"] == 2
      assert values["children.1"] == Child
      assert values["children.1.value"] == 4
    end
  end
end
