# ChzEx Implementation Prompt

**Purpose:** Complete implementation prompt for building ChzEx from the design docs using TDD.

---

## REQUIRED READING

Before implementing, you MUST read and understand these files in order:

### Design Documents (Read First)

```
docs/20251221/chz_ex_port/
├── README.md                    # Overview and summary
├── 01_ARCHITECTURE.md           # Architecture, component mapping, design decisions
├── 02_MODULE_PORTING_PLAN.md    # Module-by-module with Elixir code
├── 03_API_DESIGN.md             # Public API, 10 usage examples
├── 04_TESTING_STRATEGY.md       # Test categories, example tests
└── 05_IMPLEMENTATION_GUIDE.md   # Step-by-step, patterns, troubleshooting
```

### Python Source Files (Reference Implementation)

Read these to understand the exact behavior to port:

```
chz/chz/
├── __init__.py                  # Public API exports
├── data_model.py                # @chz.chz decorator, class transformation (762 lines)
├── field.py                     # Field specification (300 lines)
├── blueprint/
│   ├── __init__.py              # Blueprint, Castable, Reference exports
│   ├── _blueprint.py            # Main pipeline (1382 lines) - CRITICAL
│   ├── _argmap.py               # ArgumentMap, Layer (286 lines)
│   ├── _wildcard.py             # Wildcard patterns (98 lines)
│   ├── _lazy.py                 # Value, ParamRef, Thunk, evaluate (133 lines)
│   ├── _argv.py                 # CLI parsing (124 lines)
│   └── _entrypoint.py           # entrypoint, nested_entrypoint (400+ lines)
├── factories.py                 # MetaFactory, standard, subclass, function (601 lines)
├── validators.py                # Validation functions (272 lines)
├── mungers.py                   # Post-init transforms (78 lines)
├── tiepin.py                    # Type system utilities (1060 lines)
└── util.py                      # MISSING sentinel, utilities
```

### Python Test Files (Behavior Specification)

These define expected behavior - port these tests:

```
chz/tests/
├── test_blueprint.py            # Core blueprint tests
├── test_blueprint_cast.py       # Type casting tests
├── test_blueprint_errors.py     # Error handling tests
├── test_blueprint_reference.py  # Reference (@=) tests
├── test_blueprint_variadic.py   # Variadic/list tests
├── test_blueprint_root_polymorphism.py  # Polymorphism tests
├── test_data_model.py           # Schema/decorator tests
├── test_factories.py            # Factory tests
├── test_munge.py                # Munger tests
├── test_validate.py             # Validator tests
└── test_tiepin.py               # Type system tests
```

### Python Documentation

```
chz/docs/
├── 01_intro.md                  # Introduction
├── 02_chzclass.md               # @chz.chz details
├── 03_field.md                  # Field options
├── 04_validation.md             # Validation patterns
├── 05_blueprint.md              # Blueprint usage
├── 06_entrypoint.md             # CLI entrypoints
├── 07_polymorphism.md           # Polymorphic construction
├── 10_mungers.md                # Mungers
└── 21_post_init.md              # Post-init patterns
```

---

## PROJECT STRUCTURE

Create this exact structure:

```
lib/
├── chz_ex.ex                    # Main API module
└── chz_ex/
    ├── schema.ex                # use ChzEx.Schema macro
    ├── field.ex                 # Field struct
    ├── parser.ex                # CLI argument parsing
    ├── blueprint.ex             # Blueprint struct and pipeline
    ├── blueprint/
    │   ├── castable.ex          # Castable struct
    │   ├── reference.ex         # Reference struct
    │   └── computed.ex          # Computed struct
    ├── argument_map.ex          # Layered argument storage
    ├── wildcard.ex              # Wildcard pattern matching
    ├── lazy.ex                  # Value, ParamRef, Thunk, evaluate
    ├── factory.ex               # MetaFactory behaviour
    ├── factory/
    │   └── standard.ex          # Standard factory implementation
    ├── registry.ex              # Module registry (GenServer)
    ├── validator.ex             # Validation functions
    ├── munger.ex                # Munger functions
    ├── cast.ex                  # Type casting from strings
    └── error.ex                 # Error struct and formatting

test/
├── test_helper.exs
├── support/
│   └── fixtures.ex              # Shared test schemas
├── chz_ex_test.exs              # Main API tests
└── chz_ex/
    ├── field_test.exs
    ├── schema_test.exs
    ├── parser_test.exs
    ├── blueprint_test.exs
    ├── argument_map_test.exs
    ├── wildcard_test.exs
    ├── lazy_test.exs
    ├── factory_test.exs
    ├── registry_test.exs
    ├── validator_test.exs
    ├── munger_test.exs
    ├── cast_test.exs
    ├── error_test.exs
    ├── polymorphism_test.exs
    ├── reference_test.exs
    └── integration_test.exs

examples/
├── README.md                    # Examples documentation
├── run_all.sh                   # Script to run all examples
├── basic_config.exs             # Basic usage
├── nested_config.exs            # Nested structs
├── polymorphic_config.exs       # Polymorphism
├── wildcards.exs                # Wildcard patterns
├── references.exs               # References
├── validation.exs               # Custom validation
├── mungers.exs                  # Post-init transforms
├── presets.exs                  # Preset configurations
├── cli_entrypoint.exs           # CLI entrypoint
└── help_generation.exs          # Help text generation
```

---

## IMPLEMENTATION ORDER (TDD)

Follow this exact order. For each module:
1. Write tests first based on Python behavior
2. Implement until tests pass
3. Run `mix format`, `mix credo --strict`, `mix dialyzer`
4. Fix any warnings before proceeding

### Phase 1: Foundation

#### 1.1 ChzEx.Field (test/chz_ex/field_test.exs → lib/chz_ex/field.ex)

Tests to write:
```elixir
describe "new/3" do
  test "creates field with name and type"
  test "sets default value"
  test "sets default_factory"
  test "rejects both default and default_factory"
  test "normalizes validators to list"
  test "accepts munger function"
  test "stores metadata"
end

describe "has_default?/1" do
  test "false when no default"
  test "true with static default"
  test "true with default_factory"
end

describe "get_default/1" do
  test "returns static default"
  test "calls default_factory"
  test "returns nil when no default"
end

describe "required?/1" do
  test "true when no default"
  test "false when has default"
end
```

#### 1.2 ChzEx.Schema (test/chz_ex/schema_test.exs → lib/chz_ex/schema.ex)

Tests to write:
```elixir
describe "chz_schema macro" do
  test "creates struct with fields"
  test "sets default values"
  test "generates __chz_fields__/0"
  test "generates __chz__?/0 returning true"
  test "generates changeset/2"
end

describe "field types" do
  test "supports :string"
  test "supports :integer"
  test "supports :float"
  test "supports :boolean"
  test "supports {:array, :string}"
end

describe "embeds_one" do
  test "embeds nested schema"
  test "casts nested params"
end

describe "embeds_many" do
  test "embeds list of schemas"
  test "casts list of params"
end

describe "is_chz?/1" do
  test "true for chz module"
  test "true for chz struct"
  test "false for regular module"
  test "false for regular struct"
end
```

#### 1.3 ChzEx.Parser (test/chz_ex/parser_test.exs → lib/chz_ex/parser.ex)

Tests to write:
```elixir
describe "parse/1" do
  test "parses key=value"
  test "parses multiple arguments"
  test "parses dotted paths"
  test "handles equals in value"
  test "errors on missing equals"
  test "detects --help flag"
end

describe "parse_arg/1" do
  test "returns Castable for normal values"
  test "returns Reference for @= syntax"
end

describe "help_requested?/1" do
  test "detects --help"
  test "detects -h"
  test "detects help"
end
```

Also create:
- `lib/chz_ex/blueprint/castable.ex`
- `lib/chz_ex/blueprint/reference.ex`
- `lib/chz_ex/blueprint/computed.ex`

### Phase 2: Blueprint Core

#### 2.1 ChzEx.Wildcard (test/chz_ex/wildcard_test.exs → lib/chz_ex/wildcard.ex)

Tests to write:
```elixir
describe "to_regex/1" do
  test "prefix wildcard ...key"
  test "infix wildcard a...b"
  test "multiple wildcards ...a...b"
  test "no wildcard returns exact match"
  test "errors on trailing wildcard"
end

describe "matches?/2" do
  test "exact match"
  test "prefix wildcard matches"
  test "nested path matches"
end

describe "approximate/2" do
  test "high score for similar keys"
  test "returns suggestion string"
  test "low score for different keys"
end
```

#### 2.2 ChzEx.ArgumentMap (test/chz_ex/argument_map_test.exs → lib/chz_ex/argument_map.ex)

Tests to write:
```elixir
describe "add_layer/3" do
  test "adds layer with args"
  test "stores layer name"
end

describe "consolidate/1" do
  test "consolidates qualified keys"
  test "consolidates wildcard patterns"
  test "is idempotent"
end

describe "get_kv/2" do
  test "finds exact match"
  test "finds wildcard match"
  test "later layer overrides earlier"
  test "returns nil when not found"
  test "includes layer info in result"
end

describe "subpaths/2" do
  test "finds qualified subpaths"
  test "finds wildcard subpaths"
  test "respects strict option"
end
```

#### 2.3 ChzEx.Lazy (test/chz_ex/lazy_test.exs → lib/chz_ex/lazy.ex)

Tests to write:
```elixir
describe "evaluate/1" do
  test "evaluates Value"
  test "resolves ParamRef"
  test "evaluates Thunk with resolved kwargs"
  test "caches resolved values"
  test "detects cycles"
  test "requires root entry"
end

describe "check_reference_targets/2" do
  test "returns :ok for valid refs"
  test "returns error with suggestions for invalid"
end
```

#### 2.4 ChzEx.Blueprint (test/chz_ex/blueprint_test.exs → lib/chz_ex/blueprint.ex)

Tests to write:
```elixir
describe "new/1" do
  test "creates blueprint for chz module"
  test "errors for non-chz module"
end

describe "apply/3" do
  test "adds argument layer"
  test "supports layer_name option"
  test "supports subpath option"
end

describe "apply_from_argv/2" do
  test "parses and applies argv"
  test "raises HelpException on --help"
end

describe "make/1" do
  test "constructs simple struct"
  test "applies defaults"
  test "casts string values"
  test "returns error for missing required"
  test "returns error for extraneous args"
end

describe "make_from_argv/2" do
  test "full pipeline from argv to struct"
end

describe "get_help/2" do
  test "includes all parameters"
  test "shows defaults"
  test "shows types"
  test "shows doc strings"
end
```

### Phase 3: Polymorphism

#### 3.1 ChzEx.Registry (test/chz_ex/registry_test.exs → lib/chz_ex/registry.ex)

Tests to write:
```elixir
describe "register/3" do
  test "registers module under namespace"
end

describe "lookup/2" do
  test "finds registered module"
  test "returns :error for unknown"
end

describe "find_by_name/2" do
  test "searches all namespaces"
end

describe "register_module/1" do
  test "allows module for polymorphic use"
end

describe "lookup_module/1" do
  test "finds registered module by string"
  test "rejects unregistered modules"
end
```

#### 3.2 ChzEx.Factory (test/chz_ex/factory_test.exs → lib/chz_ex/factory.ex + lib/chz_ex/factory/standard.ex)

Tests to write:
```elixir
describe "Standard.unspecified_factory/1" do
  test "returns module for chz annotation"
  test "returns explicit unspecified"
  test "returns nil for non-instantiable"
end

describe "Standard.from_string/2" do
  test "resolves short name from registry"
  test "resolves fully qualified module:attr"
  test "errors for unknown"
end

describe "Standard.perform_cast/2" do
  test "casts to annotation type"
end
```

#### 3.3 Polymorphism Integration (test/chz_ex/polymorphism_test.exs)

Tests to write:
```elixir
describe "polymorphic embeds" do
  test "uses default factory when unspecified"
  test "resolves factory from string"
  test "passes subpath args to factory"
  test "errors for unknown factory"
end
```

### Phase 4: Validation & Casting

#### 4.1 ChzEx.Cast (test/chz_ex/cast_test.exs → lib/chz_ex/cast.ex)

Tests to write:
```elixir
describe "try_cast/2" do
  test "casts to :string"
  test "casts to :integer"
  test "casts to :float"
  test "casts to :boolean (true/false/t/f/1/0)"
  test "casts to {:array, type}"
  test "casts to {:map, k, v}"
  test "returns error for invalid"
end
```

#### 4.2 ChzEx.Validator (test/chz_ex/validator_test.exs → lib/chz_ex/validator.ex)

Tests to write:
```elixir
describe "typecheck/2" do
  test "passes for correct type"
  test "fails for wrong type"
end

describe "gt/1" do
  test "passes when greater"
  test "fails when not greater"
end

describe "lt/1, ge/1, le/1" do
  test "comparison validators work"
end

describe "valid_regex/2" do
  test "passes for valid regex"
  test "fails for invalid regex"
end

describe "for_all_fields/1" do
  test "applies validator to all fields"
end
```

#### 4.3 ChzEx.Munger (test/chz_ex/munger_test.exs → lib/chz_ex/munger.ex)

Tests to write:
```elixir
describe "if_none/1" do
  test "replaces nil with function result"
  test "keeps non-nil value"
end

describe "attr_if_none/1" do
  test "replaces nil with other attr"
  test "keeps non-nil value"
end

describe "from_function/1" do
  test "wraps 2-arity function"
end
```

#### 4.4 ChzEx.Error (test/chz_ex/error_test.exs → lib/chz_ex/error.ex)

Tests to write:
```elixir
describe "error formatting" do
  test "formats missing_required error"
  test "formats extraneous error with suggestions"
  test "formats validation_error"
  test "formats cast_error"
  test "formats cycle error"
end
```

### Phase 5: Main API & Integration

#### 5.1 ChzEx (test/chz_ex_test.exs → lib/chz_ex.ex)

Tests to write:
```elixir
describe "entrypoint/2" do
  test "parses argv and returns struct"
  test "returns error tuple on failure"
end

describe "entrypoint!/2" do
  test "returns struct on success"
  test "raises on failure"
end

describe "make/2" do
  test "creates struct from map"
end

describe "make!/2" do
  test "creates struct or raises"
end

describe "is_chz?/1" do
  test "delegates to Schema"
end

describe "chz_fields/1" do
  test "returns field map"
end

describe "replace/2" do
  test "updates fields via changeset"
end

describe "asdict/2" do
  test "converts to map"
  test "recursive by default"
  test "shallow option"
end
```

#### 5.2 Integration Tests (test/chz_ex/integration_test.exs)

Tests to write:
```elixir
describe "full pipeline" do
  test "basic CLI parsing"
  test "nested structs"
  test "polymorphic construction"
  test "wildcards"
  test "references"
  test "validation"
  test "mungers"
  test "error messages with suggestions"
  test "help generation"
end
```

#### 5.3 Reference Tests (test/chz_ex/reference_test.exs)

Port tests from `chz/tests/test_blueprint_reference.py`.

---

## EXAMPLES

### examples/README.md

```markdown
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
```

### examples/run_all.sh

```bash
#!/bin/bash
set -e

echo "=== ChzEx Examples ==="
echo

examples=(
  "basic_config.exs name=test value=42"
  "nested_config.exs name=exp model.hidden_dim=256"
  "polymorphic_config.exs name=exp optimizer=sgd optimizer.momentum=0.99"
  "wildcards.exs name=exp ...activation=gelu"
  "references.exs base_dim=512"
  "validation.exs value=50"
  "mungers.exs name=experiment"
  "presets.exs small model.num_heads=4"
  "cli_entrypoint.exs name=myapp --help"
  "help_generation.exs"
)

for example in "${examples[@]}"; do
  file=$(echo "$example" | cut -d' ' -f1)
  args=$(echo "$example" | cut -d' ' -f2-)

  echo "--- Running: $file $args ---"
  mix run "examples/$file" -- $args || true
  echo
done

echo "=== All examples completed ==="
```

### examples/basic_config.exs

```elixir
# Basic ChzEx configuration example

defmodule Examples.BasicConfig do
  use ChzEx.Schema

  chz_schema do
    field :name, :string, doc: "Configuration name"
    field :value, :integer, default: 0, doc: "Integer value"
    field :enabled, :boolean, default: true
  end
end

case ChzEx.entrypoint(Examples.BasicConfig) do
  {:ok, config} ->
    IO.puts("Created config:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
```

### examples/nested_config.exs

```elixir
# Nested configuration example

defmodule Examples.ModelConfig do
  use ChzEx.Schema

  chz_schema do
    field :hidden_dim, :integer, default: 768
    field :num_layers, :integer, default: 12
    field :num_heads, :integer, default: 12
  end
end

defmodule Examples.NestedConfig do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    embeds_one :model, Examples.ModelConfig
  end
end

case ChzEx.entrypoint(Examples.NestedConfig) do
  {:ok, config} ->
    IO.puts("Created nested config:")
    IO.inspect(config, pretty: true)
    IO.puts("\nModel hidden_dim: #{config.model.hidden_dim}")

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
```

### examples/polymorphic_config.exs

```elixir
# Polymorphic configuration example

defmodule Examples.Optimizer do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.001
  end
end

defmodule Examples.Adam do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.001
    field :beta1, :float, default: 0.9
    field :beta2, :float, default: 0.999
  end
end

defmodule Examples.SGD do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.01
    field :momentum, :float, default: 0.9
  end
end

defmodule Examples.PolymorphicConfig do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    embeds_one :optimizer, Examples.Optimizer,
      polymorphic: true,
      namespace: :example_optimizers,
      blueprint_unspecified: Examples.Adam
  end
end

# Register types
ChzEx.Registry.start_link([])
ChzEx.Registry.register(:example_optimizers, "adam", Examples.Adam)
ChzEx.Registry.register(:example_optimizers, "sgd", Examples.SGD)

case ChzEx.entrypoint(Examples.PolymorphicConfig) do
  {:ok, config} ->
    IO.puts("Created polymorphic config:")
    IO.inspect(config, pretty: true)
    IO.puts("\nOptimizer type: #{config.optimizer.__struct__}")

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
```

Create similar examples for:
- `wildcards.exs`
- `references.exs`
- `validation.exs`
- `mungers.exs`
- `presets.exs`
- `cli_entrypoint.exs`
- `help_generation.exs`

---

## MIX.EXS CONFIGURATION

```elixir
defmodule ChzEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/North-Shore-AI/chz_ex"

  def project do
    [
      app: :chz_ex,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "ChzEx",
      description: "Configuration management with CLI parsing for Elixir",
      source_url: @source_url,
      docs: docs(),
      package: package(),

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [
          :error_handling,
          :underspecs,
          :unknown,
          :unmatched_returns
        ]
      ],

      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ChzEx.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.11"},

      # Dev/Test
      {:stream_data, "~> 0.6", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["quality", "test --cover"]
    ]
  end

  defp docs do
    [
      main: "ChzEx",
      logo: nil,
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/guides/getting_started.md",
        "docs/guides/cli_parsing.md",
        "docs/guides/polymorphism.md",
        "docs/guides/validation.md"
      ],
      groups_for_extras: [
        Guides: ~r/docs\/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          ChzEx,
          ChzEx.Schema,
          ChzEx.Field,
          ChzEx.Blueprint
        ],
        Parsing: [
          ChzEx.Parser,
          ChzEx.ArgumentMap,
          ChzEx.Wildcard
        ],
        Construction: [
          ChzEx.Lazy,
          ChzEx.Factory,
          ChzEx.Factory.Standard,
          ChzEx.Registry
        ],
        Validation: [
          ChzEx.Validator,
          ChzEx.Munger,
          ChzEx.Cast
        ],
        Types: [
          ChzEx.Blueprint.Castable,
          ChzEx.Blueprint.Reference,
          ChzEx.Blueprint.Computed,
          ChzEx.Error
        ]
      ]
    ]
  end

  defp package do
    [
      maintainers: ["North Shore AI"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
```

---

## README.md

Create a comprehensive README at the project root:

```markdown
# ChzEx

[![Hex.pm](https://img.shields.io/hexpm/v/chz_ex.svg)](https://hex.pm/packages/chz_ex)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/chz_ex)
[![CI](https://github.com/North-Shore-AI/chz_ex/workflows/CI/badge.svg)](https://github.com/North-Shore-AI/chz_ex/actions)

Configuration management with CLI parsing for Elixir.

ChzEx is a native Elixir port of OpenAI's [chz](https://github.com/openai/chz) Python library, providing:

- **Typed configuration schemas** with compile-time validation
- **CLI argument parsing** (`name=value`, `model.layers=12`)
- **Polymorphic construction** - specify factory and arguments at runtime
- **Wildcards** (`...n_layers=100` sets all matching fields)
- **References** (`target@=source` copies values between fields)
- **Excellent error UX** with suggestions and source tracking

## Installation

Add `chz_ex` to your dependencies in `mix.exs`:

\`\`\`elixir
def deps do
  [
    {:chz_ex, "~> 0.1.0"}
  ]
end
\`\`\`

## Quick Start

### Define a Schema

\`\`\`elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :name, :string, doc: "Experiment name"
    field :learning_rate, :float, default: 0.001
    field :batch_size, :integer, default: 32
  end
end
\`\`\`

### Parse from CLI

\`\`\`elixir
# In your script or mix task
case ChzEx.entrypoint(MyApp.Config) do
  {:ok, config} ->
    IO.puts("Training with: #{inspect(config)}")

  {:error, error} ->
    IO.puts(:stderr, "Error: #{error}")
    System.halt(1)
end
\`\`\`

Run with:
\`\`\`bash
mix run train.exs -- name=experiment1 learning_rate=0.0001
\`\`\`

### Nested Configuration

\`\`\`elixir
defmodule MyApp.ModelConfig do
  use ChzEx.Schema

  chz_schema do
    field :hidden_dim, :integer, default: 768
    field :num_layers, :integer, default: 12
  end
end

defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    embeds_one :model, MyApp.ModelConfig
  end
end
\`\`\`

CLI: `name=exp model.hidden_dim=256 model.num_layers=6`

### Polymorphic Construction

\`\`\`elixir
defmodule MyApp.Optimizer do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.001
  end
end

defmodule MyApp.Adam do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.001
    field :beta1, :float, default: 0.9
  end
end

defmodule MyApp.SGD do
  use ChzEx.Schema
  chz_schema do
    field :lr, :float, default: 0.01
    field :momentum, :float, default: 0.9
  end
end

# Register at startup
ChzEx.Registry.register(:optimizers, "adam", MyApp.Adam)
ChzEx.Registry.register(:optimizers, "sgd", MyApp.SGD)

defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    embeds_one :optimizer, MyApp.Optimizer,
      polymorphic: true,
      namespace: :optimizers,
      blueprint_unspecified: MyApp.Adam
  end
end
\`\`\`

CLI: `name=exp optimizer=sgd optimizer.momentum=0.99`

### Wildcards

Set all matching fields at once:

\`\`\`bash
mix run train.exs -- name=exp ...activation=gelu ...dropout=0.1
\`\`\`

### References

Copy values between fields:

\`\`\`elixir
ChzEx.Blueprint.new(MyApp.Config)
|> ChzEx.Blueprint.apply(%{
  "base_dim" => 768,
  "hidden_dim" => ChzEx.Blueprint.Reference.new("base_dim")
})
\`\`\`

### Validation

\`\`\`elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :value, :integer, validator: [
      ChzEx.Validator.gt(0),
      ChzEx.Validator.lt(100)
    ]
  end

  @chz_validate :check_constraints
  def check_constraints(struct) do
    if struct.value > 50 do
      {:error, :value, "too high for this context"}
    else
      :ok
    end
  end
end
\`\`\`

## Documentation

- [Getting Started Guide](docs/guides/getting_started.md)
- [CLI Parsing](docs/guides/cli_parsing.md)
- [Polymorphism](docs/guides/polymorphism.md)
- [Validation](docs/guides/validation.md)
- [API Reference](https://hexdocs.pm/chz_ex)

## Examples

See the [examples/](examples/) directory for complete working examples.

\`\`\`bash
cd examples
./run_all.sh
\`\`\`

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

ChzEx is a port of [OpenAI's chz library](https://github.com/openai/chz).
\`\`\`

---

## QUALITY REQUIREMENTS

Before considering the implementation complete:

### All Tests Pass
```bash
mix test
# Expected: 0 failures
```

### No Warnings
```bash
mix compile --warnings-as-errors
# Expected: 0 warnings
```

### Credo Passes
```bash
mix credo --strict
# Expected: 0 issues
```

### Dialyzer Passes
```bash
mix dialyzer
# Expected: 0 warnings
```

### Format Check
```bash
mix format --check-formatted
# Expected: no changes needed
```

### Documentation Builds
```bash
mix docs
# Expected: builds without errors
```

### Examples Run
```bash
cd examples && ./run_all.sh
# Expected: all examples complete
```

### Test Coverage
```bash
mix test --cover
# Expected: >85% coverage
```

---

## IMPLEMENTATION CHECKLIST

Use this checklist to track progress:

- [ ] Phase 1: Foundation
  - [ ] ChzEx.Field with tests
  - [ ] ChzEx.Schema with tests
  - [ ] ChzEx.Parser with tests
  - [ ] Castable, Reference, Computed structs

- [ ] Phase 2: Blueprint Core
  - [ ] ChzEx.Wildcard with tests
  - [ ] ChzEx.ArgumentMap with tests
  - [ ] ChzEx.Lazy with tests
  - [ ] ChzEx.Blueprint with tests

- [ ] Phase 3: Polymorphism
  - [ ] ChzEx.Registry with tests
  - [ ] ChzEx.Factory behaviour
  - [ ] ChzEx.Factory.Standard with tests
  - [ ] Polymorphism integration tests

- [ ] Phase 4: Validation & Casting
  - [ ] ChzEx.Cast with tests
  - [ ] ChzEx.Validator with tests
  - [ ] ChzEx.Munger with tests
  - [ ] ChzEx.Error with tests

- [ ] Phase 5: Main API & Integration
  - [ ] ChzEx main module with tests
  - [ ] Integration tests
  - [ ] Reference tests

- [ ] Examples
  - [ ] examples/README.md
  - [ ] examples/run_all.sh
  - [ ] All 10 example files
  - [ ] All examples run successfully

- [ ] Documentation
  - [ ] README.md
  - [ ] CHANGELOG.md
  - [ ] docs/guides/getting_started.md
  - [ ] docs/guides/cli_parsing.md
  - [ ] docs/guides/polymorphism.md
  - [ ] docs/guides/validation.md
  - [ ] mix docs builds

- [ ] Quality
  - [ ] All tests pass
  - [ ] No compile warnings
  - [ ] mix credo --strict passes
  - [ ] mix dialyzer passes
  - [ ] mix format --check-formatted passes
  - [ ] >85% test coverage

---

## FINAL NOTES

1. **Read the Python source** when behavior is unclear - it's the spec
2. **Port Python tests** to ensure behavior parity
3. **Keep keys as strings** until matched against schema (security)
4. **No atom creation from user input** - check atom count in tests
5. **Error messages should help** - include suggestions and context
6. **Use Ecto changesets** for validation where possible
7. **Registry must be started** before polymorphism works - document this

The implementation is complete when all checklist items are done and all quality checks pass.
