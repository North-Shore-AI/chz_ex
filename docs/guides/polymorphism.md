# Polymorphism

Polymorphic fields let you select a concrete type at runtime.

## Define Types

```elixir
defmodule MyApp.Optimizer do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.001
  end
end

defmodule MyApp.Adam do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.001
    field :beta1, :float, default: 0.9
  end
end
```

## Register Types

```elixir
ChzEx.Registry.register(:optimizers, "adam", MyApp.Adam)
```

## Use in a Schema

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    embeds_one :optimizer, MyApp.Optimizer,
      polymorphic: true,
      namespace: :optimizers,
      blueprint_unspecified: MyApp.Adam
  end
end
```

CLI:

```bash
mix run script.exs -- name=exp optimizer=adam optimizer.beta1=0.95
```
