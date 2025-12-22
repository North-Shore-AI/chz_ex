# CLI Parsing

ChzEx parses `key=value` pairs from argv and applies them to schemas.

## Basic Keys

```bash
mix run script.exs -- name=experiment1 value=42
```

## Nested Keys

```bash
mix run script.exs -- model.hidden_dim=256 model.num_layers=6
```

## Wildcards

```bash
mix run script.exs -- ...dropout=0.1
```

## References

```bash
mix run script.exs -- target@=source
```

## Help

```bash
mix run script.exs -- --help
```
