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

## Hyphenated Flags

Use `allow_hyphens: true` to accept `--flag=value` or `-flag=value` styles:

```elixir
ChzEx.entrypoint(MyApp.Config, System.argv(), allow_hyphens: true)
```

## Strict Mode

To fail fast on unknown arguments, enable strict mode:

```elixir
{:ok, bp} = ChzEx.Blueprint.apply_from_argv(blueprint, argv, strict: true)
```

## Entrypoint Variants

ChzEx also supports command dispatch and method-style CLIs:

```elixir
ChzEx.dispatch_entrypoint(%{"run" => MyApp.Run, "tune" => MyApp.Tune})
ChzEx.methods_entrypoint(MyApp.Commands)
ChzEx.nested_entrypoint(&MyApp.CLI.main/1, MyApp.Config)
```
