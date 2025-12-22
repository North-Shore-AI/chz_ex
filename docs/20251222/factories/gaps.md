# Factories Gap Analysis

**Python Source**: `chz/factories.py` (~601 lines)
**Elixir Port**: `lib/chz_ex/factory.ex` (~9 lines), `lib/chz_ex/factory/standard.ex` (~79 lines)

## Overview

The Python `factories.py` provides a sophisticated polymorphic construction system allowing type selection at runtime via CLI or configuration. The Elixir port has a basic implementation but is missing several factory types and capabilities.

## Ported Functionality

### Fully Implemented
| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Factory behaviour | `MetaFactory` protocol | `ChzEx.Factory` behaviour | Basic interface |
| Standard factory | `standard` | `ChzEx.Factory.Standard` | Basic implementation |
| Namespace lookup | `namespace` param | `namespace` field | Registry-based |
| Unspecified default | `unspecified_factory()` | `unspecified_factory/1` | Default when none specified |

### Partially Implemented
| Feature | Python | Elixir | Missing |
|---------|--------|--------|---------|
| String parsing | `from_string()` | `from_string/2` | Limited syntax support |
| Module resolution | `Module:attr.path` | `Module:attr` | No nested attr paths |

## Missing Functionality

### 1. Subclass Factory (`subclass`)
**Lines**: 157-240

**Python Behavior**:
```python
def subclass(
    annotation: Any | tuple[Any, ...],
    *,
    default: type | None | MISSING = MISSING,
    use_parent_namespace: bool = False,
    discriminator: str = "__name__",
) -> MetaFactory:
    """Auto-discovers subclasses and allows selection by name."""

# Features:
# - Walks MRO to find all subclasses
# - Creates namespace from class __name__ or custom discriminator
# - Supports multiple base classes (tuple)
# - Optional parent namespace inheritance
```

**Elixir Gap**:
- No subclass discovery
- No automatic namespace population

**Recommendation**:
```elixir
defmodule ChzEx.Factory.Subclass do
  @behaviour ChzEx.Factory

  defstruct [:base_modules, :default, :discriminator, :use_parent_namespace]

  def new(opts \\ []) do
    %__MODULE__{
      base_modules: List.wrap(opts[:annotation]),
      default: opts[:default],
      discriminator: opts[:discriminator] || :__struct__,
      use_parent_namespace: opts[:use_parent_namespace] || false
    }
  end

  @impl true
  def unspecified_factory(%__MODULE__{default: default}), do: default

  @impl true
  def from_string(%__MODULE__{} = factory, name) do
    # Walk behaviour implementations or use registry
    case discover_implementations(factory.base_modules, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, "Unknown subtype: #{name}"}
    end
  end

  defp discover_implementations(base_modules, name) do
    # Option 1: Use __using__ callbacks to register
    # Option 2: Use :application.get_key(:modules) and filter
    # Option 3: Require explicit registration
  end
end
```

**Priority**: High - Core polymorphism feature

**Challenge**: Elixir doesn't have Python-style class hierarchies. Options:
1. Use behaviours + explicit registration
2. Use protocol implementations
3. Use compile-time module scanning

---

### 2. Function Factory (`function`)
**Lines**: 243-323

**Python Behavior**:
```python
def function(
    annotation: Any,
    *,
    default: Callable | None | MISSING = MISSING,
    namespace: str | None = None,
) -> MetaFactory:
    """Allows selection of callable functions from a namespace."""

# Features:
# - Resolves Module:function.attr paths
# - Supports nested attribute access
# - Uses tiepin for callable type checking
```

**Elixir Gap**:
- No function factory
- No callable resolution from strings

**Recommendation**:
```elixir
defmodule ChzEx.Factory.Function do
  @behaviour ChzEx.Factory

  defstruct [:annotation, :default, :namespace]

  def new(opts \\ []) do
    %__MODULE__{
      annotation: opts[:annotation],
      default: opts[:default],
      namespace: opts[:namespace]
    }
  end

  @impl true
  def unspecified_factory(%__MODULE__{default: default}), do: default

  @impl true
  def from_string(%__MODULE__{} = _factory, func_str) do
    case parse_function_reference(func_str) do
      {:ok, {module, function, arity}} ->
        {:ok, Function.capture(module, function, arity)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_function_reference(str) do
    case String.split(str, ":") do
      [mod_str, func_path] ->
        module = String.to_existing_atom("Elixir." <> mod_str)
        # Parse func_path for nested access
        resolve_function_path(module, func_path)
      _ ->
        {:error, "Invalid function reference: #{str}"}
    end
  end
end
```

**Priority**: Medium - Useful for callback configs

---

### 3. Meta-Factory Protocol (`MetaFactory`)
**Lines**: 37-96

**Python Behavior**:
```python
class MetaFactory(Protocol[_T]):
    def unspecified_factory(self) -> type[_T] | None: ...
    def from_string(self, factory_str: str) -> type[_T] | Callable[..., _T]: ...
    def perform_cast(self, value: str) -> _T: ...

# Additional methods:
def registered_factories(meta_factory: MetaFactory) -> dict[str, type]:
    """Returns all factories in the namespace."""

def beta_serialize(meta_factory: MetaFactory, value: Any) -> str | None:
    """Serializes a value back to factory string."""
```

**Elixir Gap**:
- `registered_factories/1` not implemented
- `beta_serialize/2` not implemented

**Recommendation**:
```elixir
defmodule ChzEx.Factory do
  @callback unspecified_factory(struct()) :: module() | nil
  @callback from_string(struct(), String.t()) :: {:ok, module() | fun()} | {:error, String.t()}
  @callback perform_cast(struct(), String.t()) :: {:ok, any()} | {:error, String.t()}

  # Add these:
  @callback registered_factories(struct()) :: %{String.t() => module()}
  @callback serialize(struct(), any()) :: {:ok, String.t()} | :error

  # Default implementations
  def registered_factories(%{namespace: ns}) when not is_nil(ns) do
    ChzEx.Registry.all_in_namespace(ns)
  end
  def registered_factories(_), do: %{}
end
```

**Priority**: Medium - Useful for introspection and serialization

---

### 4. Standard Factory Enhancements
**Lines**: 326-473

**Python Missing Features**:

#### 4a. Alias Support
```python
# Python allows:
# standard(aliases={"lin": "linear", "nn": "neural_net"})
```

**Recommendation**:
```elixir
defstruct [..., :aliases]

def from_string(%{aliases: aliases} = factory, name) when is_map(aliases) do
  resolved_name = Map.get(aliases, name, name)
  # ... continue resolution
end
```

#### 4b. Subclass Discovery Integration
```python
# Python's standard factory can use subclass discovery
standard(Model, auto_subclasses=True)
```

**Recommendation**:
```elixir
defstruct [..., :auto_discover]

def from_string(%{auto_discover: true, annotation: base} = factory, name) do
  case ChzEx.Factory.Subclass.discover(base, name) do
    {:ok, module} -> {:ok, module}
    :error -> # fallback to namespace lookup
  end
end
```

#### 4c. Full Module Path Parsing
```python
# Python supports: "chz.examples.Model:default_config.nested_attr"
```

Current Elixir only supports `Module:function`, not nested attribute paths.

**Recommendation**:
```elixir
defp get_module_attr(module, attr_str) do
  attrs = String.split(attr_str, ".")

  Enum.reduce_while(attrs, {:ok, module}, fn attr, {:ok, current} ->
    cond do
      is_atom(current) and function_exported?(current, String.to_atom(attr), 0) ->
        {:cont, {:ok, apply(current, String.to_atom(attr), [])}}
      is_map(current) ->
        {:cont, {:ok, Map.get(current, String.to_atom(attr))}}
      true ->
        {:halt, {:error, "Cannot access #{attr} on #{inspect(current)}"}}
    end
  end)
end
```

**Priority**: Medium - More expressive factory references

---

### 5. factory_as_value
**Lines**: 476-493

**Python Behavior**:
```python
def factory_as_value(
    factory_str: str,
    meta_factory: MetaFactory,
    param_type: TypeArg,
) -> Any:
    """Converts factory string to actual value."""
    # Used when value itself should be the factory, not an instance
```

**Elixir Gap**:
- No equivalent - always instantiates

**Recommendation**:
```elixir
def factory_as_value(factory_str, meta_factory) do
  case meta_factory.from_string(factory_str) do
    {:ok, factory} when is_atom(factory) -> {:ok, factory}
    {:ok, factory} when is_function(factory) -> {:ok, factory}
    {:error, _} = err -> err
  end
end
```

**Priority**: Low - Niche use case

---

### 6. _require_meta_factory
**Lines**: 496-520

**Python Behavior**:
```python
def _require_meta_factory(
    field_name: str, meta_factory: MetaFactory | None, field_type: Any
) -> MetaFactory:
    """Ensures a meta_factory exists, inferring from type annotation if needed."""
    # Auto-creates standard factory for:
    # - Union types with concrete classes
    # - Abstract base classes
```

**Elixir Gap**:
- No type-based factory inference

**Recommendation**:
```elixir
defmodule ChzEx.Factory.Inference do
  def infer_factory(field) do
    cond do
      field.meta_factory != nil ->
        field.meta_factory

      ChzEx.Schema.is_chz?(field.type) ->
        ChzEx.Factory.Standard.new(annotation: field.type)

      # Could add more inference rules
      true ->
        nil
    end
  end
end
```

**Priority**: Low - Convenience feature

---

## Registry Integration

The current `ChzEx.Registry` provides basic namespace support but needs enhancements:

### Current Capabilities
- `register(namespace, short_name, module)`
- `lookup(namespace, short_name)`
- `lookup_module(module_str)`

### Needed Additions
```elixir
defmodule ChzEx.Registry do
  # Add:
  def all_in_namespace(namespace) do
    GenServer.call(__MODULE__, {:all_in_namespace, namespace})
  end

  def register_with_aliases(namespace, short_name, module, aliases \\ []) do
    # Register main name
    register(namespace, short_name, module)
    # Register aliases
    Enum.each(aliases, &register(namespace, &1, module))
  end

  def discover_subclasses(base_module, callback_module \\ nil) do
    # Use :application.get_key or compile-time tracking
  end
end
```

## Implementation Priority Summary

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| Subclass factory | High | High | Core polymorphism |
| Function factory | Medium | Medium | Callback configs |
| registered_factories | Medium | Low | Introspection |
| Alias support | Medium | Low | UX improvement |
| Nested attr paths | Medium | Medium | Expressiveness |
| beta_serialize | Low | Medium | Config reproduction |
| factory_as_value | Low | Low | Niche feature |
| Type inference | Low | Medium | Convenience |

## Polymorphism Patterns in Elixir

Since Elixir lacks Python's class inheritance, consider these patterns:

### Pattern 1: Behaviour + Registry
```elixir
defmodule Animal do
  @callback speak() :: String.t()
end

defmodule Dog do
  @behaviour Animal
  use ChzEx.Schema

  def speak, do: "woof"
end

# At startup:
ChzEx.Registry.register(Animal, "dog", Dog)
```

### Pattern 2: Protocol-based
```elixir
defprotocol ChzEx.Polymorphic do
  def type_name(struct)
end

defimpl ChzEx.Polymorphic, for: Dog do
  def type_name(_), do: "dog"
end
```

### Pattern 3: Module Attribute Registration
```elixir
defmodule Dog do
  use ChzEx.Schema
  @chz_factory_name "dog"
  @chz_factory_namespace Animal
end

# Compile-time collection via __before_compile__
```

## Test Coverage Notes

Python tests in `test_factories.py` (~9842 bytes) and `test_blueprint_meta_factory.py` (~12518 bytes) cover:
- Subclass discovery
- Function factory resolution
- Standard factory variants
- Namespace handling
- Error cases

These tests are essential for ensuring polymorphism works correctly.
