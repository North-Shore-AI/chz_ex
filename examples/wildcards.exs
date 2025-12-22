# Wildcard pattern matching example

defmodule Examples.WildcardModel do
  use ChzEx.Schema

  chz_schema do
    field(:activation, :string, default: "relu")
    field(:dropout, :float, default: 0.1)
  end
end

defmodule Examples.WildcardConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)
    embeds_one(:model, Examples.WildcardModel)
  end
end

case ChzEx.entrypoint(Examples.WildcardConfig) do
  {:ok, config} ->
    IO.puts("Wildcard config:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
