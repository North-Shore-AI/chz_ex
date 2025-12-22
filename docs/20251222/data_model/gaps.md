# Data Model Gap Analysis

**Python Source**: `chz/data_model.py` (~762 lines)
**Elixir Port**: `lib/chz_ex/schema.ex` (~183 lines)

## Overview

The Python `data_model.py` is the core of chz, providing the `@chz.chz` decorator that transforms classes into immutable configuration objects. The Elixir port uses Ecto.Schema as a foundation, which provides some functionality but lacks others.

## Ported Functionality

### Fully Implemented
| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Schema definition | `@chz.chz` decorator | `use ChzEx.Schema` + `chz_schema` macro | Uses Ecto.Schema under the hood |
| Field definitions | `chz.field()` | `ChzEx.Schema.field/3` | Different API but equivalent functionality |
| Field storage | `__chz_fields__` | `__chz_fields__/0` | Stored in module attributes |
| Struct check | `is_chz()` | `is_chz?/1` | Works on modules and structs |
| Field access | `chz_fields()` | `chz_fields/1` | Returns field map |
| Replace | `replace()` | `replace/2` | Uses Ecto.Changeset |
| asdict | `asdict()` | `asdict/2` | Recursive conversion to map |

### Partially Implemented
| Feature | Python | Elixir | Missing |
|---------|--------|--------|---------|
| Embedded schemas | Direct nesting | `embeds_one/many` | Works but different pattern |
| Validation | Inline in `__init__` | Ecto.Changeset | Different timing |
| Immutability | `__setattr__` raises | Structs are mutable | Elixir structs aren't frozen |

## Missing Functionality

### 1. Method Synthesis (`_synthesise_init`, `_synthesise_field_init`)
**Lines**: 76-125

**Python Behavior**:
- Dynamically generates `__init__` method at class decoration time
- Creates field initialization code with type annotations
- Validates reserved names (`__chz`, `self`)

**Elixir Gap**:
- Ecto.Schema handles struct creation differently
- No dynamic method generation needed (Elixir pattern)

**Recommendation**: Not needed - Ecto.Schema + changeset provides equivalent functionality

---

### 2. Frozen Instance Error (`FrozenInstanceError`)
**Lines**: 36, 128-133

**Python Behavior**:
```python
def __setattr__(self, name, value):
    raise FrozenInstanceError(f"Cannot modify field {name!r}")
```

**Elixir Gap**:
- Elixir structs are mutable by default
- No enforcement of immutability

**Recommendation**:
```elixir
# Consider adding a compile-time warning or runtime check
defmodule ChzEx.Frozen do
  defmacro __using__(_opts) do
    quote do
      # Structs in Elixir are inherently immutable in functional style
      # Document that mutation should not be done directly
    end
  end
end
```

**Priority**: Low - Elixir idiom is functional transformation, not mutation

---

### 3. Recursive Repr with Cycle Detection
**Lines**: 136-169

**Python Behavior**:
```python
@_recursive_repr
def __repr__(self) -> str:
    # Uses threading.get_ident() to detect cycles
    # Handles callable repr functions per field
```

**Elixir Gap**:
- Default Elixir struct inspect doesn't handle cycles
- No per-field repr customization

**Recommendation**:
```elixir
defimpl Inspect, for: MyChzStruct do
  import Inspect.Algebra

  def inspect(struct, opts) do
    # Implement cycle detection using process dictionary or opts
    # Respect field.repr setting
  end
end
```

**Priority**: Medium - Useful for debugging deep nested configs

---

### 4. Pretty Format (`pretty_format`, `__chz_pretty__`)
**Lines**: 225-304

**Python Behavior**:
- Colored terminal output with ANSI codes
- Shows default vs non-default values
- Shows munged vs original values
- IPython integration via `_repr_pretty_`

**Elixir Gap**:
- No equivalent pretty printing
- No IEx integration

**Recommendation**:
```elixir
defmodule ChzEx.Pretty do
  def format(struct, opts \\ []) do
    colored = Keyword.get(opts, :colored, true)
    # Implement formatted output
    # Use IO.ANSI for colors
  end
end
```

**Priority**: Medium - Good for debugging/UX

---

### 5. init_property (`init_property`, `__chz_init_property__`)
**Lines**: 730-762

**Python Behavior**:
```python
class init_property:
    # Simplified cached_property that runs during __init__
    # Non-data descriptor that stores result in instance __dict__
```

**Elixir Gap**:
- No equivalent computed property mechanism
- Mungers partially cover this use case

**Recommendation**:
- Expand munger system to support computed fields
- Or add explicit `:computed` field option

**Priority**: Medium - Mungers cover most use cases

---

### 6. Traverse Utility
**Lines**: 623-648

**Python Behavior**:
```python
def traverse(obj: Any, obj_path: str = "") -> Iterable[tuple[str, Any]]:
    """Yields (path, value) pairs for all sub attributes recursively."""
```

**Elixir Gap**:
- No recursive traversal utility

**Recommendation**:
```elixir
defmodule ChzEx.Traverse do
  def traverse(struct, path \\ "") do
    Stream.resource(
      fn -> {struct, path, []} end,
      fn state -> do_traverse(state) end,
      fn _ -> :ok end
    )
  end
end
```

**Priority**: Medium - Useful for config inspection/debugging

---

### 7. beta_to_blueprint_values
**Lines**: 656-723

**Python Behavior**:
```python
def beta_to_blueprint_values(obj, skip_defaults: bool = False) -> Any:
    """Return a dict which can be used to recreate the same object via blueprint."""
```

**Elixir Gap**:
- No serialization back to blueprint format

**Recommendation**:
```elixir
defmodule ChzEx.Serialize do
  def to_blueprint_values(struct, opts \\ []) do
    skip_defaults = Keyword.get(opts, :skip_defaults, false)
    # Walk struct and emit blueprint-compatible map
  end
end
```

**Priority**: High - Important for config persistence/reproduction

---

### 8. Version Hashing
**Lines**: 491-500

**Python Behavior**:
```python
if version is not None:
    key = [f.versioning_key() for f in sorted(fields.values(), key=lambda f: f.x_name)]
    key_bytes = json.dumps(key, separators=(",", ":")).encode()
    actual_version = hashlib.sha1(key_bytes).hexdigest()[:8]
    if actual_version != expected_version:
        raise ValueError(f"Version {version!r} does not match {actual_version!r}")
```

**Elixir Gap**:
- No schema versioning
- No field hash computation

**Recommendation**:
```elixir
defmodule ChzEx.Version do
  def compute_version(module) do
    fields = module.__chz_fields__()
    # Compute deterministic hash of field definitions
    :crypto.hash(:sha, :erlang.term_to_binary(fields))
    |> Base.encode16(case: :lower)
    |> String.slice(0..7)
  end
end
```

**Priority**: Low - Useful for detecting config drift in production

---

### 9. Decorator Typecheck (`@chz.chz(typecheck=True)`)
**Lines**: 502-512

**Python Behavior**:
- Optional runtime type checking of all fields
- Uses `is_subtype_instance` from tiepin

**Elixir Gap**:
- Basic typecheck validator exists but not integrated at schema level

**Recommendation**:
- Add `typecheck: true` option to `chz_schema`
- Integrate with Ecto type validation

**Priority**: Medium - Helpful for development/debugging

---

## Implementation Priority Summary

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| beta_to_blueprint_values | High | Medium | Config persistence |
| Pretty format | Medium | Low | Developer UX |
| Traverse utility | Medium | Low | Debugging |
| init_property | Medium | Medium | Computed fields |
| Recursive repr | Medium | Medium | Debugging |
| Version hashing | Low | Low | Production safety |
| Frozen instance | Low | N/A | Elixir idiom differs |
| Decorator typecheck | Medium | Low | Development safety |

## Test Coverage Notes

Python tests in `test_data_model.py` (~30802 bytes) cover:
- Basic field handling
- Inheritance
- Validation
- Mungers
- Replace/asdict
- Edge cases

Consider porting relevant test cases to ensure parity.
