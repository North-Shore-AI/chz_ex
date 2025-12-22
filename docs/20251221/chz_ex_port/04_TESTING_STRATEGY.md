# ChzEx Testing Strategy

**Date:** 2025-12-21
**Status:** Design Phase

---

## Testing Philosophy

ChzEx testing follows these principles:

1. **Behavior parity** - Port Python chz test cases to ensure equivalent behavior
2. **Property-based testing** - Use StreamData for edge case discovery
3. **Security focus** - Explicitly test for atom exhaustion and injection
4. **Error UX testing** - Verify helpful error messages and suggestions

---

## Test Categories

### 1. Unit Tests

Each module has focused unit tests.

#### ChzEx.Parser Tests

```elixir
defmodule ChzEx.ParserTest do
  use ExUnit.Case, async: true

  alias ChzEx.Parser
  alias ChzEx.Blueprint.{Castable, Reference}

  describe "parse/1" do
    test "parses simple key=value" do
      assert {:ok, %{"name" => %Castable{value: "test"}}} =
        Parser.parse(["name=test"])
    end

    test "parses multiple arguments" do
      assert {:ok, result} = Parser.parse(["a=1", "b=2"])
      assert result["a"] == %Castable{value: "1"}
      assert result["b"] == %Castable{value: "2"}
    end

    test "parses dotted paths" do
      assert {:ok, %{"model.layers" => %Castable{value: "12"}}} =
        Parser.parse(["model.layers=12"])
    end

    test "parses references" do
      assert {:ok, %{"target" => %Reference{ref: "source"}}} =
        Parser.parse(["target@=source"])
    end

    test "handles equals in value" do
      assert {:ok, %{"expr" => %Castable{value: "a=b"}}} =
        Parser.parse(["expr=a=b"])
    end

    test "errors on missing equals" do
      assert {:error, _} = Parser.parse(["noequals"])
    end
  end

  describe "to_nested/1" do
    test "converts flat to nested" do
      flat = %{"a.b.c" => 1, "a.d" => 2, "e" => 3}
      assert %{
        "a" => %{"b" => %{"c" => 1}, "d" => 2},
        "e" => 3
      } = Parser.to_nested(flat)
    end
  end
end
```

#### ChzEx.Wildcard Tests

```elixir
defmodule ChzEx.WildcardTest do
  use ExUnit.Case, async: true

  alias ChzEx.Wildcard

  describe "to_regex/1" do
    test "prefix wildcard" do
      regex = Wildcard.to_regex("...n_layers")
      assert Regex.match?(regex, "n_layers")
      assert Regex.match?(regex, "model.n_layers")
      assert Regex.match?(regex, "a.b.c.n_layers")
      refute Regex.match?(regex, "n_layers_extra")
    end

    test "infix wildcard" do
      regex = Wildcard.to_regex("model...size")
      assert Regex.match?(regex, "model.size")
      assert Regex.match?(regex, "model.layer.size")
      refute Regex.match?(regex, "other.size")
    end

    test "multiple wildcards" do
      regex = Wildcard.to_regex("...layer...dim")
      assert Regex.match?(regex, "layer.dim")
      assert Regex.match?(regex, "model.layer.hidden.dim")
    end

    test "errors on trailing wildcard" do
      assert_raise ArgumentError, fn ->
        Wildcard.to_regex("model...")
      end
    end
  end

  describe "approximate/2" do
    test "returns score and suggestion" do
      {score, suggestion} = Wildcard.approximate("n_layer", "n_layers")
      assert score > 0.5
      assert suggestion =~ "n_layers"
    end

    test "low score for mismatches" do
      {score, _} = Wildcard.approximate("completely_different", "n_layers")
      assert score < 0.3
    end
  end
end
```

#### ChzEx.ArgumentMap Tests

```elixir
defmodule ChzEx.ArgumentMapTest do
  use ExUnit.Case, async: true

  alias ChzEx.ArgumentMap

  describe "layer precedence" do
    test "later layer overrides earlier" do
      map = ArgumentMap.new()
      |> ArgumentMap.add_layer(%{"a" => 1}, "first")
      |> ArgumentMap.add_layer(%{"a" => 2}, "second")
      |> ArgumentMap.consolidate()

      result = ArgumentMap.get_kv(map, "a")
      assert result.value == 2
      assert result.layer_name == "second"
    end

    test "wildcards apply based on layer order" do
      map = ArgumentMap.new()
      |> ArgumentMap.add_layer(%{"model.layers" => 10}, "explicit")
      |> ArgumentMap.add_layer(%{"...layers" => 20}, "wildcard")
      |> ArgumentMap.consolidate()

      # Wildcard in later layer wins
      result = ArgumentMap.get_kv(map, "model.layers")
      assert result.value == 20
    end
  end

  describe "subpaths/2" do
    test "finds qualified subpaths" do
      map = ArgumentMap.new()
      |> ArgumentMap.add_layer(%{
        "model.hidden" => 768,
        "model.layers" => 12,
        "data.path" => "/tmp"
      }, nil)
      |> ArgumentMap.consolidate()

      subpaths = ArgumentMap.subpaths(map, "model")
      assert "hidden" in subpaths
      assert "layers" in subpaths
      refute "path" in subpaths
    end
  end
end
```

#### ChzEx.Lazy Tests

```elixir
defmodule ChzEx.LazyTest do
  use ExUnit.Case, async: true

  alias ChzEx.Lazy
  alias ChzEx.Lazy.{Value, ParamRef, Thunk}

  describe "evaluate/1" do
    test "evaluates simple values" do
      mapping = %{
        "" => %Value{value: :root},
        "a" => %Value{value: 1}
      }
      assert :root == Lazy.evaluate(mapping)
    end

    test "resolves references" do
      mapping = %{
        "" => %ParamRef{ref: "a"},
        "a" => %Value{value: 42}
      }
      assert 42 == Lazy.evaluate(mapping)
    end

    test "evaluates thunks" do
      mapping = %{
        "" => %Thunk{
          fn: fn kwargs -> kwargs.x + kwargs.y end,
          kwargs: %{x: %ParamRef{ref: "a"}, y: %ParamRef{ref: "b"}}
        },
        "a" => %Value{value: 1},
        "b" => %Value{value: 2}
      }
      assert 3 == Lazy.evaluate(mapping)
    end

    test "detects cycles" do
      mapping = %{
        "" => %ParamRef{ref: "a"},
        "a" => %ParamRef{ref: "b"},
        "b" => %ParamRef{ref: "a"}
      }
      assert_raise RuntimeError, ~r/cyclic reference/i, fn ->
        Lazy.evaluate(mapping)
      end
    end
  end
end
```

### 2. Integration Tests

Test full schema → CLI → struct flow.

```elixir
defmodule ChzEx.IntegrationTest do
  use ExUnit.Case, async: true

  defmodule TestModel do
    use ChzEx.Schema

    chz_schema do
      field :hidden_dim, :integer, default: 768
      field :num_layers, :integer, default: 12
    end
  end

  defmodule TestConfig do
    use ChzEx.Schema

    chz_schema do
      field :name, :string
      field :seed, :integer, default: 42
      embeds_one :model, TestModel
    end
  end

  describe "full pipeline" do
    test "basic CLI parsing" do
      {:ok, config} = ChzEx.entrypoint(TestConfig, [
        "name=test",
        "model.hidden_dim=256"
      ])

      assert config.name == "test"
      assert config.seed == 42
      assert config.model.hidden_dim == 256
      assert config.model.num_layers == 12
    end

    test "wildcards apply" do
      {:ok, config} = ChzEx.entrypoint(TestConfig, [
        "name=test",
        "...num_layers=6"
      ])

      assert config.model.num_layers == 6
    end

    test "missing required field" do
      {:error, error} = ChzEx.entrypoint(TestConfig, [
        "seed=123"
      ])

      assert error.type == :missing_required
      assert error.path == "name"
    end

    test "extraneous field" do
      {:error, error} = ChzEx.entrypoint(TestConfig, [
        "name=test",
        "unknown=value"
      ])

      assert error.type == :extraneous
      assert error.path == "unknown"
    end
  end
end
```

### 3. Polymorphism Tests

```elixir
defmodule ChzEx.PolymorphismTest do
  use ExUnit.Case

  defmodule BaseOptimizer do
    use ChzEx.Schema
    chz_schema do
      field :lr, :float, default: 0.001
    end
  end

  defmodule Adam do
    use ChzEx.Schema
    chz_schema do
      field :lr, :float, default: 0.001
      field :beta1, :float, default: 0.9
      field :beta2, :float, default: 0.999
    end
  end

  defmodule SGD do
    use ChzEx.Schema
    chz_schema do
      field :lr, :float, default: 0.01
      field :momentum, :float, default: 0.9
    end
  end

  defmodule Config do
    use ChzEx.Schema
    chz_schema do
      field :name, :string
      embeds_one :optimizer, BaseOptimizer,
        polymorphic: true,
        namespace: :test_optimizers,
        blueprint_unspecified: Adam
    end
  end

  setup do
    # Start registry if not started
    start_supervised!(ChzEx.Registry)
    ChzEx.Registry.register(:test_optimizers, "adam", Adam)
    ChzEx.Registry.register(:test_optimizers, "sgd", SGD)
    :ok
  end

  test "default polymorphic type" do
    {:ok, config} = ChzEx.entrypoint(Config, [
      "name=test",
      "optimizer.lr=0.0001"
    ])

    assert config.optimizer.__struct__ == Adam
    assert config.optimizer.lr == 0.0001
    assert config.optimizer.beta1 == 0.9
  end

  test "explicit polymorphic type" do
    {:ok, config} = ChzEx.entrypoint(Config, [
      "name=test",
      "optimizer=sgd",
      "optimizer.momentum=0.99"
    ])

    assert config.optimizer.__struct__ == SGD
    assert config.optimizer.momentum == 0.99
  end

  test "unknown polymorphic type" do
    {:error, error} = ChzEx.entrypoint(Config, [
      "name=test",
      "optimizer=unknown"
    ])

    assert error.type == :invalid_value
    assert error.message =~ "unknown"
  end
end
```

### 4. Validation Tests

```elixir
defmodule ChzEx.ValidationTest do
  use ExUnit.Case, async: true

  defmodule ValidatedConfig do
    use ChzEx.Schema

    chz_schema do
      field :value, :integer, validator: [
        ChzEx.Validator.gt(0),
        ChzEx.Validator.lt(100)
      ]
      field :min, :integer, default: 0
      field :max, :integer, default: 100
    end

    @chz_validate :check_range
    def check_range(struct) do
      if struct.min >= struct.max do
        {:error, :min, "must be less than max"}
      else
        :ok
      end
    end
  end

  test "field validators run" do
    {:error, _} = ChzEx.make(ValidatedConfig, %{value: -1})
    {:error, _} = ChzEx.make(ValidatedConfig, %{value: 101})
    {:ok, _} = ChzEx.make(ValidatedConfig, %{value: 50})
  end

  test "class validators run" do
    {:error, error} = ChzEx.make(ValidatedConfig, %{
      value: 50,
      min: 100,
      max: 50
    })
    assert error.path == "min"
  end
end
```

### 5. Security Tests

```elixir
defmodule ChzEx.SecurityTest do
  use ExUnit.Case, async: true

  test "no atom creation from user input" do
    # Capture atom count before
    initial_atoms = :erlang.system_info(:atom_count)

    # Parse many unique keys
    for i <- 1..1000 do
      ChzEx.Parser.parse(["unknown_key_#{i}=value"])
    end

    # Should not have created many new atoms
    final_atoms = :erlang.system_info(:atom_count)
    assert final_atoms - initial_atoms < 10
  end

  test "rejects unregistered modules" do
    # Try to use a module that isn't registered
    blueprint = ChzEx.Blueprint.new(SomeConfig)

    {:error, error} = ChzEx.Blueprint.apply(blueprint, %{
      "model" => "Elixir.System"  # Potentially dangerous
    }) |> ChzEx.Blueprint.make()

    assert error.type == :invalid_value
  end

  test "no code execution in values" do
    # Values should not be eval'd
    {:ok, config} = ChzEx.make(SimpleConfig, %{
      name: "System.halt(1)"
    })

    # Should be a literal string, not executed
    assert config.name == "System.halt(1)"
  end
end
```

### 6. Property-Based Tests

```elixir
defmodule ChzEx.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  describe "parser roundtrip" do
    property "parsed args can be serialized back" do
      check all key <- string(:alphanumeric, min_length: 1),
                value <- string(:printable),
                not String.contains?(key, "="),
                not String.contains?(value, "=") do

        arg = "#{key}=#{value}"
        {:ok, parsed} = ChzEx.Parser.parse([arg])

        assert parsed[key].value == value
      end
    end
  end

  describe "wildcard matching" do
    property "exact key always matches itself" do
      check all key <- string(:alphanumeric, min_length: 1),
                not String.contains?(key, ".") do

        regex = ChzEx.Wildcard.to_regex(key)
        assert Regex.match?(regex, key)
      end
    end

    property "prefix wildcard matches any prefix" do
      check all base <- string(:alphanumeric, min_length: 1),
                prefix <- string(:alphanumeric, min_length: 1),
                not String.contains?(base, "."),
                not String.contains?(prefix, ".") do

        pattern = "...#{base}"
        regex = ChzEx.Wildcard.to_regex(pattern)

        assert Regex.match?(regex, base)
        assert Regex.match?(regex, "#{prefix}.#{base}")
      end
    end
  end
end
```

### 7. Error UX Tests

```elixir
defmodule ChzEx.ErrorUXTest do
  use ExUnit.Case, async: true

  test "typo suggestions" do
    {:error, error} = ChzEx.entrypoint(TestConfig, [
      "name=test",
      "model.hidden_dims=256"  # Typo: should be hidden_dim
    ])

    assert error.type == :extraneous
    assert "hidden_dim" in error.suggestions
  end

  test "nesting suggestions" do
    {:error, error} = ChzEx.entrypoint(TestConfig, [
      "name=test",
      "hidden_dim=256"  # Missing model. prefix
    ])

    assert error.message =~ "model.hidden_dim"
  end

  test "layer source in errors" do
    blueprint = ChzEx.Blueprint.new(TestConfig)
    |> ChzEx.Blueprint.apply(%{"bad_key" => 1}, layer_name: "my_preset")

    {:error, error} = ChzEx.Blueprint.make(blueprint)

    assert error.message =~ "my_preset"
  end

  test "help includes all params" do
    help = ChzEx.Blueprint.get_help(ChzEx.Blueprint.new(TestConfig))

    assert help =~ "name"
    assert help =~ "seed"
    assert help =~ "model.hidden_dim"
    assert help =~ "model.num_layers"
  end
end
```

---

## Test Fixtures

Create shared fixtures for common test schemas:

```elixir
# test/support/fixtures.ex
defmodule ChzEx.Test.Fixtures do
  defmodule SimpleConfig do
    use ChzEx.Schema
    chz_schema do
      field :name, :string
      field :value, :integer, default: 0
    end
  end

  defmodule NestedConfig do
    use ChzEx.Schema
    chz_schema do
      field :name, :string
      embeds_one :inner, InnerConfig
    end
  end

  defmodule InnerConfig do
    use ChzEx.Schema
    chz_schema do
      field :x, :integer, default: 0
      field :y, :integer, default: 0
    end
  end

  # ... more fixtures
end
```

---

## Test Coverage Goals

| Module | Target Coverage |
|--------|-----------------|
| ChzEx.Schema | 95% |
| ChzEx.Field | 90% |
| ChzEx.Parser | 95% |
| ChzEx.ArgumentMap | 90% |
| ChzEx.Wildcard | 95% |
| ChzEx.Lazy | 95% |
| ChzEx.Blueprint | 85% |
| ChzEx.Factory | 90% |
| ChzEx.Validator | 95% |
| ChzEx.Munger | 90% |
| ChzEx.Cast | 90% |

---

## Porting Python Tests

The Python chz library has extensive tests. Port these systematically:

| Python Test File | Elixir Equivalent |
|-----------------|-------------------|
| `test_blueprint.py` | `blueprint_test.exs` |
| `test_blueprint_cast.py` | `cast_test.exs` |
| `test_blueprint_errors.py` | `error_ux_test.exs` |
| `test_blueprint_reference.py` | `reference_test.exs` |
| `test_blueprint_variadic.py` | `variadic_test.exs` |
| `test_blueprint_root_polymorphism.py` | `polymorphism_test.exs` |
| `test_data_model.py` | `schema_test.exs` |
| `test_factories.py` | `factory_test.exs` |
| `test_munge.py` | `munger_test.exs` |
| `test_validate.py` | `validator_test.exs` |
| `test_tiepin.py` | `cast_test.exs` |

---

## CI Pipeline

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
      - run: mix deps.get
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix dialyzer
      - run: mix test --cover
```
