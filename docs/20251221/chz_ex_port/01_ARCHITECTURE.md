# ChzEx Architecture Overview

**Date:** 2025-12-21
**Status:** Design Phase
**Target:** Elixir port of Python `chz` library

---

## Executive Summary

ChzEx is a native Elixir port of OpenAI's `chz` Python configuration library. It provides:

1. **Typed configuration schemas** - Define configs with Ecto-like embedded schemas
2. **CLI argument parsing** - Parse `key=value` and `path.to.key=value` arguments
3. **Polymorphic construction** - Specify both factory and arguments at runtime
4. **Wildcards and references** - Bulk overrides and value linking
5. **Validation and munging** - Post-init transforms and comprehensive validation

---

## Python CHZ Architecture Analysis

### Core Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Python CHZ                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────┐     ┌──────────────────┐                      │
│  │   @chz.chz       │     │   chz.field()    │                      │
│  │   (decorator)    │◄────┤   (field spec)   │                      │
│  │                  │     │                  │                      │
│  │ - __init__       │     │ - default        │                      │
│  │ - __repr__       │     │ - default_factory│                      │
│  │ - __eq__/__hash__│     │ - validator      │                      │
│  │ - frozen         │     │ - munger         │                      │
│  │ - validation     │     │ - meta_factory   │                      │
│  └────────┬─────────┘     └──────────────────┘                      │
│           │                                                          │
│           ▼                                                          │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                       Blueprint Pipeline                      │   │
│  ├──────────────────────────────────────────────────────────────┤   │
│  │                                                               │   │
│  │  argv_to_blueprint_args()                                    │   │
│  │         │                                                     │   │
│  │         ▼                                                     │   │
│  │  ┌─────────────┐                                             │   │
│  │  │ ArgumentMap │──► Layers with qualified + wildcard keys    │   │
│  │  └──────┬──────┘                                             │   │
│  │         │                                                     │   │
│  │         ▼                                                     │   │
│  │  Preprocessor (wildcards, references)                        │   │
│  │         │                                                     │   │
│  │         ▼                                                     │   │
│  │  ┌─────────────┐                                             │   │
│  │  │ _make_lazy  │──► Discover params via meta_factories       │   │
│  │  └──────┬──────┘    Build Thunks for deferred construction   │   │
│  │         │                                                     │   │
│  │         ▼                                                     │   │
│  │  ┌─────────────┐                                             │   │
│  │  │  evaluate   │──► Resolve ParamRefs, call Thunks           │   │
│  │  └──────┬──────┘    Detect cycles, return final struct       │   │
│  │         │                                                     │   │
│  │         ▼                                                     │   │
│  │      Result (typed struct or error)                          │   │
│  │                                                               │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────┐     ┌──────────────────┐                      │
│  │   MetaFactory    │     │     tiepin.py    │                      │
│  │                  │     │   (type system)  │                      │
│  │ - unspecified()  │     │                  │                      │
│  │ - from_string()  │     │ - is_subtype     │                      │
│  │ - perform_cast() │     │ - is_subtype_inst│                      │
│  │                  │     │ - try_cast       │                      │
│  │ Impls:           │     │ - type_repr      │                      │
│  │ - standard       │     │                  │                      │
│  │ - subclass       │     │                  │                      │
│  │ - function       │     │                  │                      │
│  └──────────────────┘     └──────────────────┘                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User Code                CLI Input
    │                        │
    ▼                        ▼
┌────────────────┐    ┌────────────────┐
│ @chz.chz class │    │ ["a.b=1",      │
│ with fields    │    │  "model=Tfm"]  │
└───────┬────────┘    └───────┬────────┘
        │                     │
        │   ┌─────────────────┘
        │   │
        ▼   ▼
┌─────────────────────────┐
│   Blueprint(target)     │
│   .apply(args)          │
│   .apply_from_argv()    │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│   ArgumentMap           │
│   (layered key-value)   │
│   - qualified: exact    │
│   - wildcard: patterns  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│   _make_lazy()          │
│   Recursive discovery:  │
│   - Collect params      │
│   - Match to arg layers │
│   - Build Thunks        │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│   evaluate()            │
│   - Resolve ParamRefs   │
│   - Execute Thunks      │
│   - Cycle detection     │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│   Final Struct          │
│   (immutable, typed)    │
└─────────────────────────┘
```

---

## Elixir Architecture Design

### Module Structure

```
lib/chz_ex/
├── chz_ex.ex              # Main API (entrypoint, entrypoint!)
├── schema.ex              # `use ChzEx.Schema` macro
├── field.ex               # Field specification struct
├── parser.ex              # CLI argument parsing
├── blueprint.ex           # Blueprint struct and pipeline
├── argument_map.ex        # Layer-based argument storage
├── wildcard.ex            # Wildcard pattern matching
├── lazy.ex                # Evaluatable types (Value, ParamRef, Thunk)
├── factory.ex             # MetaFactory behaviour + implementations
├── validator.ex           # Validation functions
├── munger.ex              # Post-init transforms
├── cast.ex                # Type casting from strings
├── error.ex               # Error types
└── registry.ex            # Polymorphic type registry
```

### Component Mapping

| Python Module | Elixir Module | Notes |
|--------------|---------------|-------|
| `data_model.py` | `ChzEx.Schema` | Macro-based, uses Ecto embedded_schema |
| `field.py` | `ChzEx.Field` | Struct with same options |
| `blueprint/_blueprint.py` | `ChzEx.Blueprint` | Pipeline orchestration |
| `blueprint/_argv.py` | `ChzEx.Parser` | Parse `["a=1", "b=2"]` |
| `blueprint/_argmap.py` | `ChzEx.ArgumentMap` | Layered key-value storage |
| `blueprint/_wildcard.py` | `ChzEx.Wildcard` | `...` pattern matching |
| `blueprint/_lazy.py` | `ChzEx.Lazy` | Deferred evaluation |
| `factories.py` | `ChzEx.Factory` | Behaviour + implementations |
| `validators.py` | `ChzEx.Validator` | Validation functions |
| `mungers.py` | `ChzEx.Munger` | Post-init transforms |
| `tiepin.py` | `ChzEx.Cast` | Type casting |

---

## Key Design Decisions

### 1. Schema Definition

**Python:**
```python
@chz.chz
class Experiment:
    name: str
    steps: int = 1000
    model: Model = chz.field(meta_factory=factories.subclass(Model))
```

**Elixir:**
```elixir
defmodule MyApp.Experiment do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    field :steps, :integer, default: 1000
    embeds_one :model, MyApp.Model, polymorphic: true
  end
end
```

**Rationale:**
- Use Ecto's proven `embedded_schema` under the hood
- `chz_schema` macro wraps Ecto while adding ChzEx metadata
- `polymorphic: true` enables runtime type selection
- All field options map to ChzEx.Field struct

### 2. Immutability

**Python:** Uses `__setattr__` override to raise `FrozenInstanceError`

**Elixir:** Structs are immutable by default - no extra work needed!

### 3. CLI Parsing

**Python:**
```python
chz.entrypoint(Experiment)
# argv: ["name=test", "model=Transformer", "model.layers=12"]
```

**Elixir:**
```elixir
ChzEx.entrypoint(MyApp.Experiment)
# argv: ["name=test", "model=Transformer", "model.layers=12"]
```

**Implementation:**
- Split on `=` (max 2 parts)
- Build nested map from dotted paths
- Keep keys as strings until schema application (no atom creation)

### 4. Polymorphism

**Python:**
- `MetaFactory.from_string()` resolves `"Transformer"` to class
- Searches subclasses via `__subclasses__()`
- Supports `module:ClassName` syntax

**Elixir:**
- Explicit registry: `ChzEx.Registry.register(:models, "transformer", MyApp.Transformer)`
- No runtime module scanning (security + BEAM compatibility)
- Fully qualified names: `"my_app:transformer"` or short names from registry

### 5. Wildcards

**Python:** `"...n_layers"` matches any path ending in `n_layers`

**Elixir:** Same semantics, implemented with regex compilation

```elixir
defmodule ChzEx.Wildcard do
  def to_regex("..." <> rest) do
    # "...n_layers" → ~r/(.*\.)?n_layers/
    pattern = "(.*\\.)?" <> Regex.escape(rest)
    Regex.compile!(pattern)
  end
end
```

### 6. References

**Python:** `"a.b@=c.d"` copies value from `c.d` to `a.b`

**Elixir:** Same syntax, resolved during evaluation phase

```elixir
defmodule ChzEx.Lazy do
  defstruct [:type, :value]

  # Types: :value, :param_ref, :thunk
end
```

### 7. Validation

**Python:** Field validators + class validators via `@chz.validate`

**Elixir:** Ecto changesets + custom validators

```elixir
defmodule MyApp.Experiment do
  use ChzEx.Schema

  chz_schema do
    field :steps, :integer, validator: &ChzEx.Validator.gt(&1, 0)
  end

  @chz_validate :check_consistency
  def check_consistency(struct) do
    if struct.steps < struct.warmup_steps do
      {:error, "steps must be >= warmup_steps"}
    else
      :ok
    end
  end
end
```

### 8. Mungers (Post-Init Transforms)

**Python:** `munger=attr_if_none("other_field")`

**Elixir:**
```elixir
field :display_name, :string,
  munger: ChzEx.Munger.attr_if_none(:name)
```

Mungers run after changeset validation, before struct finalization.

---

## Error Handling Strategy

### Error Types

```elixir
defmodule ChzEx.Error do
  defexception [:type, :path, :message, :suggestions]

  # Types:
  # - :missing_required - Required field not specified
  # - :extraneous - Unknown field specified
  # - :invalid_value - Value doesn't match type
  # - :invalid_reference - Reference target doesn't exist
  # - :cycle - Cyclic reference detected
  # - :cast_error - Failed to cast string to type
  # - :validation_error - Validation failed
end
```

### Error Messages

Follow Python chz's excellent error UX:
- Include fuzzy matching suggestions ("Did you mean 'n_layers'?")
- Show which layer introduced the argument
- Explain nesting issues ("Did you get the nesting wrong?")

---

## Security Considerations

1. **No dynamic atom creation** - Keys stay as strings until matched against known schema
2. **Explicit module registry** - Only registered modules can be constructed
3. **No code evaluation** - Unlike Python's `eval()`, no runtime code execution
4. **Input validation** - All user input validated before use

---

## Performance Considerations

1. **Compile-time schema analysis** - Extract field info at compile time
2. **Cached regex patterns** - Compile wildcard patterns once
3. **Lazy evaluation** - Only construct what's needed
4. **Efficient layer lookup** - Binary search for consolidated qualified keys

---

## Integration Points

### With Ecto

- ChzEx schemas are Ecto embedded schemas
- Validation uses Ecto.Changeset
- Compatible with Ecto types and casts

### With Phoenix

- CLI entrypoint works standalone
- Could integrate with Phoenix config for runtime overrides

### With Mix

- Config from `mix.exs` or `config/` can feed into ChzEx
- Task wrappers for CLI execution

---

## Next Steps

1. **Phase 1:** Core schema macro and field system
2. **Phase 2:** CLI parser and argument map
3. **Phase 3:** Blueprint pipeline
4. **Phase 4:** Polymorphism and registry
5. **Phase 5:** Wildcards and references
6. **Phase 6:** Validation and mungers
7. **Phase 7:** Error UX and documentation
