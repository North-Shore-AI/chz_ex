# Tiepin (Type System) Gap Analysis

**Python Source**: `chz/tiepin.py` (~1060 lines)
**Elixir Port**: `lib/chz_ex/cast.ex` (~87 lines)

## Overview

The Python `tiepin.py` is a comprehensive runtime type checking and casting system. It handles Python's type annotation complexity including generics, unions, optionals, and callable types. The Elixir port has basic casting but lacks the full type introspection system.

## Ported Functionality

### Fully Implemented
| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| String casting | `blueprint_cast` | `Cast.try_cast/2` | Basic types |
| Integer parsing | `_cast_to_type` | `do_cast(:integer)` | Integer.parse |
| Float parsing | `_cast_to_type` | `do_cast(:float)` | Float.parse |
| Boolean parsing | `_cast_to_type` | `do_cast(:boolean)` | True/False/t/f/1/0 |
| Array casting | `list[T]` | `{:array, inner}` | Comma-separated |
| Map casting | `dict[K, V]` | `{:map, k, v}` | Key:value pairs |

### Partially Implemented
| Feature | Python | Elixir | Missing |
|---------|--------|--------|---------|
| None/nil | `None` | `nil` | Basic support only |
| Custom casts | `__chz_cast__` | `__chz_cast__/1` | Protocol not defined |

## Missing Functionality

### 1. Type Representation (`type_repr`)
**Lines**: 57-103

**Python Behavior**:
```python
def type_repr(ty: Any) -> str:
    """Returns a string representation for types and callables."""
    # Handles:
    # - Module-qualified names (chz.Foo -> chz:Foo)
    # - Generic types (list[int] -> list[int])
    # - Union types (int | str -> int | str)
    # - Callable signatures
    # - Literal types
```

**Elixir Gap**:
- Only basic `inspect/1` available
- No semantic type representation

**Recommendation**:
```elixir
defmodule ChzEx.TypeRepr do
  def repr(type) when is_atom(type), do: inspect(type)
  def repr({:array, inner}), do: "[#{repr(inner)}]"
  def repr({:map, k, v}), do: "%{#{repr(k)} => #{repr(v)}}"
  def repr({:union, types}), do: Enum.map_join(types, " | ", &repr/1)
  # etc.
end
```

**Priority**: Medium - Useful for help text and error messages

---

### 2. Type Annotation Parsing (`_get_type_args`, `_eval_type`, `eval_in_context`)
**Lines**: 107-151, 170-202

**Python Behavior**:
```python
def _get_type_args(cls: Any, types: tuple[Any, ...]) -> TypeArg:
    """Recursively normalizes type annotations."""
    # Handles ForwardRef, string annotations, generics

def eval_in_context(annotation: str, func_or_cls: Any) -> Any:
    """Evaluate a string annotation in the context of its defining module."""
```

**Elixir Gap**:
- No equivalent forward reference handling
- No runtime type annotation evaluation

**Recommendation**:
- Elixir doesn't use forward references the same way
- Consider module-based type registry for complex cases

**Priority**: Low - Elixir type system differs fundamentally

---

### 3. Union Type Handling (`UnionTypeArg`, `get_effective_type`)
**Lines**: 22-55, 215-244

**Python Behavior**:
```python
@dataclass
class UnionTypeArg(TypeArg):
    type_origins: tuple[type, ...]
    type_args: tuple[TypeArg | None, ...]

def get_effective_type(type_arg: TypeArg) -> tuple[type, ...]:
    """Flattens union types for iteration."""
```

**Elixir Gap**:
- No union type representation
- No flattening utilities

**Recommendation**:
```elixir
defmodule ChzEx.Type do
  defstruct [:origin, :args, :union_members]

  def normalize({:union, types}) do
    # Flatten nested unions
    types
    |> Enum.flat_map(fn
      {:union, nested} -> normalize(nested)
      t -> [t]
    end)
  end
end
```

**Priority**: High - Union types are common in configs

---

### 4. Optional Handling (`make_optional`, `is_optional`)
**Lines**: 246-273

**Python Behavior**:
```python
def make_optional(ty: Any) -> Any:
    """Converts T to T | None."""

def is_optional(ty: Any) -> bool:
    """Returns True if type accepts None."""
```

**Elixir Gap**:
- No explicit optional type wrapper
- Field defaults handle nil implicitly

**Recommendation**:
```elixir
defmodule ChzEx.Type do
  def optional?(type), do: # Check if type accepts nil
  def make_optional(type), do: {:union, [type, nil]}
end
```

**Priority**: Medium - Useful for type validation

---

### 5. Subtype Instance Checking (`is_subtype_instance`)
**Lines**: 288-413

**Python Behavior**:
```python
def is_subtype_instance(value: Any, ty: TypeArg, *, _seen: set | None = None) -> bool:
    """Comprehensive runtime type checking."""
    # Handles:
    # - Basic types (int, str, bool, float)
    # - Collections (list, tuple, dict, set, frozenset)
    # - Union types
    # - Optional types
    # - Literal types
    # - Callable types
    # - Generic protocols
    # - Recursive types (with cycle detection)
```

**Elixir Gap**:
- No runtime type checking
- Only Ecto type coercion

**Recommendation**:
```elixir
defmodule ChzEx.TypeCheck do
  def is_instance?(value, :string) when is_binary(value), do: true
  def is_instance?(value, :integer) when is_integer(value), do: true
  def is_instance?(value, :float) when is_float(value), do: true
  def is_instance?(value, :boolean) when is_boolean(value), do: true
  def is_instance?(nil, {:union, types}), do: nil in types
  def is_instance?(value, {:array, inner}) when is_list(value) do
    Enum.all?(value, &is_instance?(&1, inner))
  end
  # etc.
end
```

**Priority**: High - Critical for validation

---

### 6. Enum/Literal Type Casting
**Lines**: 572-608

**Python Behavior**:
```python
# Handles:
# - enum.Enum subclasses (by name or value)
# - Literal["a", "b", "c"] types
```

**Elixir Gap**:
- No enum casting
- No literal type support

**Recommendation**:
```elixir
defmodule ChzEx.Cast do
  # Add enum casting
  defp do_cast(value, module) when is_atom(module) do
    # Check if module defines __chz_enum_values__/0
    if function_exported?(module, :__chz_enum_values__, 0) do
      values = module.__chz_enum_values__()
      if value in values, do: {:ok, value}, else: {:error, "Invalid enum value"}
    else
      # existing behavior
    end
  end
end
```

**Priority**: Medium - Enums are common in configs

---

### 7. Datetime Casting
**Lines**: 617-673

**Python Behavior**:
```python
# Handles:
# - datetime.datetime (ISO 8601)
# - datetime.date (YYYY-MM-DD)
# - datetime.time (HH:MM:SS)
# - datetime.timedelta (various formats)
```

**Elixir Gap**:
- No datetime parsing
- No time/date handling

**Recommendation**:
```elixir
defmodule ChzEx.Cast do
  defp do_cast(value, DateTime) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, "Invalid datetime format"}
    end
  end

  defp do_cast(value, Date) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "Invalid date format"}
    end
  end

  defp do_cast(value, Time) do
    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> {:error, "Invalid time format"}
    end
  end
end
```

**Priority**: High - Datetime configs are very common

---

### 8. Path/Pathlib Casting
**Lines**: 682-697

**Python Behavior**:
```python
# Handles:
# - pathlib.Path
# - pathlib.PurePath
# - Expands ~ (user home)
```

**Elixir Gap**:
- No path type
- No home directory expansion

**Recommendation**:
```elixir
defmodule ChzEx.Cast do
  defp do_cast(value, :path) do
    expanded = Path.expand(value)
    {:ok, expanded}
  end
end
```

**Priority**: Medium - Useful for file configs

---

### 9. Callable Type Handling
**Lines**: 701-773

**Python Behavior**:
```python
# Handles:
# - Callable types with signatures
# - Module.function syntax
# - Object attributes (config:model.family)
```

**Elixir Gap**:
- No callable type casting
- No Module.function resolution

**Recommendation**:
```elixir
defmodule ChzEx.Cast do
  defp do_cast(value, :function) when is_binary(value) do
    case String.split(value, ".") do
      [mod, func] ->
        module = String.to_existing_atom("Elixir." <> mod)
        function = String.to_existing_atom(func)
        {:ok, Function.capture(module, function, 1)}
      _ ->
        {:error, "Invalid function reference"}
    end
  end
end
```

**Priority**: Medium - Useful for callback configs

---

### 10. JSON/bytes/frozenset Casting
**Lines**: 777-802

**Python Behavior**:
```python
# Handles:
# - bytes (from hex or raw)
# - frozenset (comma-separated)
# - JSON values (generic parsing)
```

**Elixir Gap**:
- No bytes type (Elixir has binaries)
- No frozenset (use MapSet)
- No generic JSON fallback

**Recommendation**:
```elixir
defmodule ChzEx.Cast do
  defp do_cast(value, :binary) when is_binary(value) do
    case Base.decode16(value, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:ok, value}  # Treat as raw bytes
    end
  end

  defp do_cast(value, MapSet) do
    values = String.split(value, ",", trim: true)
    {:ok, MapSet.new(values)}
  end

  defp do_cast(value, :json) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, "Invalid JSON"}
    end
  end
end
```

**Priority**: Low-Medium - Depends on use case

---

## Type Mapping Reference

| Python Type | Elixir Type | Cast Status |
|-------------|-------------|-------------|
| `str` | `:string` | Implemented |
| `int` | `:integer` | Implemented |
| `float` | `:float` | Implemented |
| `bool` | `:boolean` | Implemented |
| `None` | `nil` | Implemented |
| `list[T]` | `{:array, T}` | Implemented |
| `dict[K,V]` | `{:map, K, V}` | Implemented |
| `T \| None` | `{:union, [T, nil]}` | Missing |
| `Literal["a","b"]` | `{:literal, ["a","b"]}` | Missing |
| `datetime.datetime` | `DateTime` | Missing |
| `datetime.date` | `Date` | Missing |
| `datetime.time` | `Time` | Missing |
| `pathlib.Path` | `:path` | Missing |
| `Callable[...]` | `:function` | Missing |
| `enum.Enum` | Custom module | Missing |
| `bytes` | `:binary` | Missing |
| `frozenset` | `MapSet` | Missing |
| `tuple[T,...]` | `{:tuple, [...]}` | Missing |
| `set[T]` | `MapSet` | Missing |

## Implementation Priority Summary

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| is_subtype_instance | High | High | Core validation |
| Union type handling | High | Medium | Common pattern |
| Datetime casting | High | Low | Very common |
| Optional handling | Medium | Low | Type safety |
| Enum casting | Medium | Medium | Common pattern |
| Path casting | Medium | Low | File configs |
| type_repr | Medium | Low | UX/debugging |
| Callable casting | Medium | Medium | Callback configs |
| JSON/bytes casting | Low | Low | Niche use cases |

## Test Coverage Notes

Python tests in `test_tiepin.py` (~44221 bytes) extensively cover:
- Type annotation parsing
- Union type handling
- Subtype checking
- Casting for all types
- Edge cases and error handling

This is the most comprehensive test file - porting these tests would ensure robust type handling.
