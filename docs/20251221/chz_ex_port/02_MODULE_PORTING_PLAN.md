# ChzEx Module-by-Module Porting Plan

**Date:** 2025-12-21
**Status:** Design Phase

---

## Phase 1: Core Foundation

### 1.1 ChzEx.Field

**Source:** `chz/field.py` (300 lines)

**Purpose:** Field specification with all metadata for schema fields.

**Python Structure:**
```python
class Field:
    _name: str              # Field name as defined
    _raw_type: TypeForm     # Type annotation
    _default: Any           # Static default
    _default_factory: Callable  # Lazy default
    _munger: Munger | None  # Post-init transform
    _validator: list[Callable]  # Validators
    _meta_factory: MetaFactory  # Polymorphic factory
    _blueprint_cast: Callable   # Custom CLI cast
    _repr: bool | Callable  # Repr behavior
    _doc: str               # Help text
    _metadata: dict         # User metadata
```

**Elixir Design:**
```elixir
defmodule ChzEx.Field do
  @moduledoc """
  Field specification for ChzEx schemas.
  """

  defstruct [
    :name,           # atom - field name
    :type,           # Ecto type (:string, :integer, etc.)
    :raw_type,       # Original type annotation (for polymorphism)
    :default,        # Static default value
    :default_factory, # Fun returning default
    :munger,         # {module, fun} or anonymous function
    :validators,     # List of validator functions
    :meta_factory,   # ChzEx.Factory implementation
    :blueprint_cast, # Custom cast function
    :embed_type,     # :one or :many for embeds
    :polymorphic,    # Boolean for polymorphic embeds
    :doc,            # Help text
    :metadata,       # User-defined metadata
    repr: true       # Include in inspect
  ]

  @type t :: %__MODULE__{
    name: atom(),
    type: atom() | module(),
    raw_type: any(),
    default: any(),
    default_factory: (-> any()) | nil,
    munger: (any(), map() -> any()) | nil,
    validators: [(any(), atom() -> :ok | {:error, String.t()})],
    meta_factory: module() | nil,
    blueprint_cast: (String.t() -> any()) | nil,
    embed_type: :one | :many | nil,
    polymorphic: boolean(),
    doc: String.t(),
    metadata: map(),
    repr: boolean() | (any() -> String.t())
  }

  @doc """
  Create a new field specification.
  """
  def new(name, type, opts \\ []) do
    # Validate options
    if opts[:default] != nil and opts[:default_factory] != nil do
      raise ArgumentError, "cannot specify both :default and :default_factory"
    end

    if opts[:munger] != nil and opts[:converter] != nil do
      raise ArgumentError, "cannot specify both :munger and :converter"
    end

    munger = opts[:munger] || opts[:converter]

    %__MODULE__{
      name: name,
      type: type,
      raw_type: opts[:raw_type] || type,
      default: opts[:default],
      default_factory: opts[:default_factory],
      munger: munger,
      validators: List.wrap(opts[:validator] || opts[:validators] || []),
      meta_factory: opts[:meta_factory],
      blueprint_cast: opts[:blueprint_cast],
      embed_type: opts[:embed_type],
      polymorphic: opts[:polymorphic] || false,
      doc: opts[:doc] || "",
      metadata: opts[:metadata] || %{},
      repr: Keyword.get(opts, :repr, true)
    }
  end

  @doc """
  Get the logical name (without X_ prefix if present).
  """
  def logical_name(%__MODULE__{name: name}) do
    case Atom.to_string(name) do
      "X_" <> rest -> String.to_atom(rest)
      _ -> name
    end
  end

  @doc """
  Get the storage name (with X_ prefix).
  """
  def x_name(%__MODULE__{name: name}) do
    String.to_atom("X_" <> Atom.to_string(logical_name(%__MODULE__{name: name})))
  end
end
```

**Key Differences:**
- Elixir uses atoms for field names (safe since they come from compiled code)
- Type is Ecto type atom or module reference
- `raw_type` preserved for polymorphism resolution
- Validators are functions `(struct, field_name) -> :ok | {:error, msg}`

---

### 1.2 ChzEx.Schema

**Source:** `chz/data_model.py` (762 lines)

**Purpose:** Macro that transforms a module into a ChzEx configuration schema.

**Python Behavior:**
- `@chz.chz` decorator collects type annotations
- Synthesizes `__init__` with keyword-only args
- Adds `__repr__`, `__eq__`, `__hash__`
- Enforces immutability via `__setattr__`
- Stores field specs in `__chz_fields__`
- Creates `init_property` for munged fields

**Elixir Design:**
```elixir
defmodule ChzEx.Schema do
  @moduledoc """
  Macro for defining ChzEx configuration schemas.

  ## Usage

      defmodule MyApp.Config do
        use ChzEx.Schema

        chz_schema do
          field :name, :string
          field :steps, :integer, default: 1000
          embeds_one :model, MyApp.Model, polymorphic: true
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import ChzEx.Schema, only: [chz_schema: 1, chz_field: 2, chz_field: 3]

      @primary_key false
      @chz_fields %{}
      @chz_validators []
      @before_compile ChzEx.Schema

      Module.register_attribute(__MODULE__, :chz_fields, accumulate: false)
      Module.register_attribute(__MODULE__, :chz_validators, accumulate: true)
    end
  end

  @doc """
  Define a ChzEx schema.
  """
  defmacro chz_schema(do: block) do
    quote do
      embedded_schema do
        unquote(block)
      end
    end
  end

  @doc """
  Define a field with ChzEx options.
  """
  defmacro chz_field(name, type, opts \\ []) do
    quote do
      # Store field metadata
      @chz_fields Map.put(
        @chz_fields,
        unquote(name),
        ChzEx.Field.new(unquote(name), unquote(type), unquote(opts))
      )

      # Define the Ecto field
      field(unquote(name), unquote(type), unquote(ecto_opts(opts)))
    end
  end

  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :chz_fields)
    validators = Module.get_attribute(env.module, :chz_validators)

    quote do
      @doc false
      def __chz_fields__, do: unquote(Macro.escape(fields))

      @doc false
      def __chz_validators__, do: unquote(validators)

      @doc """
      Create a changeset for this schema.
      """
      def changeset(struct \\ %__MODULE__{}, params) do
        struct
        |> cast(params, unquote(field_names(fields)))
        |> validate_required(unquote(required_fields(fields)))
        |> apply_field_validators(unquote(Macro.escape(fields)))
        |> apply_class_validators(unquote(validators))
      end

      defp apply_field_validators(changeset, fields) do
        Enum.reduce(fields, changeset, fn {name, field}, cs ->
          Enum.reduce(field.validators, cs, fn validator, cs2 ->
            validate_change(cs2, name, fn _, value ->
              case validator.(cs2, name) do
                :ok -> []
                {:error, msg} -> [{name, msg}]
              end
            end)
          end)
        end)
      end

      defp apply_class_validators(changeset, validators) do
        Enum.reduce(validators, changeset, fn validator, cs ->
          case validator.(cs) do
            :ok -> cs
            {:error, field, msg} -> add_error(cs, field, msg)
          end
        end)
      end

      @doc """
      Check if this module is a ChzEx schema.
      """
      def __chz__?, do: true
    end
  end

  # Helper to check if a module is a ChzEx schema
  def is_chz?(module) when is_atom(module) do
    function_exported?(module, :__chz__?, 0) and module.__chz__?()
  end
  def is_chz?(%{__struct__: module}), do: is_chz?(module)
  def is_chz?(_), do: false

  # Extract Ecto-compatible options
  defp ecto_opts(opts) do
    Keyword.take(opts, [:default, :virtual, :source])
  end

  defp field_names(fields) do
    fields |> Map.keys()
  end

  defp required_fields(fields) do
    fields
    |> Enum.filter(fn {_, f} -> f.default == nil and f.default_factory == nil end)
    |> Enum.map(fn {name, _} -> name end)
  end
end
```

**Key Differences:**
- Uses Elixir macros instead of Python decorators
- Builds on Ecto's `embedded_schema` for struct definition
- `changeset/2` generated with field-level validation
- `__chz_fields__` returns field metadata map
- No need for `__setattr__` override (Elixir structs immutable)

---

## Phase 2: CLI Parsing

### 2.1 ChzEx.Parser

**Source:** `chz/blueprint/_argv.py` (124 lines)

**Purpose:** Parse CLI arguments into nested map structure.

**Python Behavior:**
```python
argv_to_blueprint_args(["a.b=1", "model=Transformer", "c@=d"])
# Returns: {"a.b": Castable("1"), "model": Castable("Transformer"), "c": Reference("d")}
```

**Elixir Design:**
```elixir
defmodule ChzEx.Parser do
  @moduledoc """
  Parse CLI arguments into blueprint argument maps.
  """

  alias ChzEx.Blueprint.{Castable, Reference}

  @doc """
  Parse argv-style arguments into a flat map.

  ## Examples

      iex> ChzEx.Parser.parse(["a.b=1", "model=Transformer"])
      {:ok, %{"a.b" => %Castable{value: "1"}, "model" => %Castable{value: "Transformer"}}}

      iex> ChzEx.Parser.parse(["a@=b"])
      {:ok, %{"a" => %Reference{ref: "b"}}}
  """
  def parse(argv) when is_list(argv) do
    argv
    |> Enum.reduce_while({:ok, %{}}, fn arg, {:ok, acc} ->
      case parse_kv(arg) do
        {:ok, key, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc """
  Parse a single key=value argument.
  """
  def parse_kv(arg) when is_binary(arg) do
    case String.split(arg, "=", parts: 2) do
      [key, value] ->
        cond do
          String.ends_with?(key, "@") ->
            # Reference: key@=value
            {:ok, String.trim_trailing(key, "@"), %Reference{ref: value}}

          true ->
            {:ok, key, %Castable{value: value}}
        end

      [_no_equals] ->
        {:error, "Invalid argument #{inspect(arg)}. Use key=value format."}
    end
  end

  @doc """
  Convert a flat dotted-key map to nested map structure.

  ## Examples

      iex> ChzEx.Parser.to_nested(%{"a.b.c" => 1, "a.d" => 2})
      %{"a" => %{"b" => %{"c" => 1}, "d" => 2}}
  """
  def to_nested(flat_map) when is_map(flat_map) do
    Enum.reduce(flat_map, %{}, fn {key, value}, acc ->
      path = String.split(key, ".")
      put_nested(acc, path, value)
    end)
  end

  defp put_nested(map, [key], value) do
    Map.put(map, key, value)
  end

  defp put_nested(map, [key | rest], value) do
    existing = Map.get(map, key, %{})
    Map.put(map, key, put_nested(existing, rest, value))
  end

  @doc """
  Convert nested map back to flat dotted-key format.
  Used for serialization.
  """
  def to_flat(nested_map, prefix \\ "") do
    Enum.flat_map(nested_map, fn {key, value} ->
      full_key = if prefix == "", do: key, else: "#{prefix}.#{key}"

      case value do
        %{} = map when map_size(map) > 0 ->
          to_flat(map, full_key)
        _ ->
          [{full_key, value}]
      end
    end)
    |> Map.new()
  end
end

defmodule ChzEx.Blueprint.Castable do
  @moduledoc "Wrapper for values that need type-aware casting."
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}
end

defmodule ChzEx.Blueprint.Reference do
  @moduledoc "Reference to another parameter in the blueprint."
  defstruct [:ref]

  @type t :: %__MODULE__{ref: String.t()}

  def new(ref) do
    if String.contains?(ref, "...") do
      raise ArgumentError, "Cannot use wildcard as a reference target"
    end
    %__MODULE__{ref: ref}
  end
end

defmodule ChzEx.Blueprint.Computed do
  @moduledoc "Value computed from other parameters."
  defstruct [:sources, :compute]

  @type t :: %__MODULE__{
    sources: %{String.t() => Reference.t()},
    compute: (map() -> any())
  }
end
```

---

### 2.2 ChzEx.ArgumentMap

**Source:** `chz/blueprint/_argmap.py` (286 lines)

**Purpose:** Layered storage for arguments with qualified and wildcard keys.

**Python Behavior:**
- Stack of `Layer` objects
- Each layer has `qualified` (exact) and `wildcard` (pattern) keys
- Latest layer wins for matching keys
- `get_kv()` checks wildcards after qualified
- `check_extraneous()` validates no unused args

**Elixir Design:**
```elixir
defmodule ChzEx.ArgumentMap do
  @moduledoc """
  Layered argument storage supporting wildcards.
  """

  alias ChzEx.Wildcard

  defstruct [
    layers: [],
    consolidated: false,
    consolidated_qualified: %{},
    consolidated_qualified_sorted: [],
    consolidated_wildcard: []
  ]

  @type layer :: %{
    args: map(),
    name: String.t() | nil,
    qualified: map(),
    wildcard: map(),
    patterns: %{String.t() => Regex.t()}
  }

  @type t :: %__MODULE__{
    layers: [layer()],
    consolidated: boolean(),
    consolidated_qualified: %{String.t() => {any(), non_neg_integer()}},
    consolidated_qualified_sorted: [String.t()],
    consolidated_wildcard: [{String.t(), Regex.t(), any(), non_neg_integer()}]
  }

  @doc """
  Create a new argument map.
  """
  def new, do: %__MODULE__{}

  @doc """
  Add a layer of arguments.
  """
  def add_layer(%__MODULE__{} = map, args, name \\ nil) do
    layer = build_layer(args, name)
    %{map | layers: map.layers ++ [layer], consolidated: false}
  end

  defp build_layer(args, name) do
    {qualified, wildcard} =
      args
      |> Enum.sort_by(fn {k, _} -> -String.length(k) end)
      |> Enum.split_with(fn {k, _} -> not String.contains?(k, "...") end)

    patterns =
      wildcard
      |> Enum.map(fn {k, _} -> {k, Wildcard.to_regex(k)} end)
      |> Map.new()

    %{
      args: args,
      name: name,
      qualified: Map.new(qualified),
      wildcard: Map.new(wildcard),
      patterns: patterns
    }
  end

  @doc """
  Consolidate layers for efficient lookup.
  """
  def consolidate(%__MODULE__{consolidated: true} = map), do: map
  def consolidate(%__MODULE__{layers: layers} = map) do
    # Qualified: later layers override earlier
    consolidated_qualified =
      layers
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {layer, idx}, acc ->
        Enum.reduce(layer.qualified, acc, fn {k, v}, acc2 ->
          Map.put(acc2, k, {v, idx})
        end)
      end)

    # Wildcard: keep all, search from latest
    consolidated_wildcard =
      layers
      |> Enum.with_index()
      |> Enum.flat_map(fn {layer, idx} ->
        Enum.map(layer.wildcard, fn {k, v} ->
          {k, layer.patterns[k], v, idx}
        end)
      end)
      |> Enum.reverse()

    %{map |
      consolidated: true,
      consolidated_qualified: consolidated_qualified,
      consolidated_qualified_sorted: consolidated_qualified |> Map.keys() |> Enum.sort(),
      consolidated_wildcard: consolidated_wildcard
    }
  end

  @doc """
  Look up a value by exact key, checking wildcards.
  """
  def get_kv(%__MODULE__{consolidated: false} = map, key) do
    map |> consolidate() |> get_kv(key)
  end

  def get_kv(%__MODULE__{} = map, key, opts \\ []) do
    ignore_wildcards = Keyword.get(opts, :ignore_wildcards, false)

    case Map.get(map.consolidated_qualified, key) do
      {value, idx} when ignore_wildcards ->
        layer = Enum.at(map.layers, idx)
        %{key: key, value: value, layer_index: idx, layer_name: layer.name}

      lookup ->
        lookup_idx = if lookup, do: elem(lookup, 1), else: -1

        # Check wildcards (from latest layer)
        wildcard_match =
          unless ignore_wildcards do
            Enum.find(map.consolidated_wildcard, fn {_k, pattern, _v, idx} ->
              idx > lookup_idx and Regex.match?(pattern, key)
            end)
          end

        case wildcard_match do
          {wk, _pattern, value, idx} ->
            layer = Enum.at(map.layers, idx)
            %{key: wk, value: value, layer_index: idx, layer_name: layer.name}

          nil when lookup != nil ->
            {value, idx} = lookup
            layer = Enum.at(map.layers, idx)
            %{key: key, value: value, layer_index: idx, layer_name: layer.name}

          nil ->
            nil
        end
    end
  end

  @doc """
  Find subpaths matching a path prefix.
  """
  def subpaths(%__MODULE__{consolidated: false} = map, path, opts) do
    map |> consolidate() |> subpaths(path, opts)
  end

  def subpaths(%__MODULE__{} = map, path, opts \\ []) do
    strict = Keyword.get(opts, :strict, false)
    path_dot = path <> "."

    # From qualified keys
    qualified_subpaths =
      map.consolidated_qualified_sorted
      |> Enum.filter(fn k ->
        cond do
          not strict and k == path -> true
          path == "" and k != "" -> true
          String.starts_with?(k, path_dot) -> true
          true -> false
        end
      end)
      |> Enum.map(fn k ->
        cond do
          k == path -> ""
          path == "" -> k
          true -> String.replace_prefix(k, path_dot, "")
        end
      end)

    # From wildcard keys
    wildcard_subpaths =
      map.consolidated_wildcard
      |> Enum.flat_map(fn {wk, pattern, _v, _idx} ->
        cond do
          path == "" ->
            [wk]

          not strict and Regex.match?(pattern, path) ->
            [""]

          true ->
            # Complex wildcard matching logic
            find_wildcard_suffix(wk, pattern, path)
        end
      end)

    (qualified_subpaths ++ wildcard_subpaths) |> Enum.uniq()
  end

  defp find_wildcard_suffix(wildcard_key, pattern, path) do
    literal = path |> String.split(".") |> List.last()

    case :binary.match(wildcard_key, literal) do
      :nomatch -> []
      {pos, len} ->
        prefix = String.slice(wildcard_key, 0, pos + len)
        suffix = String.slice(wildcard_key, pos + len, String.length(wildcard_key))

        if String.ends_with?(prefix, literal) and
           Regex.match?(Wildcard.to_regex(prefix), path) do
          suffix = if String.starts_with?(suffix, "."), do: String.slice(suffix, 1..-1//1), else: suffix
          [suffix]
        else
          []
        end
    end
  end
end
```

---

### 2.3 ChzEx.Wildcard

**Source:** `chz/blueprint/_wildcard.py` (98 lines)

**Purpose:** Convert wildcard patterns to regex and provide fuzzy matching.

**Elixir Design:**
```elixir
defmodule ChzEx.Wildcard do
  @moduledoc """
  Wildcard pattern matching for argument keys.

  Patterns use `...` to match zero or more path segments.

  ## Examples

      "...n_layers"     matches "n_layers", "model.n_layers", "a.b.n_layers"
      "model...size"    matches "model.size", "model.layer.size"
      "...layer...dim"  matches "layer.dim", "model.layer.hidden.dim"
  """

  @fuzzy_similarity 0.6

  @doc """
  Convert a wildcard key to a regex pattern.
  """
  def to_regex(key) when is_binary(key) do
    if String.ends_with?(key, "...") do
      raise ArgumentError, "Wildcard not allowed at end of key"
    end

    pattern =
      if String.starts_with?(key, "...") do
        key = String.replace_prefix(key, "...", "")
        parts = String.split(key, "...")
        escaped = Enum.map(parts, &Regex.escape/1)
        "(.*\\.)?" <> Enum.join(escaped, "\\.(.*\\.)?")
      else
        parts = String.split(key, "...")
        escaped = Enum.map(parts, &Regex.escape/1)
        Enum.join(escaped, "\\.(.*\\.)?")
      end

    {:ok, regex} = Regex.compile(pattern)
    regex
  end

  @doc """
  Check if a wildcard pattern matches a target string.
  """
  def matches?(pattern, target) when is_binary(pattern) and is_binary(target) do
    regex = to_regex(pattern)
    Regex.match?(regex, target)
  end

  @doc """
  Approximate match for error suggestions.
  Returns {score, suggested_key}.
  """
  def approximate(key, target) when is_binary(key) and is_binary(target) do
    if String.ends_with?(key, "...") do
      raise ArgumentError, "Wildcard not allowed at end of key"
    end

    pattern =
      if String.starts_with?(key, "...") do
        ["..." | String.split(String.replace_prefix(key, "...", ""), ~r/(\.\.\.)|\./)]
      else
        String.split(key, ~r/(\.\.\.)|\./
        |> Enum.filter(& &1 != nil)
      end

    target_parts = String.split(target, ".")

    do_approx_match(pattern, target_parts, 0, 0, [])
  end

  defp do_approx_match([], [], _pi, _ti, acc) do
    {1.0, Enum.join(Enum.reverse(acc), "")}
  end

  defp do_approx_match([], _target, _pi, _ti, _acc), do: {0, ""}
  defp do_approx_match(_pattern, [], _pi, _ti, _acc), do: {0, ""}

  defp do_approx_match(["..." | rest], target, pi, ti, acc) do
    # Try consuming target element or not
    with_wildcard = do_approx_match(["..." | rest], tl(target), pi, ti + 1, acc)
    without_wildcard = do_approx_match(rest, target, pi + 1, ti, add_to_acc(acc, "..."))

    if elem(with_wildcard, 0) * @fuzzy_similarity > elem(without_wildcard, 0) do
      {score, value} = with_wildcard
      {score * @fuzzy_similarity, value}
    else
      without_wildcard
    end
  end

  defp do_approx_match([p | prest], [t | trest], pi, ti, acc) do
    ratio = String.jaro_distance(p, t)

    if ratio >= @fuzzy_similarity do
      {score, value} = do_approx_match(prest, trest, pi + 1, ti + 1, add_to_acc(acc, t))
      {score * ratio, value}
    else
      {0, ""}
    end
  end

  defp add_to_acc([], item), do: [item]
  defp add_to_acc(["..." | _] = acc, item), do: [item | acc]
  defp add_to_acc([prev | rest], item), do: [item <> "." <> prev | rest]
end
```

---

## Phase 3: Blueprint Pipeline

### 3.1 ChzEx.Lazy

**Source:** `chz/blueprint/_lazy.py` (133 lines)

**Purpose:** Deferred evaluation types for the blueprint pipeline.

**Elixir Design:**
```elixir
defmodule ChzEx.Lazy do
  @moduledoc """
  Lazy evaluation types for blueprint construction.
  """

  defmodule Value do
    @moduledoc "A concrete value."
    defstruct [:value]
  end

  defmodule ParamRef do
    @moduledoc "A reference to another parameter."
    defstruct [:ref]
  end

  defmodule Thunk do
    @moduledoc "A deferred function call."
    defstruct [:fn, :kwargs]

    @type t :: %__MODULE__{
      fn: (map() -> any()),
      kwargs: %{atom() => ParamRef.t()}
    }
  end

  @type evaluatable :: Value.t() | ParamRef.t() | Thunk.t()

  @doc """
  Evaluate a value mapping, resolving all references and thunks.
  """
  def evaluate(value_mapping) when is_map(value_mapping) do
    # Must have root entry
    unless Map.has_key?(value_mapping, "") do
      raise ArgumentError, "value_mapping must contain root entry ''"
    end

    refs_in_progress = %{}
    do_evaluate("", value_mapping, refs_in_progress)
  end

  defp do_evaluate(ref, value_mapping, in_progress) do
    if Map.has_key?(in_progress, ref) do
      cycle = in_progress |> Map.keys() |> Enum.join(" -> ")
      raise "Detected cyclic reference: #{cycle} -> #{ref}"
    end

    in_progress = Map.put(in_progress, ref, true)

    case Map.get(value_mapping, ref) do
      %Value{value: value} ->
        value

      %ParamRef{ref: target} ->
        do_evaluate(target, value_mapping, in_progress)

      %Thunk{fn: func, kwargs: kwargs} ->
        resolved_kwargs =
          Enum.map(kwargs, fn {key, %ParamRef{ref: target}} ->
            {key, do_evaluate(target, value_mapping, in_progress)}
          end)
          |> Map.new()

        func.(resolved_kwargs)

      nil ->
        raise "Reference #{inspect(ref)} not found in value_mapping"
    end
  end

  @doc """
  Check that all reference targets exist.
  """
  def check_reference_targets(value_mapping, param_paths) do
    invalid =
      value_mapping
      |> Enum.flat_map(fn {param_path, evaluatable} ->
        collect_refs(evaluatable)
        |> Enum.filter(fn ref -> ref not in param_paths end)
        |> Enum.map(fn ref -> {ref, param_path} end)
      end)
      |> Enum.group_by(fn {ref, _} -> ref end, fn {_, path} -> path end)

    if map_size(invalid) > 0 do
      errors =
        Enum.map(invalid, fn {ref, referrers} ->
          suggestions = suggest_similar(ref, param_paths)
          "Invalid reference target #{inspect(ref)} from #{inspect(referrers)}#{suggestions}"
        end)

      {:error, Enum.join(errors, "\n\n")}
    else
      :ok
    end
  end

  defp collect_refs(%ParamRef{ref: ref}), do: [ref]
  defp collect_refs(%Thunk{kwargs: kwargs}) do
    Enum.flat_map(kwargs, fn {_, param_ref} -> collect_refs(param_ref) end)
  end
  defp collect_refs(_), do: []

  defp suggest_similar(ref, param_paths) do
    matches =
      param_paths
      |> Enum.map(fn p -> {p, ChzEx.Wildcard.approximate(ref, p)} end)
      |> Enum.filter(fn {_, {score, _}} -> score > 0.1 end)
      |> Enum.sort_by(fn {_, {score, _}} -> -score end)
      |> Enum.take(3)

    case matches do
      [] -> ""
      [{path, {_, suggestion}} | _] -> "\nDid you mean #{inspect(suggestion)}?"
    end
  end
end
```

---

### 3.2 ChzEx.Blueprint

**Source:** `chz/blueprint/_blueprint.py` (1382 lines)

**Purpose:** Main orchestration of the configuration construction pipeline.

This is the largest and most complex module. Key responsibilities:
- `apply/2` - Add argument layers
- `make/0` - Construct the final struct
- `_make_lazy/0` - Discover params, build value mapping
- `_construct_param/5` - Handle individual parameter construction
- `get_help/1` - Generate help text

**Elixir Design (Abbreviated):**
```elixir
defmodule ChzEx.Blueprint do
  @moduledoc """
  Blueprint for lazy configuration construction.
  """

  alias ChzEx.{ArgumentMap, Lazy, Parser, Schema}
  alias ChzEx.Lazy.{Value, ParamRef, Thunk}

  defstruct [
    :target,
    :meta_factory,
    :entrypoint_repr,
    :param,
    arg_map: %ArgumentMap{}
  ]

  @type t :: %__MODULE__{
    target: module() | (... -> any()),
    meta_factory: module() | nil,
    entrypoint_repr: String.t(),
    param: map(),
    arg_map: ArgumentMap.t()
  }

  @doc """
  Create a new blueprint for a target module or function.
  """
  def new(target) when is_atom(target) do
    if Schema.is_chz?(target) do
      %__MODULE__{
        target: target,
        meta_factory: ChzEx.Factory.Standard.new(annotation: target),
        entrypoint_repr: inspect(target),
        param: build_root_param(target),
        arg_map: ArgumentMap.new()
      }
    else
      raise ArgumentError, "#{inspect(target)} is not a ChzEx schema"
    end
  end

  @doc """
  Apply arguments to the blueprint.
  """
  def apply(%__MODULE__{} = bp, args, opts \\ []) when is_map(args) do
    layer_name = Keyword.get(opts, :layer_name)
    subpath = Keyword.get(opts, :subpath)

    args =
      if subpath do
        args
        |> Enum.map(fn {k, v} -> {"#{subpath}.#{k}", v} end)
        |> Map.new()
      else
        args
      end

    %{bp | arg_map: ArgumentMap.add_layer(bp.arg_map, args, layer_name)}
  end

  @doc """
  Apply arguments from argv.
  """
  def apply_from_argv(%__MODULE__{} = bp, argv, opts \\ []) do
    case Parser.parse(argv) do
      {:ok, args} ->
        bp = apply(bp, args, layer_name: Keyword.get(opts, :layer_name, "command line"))

        if "--help" in argv do
          raise ChzEx.HelpException, message: get_help(bp)
        end

        {:ok, bp}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Construct the final value.
  """
  def make(%__MODULE__{} = bp) do
    case make_lazy(bp) do
      {:ok, result} ->
        with :ok <- check_extraneous(bp.arg_map, result),
             :ok <- Lazy.check_reference_targets(result.value_mapping, Map.keys(result.all_params)) do
          if result.missing_params != [] do
            {:error, {:missing, result.missing_params}}
          else
            {:ok, Lazy.evaluate(result.value_mapping)}
          end
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Make from argv, suitable for CLI entrypoints.
  """
  def make_from_argv(%__MODULE__{} = bp, argv \\ nil) do
    argv = argv || System.argv()

    case apply_from_argv(bp, argv) do
      {:ok, bp} -> make(bp)
      {:error, _} = err -> err
    end
  end

  @doc """
  Generate help text.
  """
  def get_help(%__MODULE__{} = bp, opts \\ []) do
    color = Keyword.get(opts, :color, false)
    {:ok, result} = make_lazy(bp)

    header = "Entry point: #{bp.entrypoint_repr}\n\n"

    params =
      result.all_params
      |> Enum.map(fn {path, param} ->
        found = ArgumentMap.get_kv(bp.arg_map, path)
        format_param_help(path, param, found, result, color)
      end)
      |> Enum.join("\n")

    header <> "Arguments:\n" <> params
  end

  # Private implementation...

  defp make_lazy(%__MODULE__{} = bp) do
    arg_map = ArgumentMap.consolidate(bp.arg_map)

    all_params = %{}
    used_args = MapSet.new()
    meta_factory_value = %{}
    missing_params = []

    case construct_param(bp.param, "", arg_map, all_params, used_args, meta_factory_value, missing_params) do
      {:ok, value_mapping, state} ->
        {:ok, %{
          value_mapping: value_mapping,
          all_params: state.all_params,
          used_args: state.used_args,
          meta_factory_value: state.meta_factory_value,
          missing_params: state.missing_params
        }}

      {:error, _} = err ->
        err
    end
  end

  defp construct_param(param, path, arg_map, all_params, used_args, mf_value, missing) do
    # Complex recursive parameter construction logic
    # See Python _construct_param for full details
    # ...
  end

  defp build_root_param(module) do
    %{
      name: "",
      type: module,
      meta_factory: ChzEx.Factory.Standard.new(annotation: module),
      default: nil,
      doc: "",
      blueprint_cast: nil,
      metadata: %{}
    }
  end

  defp check_extraneous(arg_map, result) do
    # Check for unused arguments
    # ...
    :ok
  end

  defp format_param_help(path, param, found, result, color) do
    # Format a single parameter for --help output
    # ...
  end
end
```

---

## Phase 4: Factories and Polymorphism

### 4.1 ChzEx.Factory

**Source:** `chz/factories.py` (601 lines)

**Purpose:** Define how to construct values for typed fields, especially polymorphic ones.

**Elixir Design:**
```elixir
defmodule ChzEx.Factory do
  @moduledoc """
  Behaviour for meta-factories that describe how to construct values.
  """

  @callback unspecified_factory() :: module() | (... -> any()) | nil
  @callback from_string(String.t()) :: {:ok, module() | fun()} | {:error, String.t()}
  @callback perform_cast(String.t()) :: {:ok, any()} | {:error, String.t()}
end

defmodule ChzEx.Factory.Standard do
  @moduledoc """
  Standard meta-factory for most use cases.
  """
  @behaviour ChzEx.Factory

  defstruct [
    :annotation,
    :unspecified,
    :default_module
  ]

  def new(opts \\ []) do
    %__MODULE__{
      annotation: opts[:annotation],
      unspecified: opts[:unspecified],
      default_module: opts[:default_module]
    }
  end

  @impl true
  def unspecified_factory(%__MODULE__{unspecified: nil, annotation: annotation}) do
    get_unspecified_from_annotation(annotation)
  end
  def unspecified_factory(%__MODULE__{unspecified: unspecified}), do: unspecified

  @impl true
  def from_string(%__MODULE__{} = factory, factory_str) do
    cond do
      String.contains?(factory_str, ":") ->
        [module_str, func_str] = String.split(factory_str, ":", parts: 2)
        with {:ok, module} <- safe_module_lookup(module_str),
             {:ok, func} <- get_module_attr(module, func_str) do
          {:ok, func}
        end

      true ->
        # Look up in registry or as subclass
        case ChzEx.Registry.lookup(factory.annotation, factory_str) do
          {:ok, module} -> {:ok, module}
          :error -> find_subclass(factory_str, factory.annotation)
        end
    end
  end

  @impl true
  def perform_cast(%__MODULE__{annotation: annotation}, value) do
    ChzEx.Cast.try_cast(value, annotation)
  end

  defp get_unspecified_from_annotation(annotation) when is_atom(annotation) do
    if ChzEx.Schema.is_chz?(annotation), do: annotation, else: nil
  end
  defp get_unspecified_from_annotation(_), do: nil

  defp safe_module_lookup(module_str) do
    # Only allow registered modules
    case ChzEx.Registry.lookup_module(module_str) do
      {:ok, _} = result -> result
      :error -> {:error, "Unknown module: #{module_str}"}
    end
  end

  defp get_module_attr(module, attr_str) do
    attrs = String.split(attr_str, ".")
    Enum.reduce_while(attrs, {:ok, module}, fn attr, {:ok, current} ->
      attr_atom = String.to_existing_atom(attr)
      if function_exported?(current, attr_atom, 0) do
        {:cont, {:ok, apply(current, attr_atom, [])}}
      else
        {:halt, {:error, "No function #{attr} on #{inspect(current)}"}}
      end
    end)
  rescue
    ArgumentError -> {:error, "Unknown attribute: #{attr_str}"}
  end

  defp find_subclass(name, base_type) do
    # Check if there's a registered subclass with this name
    ChzEx.Registry.find_by_name(base_type, name)
  end
end
```

### 4.2 ChzEx.Registry

**Source:** New for Elixir (replaces Python's runtime class scanning)

**Purpose:** Explicit registry of modules for polymorphic construction.

```elixir
defmodule ChzEx.Registry do
  @moduledoc """
  Registry for polymorphic type resolution.

  Since Elixir doesn't have Python's runtime class introspection,
  modules must be explicitly registered for polymorphic construction.

  ## Usage

      # In your application startup or config
      ChzEx.Registry.register(:models, "transformer", MyApp.Transformer)
      ChzEx.Registry.register(:models, "diffusion", MyApp.Diffusion)

      # In your schema
      defmodule MyApp.Config do
        use ChzEx.Schema

        chz_schema do
          embeds_one :model, MyApp.Model, polymorphic: true, namespace: :models
        end
      end
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts ++ [name: __MODULE__])
  end

  @doc """
  Register a module under a namespace with a short name.
  """
  def register(namespace, short_name, module) when is_atom(namespace) and is_binary(short_name) and is_atom(module) do
    GenServer.call(__MODULE__, {:register, namespace, short_name, module})
  end

  @doc """
  Look up a module by namespace and short name.
  """
  def lookup(namespace, short_name) do
    GenServer.call(__MODULE__, {:lookup, namespace, short_name})
  end

  @doc """
  Find a module by its short name within a base type's namespace.
  """
  def find_by_name(base_type, name) do
    GenServer.call(__MODULE__, {:find_by_name, base_type, name})
  end

  @doc """
  Look up a module by its string name (for "module:func" syntax).
  """
  def lookup_module(module_str) do
    GenServer.call(__MODULE__, {:lookup_module, module_str})
  end

  @doc """
  Register a module as allowed for polymorphic construction.
  """
  def register_module(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:register_module, module})
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    {:ok, %{namespaces: %{}, modules: MapSet.new()}}
  end

  @impl true
  def handle_call({:register, namespace, short_name, module}, _from, state) do
    namespaces =
      state.namespaces
      |> Map.update(namespace, %{short_name => module}, &Map.put(&1, short_name, module))

    modules = MapSet.put(state.modules, module)

    {:reply, :ok, %{state | namespaces: namespaces, modules: modules}}
  end

  @impl true
  def handle_call({:lookup, namespace, short_name}, _from, state) do
    result =
      case get_in(state.namespaces, [namespace, short_name]) do
        nil -> :error
        module -> {:ok, module}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:find_by_name, _base_type, name}, _from, state) do
    # Search all namespaces for a module with this short name
    result =
      state.namespaces
      |> Enum.find_value(fn {_ns, modules} ->
        case Map.get(modules, name) do
          nil -> nil
          module -> {:ok, module}
        end
      end)
      |> case do
        nil -> {:error, "No module registered with name: #{name}"}
        result -> result
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:lookup_module, module_str}, _from, state) do
    module = String.to_existing_atom("Elixir." <> module_str)

    if MapSet.member?(state.modules, module) do
      {:reply, {:ok, module}, state}
    else
      {:reply, :error, state}
    end
  rescue
    ArgumentError -> {:reply, :error, state}
  end

  @impl true
  def handle_call({:register_module, module}, _from, state) do
    {:reply, :ok, %{state | modules: MapSet.put(state.modules, module)}}
  end
end
```

---

## Phase 5: Validation and Munging

### 5.1 ChzEx.Validator

**Source:** `chz/validators.py` (272 lines)

```elixir
defmodule ChzEx.Validator do
  @moduledoc """
  Validation functions for ChzEx schemas.
  """

  @doc """
  Type check validator using Ecto types.
  """
  def typecheck(struct, attr) do
    field = struct.__struct__.__chz_fields__()[attr]
    value = Map.get(struct, attr)

    case Ecto.Type.cast(field.type, value) do
      {:ok, _} -> :ok
      :error -> {:error, "Expected #{attr} to be #{inspect(field.type)}, got #{inspect(value)}"}
    end
  end

  @doc "Check value is greater than base."
  def gt(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value > base, do: :ok, else: {:error, "Expected #{attr} to be greater than #{base}"}
    end
  end

  @doc "Check value is less than base."
  def lt(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value < base, do: :ok, else: {:error, "Expected #{attr} to be less than #{base}"}
    end
  end

  @doc "Check value is greater than or equal to base."
  def ge(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value >= base, do: :ok, else: {:error, "Expected #{attr} to be >= #{base}"}
    end
  end

  @doc "Check value is less than or equal to base."
  def le(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value <= base, do: :ok, else: {:error, "Expected #{attr} to be <= #{base}"}
    end
  end

  @doc "Check value is a valid regex."
  def valid_regex(struct, attr) do
    value = Map.get(struct, attr)
    case Regex.compile(value) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Invalid regex in #{attr}"}
    end
  end

  @doc "Apply validator to all fields."
  def for_all_fields(validator) do
    fn struct ->
      struct.__struct__.__chz_fields__()
      |> Enum.reduce(:ok, fn {name, _field}, acc ->
        case acc do
          :ok -> validator.(struct, name)
          error -> error
        end
      end)
    end
  end
end
```

### 5.2 ChzEx.Munger

**Source:** `chz/mungers.py` (78 lines)

```elixir
defmodule ChzEx.Munger do
  @moduledoc """
  Post-init field transforms.
  """

  @doc """
  If value is nil, replace with result of function.
  """
  def if_none(replacement_fn) when is_function(replacement_fn, 1) do
    fn value, struct ->
      if is_nil(value), do: replacement_fn.(struct), else: value
    end
  end

  @doc """
  If value is nil, use another attribute.
  """
  def attr_if_none(replacement_attr) when is_atom(replacement_attr) do
    fn value, struct ->
      if is_nil(value), do: Map.get(struct, replacement_attr), else: value
    end
  end

  @doc """
  Freeze a map to make it hashable.
  """
  def freeze_map do
    fn value, _struct ->
      case value do
        nil -> nil
        map when is_map(map) -> Map.new(map)  # Already immutable in Elixir
        other -> other
      end
    end
  end

  @doc """
  Create a munger from a simple function.
  """
  def from_function(fun) when is_function(fun, 2) do
    fn value, struct -> fun.(struct, value) end
  end
end
```

---

## Phase 6: Type Casting

### 6.1 ChzEx.Cast

**Source:** `chz/tiepin.py` (1060 lines)

```elixir
defmodule ChzEx.Cast do
  @moduledoc """
  Type-aware casting from strings for CLI parsing.
  """

  @doc """
  Attempt to cast a string to a target type.
  """
  def try_cast(value, type) when is_binary(value) do
    do_cast(value, type)
  end

  defp do_cast(value, :string), do: {:ok, value}

  defp do_cast(value, :integer) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Cannot cast #{inspect(value)} to integer"}
    end
  end

  defp do_cast(value, :float) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "Cannot cast #{inspect(value)} to float"}
    end
  end

  defp do_cast(value, :boolean) do
    cond do
      value in ~w(true True t 1) -> {:ok, true}
      value in ~w(false False f 0) -> {:ok, false}
      true -> {:error, "Cannot cast #{inspect(value)} to boolean"}
    end
  end

  defp do_cast(value, :atom) do
    # Safety: only allow existing atoms
    try do
      {:ok, String.to_existing_atom(value)}
    rescue
      ArgumentError -> {:error, "Unknown atom: #{value}"}
    end
  end

  defp do_cast("nil", nil), do: {:ok, nil}
  defp do_cast("None", nil), do: {:ok, nil}

  defp do_cast(value, {:list, inner_type}) do
    values = String.split(value, ",", trim: true)
    results = Enum.map(values, &do_cast(&1, inner_type))

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, v} -> v end)}
    else
      {:error, "Cannot cast #{inspect(value)} to list of #{inspect(inner_type)}"}
    end
  end

  defp do_cast(value, {:tuple, types}) do
    values = String.split(value, ",")

    if length(values) != length(types) do
      {:error, "Tuple length mismatch"}
    else
      results = Enum.zip(values, types) |> Enum.map(fn {v, t} -> do_cast(v, t) end)

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, Enum.map(results, fn {:ok, v} -> v end) |> List.to_tuple()}
      else
        {:error, "Cannot cast #{inspect(value)} to tuple"}
      end
    end
  end

  defp do_cast(value, {:map, key_type, value_type}) do
    if String.starts_with?(value, "{") do
      # Try to parse as Elixir term
      case Code.eval_string(value) do
        {map, _} when is_map(map) ->
          # Validate types
          valid? = Enum.all?(map, fn {k, v} ->
            match?({:ok, _}, do_cast(to_string(k), key_type)) and
            match?({:ok, _}, do_cast(to_string(v), value_type))
          end)
          if valid?, do: {:ok, map}, else: {:error, "Map type mismatch"}
        _ ->
          {:error, "Cannot parse #{inspect(value)} as map"}
      end
    else
      {:error, "Cannot cast #{inspect(value)} to map"}
    end
  end

  defp do_cast(value, module) when is_atom(module) do
    # Check if module has __chz_cast__ function
    if function_exported?(module, :__chz_cast__, 1) do
      module.__chz_cast__(value)
    else
      {:error, "Cannot cast #{inspect(value)} to #{inspect(module)}"}
    end
  end

  defp do_cast(value, _type) do
    # Fallback: try literal eval
    case Code.eval_string(value) do
      {result, _} -> {:ok, result}
      _ -> {:error, "Cannot cast #{inspect(value)}"}
    end
  rescue
    _ -> {:ok, value}  # Return as string if all else fails
  end
end
```

---

## Phase 7: Main API

### 7.1 ChzEx (Main Module)

**Source:** `chz/__init__.py`, `chz/blueprint/_entrypoint.py`

```elixir
defmodule ChzEx do
  @moduledoc """
  ChzEx - Configuration management with CLI parsing.

  ## Quick Start

      defmodule MyApp.Config do
        use ChzEx.Schema

        chz_schema do
          field :name, :string
          field :steps, :integer, default: 1000
        end
      end

      # From CLI
      {:ok, config} = ChzEx.entrypoint(MyApp.Config)
      # With argv: ["name=test", "steps=500"]

      # Programmatic
      {:ok, config} = ChzEx.make(MyApp.Config, %{"name" => "test", "steps" => 500})
  """

  alias ChzEx.Blueprint

  @doc """
  Parse argv and construct a configuration.
  Returns `{:ok, struct}` or `{:error, reason}`.
  """
  def entrypoint(module, argv \\ System.argv()) do
    Blueprint.new(module)
    |> Blueprint.make_from_argv(argv)
  end

  @doc """
  Parse argv and construct a configuration.
  Raises on error.
  """
  def entrypoint!(module, argv \\ System.argv()) do
    case entrypoint(module, argv) do
      {:ok, config} -> config
      {:error, errors} -> raise ChzEx.ConfigError, errors: errors
    end
  end

  @doc """
  Construct a configuration from a map of arguments.
  """
  def make(module, args) when is_map(args) do
    Blueprint.new(module)
    |> Blueprint.apply(args)
    |> Blueprint.make()
  end

  @doc """
  Construct a configuration from a map of arguments.
  Raises on error.
  """
  def make!(module, args) when is_map(args) do
    case make(module, args) do
      {:ok, config} -> config
      {:error, errors} -> raise ChzEx.ConfigError, errors: errors
    end
  end

  @doc """
  Check if a value is a ChzEx struct.
  """
  defdelegate is_chz?(value), to: ChzEx.Schema

  @doc """
  Get the field specifications for a ChzEx struct.
  """
  def chz_fields(struct) when is_struct(struct) do
    struct.__struct__.__chz_fields__()
  end
  def chz_fields(module) when is_atom(module) do
    module.__chz_fields__()
  end

  @doc """
  Replace fields in a ChzEx struct.
  """
  def replace(struct, changes) when is_struct(struct) and is_map(changes) do
    struct.__struct__.changeset(struct, changes)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Convert a ChzEx struct to a map.
  """
  def asdict(struct, opts \\ []) do
    shallow = Keyword.get(opts, :shallow, false)
    include_type = Keyword.get(opts, :include_type, false)

    do_asdict(struct, shallow, include_type)
  end

  defp do_asdict(struct, shallow, include_type) when is_struct(struct) do
    if is_chz?(struct) do
      base =
        struct
        |> Map.from_struct()
        |> Enum.map(fn {k, v} ->
          {k, if(shallow, do: v, else: do_asdict(v, shallow, include_type))}
        end)
        |> Map.new()

      if include_type do
        Map.put(base, :__chz_type__, struct.__struct__)
      else
        base
      end
    else
      struct
    end
  end

  defp do_asdict(list, shallow, include_type) when is_list(list) do
    Enum.map(list, &do_asdict(&1, shallow, include_type))
  end

  defp do_asdict(map, shallow, include_type) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, do_asdict(v, shallow, include_type)} end)
  end

  defp do_asdict(value, _shallow, _include_type), do: value
end

defmodule ChzEx.ConfigError do
  defexception [:errors]

  @impl true
  def message(%{errors: errors}) when is_list(errors) do
    "Configuration error:\n" <> Enum.join(errors, "\n")
  end
  def message(%{errors: error}) do
    "Configuration error: #{error}"
  end
end

defmodule ChzEx.HelpException do
  defexception [:message]
end
```

---

## Implementation Order

### Sprint 1: Foundation (Week 1-2)
1. `ChzEx.Field` - Field specification struct
2. `ChzEx.Schema` - Basic macro without polymorphism
3. `ChzEx.Parser` - CLI argument parsing
4. Basic tests

### Sprint 2: Blueprint Core (Week 3-4)
1. `ChzEx.ArgumentMap` - Layered storage
2. `ChzEx.Wildcard` - Pattern matching
3. `ChzEx.Lazy` - Evaluation types
4. `ChzEx.Blueprint` - Basic make without polymorphism

### Sprint 3: Polymorphism (Week 5-6)
1. `ChzEx.Factory` - Factory behaviour and implementations
2. `ChzEx.Registry` - Module registry
3. Polymorphic blueprint construction
4. Full _make_lazy implementation

### Sprint 4: Validation & Finishing (Week 7-8)
1. `ChzEx.Validator` - Validation functions
2. `ChzEx.Munger` - Post-init transforms
3. `ChzEx.Cast` - Type casting
4. `ChzEx` main module
5. Error UX and help generation
6. Documentation and examples
