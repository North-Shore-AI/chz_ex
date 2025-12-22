# ChzEx API Design

**Date:** 2025-12-21
**Status:** Design Phase

---

## Public API Overview

### Core Functions

```elixir
# Main entrypoints
ChzEx.entrypoint(module, argv \\ System.argv())  # -> {:ok, struct} | {:error, reason}
ChzEx.entrypoint!(module, argv \\ System.argv()) # -> struct | raise
ChzEx.make(module, args)                          # -> {:ok, struct} | {:error, reason}
ChzEx.make!(module, args)                         # -> struct | raise

# Introspection
ChzEx.is_chz?(value)                              # -> boolean
ChzEx.chz_fields(struct_or_module)               # -> %{atom => Field.t}

# Utilities
ChzEx.replace(struct, changes)                   # -> {:ok, struct} | {:error, changeset}
ChzEx.asdict(struct, opts \\ [])                 # -> map
```

### Schema Macro

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    # Basic fields
    field :name, :string
    field :steps, :integer, default: 1000
    field :rate, :float, validator: ChzEx.Validator.gt(0)

    # With default factory
    field :tags, {:array, :string}, default_factory: fn -> [] end

    # Embedded structs
    embeds_one :model, MyApp.Model
    embeds_many :layers, MyApp.Layer

    # Polymorphic embeds
    embeds_one :optimizer, MyApp.Optimizer, polymorphic: true, namespace: :optimizers
  end

  # Class-level validation
  @chz_validate :check_consistency
  def check_consistency(struct) do
    if struct.steps < 10 do
      {:error, :steps, "must be at least 10"}
    else
      :ok
    end
  end
end
```

### Blueprint API

```elixir
# Create blueprint
blueprint = ChzEx.Blueprint.new(MyApp.Config)

# Apply arguments
blueprint = ChzEx.Blueprint.apply(blueprint, %{"name" => "test"})
blueprint = ChzEx.Blueprint.apply(blueprint, %{"steps" => 500}, layer_name: "override")

# Apply from argv
{:ok, blueprint} = ChzEx.Blueprint.apply_from_argv(blueprint, ["model.layers=12"])

# Build
{:ok, config} = ChzEx.Blueprint.make(blueprint)

# Get help
help_text = ChzEx.Blueprint.get_help(blueprint, color: true)
```

---

## Complete Usage Examples

### Example 1: Basic Configuration

```elixir
# Define schema
defmodule MyApp.TrainingConfig do
  use ChzEx.Schema

  chz_schema do
    field :name, :string, doc: "Experiment name"
    field :learning_rate, :float, default: 0.001, validator: ChzEx.Validator.gt(0)
    field :batch_size, :integer, default: 32, validator: ChzEx.Validator.gt(0)
    field :epochs, :integer, default: 10
    field :device, :string, default: "cuda"
  end
end

# Usage in CLI script
defmodule MyApp.Train do
  def main(argv) do
    case ChzEx.entrypoint(MyApp.TrainingConfig, argv) do
      {:ok, config} ->
        IO.puts("Training with config: #{inspect(config)}")
        run_training(config)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end
end

# Command line:
# mix run train.exs name=my_experiment learning_rate=0.0001 epochs=50
```

### Example 2: Nested Configuration

```elixir
defmodule MyApp.ModelConfig do
  use ChzEx.Schema

  chz_schema do
    field :hidden_dim, :integer, default: 768
    field :num_layers, :integer, default: 12
    field :num_heads, :integer, default: 12
    field :dropout, :float, default: 0.1
  end

  @chz_validate :check_heads
  def check_heads(struct) do
    if rem(struct.hidden_dim, struct.num_heads) != 0 do
      {:error, :num_heads, "must divide hidden_dim evenly"}
    else
      :ok
    end
  end
end

defmodule MyApp.DataConfig do
  use ChzEx.Schema

  chz_schema do
    field :dataset, :string
    field :max_length, :integer, default: 512
    field :batch_size, :integer, default: 32
  end
end

defmodule MyApp.ExperimentConfig do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    field :seed, :integer, default: 42

    embeds_one :model, MyApp.ModelConfig
    embeds_one :data, MyApp.DataConfig
  end
end

# Command line:
# mix run experiment.exs name=gpt2_small \
#   model.hidden_dim=256 model.num_layers=6 model.num_heads=8 \
#   data.dataset=wikitext data.batch_size=64
```

### Example 3: Polymorphic Configuration

```elixir
# Base type
defmodule MyApp.Optimizer do
  use ChzEx.Schema

  chz_schema do
    field :learning_rate, :float, default: 0.001
  end
end

# Implementations
defmodule MyApp.Adam do
  use ChzEx.Schema

  chz_schema do
    field :learning_rate, :float, default: 0.001
    field :beta1, :float, default: 0.9
    field :beta2, :float, default: 0.999
    field :eps, :float, default: 1.0e-8
  end
end

defmodule MyApp.SGD do
  use ChzEx.Schema

  chz_schema do
    field :learning_rate, :float, default: 0.01
    field :momentum, :float, default: 0.9
    field :weight_decay, :float, default: 0.0
  end
end

# Register polymorphic types (in application startup)
ChzEx.Registry.register(:optimizers, "adam", MyApp.Adam)
ChzEx.Registry.register(:optimizers, "sgd", MyApp.SGD)

# Config using polymorphic field
defmodule MyApp.TrainingConfig do
  use ChzEx.Schema

  chz_schema do
    field :name, :string
    embeds_one :optimizer, MyApp.Optimizer,
      polymorphic: true,
      namespace: :optimizers,
      blueprint_unspecified: MyApp.Adam
  end
end

# Command line usage:
# Default (Adam):
#   mix run train.exs name=exp1 optimizer.learning_rate=0.0001

# Explicit Adam:
#   mix run train.exs name=exp1 optimizer=adam optimizer.beta1=0.95

# SGD:
#   mix run train.exs name=exp1 optimizer=sgd optimizer.momentum=0.99
```

### Example 4: Wildcards

```elixir
defmodule MyApp.LayerConfig do
  use ChzEx.Schema

  chz_schema do
    field :hidden_dim, :integer
    field :activation, :string, default: "relu"
    field :dropout, :float, default: 0.1
  end
end

defmodule MyApp.NetworkConfig do
  use ChzEx.Schema

  chz_schema do
    embeds_many :layers, MyApp.LayerConfig
  end
end

# Apply wildcards
blueprint = ChzEx.Blueprint.new(MyApp.NetworkConfig)

# Set all layers to use same activation
blueprint = ChzEx.Blueprint.apply(blueprint, %{
  "layers.0.hidden_dim" => 512,
  "layers.1.hidden_dim" => 256,
  "layers.2.hidden_dim" => 128,
  "...activation" => "gelu",      # Wildcard: all activations
  "...dropout" => 0.2             # Wildcard: all dropouts
})

{:ok, config} = ChzEx.Blueprint.make(blueprint)
# All layers have activation="gelu" and dropout=0.2
```

### Example 5: References

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :base_dim, :integer, default: 768
    field :hidden_dim, :integer  # Will be set via reference
    field :ff_dim, :integer      # Will be computed
  end
end

blueprint = ChzEx.Blueprint.new(MyApp.Config)

# Reference: hidden_dim takes value from base_dim
blueprint = ChzEx.Blueprint.apply(blueprint, %{
  "hidden_dim" => ChzEx.Blueprint.Reference.new("base_dim")
})

# Computed: ff_dim is 4x hidden_dim
blueprint = ChzEx.Blueprint.apply(blueprint, %{
  "ff_dim" => %ChzEx.Blueprint.Computed{
    sources: %{"hd" => ChzEx.Blueprint.Reference.new("hidden_dim")},
    compute: fn %{hd: hd} -> hd * 4 end
  }
})

{:ok, config} = ChzEx.Blueprint.make(blueprint)
# config.base_dim = 768
# config.hidden_dim = 768 (from reference)
# config.ff_dim = 3072 (computed as 768 * 4)
```

### Example 6: Mungers (Post-Init Transforms)

```elixir
defmodule MyApp.ExperimentConfig do
  use ChzEx.Schema

  chz_schema do
    field :name, :string

    # If display_name is nil, use name
    field :display_name, :string,
      munger: ChzEx.Munger.attr_if_none(:name)

    # Compute output_dir from name
    field :output_dir, :string,
      munger: ChzEx.Munger.if_none(fn struct ->
        "/experiments/#{struct.name}"
      end)
  end
end

{:ok, config} = ChzEx.make(MyApp.ExperimentConfig, %{name: "gpt2"})
# config.name = "gpt2"
# config.display_name = "gpt2" (from munger)
# config.output_dir = "/experiments/gpt2" (from munger)

{:ok, config} = ChzEx.make(MyApp.ExperimentConfig, %{
  name: "gpt2",
  display_name: "GPT-2 Small",
  output_dir: "/custom/path"
})
# config.display_name = "GPT-2 Small" (explicit)
# config.output_dir = "/custom/path" (explicit)
```

### Example 7: Custom Validation

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  chz_schema do
    field :min_value, :integer, default: 0
    field :max_value, :integer, default: 100
    field :value, :integer, validator: [
      ChzEx.Validator.ge(0),
      ChzEx.Validator.le(100)
    ]
  end

  # Class-level validation
  @chz_validate :check_range
  def check_range(struct) do
    cond do
      struct.min_value > struct.max_value ->
        {:error, :min_value, "must be less than max_value"}

      struct.value < struct.min_value ->
        {:error, :value, "must be >= min_value"}

      struct.value > struct.max_value ->
        {:error, :value, "must be <= max_value"}

      true ->
        :ok
    end
  end
end
```

### Example 8: Presets

```elixir
defmodule MyApp.Presets do
  @moduledoc "Predefined configuration presets."

  def small do
    ChzEx.Blueprint.new(MyApp.Config)
    |> ChzEx.Blueprint.apply(%{
      "model.hidden_dim" => 256,
      "model.num_layers" => 6,
      "model.num_heads" => 8
    }, layer_name: "preset:small")
  end

  def medium do
    ChzEx.Blueprint.new(MyApp.Config)
    |> ChzEx.Blueprint.apply(%{
      "model.hidden_dim" => 512,
      "model.num_layers" => 12,
      "model.num_heads" => 8
    }, layer_name: "preset:medium")
  end

  def large do
    ChzEx.Blueprint.new(MyApp.Config)
    |> ChzEx.Blueprint.apply(%{
      "model.hidden_dim" => 1024,
      "model.num_layers" => 24,
      "model.num_heads" => 16
    }, layer_name: "preset:large")
  end
end

# Usage with preset + overrides
def main(argv) do
  [preset_name | rest] = argv

  preset = case preset_name do
    "small" -> MyApp.Presets.small()
    "medium" -> MyApp.Presets.medium()
    "large" -> MyApp.Presets.large()
    _ -> ChzEx.Blueprint.new(MyApp.Config)
  end

  {:ok, config} =
    preset
    |> ChzEx.Blueprint.apply_from_argv(rest)
    |> ChzEx.Blueprint.make()
end

# Command line:
# mix run train.exs medium model.num_heads=16
```

### Example 9: Help Generation

```elixir
defmodule MyApp.Config do
  use ChzEx.Schema

  @moduledoc """
  Main configuration for training experiments.

  This config controls model architecture, data loading,
  and training hyperparameters.
  """

  chz_schema do
    field :name, :string, doc: "Experiment name for logging"
    field :seed, :integer, default: 42, doc: "Random seed"

    embeds_one :model, MyApp.ModelConfig
    embeds_one :data, MyApp.DataConfig
  end
end

# Generate help
blueprint = ChzEx.Blueprint.new(MyApp.Config)
|> ChzEx.Blueprint.apply(%{"model" => MyApp.Transformer})

help = ChzEx.Blueprint.get_help(blueprint, color: true)
IO.puts(help)

# Output:
# Entry point: MyApp.Config
#
#   Main configuration for training experiments.
#
#   This config controls model architecture, data loading,
#   and training hyperparameters.
#
# Arguments:
#   name                 string     -                    Experiment name for logging
#   seed                 integer    42 (default)         Random seed
#   model                Model      Transformer
#   model.hidden_dim     integer    768 (default)        Hidden dimension
#   model.num_layers     integer    12 (default)         Number of layers
#   data.dataset         string     -                    Dataset name
#   data.batch_size      integer    32 (default)         Batch size
```

### Example 10: Error Handling

```elixir
defmodule MyApp.CLI do
  def main(argv) do
    case ChzEx.entrypoint(MyApp.Config, argv) do
      {:ok, config} ->
        run(config)

      {:error, %ChzEx.Error{type: :missing_required, path: path}} ->
        IO.puts(:stderr, "Missing required argument: #{path}")
        IO.puts(:stderr, "Run with --help for usage")
        System.halt(1)

      {:error, %ChzEx.Error{type: :extraneous, path: path, suggestions: suggestions}} ->
        IO.puts(:stderr, "Unknown argument: #{path}")
        if suggestions != [] do
          IO.puts(:stderr, "Did you mean: #{Enum.join(suggestions, ", ")}?")
        end
        System.halt(1)

      {:error, %ChzEx.Error{type: :validation_error, path: path, message: msg}} ->
        IO.puts(:stderr, "Validation error for #{path}: #{msg}")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end
  rescue
    ChzEx.HelpException ->
      # Help was requested, already printed
      System.halt(0)
  end
end
```

---

## Field Options Reference

| Option | Type | Description |
|--------|------|-------------|
| `default` | `any` | Static default value |
| `default_factory` | `(-> any)` | Function returning default |
| `validator` | `fn \| [fn]` | Validation function(s) |
| `munger` | `fn` | Post-init transform |
| `doc` | `String.t` | Help text |
| `metadata` | `map` | User-defined metadata |
| `repr` | `boolean \| fn` | Include in inspect |
| `blueprint_cast` | `fn` | Custom CLI string parser |
| `polymorphic` | `boolean` | Enable polymorphic construction |
| `namespace` | `atom` | Namespace for polymorphic lookup |
| `blueprint_unspecified` | `module` | Default factory if not specified |

---

## Validator Functions Reference

```elixir
ChzEx.Validator.typecheck        # Type matches annotation
ChzEx.Validator.gt(base)         # Greater than
ChzEx.Validator.lt(base)         # Less than
ChzEx.Validator.ge(base)         # Greater than or equal
ChzEx.Validator.le(base)         # Less than or equal
ChzEx.Validator.valid_regex      # Value is valid regex
ChzEx.Validator.for_all_fields(fn) # Apply to all fields
```

---

## Munger Functions Reference

```elixir
ChzEx.Munger.if_none(fn)         # Replace nil with fn(struct)
ChzEx.Munger.attr_if_none(attr)  # Replace nil with struct.attr
ChzEx.Munger.freeze_map          # Make map hashable (no-op in Elixir)
ChzEx.Munger.from_function(fn)   # Custom munger from fn(struct, value)
```

---

## CLI Syntax Reference

```
# Basic assignment
name=value

# Nested paths
model.hidden_dim=768

# Polymorphic selection
optimizer=adam
optimizer.learning_rate=0.001

# Lists (comma-separated)
layers=64,128,256

# References
target@=source

# Wildcards
...activation=gelu       # All fields named 'activation'
model...dropout=0.1      # All 'dropout' under model

# Help
--help
```

---

## Comparison with Python CHZ

| Feature | Python CHZ | ChzEx |
|---------|-----------|-------|
| Schema definition | `@chz.chz` decorator | `use ChzEx.Schema` macro |
| Field specification | `chz.field()` | `field/3` with options |
| Immutability | `__setattr__` override | Native (Elixir structs) |
| Polymorphism | Runtime subclass scan | Explicit registry |
| CLI parsing | `entrypoint()` | `ChzEx.entrypoint/2` |
| Wildcards | `...` syntax | Same |
| References | `@=` syntax | Same |
| Validation | `@chz.validate` | `@chz_validate` |
| Mungers | `munger=` option | Same |
| Help | `--help` | Same |
