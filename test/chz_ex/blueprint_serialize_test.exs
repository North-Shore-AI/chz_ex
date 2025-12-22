defmodule ChzEx.Blueprint.SerializeTest do
  use ExUnit.Case, async: true

  alias ChzEx.Blueprint
  alias ChzEx.Blueprint.{Castable, Reference, Serialize}

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

  defmodule Config do
    use ChzEx.Schema

    alias ChzEx.Factory.Subclass

    chz_schema do
      field(:name, :string)
      field(:count, :integer)
      field(:enabled, :boolean)
      field(:notes, {:array, :string})
      field(:tags, {:array, :string})
      field(:opts, :map)

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

  setup do
    start_supervised!(ChzEx.Registry)
    :ok = ChzEx.Registry.register_module(AlphaHandler)
    :ok = ChzEx.Registry.register_module(BetaHandler)
    :ok
  end

  describe "to_argv/1" do
    test "serializes primitive, castable, and reference values" do
      bp =
        Blueprint.new(Config)
        |> Blueprint.apply(%{
          "name" => "alpha",
          "count" => 2,
          "enabled" => true,
          "handler" => BetaHandler,
          "notes" => ["one", "two"],
          "opts" => %{"a" => 1},
          "alias" => Reference.new("name"),
          "raw" => Castable.new("42")
        })

      argv = Serialize.to_argv(bp)

      assert "name=alpha" in argv
      assert "count=2" in argv
      assert "enabled=true" in argv
      assert "handler=beta" in argv
      assert "notes=one,two" in argv
      assert "opts.a=1" in argv
      assert "alias@=name" in argv
      assert "raw=42" in argv
    end

    test "serializes string lists with commas using indexed args" do
      bp =
        Blueprint.new(Config)
        |> Blueprint.apply(%{"tags" => ["a,b", "c"]})

      argv = Serialize.to_argv(bp)

      assert "tags.0=a,b" in argv
      assert "tags.1=c" in argv
      refute Enum.any?(argv, &String.starts_with?(&1, "tags="))
    end

    test "collapses wildcard layers over previous values" do
      bp =
        Blueprint.new(Config)
        |> Blueprint.apply(%{"alpha.value" => 1, "beta.value" => 2})
        |> Blueprint.apply(%{"...value" => 3})

      argv = Serialize.to_argv(bp)

      assert "...value=3" in argv
      refute "alpha.value=1" in argv
      refute "beta.value=2" in argv
    end
  end
end
