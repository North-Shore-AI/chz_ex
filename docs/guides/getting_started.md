# Getting Started

This guide walks through defining a schema and constructing it from CLI arguments.

## Define a Schema

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    field :steps, :integer, default: 1000
  end
end
```

## Parse from CLI

```elixir
case ChzEx.entrypoint(MyApp.Config) do
  {:ok, config} -> IO.inspect(config)
  {:error, error} -> IO.puts(:stderr, ChzEx.Error.format(error))
end
```

Run with:

```bash
mix run script.exs -- name=test steps=500
```
