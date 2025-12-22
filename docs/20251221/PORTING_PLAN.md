# ChzEx Porting Plan

**Date:** 2025-12-21  
**Goal:** Standalone Elixir port of Python `chz` for tinkex_cookbook configs  
**Status:** Planning (no implementation yet)

---

## Purpose

Provide a native Elixir configuration system that mirrors Python `chz` behavior:
- Typed config schemas
- Runtime injection via CLI (`path.to.key=value`)
- Defaults and default factories
- Validation + mungers (post-init transforms)
- Polymorphic config instantiation
- Wildcards and references for bulk overrides

This library is intended to be reusable across projects and released to Hex.

---

## Scope and Non-Goals

**In scope**
- Embedded schemas for config structs
- CLI parsing for dotted paths
- Blueprint pipeline: parse -> preprocess -> cast -> validate -> build
- Polymorphic embeds with explicit registry
- Wildcards and references
- Clear error reporting (field path + reason)

**Out of scope**
- Python-style runtime class scanning (no module auto-discovery)
- Arbitrary atom creation from user input
- Complex `argparse`-style flags (keep CLI focused on `key=value`)

---

## Dependency Strategy

**Required**
- `ecto` (embedded schemas + changesets)

**Optional**
- `polymorphic_embed` (if we want configurable polymorphism without custom type)

No `ecto_sql` required. No external CLI parser required.

---

## Architecture Map

| Python `chz` | ChzEx (Elixir) |
| --- | --- |
| `@chz.chz` class | `use ChzEx.Schema` (`embedded_schema`) |
| `chz.field()` | `field/3` + metadata |
| Validation | `Ecto.Changeset` |
| `Blueprint` | `ChzEx.Blueprint` |
| `entrypoint()` | `ChzEx.entrypoint/2` |
| Polymorphism | `ChzEx.Polymorphic` registry + embed |
| Wildcards `...` | Preprocess pass before casting |
| References `@=` | Preprocess pass before casting |

---

## Proposed Public API (MVP)

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    field :steps, :integer, default: 1000
    embeds_one :model, MyApp.ModelConfig
  end
end

{:ok, cfg} = ChzEx.entrypoint(MyApp.Config, ["model.layers=12", "steps=500"])
```

---

## Implementation Phases

### Phase 0: Skeleton + Test Harness
- Create `docs/20251221/` (this file)
- Add deps in `mix.exs` (`ecto`, optional `polymorphic_embed`)
- Set up ExUnit helpers and fixtures for CLI parsing tests

### Phase 1: Schema Macro (`ChzEx.Schema`)
- `use ChzEx.Schema` => `embedded_schema`
- `chz_schema` macro to define fields + embeds
- Support `default` and `default_factory` (handled in changeset)
- Generate `changeset/2` with required fields and custom validators

### Phase 2: CLI Parser (`ChzEx.Parser`)
- Parse `["a.b=1", "model.layers=12"]` to nested map
- Safe handling of unknown keys (no atom creation)
- Deep merge of multiple keys
- Provide `parse_argv/1` and `parse_kv/1`

### Phase 3: Blueprint Pipeline (`ChzEx.Blueprint`)
- `make(module, argv_or_map)` -> struct or changeset errors
- Apply preprocess pass (wildcards, references)
- Cast via `module.changeset/2`
- Standardize error output (path + reason)

### Phase 4: Polymorphism
- Registry of allowed modules: `%{short_name => Module}`
- Enforce explicit type field (e.g. `model.type=transformer`)
- Build embedded structs based on registry lookup
- Reject unknown type (clear error)

### Phase 5: Wildcards + References
- Wildcards: `...foo=bar` applies to all matching keys
- References: `a.b@=c.d` resolves from already-parsed values
- Run in preprocess pass before changeset casting

### Phase 6: CLI Entrypoint
- `ChzEx.entrypoint(module, argv \\ System.argv())`
- Optionally allow `--help` and `--schema` hooks
- Provide errors as `%ChzEx.Error{path, message}`

### Phase 7: Documentation + Hex Release
- README with examples + migration tips
- Publish to Hex as `chz_ex` (target `0.1.0`)

---

## Testing Plan

- **Parser tests:** dotted paths, repeated keys, list indices (if supported)
- **Schema tests:** default vs default_factory, required validation
- **Blueprint tests:** full argv -> struct conversion
- **Polymorphism tests:** allowed types, unknown types, nested embeds
- **Wildcards/refs:** precedence, merge order, error handling
- **Security tests:** ensure no atom leaks from untrusted input

---

## Security Constraints

- Never convert user input keys to atoms.
- Only allow modules registered in `ChzEx.Registry`.
- Reject unknown keys with explicit errors.

---

## Integration Targets

Primary consumer: **tinkex_cookbook** configs.  
Secondary consumers: other Tinkex apps requiring runtime CLI overrides.

Once `chz_ex` is available:
- Replace `@chz.chz` configs with `use ChzEx.Schema`
- Convert CLI usage to `ChzEx.entrypoint/2`
- Keep dataset layer on `crucible_datasets ~> 0.4.1`

---

## Open Questions

- Do we need list index support (`layers.0.size=...`)?
- Should we include `polymorphic_embed` or keep a custom type?
- Should we support env var overrides in addition to argv?

