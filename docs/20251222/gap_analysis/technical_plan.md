# ChzEx Gap Analysis: Technical Implementation Plan

**Date:** 2025-12-22
**Status:** Analysis Complete
**Scope:** Python `chz` → Elixir `chz_ex` port completeness

---

## Executive Summary

After detailed code analysis of both codebases, this document categorizes gaps into three tiers:
1. **Confirmed Gaps** - Features missing that have clear Elixir equivalents
2. **Design Decisions** - Features handled differently (not bugs)
3. **Not Applicable** - Python-specific features that don't translate

---

## 1. Confirmed Gaps (Implement)

### 1.1 Version Suffix Support (`-N` Convention)

**Status:** Gap Confirmed
**Priority:** Low
**Effort:** Small

**Python Behavior (`chz/data_model.py:491-501`):**
```python
if version is not None:
    expected_version = version.split("-")[0]  # Allows "b4d37d6e-3" format
```
The `-N` suffix allows iteration tracking without invalidating the hash (e.g., `a1b2c3d4-v2`).

**Current ChzEx (`lib/chz_ex/schema.ex:194-203`):**
```elixir
defp validate_version!(version, version_hash, module) do
  if version != version_hash do  # Exact match only
    raise ArgumentError, ...
  end
end
```

**Implementation Plan:**
```elixir
# In lib/chz_ex/schema.ex:194-203
defp validate_version!(nil, _version_hash, _module), do: :ok

defp validate_version!(version, version_hash, module) do
  # Extract hash portion before any suffix
  expected = version |> String.split("-") |> List.first()

  if expected != version_hash do
    raise ArgumentError,
          "Schema version #{inspect(version)} does not match #{inspect(version_hash)} for #{inspect(module)}"
  end
  :ok
end
```

**Tests:**
```elixir
# test/chz_ex/schema_test.exs
test "version with suffix is valid" do
  # version: "a1b2c3d4-v2" should match hash "a1b2c3d4"
end
```

---

### 1.2 TypedDict/Map Field Expansion

**Status:** Gap Confirmed
**Priority:** Medium
**Effort:** Medium

**Python Behavior (`chz/blueprint/_blueprint.py:798-815`):**
TypedDict fields are expanded into individual blueprint parameters:
```python
@chz.chz
class Main:
    foo: Foo  # TypedDict with {bar: int, baz: str}

# Blueprint exposes: foo.bar, foo.baz as parameters
```

**Current ChzEx:**
Maps are treated as atomic values - no field expansion for map types.

**Implementation Plan:**

1. **Add MapSchema type** (`lib/chz_ex/type.ex`):
```elixir
# New type: {:map_schema, %{field => type}}
def type_repr({:map_schema, fields}) do
  fields_str = fields |> Enum.map(fn {k, v} -> "#{k}: #{type_repr(v)}" end) |> Enum.join(", ")
  "%{#{fields_str}}"
end
```

2. **Field expansion in Blueprint** (`lib/chz_ex/blueprint.ex`):
```elixir
defp construct_map_schema(field, path, state) when is_map(field.type) do
  # Treat map schema like embeds_one but builds a map instead of struct
  fields = field.type  # %{bar: :integer, baz: :string}

  {kwargs, state} =
    Enum.reduce(fields, {%{}, state}, fn {name, type}, {acc, st} ->
      param_path = join_path(path, Atom.to_string(name))
      # Create virtual field for each map key
      virtual_field = %ChzEx.Field{name: name, type: type, ...}
      st = construct_scalar(virtual_field, param_path, st)
      {Map.put(acc, name, %Lazy.ParamRef{ref: param_path}), st}
    end)

  thunk = %Lazy.Thunk{
    fn: fn resolved -> Map.new(resolved) end,
    kwargs: kwargs
  }

  put_value(state, path, thunk)
end
```

3. **Schema macro support**:
```elixir
# Allow inline map schemas
field :config, %{timeout: :integer, retries: :integer}
```

---

### 1.3 Required/NotRequired Map Fields

**Status:** Gap Confirmed
**Priority:** Medium
**Effort:** Small (extends 1.2)

**Python Behavior (`chz/tests/test_blueprint_variadic.py:217-294`):**
```python
class Foo(typing.TypedDict):
    a: int                    # Required
    b: typing.Required[int]   # Explicit required
    c: typing.NotRequired[int]  # Optional
```

**Implementation Plan:**

1. **Extend map_schema type**:
```elixir
# {:map_schema, %{field => {type, required?}}}
field :config, %{
  timeout: {:integer, :required},
  retries: {:integer, :optional}
}
```

2. **Or use struct-like syntax**:
```elixir
field :config, :map, keys: [
  timeout: [type: :integer, required: true],
  retries: [type: :integer, default: 3]
]
```

---

### 1.4 Variadic TypedDict Support (Heterogeneous Tuples)

**Status:** Gap Confirmed
**Priority:** Medium
**Effort:** Medium

**Python Behavior (`chz/tests/test_blueprint_variadic.py:84-127`):**
```python
@chz.chz
class MainHeteroTuple:
    xs: tuple[X, Y, X]  # Each position has specific type

chz.Blueprint(MainHeteroTuple).apply(
    {"xs.0.a": 1, "xs.1.b": "str", "xs.2.a": 3}
).make()
```

**Current ChzEx:**
Tuples are treated uniformly - no per-position type checking.

**Implementation Plan:**

1. **Add heterogeneous tuple type** (`lib/chz_ex/type.ex`):
```elixir
# {:tuple, [:integer, :string, :integer]} - fixed positions
# {:tuple_variadic, :integer} - homogeneous (current)
def type_repr({:tuple, types}) when is_list(types) do
  types_str = Enum.map_join(types, ", ", &type_repr/1)
  "{#{types_str}}"
end
```

2. **Blueprint construction** (`lib/chz_ex/blueprint.ex`):
```elixir
defp construct_hetero_tuple(field, path, {:tuple, types}, subpaths, state) do
  indices = 0..(length(types) - 1)

  {kwargs, state} =
    Enum.reduce(Enum.with_index(types), {%{}, state}, fn {type, idx}, {acc, st} ->
      index_path = join_path(path, Integer.to_string(idx))
      # Construct with specific type for this position
      st = construct_schema_or_scalar(type, index_path, st)
      {Map.put(acc, idx, %Lazy.ParamRef{ref: index_path}), st}
    end)

  thunk = %Lazy.Thunk{
    fn: fn resolved ->
      indices |> Enum.map(&Map.fetch!(resolved, &1)) |> List.to_tuple()
    end,
    kwargs: kwargs
  }

  put_value(state, path, thunk)
end
```

---

### 1.5 `meta_factory: nil` to Disable Polymorphism

**Status:** Gap Confirmed
**Priority:** Low
**Effort:** Small

**Python Behavior:**
```python
a: A = chz.field(meta_factory=None)  # Explicitly disable polymorphism
```

**Current ChzEx:**
`meta_factory: nil` doesn't explicitly disable - it falls back to StandardFactory.

**Implementation Plan:**
```elixir
# In lib/chz_ex/blueprint.ex:382-410
def meta_factory_for_field(%ChzEx.Field{meta_factory: :disabled} = _field) do
  nil  # Return nil to signal no polymorphism
end

def meta_factory_for_field(%ChzEx.Field{} = field) do
  # ... existing logic
end

# Usage:
field :config, MyConfig, meta_factory: :disabled
```

---

### 1.6 Computed Reference Integration Verification

**Status:** Needs Verification
**Priority:** Medium
**Effort:** Small-Medium

**Python Behavior (`chz/blueprint/_blueprint.py:88-97`):**
```python
@dataclass
class Computed(SpecialArg):
    src: dict[str, Reference]
    compute: Callable[..., Any]
```

**Current ChzEx (`lib/chz_ex/blueprint/computed.ex`):**
```elixir
defstruct [:sources, :compute]
```

**The integration exists** in `lib/chz_ex/blueprint.ex:291-294`:
```elixir
defp resolve_scalar_value(_field, _path, %ChzEx.Blueprint.Computed{} = computed, state) do
  kwargs = build_computed_kwargs(computed.sources)
  {%Lazy.Thunk{fn: computed.compute, kwargs: kwargs}, state}
end
```

**Verification Tasks:**
1. Add comprehensive tests for Computed usage
2. Verify cycle detection works with Computed references
3. Add example in `examples/computed.exs`

---

### 1.7 Help Text Quality Improvements

**Status:** Gap Confirmed
**Priority:** Low
**Effort:** Medium

**Python Features Missing in ChzEx:**
1. Warning header for missing required fields
2. Document type showing per-param current value source (e.g., "from command line")
3. Layer attribution in error messages

**Implementation Plan:**

1. **Add warning header** (`lib/chz_ex/blueprint.ex:152-190`):
```elixir
def get_help(%__MODULE__{} = bp, _opts \\ []) do
  {:ok, state} = make_lazy(bp)

  missing = state.missing_params
  warning = if missing != [] do
    "WARNING: Missing required arguments for parameter(s): #{Enum.join(missing, ", ")}\n\n"
  else
    ""
  end

  warning <> "Entry point: #{bp.entrypoint_repr}\n\n" <> ...
end
```

2. **Layer attribution in errors** (`lib/chz_ex/error.ex`):
```elixir
defstruct [
  # ... existing fields
  :layer  # "command line", "preset:default", etc.
]

def format(%__MODULE__{layer: layer} = error) when layer != nil do
  "#{base_format(error)} (from #{layer})"
end
```

---

## 2. Design Decisions (Different by Design)

### 2.1 `init_property` vs Mungers

**Status:** Design Decision - Not a Gap
**Python:** `@chz.init_property` for lazy cached properties computed during `__init__`
**Elixir:** `munger` field option provides similar post-init transformation

**Python Pattern:**
```python
@chz.init_property
def log_path(self) -> str:
    return re.sub(r"[^a-zA-Z]", "", self.name)
```

**Elixir Equivalent:**
```elixir
field :name, :string
field :log_path, :string,
  munger: ChzEx.Munger.if_none(fn struct ->
    String.replace(struct.name, ~r/[^a-zA-Z]/, "")
  end)
```

**Key Differences:**
1. Python: Property-based, accessed lazily
2. Elixir: Applied during construction, stored as field value

**Recommendation:** Document the pattern difference rather than implement `init_property`.

---

### 2.2 `X_` Prefix Magic

**Status:** Design Decision - Not Applicable
**Python:** `X_` prefix stores raw value, `logical_name` exposes transformed value
**Elixir:** Mungers transform values in-place, no separate storage

**Python Pattern:**
```python
X_wandb_log_name: Optional[str] = None

@chz.init_property
def wandb_log_name(self) -> str:
    return self.X_wandb_log_name or self.name
```

**Elixir Equivalent:**
```elixir
field :wandb_log_name, :string,
  munger: ChzEx.Munger.attr_if_none(:name)
```

**Recommendation:** Document that mungers replace the X_ pattern.

---

### 2.3 `functools.partial` Support

**Status:** Design Decision - Not Applicable
**Reason:** Elixir doesn't have an equivalent partial application pattern for module structs

**Python Pattern:**
```python
partial_foo = functools.partial(Foo, a=3, b=4)
chz.Blueprint(partial_foo).make()
```

**Elixir Alternative:**
```elixir
# Use presets layer instead
ChzEx.Blueprint.new(Foo)
|> ChzEx.Blueprint.apply(%{"a" => 3, "b" => 4}, layer_name: "partial_defaults")
|> ChzEx.Blueprint.make()
```

**Recommendation:** Document preset layers as the partial equivalent.

---

### 2.4 Lambda String Parsing

**Status:** Not Applicable
**Reason:** Python-specific feature (`"lambda: A()"` in argv)

**Python Pattern:**
```python
argv = ["a=lambda: A()", "cal=lambda d: Calendar(int(d))"]
```

**Recommendation:** Not portable - skip implementation.

---

### 2.5 `*args`/`**kwargs` Blueprint Collection

**Status:** Design Decision - Not Applicable
**Reason:** Elixir functions don't have variadic args in the same way

**Python Pattern:**
```python
def foo(*args: int, **kwargs: str): ...
```

**Elixir Alternative:** Use `embeds_many` for variadic collections.

---

## 3. Implementation Priority Matrix

| Feature | Priority | Effort | Impact | Recommendation |
|---------|----------|--------|--------|----------------|
| 1.1 Version Suffix | Low | Small | Low | Implement |
| 1.2 TypedDict Expansion | Medium | Medium | Medium | Implement |
| 1.3 Required/NotRequired | Medium | Small | Medium | Implement |
| 1.4 Heterogeneous Tuples | Medium | Medium | Medium | Implement |
| 1.5 meta_factory: nil | Low | Small | Low | Implement |
| 1.6 Computed Verification | Medium | Small | High | Verify + Test |
| 1.7 Help Quality | Low | Medium | Low | Implement |

---

## 4. Detailed Implementation Tasks

### Phase 1: Quick Wins (1-2 days)

#### Task 1.1: Version Suffix Support
```
File: lib/chz_ex/schema.ex
Lines: 194-203
Changes:
  - Split version string on "-"
  - Compare only first part against hash
Tests: test/chz_ex/schema_test.exs
```

#### Task 1.5: meta_factory: nil
```
File: lib/chz_ex/blueprint.ex
Lines: 382-410
Changes:
  - Handle meta_factory: :disabled explicitly
  - Return nil to skip polymorphic construction
File: lib/chz_ex/field.ex
Changes:
  - Document :disabled option
Tests: test/chz_ex/blueprint_test.exs
```

### Phase 2: Type System Extensions (3-5 days)

#### Task 1.2: TypedDict/Map Schema Support
```
Files:
  - lib/chz_ex/type.ex: Add {:map_schema, fields} type
  - lib/chz_ex/schema.ex: Support inline map schemas
  - lib/chz_ex/blueprint.ex: construct_map_schema/3
  - lib/chz_ex/cast.ex: Cast to map schemas
Tests: test/chz_ex/blueprint_map_schema_test.exs
Examples: examples/map_schema.exs
```

#### Task 1.4: Heterogeneous Tuple Support
```
Files:
  - lib/chz_ex/type.ex: Add {:tuple, [types]} for fixed tuples
  - lib/chz_ex/blueprint.ex: construct_hetero_tuple/5
  - lib/chz_ex/cast.ex: Cast per-position
Tests: test/chz_ex/blueprint_tuple_test.exs
```

### Phase 3: Polish (2-3 days)

#### Task 1.6: Computed Verification
```
Files:
  - test/chz_ex/blueprint_computed_test.exs (new)
  - examples/computed.exs (new)
Changes:
  - Add edge case tests
  - Verify cycle detection
  - Document usage patterns
```

#### Task 1.7: Help Quality
```
File: lib/chz_ex/blueprint.ex
Lines: 152-190
Changes:
  - Add missing params warning header
  - Show layer attribution
  - Improve formatting
```

---

## 5. Test Coverage Requirements

### New Test Files
```
test/chz_ex/schema_version_test.exs
test/chz_ex/blueprint_map_schema_test.exs
test/chz_ex/blueprint_tuple_test.exs
test/chz_ex/blueprint_computed_test.exs
```

### Example Files
```
examples/map_schema.exs
examples/hetero_tuple.exs
examples/computed.exs
examples/version_suffix.exs
```

---

## 6. Appendix: Feature Comparison Matrix

| Feature | Python chz | ChzEx | Status |
|---------|-----------|-------|--------|
| Basic schema definition | `@chz.chz` | `use ChzEx.Schema` | Complete |
| Field validation | `@chz.validate` | `@chz_validate` | Complete |
| Lazy construction | Blueprint | Blueprint | Complete |
| References | `@=` syntax | `@=` syntax | Complete |
| Wildcards | `...` | `...` | Complete |
| Polymorphism | meta_factory | meta_factory | Complete |
| Mungers | Built-in | ChzEx.Munger | Complete |
| Pretty printing | `pretty_format` | ChzEx.Pretty | Complete |
| CLI parsing | `make_from_argv` | `make_from_argv` | Complete |
| dispatch_entrypoint | Yes | Yes | Complete |
| methods_entrypoint | Yes | Yes | Complete |
| nested_entrypoint | Yes | Yes | Complete |
| Version hashing | SHA1 | SHA1 | Complete |
| Version suffix (`-N`) | Yes | No | **Gap** |
| TypedDict expansion | Yes | No | **Gap** |
| Required/NotRequired | Yes | No | **Gap** |
| Hetero tuples | Yes | No | **Gap** |
| init_property | Yes | munger (alt) | Design diff |
| X_ prefix | Yes | munger (alt) | Design diff |
| functools.partial | Yes | presets (alt) | Design diff |
| *args/**kwargs | Yes | N/A | Not applicable |
| Lambda parsing | Yes | N/A | Not applicable |

---

## 7. Conclusion

The ChzEx port is **highly complete** with all core functionality implemented. The identified gaps are:
- **7 items** to implement (1.1-1.7)
- **Several design differences** that are intentional and documented

The most impactful additions would be:
1. **Map schema support** (1.2) - Enables TypedDict-like patterns
2. **Heterogeneous tuples** (1.4) - Enables fixed-position typed tuples

These can be implemented incrementally without breaking existing functionality.
