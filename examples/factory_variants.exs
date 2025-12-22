# Factory meta-factory example (Subclass + Function)

defmodule Examples.Handler do
  @callback name() :: String.t()
end

defmodule Examples.AlphaHandler do
  @behaviour Examples.Handler
  use ChzEx.Schema

  chz_schema do
    field(:message, :string, default: "alpha")
  end

  def name, do: "alpha"
end

defmodule Examples.BetaHandler do
  @behaviour Examples.Handler
  use ChzEx.Schema

  chz_schema do
    field(:message, :string, default: "beta")
  end

  def name, do: "beta"
end

defmodule Examples.FactoryConfig do
  use ChzEx.Schema

  chz_schema do
    embeds_one(:handler, Examples.AlphaHandler,
      polymorphic: true,
      meta_factory:
        ChzEx.Factory.Subclass.new(
          annotation: Examples.Handler,
          default: Examples.AlphaHandler,
          discriminator: :name
        )
    )
  end
end

defmodule Examples.Transforms do
  def double(value), do: value * 2
end

ChzEx.Registry.start_link([])
ChzEx.Registry.register_module(Examples.AlphaHandler)
ChzEx.Registry.register_module(Examples.BetaHandler)

case ChzEx.entrypoint(Examples.FactoryConfig) do
  {:ok, config} ->
    IO.puts("Subclass factory config:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end

factory = ChzEx.Factory.Function.new(annotation: :integer, default_module: Examples.Transforms)
{:ok, fun} = ChzEx.Factory.Function.from_string(factory, "double/1")
IO.puts("Function factory double(3): #{fun.(3)}")
