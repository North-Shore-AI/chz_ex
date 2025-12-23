# Changelog

## Unreleased

## [0.1.2] - 2025-12-22

### Added
- Version suffix support (`-N` convention) for schema versioning iteration tracking.
- Map schema types (`{:map_schema, %{key => type}}`) with field expansion in blueprint.
- Required/optional map fields using `{type, :required}` or `{type, :optional}` syntax.
- Heterogeneous tuple types (`{:tuple, [type1, type2, ...]}`) with per-position types.
- `meta_factory: :disabled` option to explicitly disable polymorphism on fields.
- Comprehensive Computed reference tests and verification.
- Help text improvements with warnings for missing required parameters.

### Changed
- Blueprint construction now expands map schema and tuple types as indexed parameters.
- Field macro converts ChzEx-specific types to Ecto-compatible types automatically.

## [0.1.1] - 2025-12-22

### Added
- Subclass and function meta-factories for polymorphic construction.
- Registry helpers for aliases and namespace listings.
- Union/optional type helpers, runtime type checks, and richer casting targets.
- Entrypoint variants (`dispatch`, `methods`, `nested`) and CLI error handling helper.
- Blueprint serialization to argv and config serialization to blueprint values.
- Pretty formatting, traversal utilities, and schema version hashing.
- Additional validators, override checks, and `ChzEx.Validate` macro helpers.
- New munger helpers (`transform`, `default`, `compose`, `coerce`).
- Entrypoint variants and serialization roundtrip examples.
- Type system guide documentation.

### Changed
- Standard factory resolution now supports nested attribute paths and aliases.
- Blueprint strict mode and polymorphic list construction coverage improved.
- CLI parsing can strip leading hyphens via `allow_hyphens: true`.

## [0.1.0] - 2025-12-21

- Initial port skeleton and core features.
