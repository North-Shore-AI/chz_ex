# ChzEx Actual Gap Review (2025-12-22)

## Scope
This document updates the 2025-12-22 gap analysis with the current, actual deltas
between `chz/chz` (Python) and `lib/chz_ex` (Elixir) after the latest port work.

## Status Summary
The following gaps identified in `docs/20251222/*/gaps.md` are now implemented:

- Type system parity: unions, optionals, runtime checks, enums/literals, callable refs,
  datetime/date/time, path expansion, bytes/binary, MapSet.
- Polymorphism: standard/subclass/function factories, aliases, nested attribute paths,
  `registered_factories/1`, and `serialize/2`.
- Entrypoints: dispatch, methods, nested entrypoints, and CLI error handling helpers.
- Blueprint enhancements: strict apply, argv serialization, polymorphic arrays,
  richer extraneous hints, and error context wrapping.
- Validators: `@chz_validate` macro, new validators, composition, and override checks.
- Data model utilities: pretty formatting, traversal, schema version hashes,
  and `to_blueprint_values` serialization.
- Mungers: `transform/1`, `default/1`, `compose/1`, and `coerce/1`.

## Remaining Gaps vs Python
These are the only remaining differences that are not fully ported today:

1. Fraction casting (`fractions.Fraction` in Python)
   - Elixir has no standard fraction type in stdlib.
   - Current status: not implemented.
   - Options: introduce a small Fraction struct or add a dependency and update
     `ChzEx.Cast` to map `:fraction` or a module type.

2. Path object semantics (`pathlib.Path` in Python)
   - Current Elixir behavior: `:path` casts to a binary using `Path.expand/1`.
   - If a structured path object is required, add a dedicated path struct module
     and a cast hook.

3. Python-only introspection or notebook integrations
   - Examples: `ForwardRef` evaluation, `_repr_pretty_`, `init_property`.
   - Not applicable to Elixir; mungers and `ChzEx.Pretty` cover the core use cases.

## Action Plan (If Full Parity Is Required)

- Add a lightweight fraction type and `ChzEx.Cast` support (with tests).
- Add a path struct and opt-in casting to it (with tests).
- Otherwise, no remaining functional gaps impact the current test suite or CLI UX.

## Verification Checklist

- `mix test`
- `mix format --check-formatted`
- `mix credo --strict`
- `mix dialyzer`
- `mix docs`
- `examples/run_all.sh`
