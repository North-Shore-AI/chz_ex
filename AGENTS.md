# ChzEx Agent Instructions

This file is the single source of truth for contributors (human or AI) working in this repo.

## Project Goal

ChzEx is an Elixir port of OpenAI's `chz` library. The implementation must match the Python behavior described in the design docs and tests.

## Required Reading (in order)

1. `docs/20251221/chz_ex_port/README.md`
2. `docs/20251221/chz_ex_port/01_ARCHITECTURE.md`
3. `docs/20251221/chz_ex_port/02_MODULE_PORTING_PLAN.md`
4. `docs/20251221/chz_ex_port/03_API_DESIGN.md`
5. `docs/20251221/chz_ex_port/04_TESTING_STRATEGY.md`
6. `docs/20251221/chz_ex_port/05_IMPLEMENTATION_GUIDE.md`

Python reference implementation (behavior spec):

- `chz/chz/__init__.py`
- `chz/chz/data_model.py`
- `chz/chz/field.py`
- `chz/chz/blueprint/_blueprint.py`
- `chz/chz/blueprint/_argmap.py`
- `chz/chz/blueprint/_wildcard.py`
- `chz/chz/blueprint/_lazy.py`
- `chz/chz/blueprint/_argv.py`
- `chz/chz/blueprint/_entrypoint.py`
- `chz/chz/factories.py`
- `chz/chz/validators.py`
- `chz/chz/mungers.py`
- `chz/chz/tiepin.py`
- `chz/chz/util.py`

Python tests to port:

- `chz/tests/test_blueprint.py`
- `chz/tests/test_blueprint_cast.py`
- `chz/tests/test_blueprint_errors.py`
- `chz/tests/test_blueprint_reference.py`
- `chz/tests/test_blueprint_variadic.py`
- `chz/tests/test_blueprint_root_polymorphism.py`
- `chz/tests/test_data_model.py`
- `chz/tests/test_factories.py`
- `chz/tests/test_munge.py`
- `chz/tests/test_validate.py`
- `chz/tests/test_tiepin.py`

Python docs for behavior details:

- `chz/docs/01_intro.md`
- `chz/docs/02_chzclass.md`
- `chz/docs/03_field.md`
- `chz/docs/04_validation.md`
- `chz/docs/05_blueprint.md`
- `chz/docs/06_entrypoint.md`
- `chz/docs/07_polymorphism.md`
- `chz/docs/10_mungers.md`
- `chz/docs/21_post_init.md`

## Implementation Rules

- Follow the design docs and port tests first (TDD).
- **No atom creation from user input.** Keep keys as strings until matched against schema.
- Use Ecto changesets for validation when possible.
- Errors should include context and suggestions.
- Use `rg` for search.
- Default to ASCII; only use non-ASCII if the file already uses it and it is necessary.

## File Layout (must match)

```
lib/
  chz_ex.ex
  chz_ex/
    schema.ex
    field.ex
    parser.ex
    blueprint.ex
    blueprint/
      castable.ex
      reference.ex
      computed.ex
    argument_map.ex
    wildcard.ex
    lazy.ex
    factory.ex
    factory/
      standard.ex
    registry.ex
    validator.ex
    munger.ex
    cast.ex
    error.ex
test/
  test_helper.exs
  support/fixtures.ex
  chz_ex_test.exs
  chz_ex/
    ...
examples/
  README.md
  run_all.sh
  *.exs
```

## Quality Gates

Run these before declaring work complete:

```
mix format
mix test
mix credo --strict
mix dialyzer
mix docs
```

Examples:

```
examples/run_all.sh
```

## Safety

- Do not use destructive git commands (`git reset --hard`, etc.) unless explicitly asked.
- If you notice unexpected changes in unrelated files, stop and ask for guidance.
