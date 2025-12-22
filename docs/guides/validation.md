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
