# ChzEx Actual Gap Assessment and Action Plan (2025-12-22)

This document reconciles the two provided gap analyses with the current state of the Elixir port,
then records the remaining gaps vs the Python `chz` codebase and a prioritized action plan.

## Scope And Sources

Reviewed:
- Python reference: `chz/chz/` (notably `tiepin.py`, `factories.py`, `data_model.py`,
  `validators.py`, `mungers.py`, `blueprint/_blueprint.py`, `blueprint/_argv.py`,
  `blueprint/_entrypoint.py`).
- Elixir port: `lib/chz_ex/` and `test/` plus examples in `examples/`.
- The two provided gap analyses in the prompt.

## Corrections To The Provided Gap Analyses

The following items are **now implemented** in the Elixir port and should be marked complete:
- Factory system: `ChzEx.Factory.Standard`, `ChzEx.Factory.Subclass`, `ChzEx.Factory.Function`,
  registry helpers (`register_with_aliases/4`, `all_in_namespace/1`, `registered_modules/0`),
  nested attribute paths in Standard factory, and `serialize/2` callbacks.
- Type system upgrades: union/optional helpers, `type_repr/1`, `is_instance?/2`, datetime/date/time,
  path, bytes/binary, enum/literal, mapset, and function reference casting.

The following items **remain missing** (or only partially implemented) and still need work:
- CLI entrypoint variants (nested/methods/dispatch), `allow_hyphens` parsing, and error handling
  that matches Python entrypoint behavior.
- Round-trip serialization (`beta_to_blueprint_values`, blueprint-to-argv utilities).
- Additional validators and override tracking.
- Data model utilities (pretty format, traverse, version hashing, custom inspect).
- Blueprint enhancements (strict apply, polymorphic array elements, richer extraneous errors).

The following items should be treated as **not applicable or intentionally different** in Elixir:
- Python dataclass immutability hooks (Elixir structs are immutable by default).
- Python-specific typing constructs such as `TypedDict`, `NamedTuple`, or `_repr_pretty_`.

## Current Parity Snapshot

Implemented and verified:
- Schema definition, fields, defaults, validators, and mungers (core functionality).
- Blueprint system (apply/make, references, computed values, wildcards, lazy evaluation).
- Factory system (Standard/Subclass/Function + registry).
- Type casting for common primitives, unions, optionals, literal/enum, datetime, path, bytes, mapset.

Partially implemented:
- Validators (only a subset vs Python).
- Blueprint error ergonomics (basic suggestions exist, but not full Python-level hints).
- Type checking (basic, not Python-level generic or callable signature validation).

Missing:
- Entrypoint variants, round-trip serialization, traverse/pretty, version hashing, strict apply,
  polymorphic arrays, override tracking, and a set of validators/munger helpers.

## Confirmed Gaps (By Module)

### Entrypoints And CLI
Python: `blueprint/_entrypoint.py`, `blueprint/_argv.py`
Elixir: `lib/chz_ex.ex`, `lib/chz_ex/parser.ex`

Missing:
- `nested_entrypoint`, `methods_entrypoint`, `dispatch_entrypoint`, and structured CLI error
  handling (exit codes and help formatting).
- `allow_hyphens: true` to accept `--flag=value` style input.
- Function targets: Python entrypoints accept callables; Elixir `Blueprint.new/1` only accepts
  ChzEx schemas, so entrypoints for functions are unsupported.

### Serialization And Round-Trip
Python: `beta_to_blueprint_values`, `beta_blueprint_to_argv`, `beta_argv_arg_to_string`
Elixir: no equivalent

Missing:
- `ChzEx.Serialize.to_blueprint_values/2` (flatten struct to blueprint args).
- `ChzEx.Blueprint.Serialize.to_argv/1` (blueprint to argv).
- No integration of factory `serialize/2` into any round-trip APIs.

### Validators
Python: `validators.py`
Elixir: `lib/chz_ex/validator.ex`

Missing:
- `instancecheck`, `instance_of`, `const_default`, `in_range`, `one_of`, `matches`, `not_empty`.
- Validator composition: `all/1`, `any/1`, `when_field/3`.
- `check_field_consistency_in_tree` and override tracking (IsOverrideMixin).
- `@chz.validate` decorator equivalent (Elixir uses `@chz_validate` attribute only).

### Schema/Data Model Utilities
Python: `data_model.py`
Elixir: `lib/chz_ex/schema.ex`

Missing:
- `pretty_format` / `__chz_pretty__` equivalent.
- `traverse/2` utility for recursive path walking.
- Version hashing / schema drift detection.
- Custom `Inspect` with cycle detection.
- `typecheck: true` schema option (automatic runtime type validation).

### Blueprint Enhancements
Python: `blueprint/_blueprint.py`
Elixir: `lib/chz_ex/blueprint.ex`

Missing:
- Polymorphic element construction for `embeds_many` / list fields.
- `apply(..., strict: true)` (early extraneous argument detection).
- Rich extraneous argument hints (nesting hints, allow_hyphens hint, ancestor hints).
- Exception wrapping with construction context.

### Casting And Type System
Python: `tiepin.py`
Elixir: `lib/chz_ex/type.ex`, `lib/chz_ex/cast.ex`

Remaining differences:
- No tuple casting or typed tuple support.
- No TypedDict-like map validation.
- Callable casting limited to `Module:function/arity` with explicit arity.
- `is_instance?/2` is intentionally shallow vs Python `is_subtype_instance` (no generics or
  signature validation).
- Python-specific casts (e.g., `fractions.Fraction`) are not supported.

### Factories
Python: `factories.py`
Elixir: `lib/chz_ex/factory/*.ex`, `lib/chz_ex/registry.ex`

Remaining differences:
- Subclass discovery in Python uses class hierarchies; Elixir requires explicit registry entries.
- Function factory in Python accepts lambda expressions; Elixir intentionally does not.
- `ChzEx.Factory.Function` is not integrated into Blueprint construction for polymorphic fields
  (Blueprint assumes a schema module as the factory target).

### Mungers
Python: `mungers.py`
Elixir: `lib/chz_ex/munger.ex`

Missing helpers:
- `transform/1`, `default/1`, `compose/1`, `coerce/1`.

## Technical Action Plan (Prioritized)

1. Entrypoints And CLI Ergonomics
   - Add `ChzEx.CLI` (or extend `ChzEx`) with `with_error_handling/1`, `nested_entrypoint/3`,
     `methods_entrypoint/2`, and `dispatch_entrypoint/2`.
   - Extend `ChzEx.Parser.parse/2` with `allow_hyphens: true` support.
   - Expand `Blueprint` to accept function targets or add a function wrapper entrypoint.

2. Round-Trip Serialization
   - Implement `ChzEx.Serialize.to_blueprint_values/2` to flatten configs.
   - Implement `ChzEx.Blueprint.Serialize.to_argv/1` and `beta_argv_arg_to_string`.
   - Use factory `serialize/2` for polymorphic fields.

3. Validators And Override Tracking
   - Add missing validators and composition helpers.
   - Implement `check_field_consistency_in_tree`.
   - Add an optional macro for `@chz.validate` equivalents.

4. Blueprint Enhancements
   - Add strict apply mode.
   - Add polymorphic list element construction for `embeds_many`.
   - Enrich extraneous argument errors (nesting hints, allow_hyphens suggestions).

5. Schema/Data Model Utilities
   - Implement `ChzEx.Traverse.traverse/2`.
   - Add `ChzEx.Pretty.format/2`.
   - Add schema version hash support and custom Inspect with cycle detection.

6. Type System Deepening (Optional)
   - Support tuple casting and typed tuple checks.
   - Consider typed-map validation beyond basic `{:map, k, v}`.

7. Munger Helpers
   - Add `transform`, `default`, `compose`, and `coerce` helpers.

## Testing And Documentation Updates

Testing targets to port or expand:
- Entrypoint behaviors: Python `test_blueprint.py` and `_entrypoint` cases.
- Serialization round-trip: `beta_blueprint_to_argv` and `beta_to_blueprint_values`.
- Additional validators: `test_validate.py` coverage.
- Polymorphic array construction: `test_blueprint_variadic.py`.

Documentation follow-ups:
- Add or update guides for entrypoints and serialization once implemented.
- Update examples for strict apply and serialization once available.
