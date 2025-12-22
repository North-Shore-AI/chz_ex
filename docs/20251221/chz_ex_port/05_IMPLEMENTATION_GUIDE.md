# ChzEx Implementation Guide

**Date:** 2025-12-21
**Status:** Design Phase

---

## Getting Started

### Project Setup

```bash
# Create new mix project
mix new chz_ex --sup

# Add dependencies to mix.exs
defp deps do
  [
    {:ecto, "~> 3.11"},
    {:stream_data, "~> 0.6", only: [:test, :dev]},
    {:ex_doc, "~> 0.31", only: :dev},
    {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end
```

### Module Structure

```
lib/
├── chz_ex.ex                    # Main API
├── chz_ex/
│   ├── schema.ex                # Schema macro
│   ├── field.ex                 # Field struct
│   ├── parser.ex                # CLI parsing
│   ├── blueprint.ex             # Blueprint pipeline
│   ├── argument_map.ex          # Layered args
│   ├── wildcard.ex              # Pattern matching
│   ├── lazy.ex                  # Deferred evaluation
│   ├── factory.ex               # MetaFactory behaviour
│   ├── factory/
│   │   └── standard.ex          # Standard factory
│   ├── registry.ex              # Module registry
│   ├── validator.ex             # Validators
│   ├── munger.ex                # Mungers
│   ├── cast.ex                  # Type casting
│   └── error.ex                 # Error types
└── mix.exs

test/
├── chz_ex/
│   ├── schema_test.exs
│   ├── parser_test.exs
│   ├── blueprint_test.exs
│   ├── wildcard_test.exs
│   └── ...
├── support/
│   └── fixtures.ex
└── test_helper.exs
```

---

## Implementation Details

### Step 1: ChzEx.Field

Start with the field specification struct - it's a dependency of everything else.

```elixir
# lib/chz_ex/field.ex
defmodule ChzEx.Field do
  @moduledoc """
  Field specification for ChzEx schemas.

  Holds all metadata about a field: type, default, validators, etc.
  """

  @enforce_keys [:name, :type]
  defstruct [
    :name,
    :type,
    :raw_type,
    :default,
    :default_factory,
    :munger,
    :meta_factory,
    :blueprint_cast,
    :embed_type,
    :doc,
    validators: [],
    polymorphic: false,
    namespace: nil,
    blueprint_unspecified: nil,
    metadata: %{},
    repr: true
  ]

  @type validator :: (struct(), atom() -> :ok | {:error, String.t()})
  @type munger :: (any(), struct() -> any())

  @type t :: %__MODULE__{
    name: atom(),
    type: atom() | module(),
    raw_type: any(),
    default: any(),
    default_factory: (-> any()) | nil,
    munger: munger() | nil,
    validators: [validator()],
    meta_factory: module() | nil,
    blueprint_cast: (String.t() -> {:ok, any()} | {:error, String.t()}) | nil,
    embed_type: :one | :many | nil,
    polymorphic: boolean(),
    namespace: atom() | nil,
    blueprint_unspecified: module() | nil,
    doc: String.t() | nil,
    metadata: map(),
    repr: boolean() | (any() -> String.t())
  }

  @doc """
  Create a new field specification.

  ## Options

    * `:default` - Static default value
    * `:default_factory` - Function returning default
    * `:validator` / `:validators` - Validation function(s)
    * `:munger` - Post-init transform
    * `:doc` - Help text
    * `:repr` - Include in inspect
    * `:polymorphic` - Enable polymorphic construction
    * `:namespace` - Namespace for polymorphic lookup
    * `:blueprint_unspecified` - Default factory

  """
  def new(name, type, opts \\ []) when is_atom(name) do
    validate_opts!(opts)

    %__MODULE__{
      name: name,
      type: normalize_type(type),
      raw_type: Keyword.get(opts, :raw_type, type),
      default: Keyword.get(opts, :default),
      default_factory: Keyword.get(opts, :default_factory),
      munger: normalize_munger(Keyword.get(opts, :munger)),
      validators: normalize_validators(opts),
      meta_factory: Keyword.get(opts, :meta_factory),
      blueprint_cast: Keyword.get(opts, :blueprint_cast),
      embed_type: Keyword.get(opts, :embed_type),
      polymorphic: Keyword.get(opts, :polymorphic, false),
      namespace: Keyword.get(opts, :namespace),
      blueprint_unspecified: Keyword.get(opts, :blueprint_unspecified),
      doc: Keyword.get(opts, :doc),
      metadata: Keyword.get(opts, :metadata, %{}),
      repr: Keyword.get(opts, :repr, true)
    }
  end

  @doc """
  Check if field has a default value (static or factory).
  """
  def has_default?(%__MODULE__{default: nil, default_factory: nil}), do: false
  def has_default?(%__MODULE__{}), do: true

  @doc """
  Get the default value for a field.
  """
  def get_default(%__MODULE__{default: default}) when not is_nil(default), do: default
  def get_default(%__MODULE__{default_factory: factory}) when is_function(factory, 0), do: factory.()
  def get_default(%__MODULE__{}), do: nil

  @doc """
  Check if field is required (no default).
  """
  def required?(%__MODULE__{} = field), do: not has_default?(field)

  # Private helpers

  defp validate_opts!(opts) do
    if opts[:default] != nil and opts[:default_factory] != nil do
      raise ArgumentError, "cannot specify both :default and :default_factory"
    end
  end

  defp normalize_type({:array, inner}), do: {:array, normalize_type(inner)}
  defp normalize_type({:map, k, v}), do: {:map, normalize_type(k), normalize_type(v)}
  defp normalize_type(type), do: type

  defp normalize_validators(opts) do
    validators = Keyword.get(opts, :validator) || Keyword.get(opts, :validators) || []
    List.wrap(validators)
  end

  defp normalize_munger(nil), do: nil
  defp normalize_munger(fun) when is_function(fun, 2), do: fun
  defp normalize_munger(%{__struct__: _} = munger), do: munger
  defp normalize_munger(other) do
    raise ArgumentError, "munger must be a 2-arity function, got: #{inspect(other)}"
  end
end
```

### Step 2: ChzEx.Schema

The macro that transforms modules into ChzEx schemas.

```elixir
# lib/chz_ex/schema.ex
defmodule ChzEx.Schema do
  @moduledoc """
  Macro for defining ChzEx configuration schemas.

  ## Usage

      defmodule MyApp.Config do
        use ChzEx.Schema

        chz_schema do
          field :name, :string
          field :value, :integer, default: 0
        end
      end

  Fields defined inside `chz_schema` become struct fields with
  ChzEx metadata for CLI parsing and validation.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import ChzEx.Schema, only: [chz_schema: 1]

      @primary_key false
      @before_compile ChzEx.Schema

      Module.register_attribute(__MODULE__, :chz_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :chz_validators, accumulate: true)
      Module.register_attribute(__MODULE__, :chz_embeds, accumulate: true)
    end
  end

  @doc """
  Define a ChzEx schema block.
  """
  defmacro chz_schema(do: block) do
    quote do
      # Import field helpers
      import ChzEx.Schema, only: [
        field: 2, field: 3,
        embeds_one: 2, embeds_one: 3,
        embeds_many: 2, embeds_many: 3
      ]

      # Process the block
      unquote(block)
    end
  end

  @doc """
  Define a scalar field.
  """
  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      # Store ChzEx field metadata
      chz_field = ChzEx.Field.new(name, type, opts)
      Module.put_attribute(__MODULE__, :chz_fields, {name, chz_field})

      # Define the Ecto field
      ecto_opts = Keyword.take(opts, [:default, :virtual, :source])
      Ecto.Schema.__field__(__MODULE__, name, type, ecto_opts)
    end
  end

  @doc """
  Define an embedded struct field.
  """
  defmacro embeds_one(name, schema, opts \\ []) do
    quote bind_quoted: [name: name, schema: schema, opts: opts] do
      chz_field = ChzEx.Field.new(name, schema, Keyword.put(opts, :embed_type, :one))
      Module.put_attribute(__MODULE__, :chz_fields, {name, chz_field})
      Module.put_attribute(__MODULE__, :chz_embeds, {name, :one, schema, opts})

      # Ecto embeds_one
      Ecto.Schema.__embeds_one__(__MODULE__, name, schema, [])
    end
  end

  @doc """
  Define an embedded list field.
  """
  defmacro embeds_many(name, schema, opts \\ []) do
    quote bind_quoted: [name: name, schema: schema, opts: opts] do
      chz_field = ChzEx.Field.new(name, schema, Keyword.put(opts, :embed_type, :many))
      Module.put_attribute(__MODULE__, :chz_fields, {name, chz_field})
      Module.put_attribute(__MODULE__, :chz_embeds, {name, :many, schema, opts})

      # Ecto embeds_many
      Ecto.Schema.__embeds_many__(__MODULE__, name, schema, [])
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :chz_fields) |> Enum.reverse()
    validators = Module.get_attribute(env.module, :chz_validators) |> Enum.reverse()
    embeds = Module.get_attribute(env.module, :chz_embeds) |> Enum.reverse()

    fields_map = Map.new(fields)
    field_names = Keyword.keys(fields)
    required = fields |> Enum.filter(fn {_, f} -> ChzEx.Field.required?(f) end) |> Keyword.keys()

    quote do
      @doc false
      def __chz__?, do: true

      @doc false
      def __chz_fields__, do: unquote(Macro.escape(fields_map))

      @doc false
      def __chz_validators__, do: unquote(validators)

      @doc false
      def __chz_embeds__, do: unquote(Macro.escape(embeds))

      @doc """
      Create a changeset for this schema.
      """
      def changeset(struct \\ %__MODULE__{}, params) do
        struct
        |> cast(params, unquote(field_names -- Keyword.keys(embeds)))
        |> validate_required(unquote(required))
        |> cast_embeds(unquote(Macro.escape(embeds)))
        |> run_chz_validators(unquote(Macro.escape(fields_map)))
      end

      defp cast_embeds(changeset, embeds) do
        Enum.reduce(embeds, changeset, fn {name, _type, _schema, _opts}, cs ->
          cast_embed(cs, name)
        end)
      end

      defp run_chz_validators(changeset, fields) do
        # Run field-level validators
        changeset = Enum.reduce(fields, changeset, fn {name, field}, cs ->
          Enum.reduce(field.validators, cs, fn validator, cs2 ->
            if cs2.valid? do
              case validator.(Ecto.Changeset.apply_changes(cs2), name) do
                :ok -> cs2
                {:error, msg} -> add_error(cs2, name, msg)
              end
            else
              cs2
            end
          end)
        end)

        # Run class-level validators
        Enum.reduce(__chz_validators__(), changeset, fn validator, cs ->
          if cs.valid? do
            case validator.(Ecto.Changeset.apply_changes(cs)) do
              :ok -> cs
              {:error, field, msg} -> add_error(cs, field, msg)
            end
          else
            cs
          end
        end)
      end

      @doc """
      Create a struct from a map, running validations.
      """
      def new(params) do
        case changeset(params) |> Ecto.Changeset.apply_action(:insert) do
          {:ok, struct} -> {:ok, struct}
          {:error, changeset} -> {:error, format_errors(changeset)}
        end
      end

      defp format_errors(changeset) do
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)
      end
    end
  end

  @doc """
  Check if a module or struct is a ChzEx schema.
  """
  def is_chz?(module) when is_atom(module) do
    function_exported?(module, :__chz__?, 0) and module.__chz__?()
  end
  def is_chz?(%{__struct__: module}), do: is_chz?(module)
  def is_chz?(_), do: false
end
```

### Step 3: ChzEx.Parser

CLI argument parsing.

```elixir
# lib/chz_ex/parser.ex
defmodule ChzEx.Parser do
  @moduledoc """
  Parse CLI arguments into blueprint argument maps.
  """

  alias ChzEx.Blueprint.{Castable, Reference}

  @doc """
  Parse a list of "key=value" strings into a map.

  ## Examples

      iex> Parser.parse(["name=test", "value=42"])
      {:ok, %{"name" => %Castable{value: "test"}, "value" => %Castable{value: "42"}}}

      iex> Parser.parse(["target@=source"])
      {:ok, %{"target" => %Reference{ref: "source"}}}

  """
  @spec parse([String.t()]) :: {:ok, map()} | {:error, String.t()}
  def parse(argv) when is_list(argv) do
    result =
      Enum.reduce_while(argv, {:ok, %{}}, fn arg, {:ok, acc} ->
        # Skip help flag
        if arg in ["--help", "-h", "help"] do
          {:cont, {:ok, Map.put(acc, :__help__, true)}}
        else
          case parse_arg(arg) do
            {:ok, key, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
            {:error, _} = err -> {:halt, err}
          end
        end
      end)

    result
  end

  @doc """
  Parse a single argument string.
  """
  @spec parse_arg(String.t()) :: {:ok, String.t(), Castable.t() | Reference.t()} | {:error, String.t()}
  def parse_arg(arg) when is_binary(arg) do
    case String.split(arg, "=", parts: 2) do
      [key, value] ->
        cond do
          # Reference syntax: key@=value
          String.ends_with?(key, "@") ->
            ref_key = String.trim_trailing(key, "@")
            {:ok, ref_key, %Reference{ref: value}}

          # Normal key=value
          true ->
            {:ok, key, %Castable{value: value}}
        end

      [_no_equals] ->
        {:error, "Invalid argument #{inspect(arg)}. Arguments must be in key=value format."}
    end
  end

  @doc """
  Check if help was requested.
  """
  def help_requested?(args) when is_map(args), do: Map.get(args, :__help__, false)
  def help_requested?(argv) when is_list(argv), do: Enum.any?(argv, &(&1 in ["--help", "-h", "help"]))
end

defmodule ChzEx.Blueprint.Castable do
  @moduledoc "A string value that needs type-aware casting."
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  def new(value) when is_binary(value), do: %__MODULE__{value: value}
end

defmodule ChzEx.Blueprint.Reference do
  @moduledoc "A reference to another parameter."
  defstruct [:ref]

  @type t :: %__MODULE__{ref: String.t()}

  def new(ref) when is_binary(ref) do
    if String.contains?(ref, "...") do
      raise ArgumentError, "Reference target cannot contain wildcards"
    end
    %__MODULE__{ref: ref}
  end
end
```

### Step 4: Complete Blueprint Implementation

Due to length, here's the key make_lazy algorithm:

```elixir
# lib/chz_ex/blueprint.ex (partial - key algorithm)
defmodule ChzEx.Blueprint do
  # ... struct and basic functions ...

  @doc """
  Execute the lazy make algorithm.
  """
  def make_lazy(%__MODULE__{} = bp) do
    arg_map = ArgumentMap.consolidate(bp.arg_map)

    state = %{
      arg_map: arg_map,
      all_params: %{},
      used_args: MapSet.new(),
      meta_factory_value: %{},
      missing_params: [],
      value_mapping: %{}
    }

    case construct_param(bp.param, "", state) do
      {:ok, evaluatable, state} ->
        state = %{state | value_mapping: Map.put(state.value_mapping, "", evaluatable)}
        {:ok, state}

      {:error, _} = err ->
        err
    end
  end

  defp construct_param(param, path, state) do
    # Record this param
    state = %{state | all_params: Map.put(state.all_params, path, param)}

    # Check if there's a value in arg_map
    found = ArgumentMap.get_kv(state.arg_map, path)

    cond do
      # Direct value provided
      found != nil and not is_struct(found.value, Castable) ->
        # Mark as used
        state = %{state | used_args: MapSet.put(state.used_args, {found.key, found.layer_index})}

        # Check for subpaths (nested construction)
        subpaths = ArgumentMap.subpaths(state.arg_map, path, strict: true)

        if subpaths == [] do
          # Simple value
          {:ok, %Lazy.Value{value: found.value}, state}
        else
          # Value is a factory, recurse into its params
          construct_factory_params(found.value, path, subpaths, state)
        end

      # Castable string - need to cast and possibly use as factory
      found != nil ->
        handle_castable(found, param, path, state)

      # No value - check for subpaths or defaults
      true ->
        handle_missing(param, path, state)
    end
  end

  defp construct_factory_params(factory, path, subpaths, state) do
    # Get the factory's params
    factory_params = get_params_for_factory(factory)

    # Construct each param
    kwargs = %{}
    state =
      Enum.reduce_while(factory_params, {:ok, kwargs, state}, fn {name, param}, {:ok, kwargs, state} ->
        param_path = join_path(path, Atom.to_string(name))

        case construct_param(param, param_path, state) do
          {:ok, evaluatable, state} ->
            {:cont, {:ok, Map.put(kwargs, name, %Lazy.ParamRef{ref: param_path}), state}}
          {:error, _} = err ->
            {:halt, err}
        end
      end)

    case state do
      {:ok, kwargs, state} ->
        thunk = %Lazy.Thunk{
          fn: fn resolved_kwargs -> struct!(factory, resolved_kwargs) end,
          kwargs: kwargs
        }
        {:ok, thunk, state}

      {:error, _} = err ->
        err
    end
  end

  defp handle_castable(found, param, path, state) do
    # Try to cast the string value
    case ChzEx.Cast.try_cast(found.value.value, param.type) do
      {:ok, value} ->
        state = %{state | used_args: MapSet.put(state.used_args, {found.key, found.layer_index})}
        {:ok, %Lazy.Value{value: value}, state}

      {:error, reason} ->
        # Maybe it's a factory name?
        case resolve_factory(found.value.value, param, state) do
          {:ok, factory} ->
            # Recurse with factory
            construct_factory_params(factory, path, [], state)

          :error ->
            {:error, %ChzEx.Error{type: :cast_error, path: path, message: reason}}
        end
    end
  end

  defp handle_missing(param, path, state) do
    # Check for subpaths that might indicate implicit construction
    subpaths = ArgumentMap.subpaths(state.arg_map, path, strict: true)

    cond do
      subpaths != [] and param.meta_factory ->
        # Implicit construction using unspecified factory
        case param.meta_factory.unspecified_factory() do
          nil ->
            state = %{state | missing_params: [path | state.missing_params]}
            {:ok, %Lazy.Value{value: nil}, state}

          factory ->
            construct_factory_params(factory, path, subpaths, state)
        end

      ChzEx.Field.has_default?(param) ->
        {:ok, %Lazy.Value{value: ChzEx.Field.get_default(param)}, state}

      true ->
        state = %{state | missing_params: [path | state.missing_params]}
        {:ok, %Lazy.Value{value: nil}, state}
    end
  end

  defp join_path("", child), do: child
  defp join_path(parent, child), do: "#{parent}.#{child}"

  defp get_params_for_factory(factory) when is_atom(factory) do
    if ChzEx.Schema.is_chz?(factory) do
      factory.__chz_fields__()
      |> Enum.map(fn {name, field} -> {name, field} end)
    else
      []
    end
  end

  defp resolve_factory(name, param, _state) do
    if param.meta_factory do
      param.meta_factory.from_string(name)
    else
      :error
    end
  end
end
```

---

## Python CHZ TODOs and CLAUDE Comments

Found in source code analysis:

### High Priority for Port

1. **`_blueprint.py:413`** - Help output should show cast or meta_factory info
2. **`_blueprint.py:968`** - Allow accessing parent attributes in factories
3. **`_blueprint.py:974`** - Support factories returning blueprints (better presets)

### Implementation Notes

4. **`factories.py:56`** - Document advanced factory tricks (see test_factories.py)
5. **`tiepin.py:1002-1008`** - Type system TODOs (overloads, ParamSpec, etc.) - not needed for Elixir
6. **`blueprint/_argv.py:18`** - Support `model[family=linear n_layers=1]` syntax
7. **`blueprint/_argv.py:66`** - Incomplete blueprint → argv conversion

### Elixir-Specific Considerations

- **No `__subclasses__()`** - Use explicit registry instead
- **No `eval()`** - Use pattern matching and explicit parsing
- **No `__setattr__`** - Elixir structs are naturally immutable
- **No forward references** - Compile-time type resolution
- **No metaclasses** - Use macros for code generation

---

## Development Workflow

### 1. Start with Tests

Write tests first based on Python behavior:

```bash
# Run specific test
mix test test/chz_ex/parser_test.exs

# Run with coverage
mix test --cover

# Run with trace
mix test --trace
```

### 2. Implement Incrementally

```
Phase 1: Field + Schema + Parser
Phase 2: ArgumentMap + Wildcard + Lazy
Phase 3: Blueprint (basic)
Phase 4: Factory + Registry (polymorphism)
Phase 5: Validator + Munger + Cast
Phase 6: Error UX + Help
Phase 7: Documentation
```

### 3. Quality Checks

```bash
mix format
mix credo --strict
mix dialyzer
```

### 4. Documentation

```bash
mix docs
open doc/index.html
```

---

## Common Patterns

### Pattern: Handling Ecto Types

```elixir
# Map Ecto types to ChzEx casting
defp ecto_type_to_cast(:string), do: :string
defp ecto_type_to_cast(:integer), do: :integer
defp ecto_type_to_cast(:float), do: :float
defp ecto_type_to_cast(:boolean), do: :boolean
defp ecto_type_to_cast({:array, inner}), do: {:list, ecto_type_to_cast(inner)}
defp ecto_type_to_cast(module) when is_atom(module), do: {:module, module}
```

### Pattern: Safe Atom Handling

```elixir
# Never create atoms from user input
def safe_field_lookup(schema, key) when is_binary(key) do
  fields = schema.__chz_fields__()

  Enum.find_value(fields, fn {name, field} ->
    if Atom.to_string(name) == key do
      field
    end
  end)
end
```

### Pattern: Error Accumulation

```elixir
# Accumulate multiple errors instead of failing fast
def validate_all(struct, validators) do
  Enum.reduce(validators, [], fn validator, errors ->
    case validator.(struct) do
      :ok -> errors
      {:error, field, msg} -> [{field, msg} | errors]
    end
  end)
  |> case do
    [] -> :ok
    errors -> {:error, Enum.reverse(errors)}
  end
end
```

---

## Troubleshooting

### Issue: Circular Dependencies

If modules have circular dependencies, use `@compile {:no_warn_undefined, ...}` or restructure to break the cycle.

### Issue: Macro Hygiene

When generating code in macros, use `unquote` carefully and test with `Macro.expand`.

### Issue: Ecto Changeset Timing

Ecto validations run when `apply_action` is called, not when `cast` is called. Plan accordingly.

---

## Next Steps

1. Implement `ChzEx.Field` and write tests
2. Implement `ChzEx.Schema` macro and verify struct generation
3. Implement `ChzEx.Parser` with full test coverage
4. Continue with blueprint components
5. Add polymorphism support
6. Polish error UX
7. Write documentation and examples
