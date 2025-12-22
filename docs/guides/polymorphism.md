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

## Subclass Meta-Factory (Behaviour-based)

Use `ChzEx.Factory.Subclass` when you want to select a module by behaviour and a custom discriminator.

```elixir
defmodule MyApp.Handler do
  @callback name() :: String.t()
end

defmodule MyApp.AlphaHandler do
  @behaviour MyApp.Handler
  use ChzEx.Schema

  chz_schema do
    field :message, :string, default: "alpha"
  end

  def name, do: "alpha"
end

defmodule MyApp.BetaHandler do
  @behaviour MyApp.Handler
  use ChzEx.Schema

  chz_schema do
    field :message, :string, default: "beta"
  end

  def name, do: "beta"
end

ChzEx.Registry.register_module(MyApp.AlphaHandler)
ChzEx.Registry.register_module(MyApp.BetaHandler)
```

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    embeds_one :handler, MyApp.AlphaHandler,
      polymorphic: true,
      meta_factory:
        ChzEx.Factory.Subclass.new(
          annotation: MyApp.Handler,
          default: MyApp.AlphaHandler,
          discriminator: :name
        )
  end
end
```

CLI:

```bash
mix run script.exs -- handler=beta handler.message=hello
```

## Polymorphic Lists

You can also use polymorphism in `embeds_many` fields:

```elixir
defmodule MyApp.Layer do
  use ChzEx.Schema
  chz_schema do
    field :kind, :string
  end
end

defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    embeds_many :layers, MyApp.Layer,
      polymorphic: true,
      namespace: :layers
  end
end
```

CLI:

```bash
mix run script.exs -- layers.0=conv layers.0.kind=conv layers.1=attn layers.1.kind=attn
```

## Aliases

Standard factories can map aliases to registered names:

```elixir
factory = ChzEx.Factory.Standard.new(namespace: :optimizers, aliases: %{\"a\" => \"adam\"})
```

## Function Meta-Factory (Manual Resolution)

Function meta-factories resolve callable references for advanced workflows.

```elixir
defmodule MyApp.Transforms do
  def double(value), do: value * 2
end

factory = ChzEx.Factory.Function.new(annotation: :integer, default_module: MyApp.Transforms)
{:ok, fun} = ChzEx.Factory.Function.from_string(factory, "double/1")
fun.(3)
```
