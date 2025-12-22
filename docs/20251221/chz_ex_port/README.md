# ChzEx Port Documentation

**Date:** 2025-12-21
**Author:** Claude
**Status:** Design Complete

---

## Overview

This directory contains the complete design documentation for porting OpenAI's `chz` Python configuration library to Elixir as `ChzEx`.

## Document Index

| Document | Description |
|----------|-------------|
| [01_ARCHITECTURE.md](01_ARCHITECTURE.md) | High-level architecture, component mapping, design decisions |
| [02_MODULE_PORTING_PLAN.md](02_MODULE_PORTING_PLAN.md) | Detailed module-by-module implementation plan with code |
| [03_API_DESIGN.md](03_API_DESIGN.md) | Public API design, usage examples, reference |
| [04_TESTING_STRATEGY.md](04_TESTING_STRATEGY.md) | Testing approach, test cases, coverage goals |
| [05_IMPLEMENTATION_GUIDE.md](05_IMPLEMENTATION_GUIDE.md) | Step-by-step implementation guide, patterns, troubleshooting |

---

## Quick Summary

### What is CHZ?

CHZ is OpenAI's configuration management library that provides:
- **Typed configuration schemas** with validation
- **CLI argument parsing** (`name=value`, `model.layers=12`)
- **Polymorphic construction** (specify factory + arguments at runtime)
- **Wildcards** (`...n_layers=100` sets all `n_layers` fields)
- **References** (`target@=source` copies values)
- **Immutability** by default

### Why Port to Elixir?

- Elixir structs are naturally immutable (no `__setattr__` hack needed)
- Ecto provides battle-tested schema/changeset infrastructure
- Pattern matching simplifies parsing and validation
- OTP supervision for registry management
- Better for building research infrastructure

### Key Differences from Python

| Aspect | Python CHZ | ChzEx |
|--------|-----------|-------|
| Schema definition | `@chz.chz` decorator | `use ChzEx.Schema` macro |
| Polymorphism | Runtime `__subclasses__()` scan | Explicit `ChzEx.Registry` |
| Type checking | Custom `tiepin.py` | Ecto types + custom cast |
| Immutability | `__setattr__` override | Native (free!) |
| Code generation | Python metaclasses | Elixir macros |

---

## Implementation Phases

### Phase 1: Foundation
- `ChzEx.Field` - Field specification struct
- `ChzEx.Schema` - Macro for schema definition
- `ChzEx.Parser` - CLI argument parsing

### Phase 2: Blueprint Core
- `ChzEx.ArgumentMap` - Layered argument storage
- `ChzEx.Wildcard` - Pattern matching
- `ChzEx.Lazy` - Deferred evaluation
- `ChzEx.Blueprint` - Pipeline orchestration

### Phase 3: Polymorphism
- `ChzEx.Factory` - MetaFactory behaviour
- `ChzEx.Registry` - Module registration

### Phase 4: Validation & Finishing
- `ChzEx.Validator` - Validation functions
- `ChzEx.Munger` - Post-init transforms
- `ChzEx.Cast` - Type casting
- Error UX and help generation

---

## Example Usage

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :name, :string, doc: "Experiment name"
    field :steps, :integer, default: 1000
    embeds_one :model, MyApp.Model, polymorphic: true
  end
end

# From CLI
{:ok, config} = ChzEx.entrypoint(MyApp.Config)
# argv: ["name=test", "model=Transformer", "model.layers=12"]

# Programmatic
{:ok, config} = ChzEx.make(MyApp.Config, %{
  "name" => "test",
  "model" => MyApp.Transformer,
  "model.layers" => 12
})
```

---

## Security Considerations

1. **No dynamic atom creation** - User input stays as strings
2. **Explicit module registry** - Only registered modules can be constructed
3. **No code evaluation** - Unlike Python's `eval()`
4. **Input validation** - All user input validated before use

---

## Files in Source CHZ

The original Python chz library is located at `chz/chz/` with these key files:

| File | Lines | Purpose |
|------|-------|---------|
| `data_model.py` | 762 | Core `@chz.chz` decorator |
| `field.py` | 300 | Field specification |
| `blueprint/_blueprint.py` | 1382 | Blueprint pipeline |
| `blueprint/_argmap.py` | 286 | Layered argument storage |
| `blueprint/_wildcard.py` | 98 | Wildcard patterns |
| `blueprint/_lazy.py` | 133 | Deferred evaluation |
| `blueprint/_argv.py` | 124 | CLI parsing |
| `factories.py` | 601 | Polymorphic factories |
| `validators.py` | 272 | Validation functions |
| `mungers.py` | 78 | Post-init transforms |
| `tiepin.py` | 1060 | Type system utilities |

---

## Next Steps

1. Create the Elixir project structure
2. Implement Phase 1 modules with tests
3. Port Python test cases incrementally
4. Iterate on API based on usage
5. Document and publish
