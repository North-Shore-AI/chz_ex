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
case ChzEx.entrypoint(MyApp.Config, System.argv(), allow_hyphens: true) do
  {:ok, config} -> IO.inspect(config)
  {:error, error} -> IO.puts(:stderr, ChzEx.Error.format(error))
end
```

Run with:

```bash
mix run script.exs -- name=test steps=500
```

## CLI Wrapper Helper

Use `ChzEx.CLI.with_error_handling/1` to standardize exit codes and help output:

```elixir
ChzEx.CLI.with_error_handling(fn ->
  ChzEx.entrypoint(MyApp.Config)
end)
```

## Serialize and Inspect

```elixir
values = ChzEx.Serialize.to_blueprint_values(config)
argv = ChzEx.Blueprint.Serialize.to_argv(blueprint)
IO.puts(ChzEx.Pretty.format(config, true))
```
