# ChzEx Examples

Examples demonstrating ChzEx usage.

## Running Examples

```bash
# Run all examples
./run_all.sh

# Run individual example
mix run examples/basic_config.exs -- name=test value=42
```

## Examples

| File | Description |
|------|-------------|
| basic_config.exs | Simple schema with defaults |
| nested_config.exs | Nested embedded schemas |
| polymorphic_config.exs | Polymorphic type selection |
| wildcards.exs | Wildcard pattern matching |
| references.exs | Parameter references |
| validation.exs | Field and class validators |
| mungers.exs | Post-init transforms |
| presets.exs | Configuration presets |
| cli_entrypoint.exs | Full CLI application |
| help_generation.exs | --help output |
