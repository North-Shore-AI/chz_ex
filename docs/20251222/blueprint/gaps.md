# Blueprint Gap Analysis

**Python Source**: `chz/blueprint/_blueprint.py` (~1382 lines), `_argmap.py` (~286 lines), `_argv.py` (~124 lines), `_lazy.py` (~133 lines), `_wildcard.py` (~98 lines)
**Elixir Port**: `lib/chz_ex/blueprint.ex` (~627 lines), `argument_map.ex` (~212 lines), `parser.ex` (~54 lines), `lazy.ex` (~138 lines), `wildcard.ex` (~134 lines)

## Overview

The Blueprint system is the core of chz's CLI integration, providing lazy construction of configuration objects from command-line arguments. The Elixir port has good foundational coverage but is missing some advanced features.

## Module-by-Module Analysis

---

## 1. Blueprint Core (`_blueprint.py` -> `blueprint.ex`)

### Ported Functionality
| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Blueprint struct | `Blueprint[T]` | `%Blueprint{}` | Similar structure |
| `new()` | `Blueprint(target)` | `Blueprint.new/1` | Creates blueprint |
| `apply()` | `blueprint.apply()` | `Blueprint.apply/3` | Add argument layer |
| `make()` | `blueprint.make()` | `Blueprint.make/1` | Construct value |
| `make_from_argv()` | `make_from_argv()` | `make_from_argv/2` | CLI construction |
| Help generation | `get_help()` | `get_help/2` | Basic help text |
| Lazy construction | `_MakeResult` | Internal state | Deferred evaluation |
| Embed handling | Nested schemas | `embeds_one/many` | Different API |

### Missing Features

#### 1a. Recursive Construction (`_make_schema`)
**Lines**: 374-520

**Python Behavior**:
```python
def _make_schema(
    make_result: _MakeResult,
    info: _SchemaInfo,
    param_path: str,
) -> _Evaluatable:
    # Handles:
    # - Recursive schema construction
    # - Polymorphic field detection
    # - Meta-factory resolution
    # - Default instance creation
    # - Field annotation extraction
```

**Elixir Gap**:
- Basic recursive construction exists
- Missing: Annotation-based polymorphism detection
- Missing: Field doc extraction from annotations

**Priority**: Medium - Mostly works but less introspective

---

#### 1b. Variadic/Array Construction (`_make_variadic`)
**Lines**: 523-614

**Python Behavior**:
```python
def _make_variadic(
    make_result: _MakeResult,
    info: _SchemaInfo,
    field: Field,
    param_path: str,
    indices: list[str],
) -> _Evaluatable:
    # Handles:
    # - List/tuple field construction
    # - Indexed subpath matching (field.0, field.1, etc.)
    # - Polymorphic elements in arrays
```

**Elixir Gap**:
- Basic `embeds_many` works
- Missing: Polymorphic array elements
- Missing: Sparse index handling

**Recommendation**:
```elixir
defp construct_embed_many_polymorphic(field, path, subpaths, state) do
  # Each index could have different type via factory
  indices = extract_indices(subpaths)

  {kwargs, state} =
    Enum.reduce(indices, {%{}, state}, fn idx, {acc, st} ->
      idx_path = join_path(path, idx)
      # Resolve factory for this specific index
      factory = resolve_factory_for_index(field, idx_path, st)
      st = construct_schema(factory, idx_path, st)
      {Map.put(acc, idx, %Lazy.ParamRef{ref: idx_path}), st}
    end)
  # ...
end
```

**Priority**: Medium - Arrays of polymorphic types

---

#### 1c. Found Argument Description (`_found_arg_desc`)
**Lines**: 618-678

**Python Behavior**:
```python
def _found_arg_desc(
    make_result: _MakeResult,
    found_arg: _FoundArgument | None,
    *,
    param_path: str,
    param: Field,
    omit_redundant: bool,
) -> str:
    """Generates human-readable description of argument value."""
    # Used in:
    # - Help text
    # - Error messages
    # - Debug output
```

**Elixir Gap**:
- Basic value description in help
- Missing: Layer attribution
- Missing: Type representation

**Recommendation**:
```elixir
defp format_found_arg(found, field, param_path) do
  case found do
    nil ->
      if Field.has_default?(field) do
        "#{inspect(Field.get_default(field))} (default)"
      else
        "- (required)"
      end

    %{value: %Castable{value: v}, layer_name: layer} ->
      "#{v} (from #{layer || "unknown"})"

    %{value: %Reference{ref: ref}} ->
      "@=#{ref}"

    %{value: value} ->
      inspect(value)
  end
end
```

**Priority**: Low - UX improvement

---

#### 1d. Extraneous Argument Hints
**Lines**: 270-274 in `_argmap.py`

**Python Behavior**:
```python
# Rich error messages with suggestions:
# - "Did you mean X?"
# - "Did you get the nesting wrong, maybe you meant X?"
# - "Did you mean to use allow_hyphens=True?"
# - "No param found matching X"
# - "Param X is closest valid ancestor"
```

**Elixir Gap**:
- Basic extraneous detection exists
- Missing: Ancestor path analysis
- Missing: allow_hyphens hint

**Recommendation**:
```elixir
defp format_extraneous_error(key, param_paths) do
  base = "Unknown argument: #{key}"

  suggestions = suggestions_for(key, param_paths)
  ancestor = find_valid_ancestor(key, param_paths)

  cond do
    suggestions != [] ->
      "#{base}\nDid you mean: #{Enum.join(suggestions, ", ")}?"

    ancestor != nil ->
      "#{base}\nClosest valid ancestor: #{ancestor}"

    String.starts_with?(key, "--") ->
      "#{base}\nDid you mean to use allow_hyphens: true?"

    true ->
      base
  end
end
```

**Priority**: Medium - Better error UX

---

#### 1e. Construction Error Context (`ConstructionException`)
**Lines**: 32 in `_entrypoint.py`, used throughout

**Python Behavior**:
```python
class ConstructionException(EntrypointException):
    """Raised when object construction fails."""
    # Wraps inner exceptions with context about which param failed
```

**Elixir Gap**:
- Basic `ChzEx.Error` exists
- Missing: Exception chaining with context

**Recommendation**:
```elixir
defmodule ChzEx.Error do
  # Add:
  defstruct [..., :cause, :context]

  def wrap(error, context) do
    %__MODULE__{
      type: :construction_error,
      message: Exception.message(error),
      cause: error,
      context: context
    }
  end
end
```

**Priority**: Medium - Better debugging

---

## 2. Argument Map (`_argmap.py` -> `argument_map.ex`)

### Ported Functionality
| Feature | Status | Notes |
|---------|--------|-------|
| Layer structure | Good | Qualified + wildcard separation |
| `consolidate()` | Good | Efficient lookup preparation |
| `get_kv()` | Good | Wildcard-aware lookup |
| `subpaths()` | Good | Subpath discovery |
| Wildcard regex | Good | Pattern compilation |

### Missing Features

#### 2a. `check_extraneous()` Method
**Lines**: 195-274

**Python Behavior**:
- Integrated directly into ArgumentMap
- Returns detailed error context
- Suggests similar parameters

**Elixir Status**:
- Moved to `Blueprint.check_extraneous/2`
- Less detailed error messages

**Priority**: Low - Functionally equivalent

---

#### 2b. Layer Nesting (`nest_subpath`)
**Lines**: 45-51

**Python Behavior**:
```python
def nest_subpath(self, subpath: str | None) -> Layer:
    """Creates a new layer with all keys prefixed by subpath."""
```

**Elixir Gap**:
- Not implemented
- Used for applying config at specific path

**Recommendation**:
```elixir
def nest_layer(layer, subpath) when is_binary(subpath) do
  %{layer |
    args: Map.new(layer.args, fn {k, v} -> {"#{subpath}.#{k}", v} end),
    qualified: Map.new(layer.qualified, fn {k, v} -> {"#{subpath}.#{k}", v} end),
    # ... update other fields
  }
end
```

**Priority**: Low - Niche use case

---

## 3. Argv Parsing (`_argv.py` -> `parser.ex`)

### Ported Functionality
| Feature | Status | Notes |
|---------|--------|-------|
| `key=value` parsing | Good | Basic format |
| `key@=ref` references | Good | Reference syntax |
| Help flags | Good | `--help`, `-h` |

### Missing Features

#### 3a. `allow_hyphens` Support
**Lines**: 15-28

**Python Behavior**:
```python
def argv_to_blueprint_args(
    argv: list[str], *, allow_hyphens: bool = False
) -> dict[str, ...]:
    # When allow_hyphens=True:
    # - Strips leading hyphens from keys
    # - Allows "--key=value" format
```

**Elixir Gap**:
- Not implemented

**Recommendation**:
```elixir
def parse(argv, opts \\ []) do
  allow_hyphens = Keyword.get(opts, :allow_hyphens, false)

  Enum.reduce_while(argv, {:ok, %{}}, fn arg, {:ok, acc} ->
    key = if allow_hyphens, do: String.trim_leading(arg, "-"), else: arg
    # ... rest of parsing
  end)
end
```

**Priority**: Medium - Common CLI pattern

---

#### 3b. `beta_blueprint_to_argv`
**Lines**: 71-123

**Python Behavior**:
```python
def beta_blueprint_to_argv(blueprint: Blueprint[T]) -> list[str]:
    """Returns a list of arguments that would recreate the given blueprint."""
    # Handles:
    # - Castable -> "key=value"
    # - Reference -> "key@=ref"
    # - Lists -> comma-separated or indexed
    # - Dicts -> nested keys
    # - Primitives -> repr()
```

**Elixir Gap**:
- Not implemented
- Important for config reproduction

**Recommendation**:
```elixir
defmodule ChzEx.Blueprint.Serialize do
  def to_argv(%Blueprint{} = bp) do
    bp.arg_map.layers
    |> Enum.flat_map(fn layer -> Map.to_list(layer.args) end)
    |> collapse_layers()
    |> Enum.flat_map(&arg_to_string/1)
  end

  defp arg_to_string({key, %Castable{value: v}}), do: ["#{key}=#{v}"]
  defp arg_to_string({key, %Reference{ref: r}}), do: ["#{key}@=#{r}"]
  defp arg_to_string({key, list}) when is_list(list) do
    # Handle list serialization
  end
  # ...
end
```

**Priority**: High - Config reproduction/persistence

---

## 4. Lazy Evaluation (`_lazy.py` -> `lazy.ex`)

### Ported Functionality
| Feature | Status | Notes |
|---------|--------|-------|
| `Value` | Good | Concrete values |
| `ParamRef` | Good | References |
| `Thunk` | Good | Deferred computation |
| `evaluate()` | Good | With cycle detection |
| `check_reference_targets()` | Good | Validation |

### Missing Features

#### 4a. Exception Context (`add_note`)
**Lines**: 60-62, 72-74

**Python Behavior**:
```python
except Exception as e:
    e.add_note(f" (when dereferencing {ref!r})")
    raise
```

**Elixir Gap**:
- Exceptions don't support adding notes
- Context lost during evaluation

**Recommendation**:
```elixir
defp do_evaluate(ref, value_mapping, cache, in_progress, stack) do
  try do
    # ... evaluation
  rescue
    e ->
      reraise ChzEx.Error.wrap(e, "when evaluating #{ref}"), __STACKTRACE__
  end
end
```

**Priority**: Medium - Better error messages

---

## 5. Wildcard (`_wildcard.py` -> `wildcard.ex`)

### Ported Functionality
| Feature | Status | Notes |
|---------|--------|-------|
| `to_regex()` | Good | Pattern compilation |
| `matches?()` | Good | Pattern matching |
| `approximate()` | Good | Fuzzy matching |

### Missing Features

#### 5a. `_wildcard_key_match` (Non-regex implementation)
**Lines**: 18-43

**Python Behavior**:
```python
def _wildcard_key_match(key: str, target_str: str) -> bool:
    """Dynamic programming implementation without regex."""
    # Currently unused but tested
```

**Elixir Gap**:
- Not implemented (only regex version)
- Could be useful for performance

**Priority**: Low - Regex version works fine

---

## Test Coverage Mapping

| Python Test File | Coverage | Elixir Equivalent Needed |
|------------------|----------|--------------------------|
| `test_blueprint.py` | Core functionality | High priority |
| `test_blueprint_cast.py` | Type casting | Medium priority |
| `test_blueprint_errors.py` | Error handling | High priority |
| `test_blueprint_reference.py` | References | Medium priority |
| `test_blueprint_variadic.py` | Arrays | Medium priority |
| `test_blueprint_unit.py` | Unit tests | High priority |

## Implementation Priority Summary

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| beta_blueprint_to_argv | High | Medium | Config persistence |
| allow_hyphens | Medium | Low | CLI compatibility |
| Rich error messages | Medium | Medium | Developer UX |
| Exception context | Medium | Low | Debugging |
| Polymorphic arrays | Medium | High | Advanced use cases |
| Layer nesting | Low | Low | Niche feature |
| Non-regex wildcard | Low | Medium | Performance |

## Architecture Notes

The Elixir port follows a similar architecture to Python but with some differences:

1. **State Threading**: Python uses mutable `_MakeResult`, Elixir threads immutable state
2. **Type System**: Python has rich runtime types, Elixir relies on Ecto types
3. **Error Handling**: Python uses exceptions with context, Elixir uses `{:error, ...}` tuples
4. **Lazy Evaluation**: Both implementations are similar, using thunks and references

The foundation is solid - most gaps are around polish and edge cases rather than core functionality.
