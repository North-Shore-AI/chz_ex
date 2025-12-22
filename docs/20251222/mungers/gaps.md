# Mungers Gap Analysis

**Python Source**: `chz/mungers.py` (~78 lines)
**Elixir Port**: `lib/chz_ex/munger.ex` (~30 lines)

## Overview

Mungers are post-init field transformers that can modify field values after all fields have been initialized. The Elixir port covers the core functionality well.

## Ported Functionality

### Fully Implemented
| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| `if_none` | `munger.if_none(fn)` | `Munger.if_none/1` | Replace nil with computed value |
| `attr_if_none` | `munger.attr_if_none(attr)` | `Munger.attr_if_none/1` | Copy from another field |
| Custom munger | 2-arity function | 2-arity function | `fn value, struct -> new_value end` |

## Missing Functionality

### 1. `from_function` Helper
**Lines**: 61-78

**Python Behavior**:
```python
def from_function(fn: Callable[[T, U], V]) -> Munger[T, U, V]:
    """Create a munger from a simple function.

    The function takes (struct, value) instead of (value, struct).
    """
    return lambda value, struct: fn(struct, value)
```

**Elixir Gap**:
- Currently exists but could be clearer

**Current Elixir**:
```elixir
def from_function(fun) when is_function(fun, 2) do
  fn value, struct -> fun.(struct, value) end
end
```

**Status**: Implemented - signature differs slightly from Python

---

### 2. Additional Munger Utilities

These aren't in the Python source but would be useful additions:

#### 2a. `transform`
```elixir
def transform(fun) when is_function(fun, 1) do
  fn value, _struct -> fun.(value) end
end

# Usage:
field :name, :string, munger: Munger.transform(&String.upcase/1)
```

#### 2b. `default`
```elixir
def default(default_value) do
  fn value, _struct ->
    if is_nil(value), do: default_value, else: value
  end
end

# Usage:
field :timeout, :integer, munger: Munger.default(30_000)
```

#### 2c. `coerce`
```elixir
def coerce(type) do
  fn value, _struct ->
    case ChzEx.Cast.try_cast(to_string(value), type) do
      {:ok, coerced} -> coerced
      {:error, _} -> value
    end
  end
end
```

#### 2d. `compose`
```elixir
def compose(mungers) when is_list(mungers) do
  fn value, struct ->
    Enum.reduce(mungers, value, fn munger, acc ->
      munger.(acc, struct)
    end)
  end
end

# Usage:
field :name, :string, munger: Munger.compose([
  Munger.if_none(fn _ -> "default" end),
  Munger.transform(&String.trim/1),
  Munger.transform(&String.upcase/1)
])
```

---

### 3. Munger Protocol/Behaviour

**Python Pattern**:
```python
# Python uses duck typing - any callable with correct signature
Munger = Callable[[T, U], V]
```

**Elixir Recommendation**:
```elixir
# Could add a behaviour for complex mungers:
defmodule ChzEx.Munger.Behaviour do
  @callback munge(value :: any(), struct :: struct()) :: any()
end

# Simple functions still work directly
```

**Priority**: Low - Current function approach is sufficient

---

## Integration Notes

### Munger Execution Order

In the Elixir port (`blueprint.ex:606-617`):
```elixir
defp apply_mungers(struct) do
  fields = struct.__struct__.__chz_fields__()

  Enum.reduce(fields, struct, fn {name, field}, acc ->
    value = Map.get(acc, name) |> apply_mungers_to_value()
    acc = Map.put(acc, name, value)

    case field.munger do
      nil -> acc
      munger -> Map.put(acc, name, munger.(value, acc))
    end
  end)
end
```

**Note**: Mungers run after all fields are set, allowing access to other field values.

### Recursive Munging

The port correctly handles nested structures:
```elixir
defp apply_mungers_to_value(value) do
  cond do
    Schema.is_chz?(value) -> apply_mungers(value)
    is_list(value) -> Enum.map(value, &apply_mungers_to_value/1)
    true -> value
  end
end
```

---

## Implementation Priority Summary

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| transform helper | Low | Low | Convenience |
| default helper | Low | Low | Convenience |
| compose helper | Low | Low | Complex transforms |
| coerce helper | Low | Low | Type flexibility |

## Status: Mostly Complete

The mungers module is one of the better-ported components. The core functionality is present and working. The suggested additions are convenience helpers rather than missing functionality.

## Recommended Final Module

```elixir
defmodule ChzEx.Munger do
  @moduledoc """
  Post-init field transforms.

  Mungers are 2-arity functions that take `(value, struct)` and return
  the new value for the field. They run after all fields have been
  initialized, allowing access to other field values.

  ## Examples

      # Replace nil with computed value
      field :display_name, :string,
        munger: Munger.if_none(fn struct -> struct.first_name end)

      # Copy from another field
      field :backup_email, :string,
        munger: Munger.attr_if_none(:primary_email)

      # Transform value
      field :name, :string,
        munger: Munger.transform(&String.upcase/1)

      # Compose multiple mungers
      field :slug, :string,
        munger: Munger.compose([
          Munger.if_none(fn s -> s.title end),
          Munger.transform(&Slug.slugify/1)
        ])
  """

  @doc "If value is nil, replace with result of function."
  def if_none(replacement_fn) when is_function(replacement_fn, 1) do
    fn value, struct ->
      if is_nil(value), do: replacement_fn.(struct), else: value
    end
  end

  @doc "If value is nil, use another attribute."
  def attr_if_none(replacement_attr) when is_atom(replacement_attr) do
    fn value, struct ->
      if is_nil(value), do: Map.get(struct, replacement_attr), else: value
    end
  end

  @doc "Apply a 1-arity transform to the value."
  def transform(fun) when is_function(fun, 1) do
    fn value, _struct -> fun.(value) end
  end

  @doc "Provide a static default for nil values."
  def default(default_value) do
    fn value, _struct ->
      if is_nil(value), do: default_value, else: value
    end
  end

  @doc "Compose multiple mungers (left to right)."
  def compose(mungers) when is_list(mungers) do
    fn value, struct ->
      Enum.reduce(mungers, value, fn munger, acc ->
        munger.(acc, struct)
      end)
    end
  end

  @doc "Create a munger from a (struct, value) function."
  def from_function(fun) when is_function(fun, 2) do
    fn value, struct -> fun.(struct, value) end
  end
end
```
