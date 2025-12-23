# Type System and Casting

ChzEx provides a small runtime type system (`ChzEx.Type`) and CLI casting helpers
(`ChzEx.Cast`) to match Python chz behavior.

## Type Representation

`ChzEx.Type.type_repr/1` returns a human-readable string:

```elixir
ChzEx.Type.type_repr({:union, [:integer, :string]})
# "integer | string"

ChzEx.Type.type_repr({:array, :float})
# "[float]"
```

## Optional and Union Types

```elixir
optional = ChzEx.Type.make_optional(:integer)
ChzEx.Type.optional?(optional) # true
```

## Runtime Type Checking

```elixir
ChzEx.Type.is_instance?(42, :integer) # true
ChzEx.Type.is_instance?([1, 2], {:array, :integer}) # true
```

## Casting from CLI

`ChzEx.Cast.try_cast/2` powers CLI parsing:

```elixir
ChzEx.Cast.try_cast("12", :integer)
ChzEx.Cast.try_cast("true", :boolean)
ChzEx.Cast.try_cast("a,b", {:array, :string})
ChzEx.Cast.try_cast("2025-12-22", Date)
ChzEx.Cast.try_cast("~/data", :path)
```

Supported targets include:

- `:string`, `:integer`, `:float`, `:boolean`
- `{:array, t}` and `{:map, k, v}`
- `{:union, [t...]}`, `{:literal, [v...]}`, `{:enum, [v...]}`
- `:function` and `{:function, arity}`
- `:path`, `Date`, `DateTime`, `Time`
- `:binary`, `:bytes`, `{:mapset, t}`

## Schema Type Checking

Enable runtime type checking for a schema:

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema typecheck: true do
    field :count, :integer
  end
end
```

When enabled, `ChzEx.Validator.typecheck/2` is applied to all fields.

## Map Schema Types

Map schemas allow typed maps with individual field expansion in blueprints:

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :options, {:map_schema, %{
      timeout: :integer,
      retries: :integer
    }}
  end
end

# CLI: options.timeout=30 options.retries=3
# Result: %{timeout: 30, retries: 3}
```

Fields can be marked as optional:

```elixir
field :settings, {:map_schema, %{
  host: {:string, :required},
  port: {:integer, :required},
  ssl: {:boolean, :optional}
}}
```

## Heterogeneous Tuple Types

Tuples with specific types at each position:

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :coords, {:tuple, [:integer, :integer, :string]}
  end
end

# CLI: coords.0=10 coords.1=20 coords.2=north
# Result: {10, 20, "north"}
```

## Schema Version Hashing

Use `version:` to detect schema drift at compile time:

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema version: "a1b2c3d4" do
    field :count, :integer
  end
end

ChzEx.Schema.version_hash(MyApp.Config)
```

Version strings support suffixes for iteration tracking:

```elixir
chz_schema version: "a1b2c3d4-v2" do
  # The suffix "-v2" is ignored when validating the hash
end
```
