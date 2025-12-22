# Validators Gap Analysis

**Python Source**: `chz/validators.py` (~272 lines)
**Elixir Port**: `lib/chz_ex/validator.ex` (~79 lines)

## Overview

The Python `validators.py` provides a rich set of validation utilities for both field-level and class-level validation. The Elixir port has basic validators but is missing the class-level system and several specialized validators.

## Ported Functionality

### Fully Implemented
| Validator | Python | Elixir | Notes |
|-----------|--------|--------|-------|
| Greater than | `gt(n)` | `gt(n)` | Comparison validator |
| Less than | `lt(n)` | `lt(n)` | Comparison validator |
| Greater or equal | `ge(n)` | `ge(n)` | Comparison validator |
| Less or equal | `le(n)` | `le(n)` | Comparison validator |
| Valid regex | `is_valid_regex` | `valid_regex/2` | Regex compilation check |
| Type check | `typecheck` | `typecheck/2` | Basic Ecto type check |

### Partially Implemented
| Feature | Python | Elixir | Missing |
|---------|--------|--------|---------|
| For all fields | `for_all_fields()` | `for_all_fields/1` | Different pattern |

## Missing Functionality

### 1. Class-Level Validator Decorator (`@chz.validate`)
**Lines**: 16-67

**Python Behavior**:
```python
def validate(fn: _F) -> _F:
    """Decorator to mark a method as a class-level validator."""
    _chz_validate_methods[fn] = True
    return fn

# Usage:
@chz.chz
class Config:
    a: int
    b: int

    @chz.validate
    def check_a_less_than_b(self) -> None:
        if self.a >= self.b:
            raise ValueError("a must be less than b")
```

**Elixir Gap**:
- No decorator equivalent
- Basic class validators via `@chz_validate` attribute work differently

**Recommendation**:
```elixir
defmodule ChzEx.Validate do
  defmacro validate(name, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :chz_validate, unquote(name))

      def unquote(name)(struct) do
        unquote(block)
      end
    end
  end
end

# Usage:
defmodule Config do
  use ChzEx.Schema
  import ChzEx.Validate

  chz_schema do
    field :a, :integer
    field :b, :integer
  end

  validate :check_a_less_than_b do
    if struct.a >= struct.b do
      {:error, :a, "must be less than b"}
    else
      :ok
    end
  end
end
```

**Priority**: High - Common validation pattern

---

### 2. IsOverrideMixin
**Lines**: 70-127

**Python Behavior**:
```python
class IsOverrideMixin:
    """Mixin that provides validation utilities for tracking what was overridden."""

    is_override: ClassVar[FieldValidator | None]

    @classmethod
    def is_override_validator(cls) -> FieldValidator:
        """Creates validator that checks if field was explicitly set."""

    def check_no_non_overrides(self) -> None:
        """Raises if any field was not explicitly overridden."""

    def check_no_overrides(self) -> None:
        """Raises if any field was explicitly overridden."""
```

**Elixir Gap**:
- No override tracking
- Would require blueprint integration

**Recommendation**:
```elixir
defmodule ChzEx.Override do
  @moduledoc """
  Track which fields were explicitly set vs defaulted.
  """

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :chz_overrides, accumulate: false)

      def __chz_track_overrides__(fields) do
        Process.put(:chz_overrides, fields)
      end

      def __chz_was_overridden__(field) do
        overrides = Process.get(:chz_overrides, [])
        field in overrides
      end
    end
  end

  def is_override_validator do
    fn struct, attr ->
      if struct.__chz_was_overridden__(attr) do
        :ok
      else
        {:error, "#{attr} must be explicitly set"}
      end
    end
  end
end
```

**Priority**: Medium - Useful for strict configs

---

### 3. check_field_consistency_in_tree
**Lines**: 185-231

**Python Behavior**:
```python
def check_field_consistency_in_tree(
    root: Any,
    field_name: str,
    *,
    first_wins: bool = False,
) -> None:
    """Validates that a field has consistent values across nested objects."""

# Example: Ensure all nested configs use same seed value
check_field_consistency_in_tree(config, "seed")
```

**Elixir Gap**:
- No recursive consistency check
- Would need to traverse embedded schemas

**Recommendation**:
```elixir
defmodule ChzEx.Validator do
  def check_field_consistency(root, field_name, opts \\ []) do
    first_wins = Keyword.get(opts, :first_wins, false)
    values = collect_field_values(root, field_name)

    case Enum.uniq(values) do
      [] -> :ok
      [_single] -> :ok
      multiple when first_wins -> {:error, "Inconsistent #{field_name} values: #{inspect(multiple)}"}
      multiple -> {:error, "Inconsistent #{field_name} values: #{inspect(multiple)}"}
    end
  end

  defp collect_field_values(struct, field_name) when is_struct(struct) do
    if ChzEx.Schema.is_chz?(struct) do
      value = Map.get(struct, String.to_atom(field_name))
      nested = collect_from_fields(struct, field_name)
      if value != nil, do: [value | nested], else: nested
    else
      []
    end
  end

  defp collect_from_fields(struct, field_name) do
    struct
    |> Map.from_struct()
    |> Enum.flat_map(fn {_k, v} -> collect_field_values(v, field_name) end)
  end
end
```

**Priority**: Medium - Useful for nested config validation

---

### 4. Specialized Validators

#### 4a. `in_range(min, max)`
**Lines**: Not explicit but common pattern

**Python Behavior**:
```python
# Common composition:
validator=[chz.gt(0), chz.lt(100)]
```

**Elixir Recommendation**:
```elixir
def in_range(min, max) do
  fn struct, attr ->
    value = Map.get(struct, attr)
    cond do
      value < min -> {:error, "#{attr} must be >= #{min}"}
      value > max -> {:error, "#{attr} must be <= #{max}"}
      true -> :ok
    end
  end
end
```

---

#### 4b. `one_of(values)`
**Lines**: Not in Python source but commonly needed

**Elixir Recommendation**:
```elixir
def one_of(allowed_values) do
  fn struct, attr ->
    value = Map.get(struct, attr)
    if value in allowed_values do
      :ok
    else
      {:error, "#{attr} must be one of: #{inspect(allowed_values)}"}
    end
  end
end
```

---

#### 4c. `matches(regex)`
**Lines**: Extends `is_valid_regex`

**Elixir Recommendation**:
```elixir
def matches(pattern) do
  regex = if is_binary(pattern), do: Regex.compile!(pattern), else: pattern

  fn struct, attr ->
    value = Map.get(struct, attr)
    if Regex.match?(regex, value) do
      :ok
    else
      {:error, "#{attr} must match pattern #{inspect(pattern)}"}
    end
  end
end
```

---

#### 4d. `not_empty`

**Elixir Recommendation**:
```elixir
def not_empty do
  fn struct, attr ->
    value = Map.get(struct, attr)
    cond do
      is_nil(value) -> {:error, "#{attr} cannot be nil"}
      is_binary(value) and value == "" -> {:error, "#{attr} cannot be empty"}
      is_list(value) and value == [] -> {:error, "#{attr} cannot be empty"}
      is_map(value) and map_size(value) == 0 -> {:error, "#{attr} cannot be empty"}
      true -> :ok
    end
  end
end
```

---

### 5. Validator Composition
**Lines**: Implicit in field handling

**Python Behavior**:
```python
# Multiple validators are applied in order
chz.field(validator=[gt(0), lt(100), is_valid_regex])
```

**Elixir Status**:
- Works but could be more ergonomic

**Recommendation**:
```elixir
defmodule ChzEx.Validator do
  # Add composition helpers
  def all(validators) when is_list(validators) do
    fn struct, attr ->
      Enum.reduce_while(validators, :ok, fn validator, :ok ->
        case validator.(struct, attr) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end
      end)
    end
  end

  def any(validators) when is_list(validators) do
    fn struct, attr ->
      results = Enum.map(validators, &(&1.(struct, attr)))
      if Enum.any?(results, &(&1 == :ok)) do
        :ok
      else
        errors = Enum.filter(results, &match?({:error, _}, &1))
        {:error, Enum.map_join(errors, "; ", fn {:error, msg} -> msg end)}
      end
    end
  end
end
```

**Priority**: Medium - Better ergonomics

---

### 6. Conditional Validators

**Python Pattern**:
```python
def when_field_equals(field, value, then_validator):
    """Apply validator only when another field has specific value."""
```

**Elixir Recommendation**:
```elixir
def when_field(field, condition, then_validator) do
  fn struct, attr ->
    field_value = Map.get(struct, field)
    if condition.(field_value) do
      then_validator.(struct, attr)
    else
      :ok
    end
  end
end

def when_field_equals(field, expected, then_validator) do
  when_field(field, &(&1 == expected), then_validator)
end

# Usage:
field :password_confirm, :string,
  validator: when_field_equals(:password_required, true, not_empty())
```

**Priority**: Medium - Complex validation scenarios

---

## Integration with Ecto Changeset

The current implementation integrates with Ecto.Changeset. Consider leveraging more Ecto validators:

```elixir
defmodule ChzEx.Validator do
  # Wrap Ecto validators for ChzEx interface
  def ecto_validate(validation_fn) do
    fn struct, attr ->
      changeset =
        struct.__struct__
        |> struct()
        |> Ecto.Changeset.cast(Map.from_struct(struct), [attr])
        |> validation_fn.()

      if changeset.valid? do
        :ok
      else
        {_, {msg, _}} = hd(changeset.errors)
        {:error, msg}
      end
    end
  end

  # Example wrappers
  def length(opts) do
    ecto_validate(&Ecto.Changeset.validate_length(&1, :field, opts))
  end

  def format(regex) do
    ecto_validate(&Ecto.Changeset.validate_format(&1, :field, regex))
  end
end
```

---

## Implementation Priority Summary

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| @chz.validate decorator | High | Medium | Class-level validation |
| check_field_consistency | Medium | Medium | Nested config validation |
| Validator composition | Medium | Low | Ergonomics |
| IsOverrideMixin | Medium | High | Strict configs |
| in_range, one_of, etc. | Low | Low | Convenience |
| Conditional validators | Medium | Medium | Complex scenarios |

## Test Coverage Notes

Python tests in `test_validate.py` (~19078 bytes) cover:
- Field validators
- Class validators
- IsOverrideMixin
- Consistency checks
- Edge cases

The test file is comprehensive and should be referenced when implementing missing validators.

## Recommended Validator Library

```elixir
defmodule ChzEx.Validator do
  # Comparison
  def gt(n), do: ...
  def lt(n), do: ...
  def ge(n), do: ...
  def le(n), do: ...
  def in_range(min, max), do: ...

  # String
  def matches(pattern), do: ...
  def not_empty(), do: ...
  def min_length(n), do: ...
  def max_length(n), do: ...

  # Collection
  def one_of(values), do: ...
  def subset_of(values), do: ...

  # Type
  def typecheck(struct, attr), do: ...
  def valid_regex(struct, attr), do: ...

  # Composition
  def all(validators), do: ...
  def any(validators), do: ...
  def when_field(field, condition, validator), do: ...

  # Meta
  def for_all_fields(validator), do: ...
end
```
