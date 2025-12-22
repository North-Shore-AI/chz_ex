# Nested configuration example

defmodule Examples.ModelConfig do
  use ChzEx.Schema

  chz_schema do
    field(:hidden_dim, :integer, default: 768)
    field(:num_layers, :integer, default: 12)
    field(:num_heads, :integer, default: 12)
  end
end

defmodule Examples.NestedConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)
    embeds_one(:model, Examples.ModelConfig)
  end
end

case ChzEx.entrypoint(Examples.NestedConfig) do
  {:ok, config} ->
    IO.puts("Created nested config:")
    IO.inspect(config, pretty: true)
    IO.puts("\nModel hidden_dim: #{config.model.hidden_dim}")

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
