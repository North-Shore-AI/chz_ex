# ChzEx Implementation Agent Prompt

You are tasked with completing the Elixir port of the Python `chz` configuration library. This is a comprehensive implementation task that requires careful attention to detail, test-driven development, and thorough documentation.

## Project Overview

**Repository**: ChzEx - Configuration management with CLI parsing for Elixir
**Python Source**: `./chz/chz/` - Original Python implementation
**Elixir Port**: `./lib/chz_ex/` - Partial Elixir implementation
**Gap Analysis**: `./docs/20251222/` - Detailed gap analysis documents

## Your Mission

Complete the Elixir port by implementing all missing functionality identified in the gap analysis, using TDD methodology, and ensuring production-quality code with comprehensive documentation.

---

## Phase 1: Reading & Context Gathering

**CRITICAL**: Before writing ANY code, you MUST read and understand the following files in this exact order:

### 1.1 Gap Analysis Documents (Read First)
```
docs/20251222/README.md              # Overview and priority summary
docs/20251222/tiepin/gaps.md         # Type system - HIGHEST PRIORITY
docs/20251222/factories/gaps.md      # Polymorphism - HIGH PRIORITY
docs/20251222/entrypoints/gaps.md    # CLI patterns - HIGH PRIORITY
docs/20251222/data_model/gaps.md     # Schema features
docs/20251222/blueprint/gaps.md      # Construction system
docs/20251222/validators/gaps.md     # Validation system
docs/20251222/mungers/gaps.md        # Post-init transforms
```

### 1.2 Python Source Files (Reference Implementation)
```
./chz/chz/tiepin.py                  # Type system (~1060 lines)
./chz/chz/factories.py               # Meta-factories (~601 lines)
./chz/chz/data_model.py              # Core decorator (~762 lines)
./chz/chz/validators.py              # Validators (~272 lines)
./chz/chz/mungers.py                 # Mungers (~78 lines)
./chz/chz/blueprint/__init__.py      # Blueprint exports
./chz/chz/blueprint/_blueprint.py    # Blueprint core (~1382 lines)
./chz/chz/blueprint/_argmap.py       # Argument mapping (~286 lines)
./chz/chz/blueprint/_argv.py         # CLI parsing (~124 lines)
./chz/chz/blueprint/_entrypoint.py   # Entrypoints (~241 lines)
./chz/chz/blueprint/_lazy.py         # Lazy evaluation (~133 lines)
./chz/chz/blueprint/_wildcard.py     # Wildcard patterns (~98 lines)
```

### 1.3 Python Test Files (Test Cases to Port)
```
./chz/tests/test_tiepin.py           # Type system tests (~44KB)
./chz/tests/test_data_model.py       # Data model tests (~31KB)
./chz/tests/test_validate.py         # Validation tests (~19KB)
./chz/tests/test_blueprint.py        # Blueprint tests (~22KB)
./chz/tests/test_factories.py        # Factory tests (~10KB)
./chz/tests/test_blueprint_meta_factory.py  # Meta-factory tests (~13KB)
./chz/tests/test_blueprint_variadic.py      # Array tests (~13KB)
./chz/tests/test_blueprint_reference.py     # Reference tests (~4KB)
./chz/tests/test_blueprint_cast.py          # Casting tests (~5KB)
./chz/tests/test_munge.py                   # Munger tests (~5KB)
```

### 1.4 Existing Elixir Implementation
```
./lib/chz_ex.ex                      # Main module
./lib/chz_ex/schema.ex               # Schema macro
./lib/chz_ex/field.ex                # Field specs
./lib/chz_ex/blueprint.ex            # Blueprint construction
./lib/chz_ex/blueprint/castable.ex   # Castable wrapper
./lib/chz_ex/blueprint/reference.ex  # Reference wrapper
./lib/chz_ex/blueprint/computed.ex   # Computed fields
./lib/chz_ex/argument_map.ex         # Argument storage
./lib/chz_ex/parser.ex               # CLI parsing
./lib/chz_ex/lazy.ex                 # Lazy evaluation
./lib/chz_ex/wildcard.ex             # Wildcard patterns
./lib/chz_ex/cast.ex                 # Type casting
./lib/chz_ex/factory.ex              # Factory behaviour
./lib/chz_ex/factory/standard.ex     # Standard factory
./lib/chz_ex/validator.ex            # Validators
./lib/chz_ex/munger.ex               # Mungers
./lib/chz_ex/error.ex                # Error types
./lib/chz_ex/registry.ex             # Type registry
./lib/chz_ex/help_exception.ex       # Help exception
./lib/chz_ex/application.ex          # OTP application
```

### 1.5 Existing Elixir Tests
```
./test/chz_ex_test.exs               # Main tests
./test/test_helper.exs               # Test setup
```

### 1.6 Project Configuration
```
./mix.exs                            # Project config (note current version)
./README.md                          # Current README
./CHANGELOG.md                       # If exists, or create new
```

---

## Phase 2: Implementation Order (By Priority)

Implement in this order, completing each section fully (including tests) before moving to the next:

### 2.1 Type System (`lib/chz_ex/type.ex`, `lib/chz_ex/cast.ex`)
**Gap Doc**: `docs/20251222/tiepin/gaps.md`

Implement:
- [ ] Union type representation `{:union, [type1, type2]}`
- [ ] Optional handling `make_optional/1`, `optional?/1`
- [ ] `is_instance?/2` - Runtime type checking
- [ ] DateTime/Date/Time casting
- [ ] Path casting with `~` expansion
- [ ] Enum/Literal type casting
- [ ] Callable/function reference casting
- [ ] `type_repr/1` - Human-readable type strings
- [ ] Bytes/binary casting
- [ ] MapSet casting

### 2.2 Factory System (`lib/chz_ex/factory/`)
**Gap Doc**: `docs/20251222/factories/gaps.md`

Implement:
- [ ] `ChzEx.Factory.Subclass` - Behaviour-based polymorphism
- [ ] `ChzEx.Factory.Function` - Callable factories
- [ ] `registered_factories/1` callback
- [ ] `serialize/2` callback for config reproduction
- [ ] Alias support in Standard factory
- [ ] Nested attribute path resolution (`Module:attr.nested.path`)

### 2.3 CLI Entrypoints (`lib/chz_ex/cli.ex`)
**Gap Doc**: `docs/20251222/entrypoints/gaps.md`

Implement:
- [ ] `ChzEx.CLI.with_error_handling/1` - Exit code handling
- [ ] `ChzEx.dispatch_entrypoint/2` - Multi-command dispatch
- [ ] `ChzEx.methods_entrypoint/2` - Method-based dispatch
- [ ] `ChzEx.nested_entrypoint/3` - Function wrapper
- [ ] `allow_hyphens: true` option in parser
- [ ] Improved help text formatting

### 2.4 Blueprint Enhancements (`lib/chz_ex/blueprint.ex`)
**Gap Doc**: `docs/20251222/blueprint/gaps.md`

Implement:
- [ ] `ChzEx.Blueprint.Serialize.to_argv/1` - Config to argv
- [ ] Polymorphic array element construction
- [ ] Rich extraneous argument error messages
- [ ] Exception context wrapping
- [ ] Layer nesting (`nest_subpath`)

### 2.5 Validators (`lib/chz_ex/validator.ex`)
**Gap Doc**: `docs/20251222/validators/gaps.md`

Implement:
- [ ] `@chz.validate` decorator equivalent via macro
- [ ] `check_field_consistency/3` - Tree consistency
- [ ] `in_range/2`, `one_of/1`, `matches/1`, `not_empty/0`
- [ ] `all/1`, `any/1` - Validator composition
- [ ] `when_field/3` - Conditional validation
- [ ] Override tracking mixin

### 2.6 Data Model Enhancements (`lib/chz_ex/schema.ex`)
**Gap Doc**: `docs/20251222/data_model/gaps.md`

Implement:
- [ ] `ChzEx.Pretty.format/2` - Colored terminal output
- [ ] `ChzEx.Traverse.traverse/2` - Recursive field walker
- [ ] `ChzEx.Serialize.to_blueprint_values/2` - Config serialization
- [ ] Version hashing for schema drift detection
- [ ] Custom `Inspect` implementation with cycle detection

### 2.7 Munger Enhancements (`lib/chz_ex/munger.ex`)
**Gap Doc**: `docs/20251222/mungers/gaps.md`

Implement:
- [ ] `transform/1` - Simple value transform
- [ ] `default/1` - Static default value
- [ ] `compose/1` - Munger composition
- [ ] `coerce/1` - Type coercion munger

---

## Phase 3: TDD Methodology

For EACH feature implementation:

### 3.1 Test First
```elixir
# 1. Create or update test file
# test/chz_ex/{module}_test.exs

defmodule ChzEx.{Module}Test do
  use ExUnit.Case, async: true

  describe "{feature}" do
    test "basic case" do
      # Arrange
      # Act
      # Assert
    end

    test "edge case" do
      # ...
    end

    test "error case" do
      # ...
    end
  end
end
```

### 3.2 Run Test (Should Fail)
```bash
mix test test/chz_ex/{module}_test.exs --trace
```

### 3.3 Implement Minimum Code
Write just enough code to make the test pass.

### 3.4 Run Test (Should Pass)
```bash
mix test test/chz_ex/{module}_test.exs --trace
```

### 3.5 Refactor
Clean up code while keeping tests green.

### 3.6 Run Full Suite
```bash
mix test
```

---

## Phase 4: Quality Gates

After implementing each major section, verify:

### 4.1 All Tests Pass
```bash
mix test
```

### 4.2 No Compiler Warnings
```bash
mix compile --warnings-as-errors
```

### 4.3 Code Formatting
```bash
mix format --check-formatted
```

### 4.4 Credo (if available)
```bash
mix credo --strict
```

### 4.5 Dialyzer
```bash
mix dialyzer
```

**CRITICAL**: Do NOT proceed to the next section until all quality gates pass.

---

## Phase 5: Documentation Updates

### 5.1 Update README.md

The README must include:
- Feature overview with all new capabilities
- Installation instructions
- Quick start guide
- All public API functions with examples
- CLI usage examples
- Configuration options
- Links to detailed documentation

### 5.2 Update/Create Guide Documents

Create or update in `docs/`:
- `docs/getting_started.md` - Tutorial for new users
- `docs/cli_guide.md` - CLI usage patterns
- `docs/polymorphism.md` - Factory/polymorphic construction
- `docs/validation.md` - Validation patterns
- `docs/type_system.md` - Type casting reference

### 5.3 Module Documentation

Every public module must have:
- `@moduledoc` with overview and examples
- `@doc` for every public function
- Typespecs (`@spec`) for every public function
- Usage examples in docs

---

## Phase 6: Examples

### 6.1 Create Examples Directory Structure
```
examples/
├── README.md              # Overview of all examples
├── run_all.sh             # Script to run all examples
├── basic_config/          # Simple config example
│   ├── config.ex
│   └── main.exs
├── cli_dispatch/          # dispatch_entrypoint example
│   ├── commands.ex
│   └── main.exs
├── polymorphic_types/     # Factory/polymorphism example
│   ├── models.ex
│   └── main.exs
├── nested_validation/     # Complex validation example
│   ├── config.ex
│   └── main.exs
└── escript_cli/           # Full escript example
    ├── mix.exs
    ├── lib/
    └── README.md
```

### 6.2 Examples README.md
```markdown
# ChzEx Examples

## Running Examples

```bash
# Run all examples
./run_all.sh

# Run specific example
cd basic_config && elixir main.exs
```

## Examples Overview

| Example | Description | Key Features |
|---------|-------------|--------------|
| basic_config | Simple configuration | Schema, fields, defaults |
| cli_dispatch | Multi-command CLI | dispatch_entrypoint |
| polymorphic_types | Runtime type selection | Factories, polymorphism |
| nested_validation | Complex validation | Validators, consistency |
| escript_cli | Production CLI tool | Full escript setup |
```

### 6.3 run_all.sh
```bash
#!/bin/bash
set -e

echo "=== Running ChzEx Examples ==="

for dir in */; do
  if [ -f "$dir/main.exs" ]; then
    echo ""
    echo "--- Running $dir ---"
    cd "$dir"
    elixir main.exs
    cd ..
  fi
done

echo ""
echo "=== All examples completed successfully ==="
```

---

## Phase 7: Version Bump & Changelog

### 7.1 Determine Version Bump

Current version in `mix.exs`. Based on changes:
- PATCH (x.y.Z): Bug fixes only
- MINOR (x.Y.z): New features, backward compatible
- MAJOR (X.y.z): Breaking changes

For this implementation: **MINOR bump** (new features, backward compatible)

### 7.2 Update mix.exs
```elixir
def project do
  [
    ...
    version: "0.2.0",  # Bump from 0.1.0
    ...
  ]
end
```

### 7.3 Update README.md Version Badge/Reference
Update any version references in README.md to match.

### 7.4 Create/Update CHANGELOG.md
```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-12-22

### Added
- Complete type system with union types, optionals, and runtime type checking
- DateTime, Date, Time, and Path casting support
- Enum and Literal type support
- `ChzEx.Factory.Subclass` for behaviour-based polymorphism
- `ChzEx.Factory.Function` for callable factories
- `ChzEx.dispatch_entrypoint/2` for multi-command CLI tools
- `ChzEx.methods_entrypoint/2` for method-based dispatch
- `ChzEx.nested_entrypoint/3` for function wrappers
- `ChzEx.CLI.with_error_handling/1` for proper exit codes
- `allow_hyphens: true` option for CLI argument parsing
- `ChzEx.Blueprint.Serialize.to_argv/1` for config serialization
- Polymorphic array element construction
- `@chz_validate` macro for class-level validation
- `check_field_consistency/3` for nested config validation
- New validators: `in_range/2`, `one_of/1`, `matches/1`, `not_empty/0`
- Validator composition: `all/1`, `any/1`, `when_field/3`
- `ChzEx.Pretty.format/2` for colored terminal output
- `ChzEx.Traverse.traverse/2` for recursive config walking
- `ChzEx.Serialize.to_blueprint_values/2` for config persistence
- Additional mungers: `transform/1`, `default/1`, `compose/1`
- Comprehensive examples directory
- Full documentation suite

### Changed
- Improved error messages with suggestions for typos
- Enhanced help text formatting
- Better exception context in construction errors

### Fixed
- Wildcard pattern edge cases
- Nested embed validation ordering

## [0.1.0] - 2025-12-21

### Added
- Initial release
- Basic schema definition with `chz_schema` macro
- Field specifications with defaults, validators, mungers
- Blueprint construction with lazy evaluation
- CLI argument parsing
- Wildcard pattern support
- Reference support between fields
- ArgumentMap with layered storage
- Basic type casting (string, integer, float, boolean, array, map)
- Basic validators (gt, lt, ge, le, valid_regex, typecheck)
- Basic mungers (if_none, attr_if_none)
- Error handling and help generation
- Polymorphic embedding support
- Computed fields
```

---

## Phase 8: Final Verification

Before declaring completion, run this full verification:

```bash
#!/bin/bash
set -e

echo "=== ChzEx Final Verification ==="

echo ""
echo "1. Compile with warnings as errors..."
mix compile --warnings-as-errors

echo ""
echo "2. Run all tests..."
mix test

echo ""
echo "3. Check formatting..."
mix format --check-formatted

echo ""
echo "4. Run Credo..."
mix credo --strict || echo "Credo not configured, skipping"

echo ""
echo "5. Run Dialyzer..."
mix dialyzer

echo ""
echo "6. Run examples..."
cd examples && ./run_all.sh && cd ..

echo ""
echo "7. Generate docs..."
mix docs

echo ""
echo "=== ALL CHECKS PASSED ==="
echo "Version: $(grep 'version:' mix.exs | head -1)"
```

---

## Success Criteria

You are DONE when ALL of the following are true:

1. ✅ All gap analysis items implemented
2. ✅ All tests pass (`mix test` exits 0)
3. ✅ No compiler warnings (`mix compile --warnings-as-errors` exits 0)
4. ✅ No Dialyzer warnings (`mix dialyzer` exits 0)
5. ✅ Code formatted (`mix format --check-formatted` exits 0)
6. ✅ README.md fully updated with all features
7. ✅ All guide documents created/updated
8. ✅ Examples directory complete with run_all.sh
9. ✅ All examples run successfully
10. ✅ mix.exs version bumped to 0.2.0
11. ✅ CHANGELOG.md updated with 2025-12-22 entry
12. ✅ All public functions have @doc and @spec

---

## Important Notes

1. **Read Before Write**: Always read the Python source AND existing Elixir code before implementing. The gap docs identify WHAT is missing, but you need to understand HOW it works in Python.

2. **Elixir Idioms**: Don't blindly port Python patterns. Use Elixir idioms:
   - Pattern matching over conditionals
   - Pipes over nested calls
   - Behaviours over inheritance
   - Protocols over duck typing
   - `{:ok, value}` / `{:error, reason}` over exceptions

3. **Backward Compatibility**: All existing public APIs must continue to work. Add new features, don't break old ones.

4. **Test Coverage**: Aim for comprehensive test coverage. Port relevant test cases from Python tests.

5. **Documentation**: Code without documentation is incomplete. Every public function needs docs and examples.

6. **Incremental Commits**: Commit after each major section with descriptive messages.

---

## Getting Started

Begin by reading the files in Phase 1 in order. Take notes on:
- What functionality exists in Python
- What's already implemented in Elixir
- What's missing (per gap docs)
- How to implement in idiomatic Elixir

Then proceed through Phases 2-8 systematically.

Good luck! 🚀
