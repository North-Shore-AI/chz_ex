# Validation

ChzEx supports field validators and class-level validators.

## Field Validators

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :value, :integer, validator: [
      ChzEx.Validator.gt(0),
      ChzEx.Validator.lt(100)
    ]
  end
end
```

## Additional Built-ins

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :mode, :string, validator: ChzEx.Validator.one_of(["fast", "slow"])
    field :rate, :float, validator: ChzEx.Validator.in_range(0.0, 1.0)
    field :tag, :string, validator: ChzEx.Validator.matches(~r/^[a-z]/)
    field :name, :string, validator: ChzEx.Validator.not_empty()
    field :kind, :string, validator: ChzEx.Validator.const_default("alpha")

    field :timeout, :integer,
      validator: ChzEx.Validator.when_field(:mode, "fast", ChzEx.Validator.lt(10))
  end
end
```

Validators can also be composed:

```elixir
field :value, :integer,
  validator: ChzEx.Validator.all([ChzEx.Validator.gt(0), ChzEx.Validator.lt(100)])
```

## Class Validators

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :min, :integer, default: 0
    field :max, :integer, default: 100
  end

  @chz_validate :check_range
  def check_range(struct) do
    if struct.min > struct.max do
      {:error, :min, "must be less than max"}
    else
      :ok
    end
  end
end
```

## Validator Macro

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema
  import ChzEx.Validate, only: [validate: 2]

  chz_schema do
    field :min, :integer, default: 0
    field :max, :integer, default: 100
  end

  validate :check_range do
    if struct.min > struct.max do
      {:error, :min, "must be less than max"}
    else
      :ok
    end
  end
end
```

## Override Checking

Use `chz_parent/1` and `ChzEx.Validator.IsOverrideMixin` to ensure overridden fields exist:

```elixir
defmodule MyApp.Base do
  use ChzEx.Schema
  chz_schema do
    field :name, :string
  end
end

defmodule MyApp.Child do
  use ChzEx.Schema
  use ChzEx.Validator.IsOverrideMixin

  chz_parent MyApp.Base

  chz_schema do
    field :name, :string
  end
end
```

You can also apply the override validator directly:

```elixir
chz_schema do
  field :name, :string, validator: ChzEx.Validator.override?()
end
```

## Consistency Checks

Use `ChzEx.Validator.check_field_consistency_in_tree/3` to ensure a field has the
same value across a nested tree:

```elixir
case ChzEx.Validator.check_field_consistency_in_tree(config, [:seed]) do
  :ok -> :ok
  {:error, message} -> IO.puts(:stderr, message)
end
```
