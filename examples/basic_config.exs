# Basic ChzEx configuration example

defmodule Examples.BasicConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string, doc: "Configuration name")
    field(:value, :integer, default: 0, doc: "Integer value")
    field(:enabled, :boolean, default: true)
  end
end

case ChzEx.entrypoint(Examples.BasicConfig) do
  {:ok, config} ->
    IO.puts("Created config:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
