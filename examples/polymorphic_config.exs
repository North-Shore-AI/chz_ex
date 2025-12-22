# Polymorphic configuration example

defmodule Examples.Optimizer do
  use ChzEx.Schema

  chz_schema do
    field(:lr, :float, default: 0.001)
  end
end

defmodule Examples.Adam do
  use ChzEx.Schema

  chz_schema do
    field(:lr, :float, default: 0.001)
    field(:beta1, :float, default: 0.9)
    field(:beta2, :float, default: 0.999)
  end
end

defmodule Examples.SGD do
  use ChzEx.Schema

  chz_schema do
    field(:lr, :float, default: 0.01)
    field(:momentum, :float, default: 0.9)
  end
end

defmodule Examples.PolymorphicConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)

    embeds_one(:optimizer, Examples.Optimizer,
      polymorphic: true,
      namespace: :example_optimizers,
      blueprint_unspecified: Examples.Adam
    )
  end
end

# Register types
ChzEx.Registry.start_link([])
ChzEx.Registry.register(:example_optimizers, "adam", Examples.Adam)
ChzEx.Registry.register(:example_optimizers, "sgd", Examples.SGD)

case ChzEx.entrypoint(Examples.PolymorphicConfig) do
  {:ok, config} ->
    IO.puts("Created polymorphic config:")
    IO.inspect(config, pretty: true)
    IO.puts("\nOptimizer type: #{config.optimizer.__struct__}")

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
