# Entrypoints Gap Analysis

**Python Source**: `chz/blueprint/_entrypoint.py` (~241 lines), `chz/universal.py` (~unknown lines)
**Elixir Port**: `lib/chz_ex.ex` (entrypoint functions, ~47 lines)

## Overview

The Python `_entrypoint.py` provides multiple CLI entry point patterns for different use cases. The Elixir port has basic `entrypoint/2` but is missing the specialized variants.

## Ported Functionality

### Fully Implemented
| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Basic entrypoint | `chz.entrypoint(Target)` | `ChzEx.entrypoint/2` | Parse argv, construct |
| Bang variant | N/A | `ChzEx.entrypoint!/2` | Raises on error |
| Make from map | `Blueprint.make()` | `ChzEx.make/2` | Non-CLI construction |
| Help exception | `EntrypointHelpException` | `ChzEx.HelpException` | Display help |

### Partially Implemented
| Feature | Python | Elixir | Missing |
|---------|--------|--------|---------|
| Error handling | `@exit_on_entrypoint_error` | Basic try/rescue | Exit codes, formatting |

## Missing Functionality

### 1. `nested_entrypoint`
**Lines**: 84-109

**Python Behavior**:
```python
@exit_on_entrypoint_error
def nested_entrypoint(
    main: Callable[[Any], _T], *, argv: list[str] | None = None, allow_hyphens: bool = False
) -> _T:
    """Easy way to create a script entrypoint for functions that take a chz object.

    Example:
        @chz.chz
        class Run:
            name: str

        def main(run: Run) -> None:
            ...

        if __name__ == "__main__":
            chz.nested_entrypoint(main)
    """
    target = get_nested_target(main)
    value = chz.Blueprint(target).make_from_argv(argv, allow_hyphens=allow_hyphens)
    return main(value)
```

**Elixir Gap**:
- No equivalent
- Would need to inspect function arguments

**Recommendation**:
```elixir
defmodule ChzEx do
  @doc """
  Entrypoint for functions that take a ChzEx struct as argument.

  ## Example

      defmodule MyApp.Config do
        use ChzEx.Schema
        chz_schema do
          field :name, :string
        end
      end

      defmodule MyApp.CLI do
        def main(config) do
          IO.puts("Running with: \#{config.name}")
        end
      end

      # In your escript or mix task:
      ChzEx.nested_entrypoint(&MyApp.CLI.main/1, MyApp.Config)
  """
  def nested_entrypoint(main_fn, target_module, argv \\ System.argv()) do
    case entrypoint(target_module, argv) do
      {:ok, config} -> {:ok, main_fn.(config)}
      {:error, _} = err -> err
    end
  end

  def nested_entrypoint!(main_fn, target_module, argv \\ System.argv()) do
    config = entrypoint!(target_module, argv)
    main_fn.(config)
  end
end
```

**Priority**: Medium - Convenient pattern

---

### 2. `methods_entrypoint`
**Lines**: 111-169

**Python Behavior**:
```python
@exit_on_entrypoint_error
def methods_entrypoint(
    target: type[_T],
    *,
    argv: list[str] | None = None,
    transform: Callable[[Blueprint, Any, str], Blueprint] | None = None,
) -> _T:
    """Easy way to create a script entrypoint for methods on a class.

    Example:
        @chz.chz
        class Run:
            name: str

            def launch(self, cluster: str):
                return ("launch", self, cluster)

        if __name__ == "__main__":
            print(chz.methods_entrypoint(Run))

    Command line:
        python main.py launch self.name=job cluster=owl
        python main.py launch --help
        python main.py --help
    """
```

**Elixir Gap**:
- No equivalent
- Would need function discovery

**Recommendation**:
```elixir
defmodule ChzEx do
  @doc """
  Entrypoint that dispatches to methods on a module.

  ## Example

      defmodule MyApp.Commands do
        use ChzEx.Schema

        chz_schema do
          field :name, :string
        end

        def launch(config, opts) do
          cluster = Keyword.fetch!(opts, :cluster)
          {:launch, config.name, cluster}
        end

        def status(config, _opts) do
          {:status, config.name}
        end

        # Register available commands
        def __chz_commands__ do
          [
            {:launch, "Launch a job on a cluster", [cluster: :string]},
            {:status, "Check job status", []}
          ]
        end
      end

      # Usage: mix my_app launch name=foo cluster=owl
      ChzEx.methods_entrypoint(MyApp.Commands)
  """
  def methods_entrypoint(target, argv \\ System.argv(), opts \\ []) do
    case argv do
      [] ->
        show_methods_help(target)
        {:error, :no_command}

      ["--help"] ->
        show_methods_help(target)
        {:ok, :help}

      [method | rest] ->
        dispatch_method(target, method, rest, opts)
    end
  end

  defp show_methods_help(target) do
    IO.puts("Available commands for #{inspect(target)}:")

    if function_exported?(target, :__chz_commands__, 0) do
      target.__chz_commands__()
      |> Enum.each(fn {name, doc, _args} ->
        IO.puts("  #{name}  #{doc}")
      end)
    else
      # Introspect public functions
      target.__info__(:functions)
      |> Enum.filter(fn {name, arity} -> arity >= 1 and not hidden?(name) end)
      |> Enum.each(fn {name, arity} ->
        IO.puts("  #{name}/#{arity}")
      end)
    end
  end

  defp hidden?(name), do: String.starts_with?(Atom.to_string(name), "_")

  defp dispatch_method(target, method_str, argv, opts) do
    method = String.to_existing_atom(method_str)
    transform = Keyword.get(opts, :transform)

    # Build blueprint for target + method args
    bp = Blueprint.new(target)
    bp = if transform, do: transform.(bp, target, method_str), else: bp

    case Blueprint.make_from_argv(bp, argv) do
      {:ok, config} ->
        # Call the method with config and remaining args
        apply(target, method, [config, []])

      {:error, _} = err ->
        err
    end
  end
end
```

**Priority**: Medium - Useful for CLI tools

---

### 3. `dispatch_entrypoint`
**Lines**: 172-213

**Python Behavior**:
```python
@exit_on_entrypoint_error
def dispatch_entrypoint(
    targets: dict[str, Callable[..., _T]], *, argv: list[str] | None = None
) -> _T:
    """Easy way to create a script entrypoint for dispatching to different functions.

    Example:
        def say_hello(name: str) -> None:
            print(f"Hello, {name}!")

        def say_goodbye(name: str) -> None:
            print(f"Goodbye, {name}!")

        chz.dispatch_entrypoint({
            "hello": say_hello,
            "goodbye": say_goodbye,
        })
    """
```

**Elixir Gap**:
- No equivalent
- Simpler than methods_entrypoint

**Recommendation**:
```elixir
defmodule ChzEx do
  @doc """
  Dispatch to different config modules based on first argument.

  ## Example

      ChzEx.dispatch_entrypoint(%{
        "train" => MyApp.TrainConfig,
        "eval" => MyApp.EvalConfig,
        "serve" => MyApp.ServeConfig
      })
  """
  def dispatch_entrypoint(targets, argv \\ System.argv()) when is_map(targets) do
    case argv do
      [] ->
        show_dispatch_help(targets)
        {:error, :no_command}

      ["--help"] ->
        show_dispatch_help(targets)
        {:ok, :help}

      [command | rest] ->
        case Map.fetch(targets, command) do
          {:ok, target} ->
            entrypoint(target, rest)

          :error ->
            IO.puts(:stderr, "Unknown command: #{command}")
            show_dispatch_help(targets)
            {:error, {:unknown_command, command}}
        end
    end
  end

  defp show_dispatch_help(targets) do
    IO.puts("Available commands:")

    targets
    |> Enum.each(fn {name, target} ->
      doc = get_module_doc(target)
      IO.puts("  #{name}  #{doc}")
    end)
  end

  defp get_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} ->
        doc |> String.split("\n") |> hd()

      _ ->
        ""
    end
  end
end
```

**Priority**: High - Very common CLI pattern

---

### 4. `get_nested_target`
**Lines**: 225-241

**Python Behavior**:
```python
def get_nested_target(main: Callable[[_T], object]) -> type[_T]:
    """Returns the type of the first argument of a function.

    Example:
        def main(run: Run) -> None: ...
        assert chz.get_nested_target(main) is Run
    """
```

**Elixir Gap**:
- No runtime type annotation access
- Elixir functions don't have introspectable type annotations

**Alternative**:
```elixir
# In Elixir, require explicit target module:
ChzEx.nested_entrypoint(&main/1, RunConfig)

# Or use a convention:
defmodule MyApp.CLI do
  @chz_target MyApp.Config

  def main(config) do
    # ...
  end
end
```

**Priority**: Low - Elixir patterns differ

---

### 5. `exit_on_entrypoint_error` Decorator
**Lines**: 35-50

**Python Behavior**:
```python
def exit_on_entrypoint_error(fn: _F) -> _F:
    @functools.wraps(fn)
    def inner(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except EntrypointException as e:
            if isinstance(e, EntrypointHelpException):
                print(e, end="")
            else:
                print("Error:", file=sys.stderr)
                print(e, file=sys.stderr)
            if "PYTEST_VERSION" in os.environ:
                raise
            sys.exit(1)
    return inner
```

**Elixir Gap**:
- No automatic exit on error
- No pytest detection

**Recommendation**:
```elixir
defmodule ChzEx.CLI do
  @doc """
  Wrap an entrypoint to handle errors and exit appropriately.
  """
  def with_error_handling(fun) do
    try do
      case fun.() do
        {:ok, result} -> result
        {:error, %ChzEx.HelpException{message: msg}} ->
          IO.puts(msg)
          System.halt(0)
        {:error, error} ->
          IO.puts(:stderr, "Error: #{format_error(error)}")
          unless Mix.env() == :test, do: System.halt(1)
      end
    rescue
      e in ChzEx.HelpException ->
        IO.puts(e.message)
        System.halt(0)

      e in ChzEx.ConfigError ->
        IO.puts(:stderr, "Error: #{Exception.message(e)}")
        unless Mix.env() == :test, do: System.halt(1)
    end
  end

  defp format_error(%ChzEx.Error{} = e), do: ChzEx.Error.format(e)
  defp format_error(errors) when is_list(errors), do: Enum.map_join(errors, "\n", &format_error/1)
  defp format_error(error), do: inspect(error)
end

# Usage in escript:
defmodule MyApp.CLI do
  def main(argv) do
    ChzEx.CLI.with_error_handling(fn ->
      ChzEx.entrypoint(MyApp.Config, argv)
    end)
  end
end
```

**Priority**: High - Essential for CLI tools

---

### 6. Universal Entrypoint (`python -m chz.universal`)
**Source**: `chz/universal.py`

**Python Behavior**:
```bash
# Can run any chz class directly from command line:
python -m chz.universal my_module:MyConfig name=foo
python -m chz.universal my_module:my_function arg=value
```

**Elixir Gap**:
- No equivalent universal runner

**Recommendation**:
```elixir
# Create a mix task:
defmodule Mix.Tasks.ChzEx.Run do
  use Mix.Task

  @shortdoc "Run a ChzEx config from command line"

  def run(argv) do
    case argv do
      [] ->
        IO.puts("Usage: mix chz_ex.run Module.Name key=value ...")

      [module_str | args] ->
        module = Module.concat([module_str])

        if ChzEx.Schema.is_chz?(module) do
          ChzEx.CLI.with_error_handling(fn ->
            ChzEx.entrypoint(module, args)
          end)
          |> IO.inspect()
        else
          IO.puts(:stderr, "#{module} is not a ChzEx schema")
        end
    end
  end
end
```

**Priority**: Low - Mix tasks cover this use case

---

## Exception Classes

### Ported
| Python | Elixir | Notes |
|--------|--------|-------|
| `EntrypointHelpException` | `ChzEx.HelpException` | Help display |
| `InvalidBlueprintArg` | `ChzEx.Error{type: :invalid_value}` | Invalid args |
| `MissingBlueprintArg` | `ChzEx.Error{type: :missing_required}` | Missing args |
| `ExtraneousBlueprintArg` | `ChzEx.Error{type: :extraneous}` | Unknown args |

### Missing
| Python | Description | Priority |
|--------|-------------|----------|
| `ConstructionException` | Wraps construction failures | Medium |
| `EntrypointException` | Base class | Low (Elixir pattern differs) |

---

## Escript Integration

For Elixir CLI tools, consider this pattern:

```elixir
# mix.exs
def project do
  [
    ...
    escript: [main_module: MyApp.CLI]
  ]
end

# lib/my_app/cli.ex
defmodule MyApp.CLI do
  def main(argv) do
    Application.ensure_all_started(:my_app)

    ChzEx.CLI.with_error_handling(fn ->
      ChzEx.dispatch_entrypoint(%{
        "train" => MyApp.TrainConfig,
        "eval" => MyApp.EvalConfig
      }, argv)
    end)
  end
end
```

---

## Implementation Priority Summary

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| dispatch_entrypoint | High | Low | Common pattern |
| exit_on_entrypoint_error | High | Low | CLI polish |
| methods_entrypoint | Medium | Medium | Tool building |
| nested_entrypoint | Medium | Low | Convenience |
| Universal runner | Low | Medium | Mix tasks cover this |
| get_nested_target | Low | N/A | Elixir pattern differs |

## Recommended CLI Module

```elixir
defmodule ChzEx.CLI do
  # Error handling
  def with_error_handling(fun)

  # Dispatch patterns
  def dispatch(targets, argv)
  def methods(target, argv)
  def nested(main_fn, target, argv)

  # Help generation
  def show_help(target)
  def show_dispatch_help(targets)
  def show_methods_help(target)
end
```
