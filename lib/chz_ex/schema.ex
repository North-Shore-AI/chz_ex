defmodule ChzEx.Schema do
  @moduledoc """
  Macro for defining ChzEx configuration schemas.
  """

  defmacro chz_schema(opts \\ [], do: block) do
    block = rewrite_schema_block(block)

    quote do
      Module.put_attribute(
        __MODULE__,
        :chz_schema_version,
        Keyword.get(unquote(opts), :version)
      )

      Module.put_attribute(
        __MODULE__,
        :chz_schema_typecheck,
        Keyword.get(unquote(opts), :typecheck, false)
      )

      embedded_schema do
        unquote(block)
      end
    end
  end

  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      chz_field = ChzEx.Field.new(name, type, opts)
      Module.put_attribute(__MODULE__, :chz_fields, {name, chz_field})

      ecto_opts = Keyword.take(opts, [:default, :virtual, :source])
      Ecto.Schema.__field__(__MODULE__, name, type, ecto_opts)
    end
  end

  defmacro chz_parent(module) do
    quote bind_quoted: [module: module] do
      Module.put_attribute(__MODULE__, :chz_parents, module)
    end
  end

  defmacro embeds_one(name, schema, opts \\ []) do
    quote bind_quoted: [name: name, schema: schema, opts: opts] do
      chz_field = ChzEx.Field.new(name, schema, Keyword.put(opts, :embed_type, :one))
      Module.put_attribute(__MODULE__, :chz_fields, {name, chz_field})
      Module.put_attribute(__MODULE__, :chz_embeds, {name, :one, schema, opts})

      Ecto.Schema.__embeds_one__(__MODULE__, name, schema, [])
    end
  end

  defmacro embeds_many(name, schema, opts \\ []) do
    quote bind_quoted: [name: name, schema: schema, opts: opts] do
      chz_field = ChzEx.Field.new(name, schema, Keyword.put(opts, :embed_type, :many))
      Module.put_attribute(__MODULE__, :chz_fields, {name, chz_field})
      Module.put_attribute(__MODULE__, :chz_embeds, {name, :many, schema, opts})

      Ecto.Schema.__embeds_many__(__MODULE__, name, schema, [])
    end
  end

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import ChzEx.Schema, only: [chz_schema: 1, chz_schema: 2, chz_parent: 1]

      @primary_key false
      @before_compile ChzEx.Schema

      Module.register_attribute(__MODULE__, :chz_fields, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :chz_embeds, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :chz_validate, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :chz_parents, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :chz_schema_version, persist: true)
      Module.register_attribute(__MODULE__, :chz_schema_typecheck, persist: true)
    end
  end

  defp rewrite_schema_block(block) do
    Macro.prewalk(block, fn
      {:field, meta, args} when is_list(args) ->
        {{:., meta, [ChzEx.Schema, :field]}, meta, args}

      {:embeds_one, meta, args} when is_list(args) ->
        {{:., meta, [ChzEx.Schema, :embeds_one]}, meta, args}

      {:embeds_many, meta, args} when is_list(args) ->
        {{:., meta, [ChzEx.Schema, :embeds_many]}, meta, args}

      other ->
        other
    end)
  end

  defmacro __before_compile__(env) do
    meta = compile_schema_metadata(env)
    core_ast = generate_core_functions(meta)
    inspect_ast = maybe_generate_inspect_impl(meta.include_inspect)

    quote do
      unquote(core_ast)
      unquote(inspect_ast)
    end
  end

  defp generate_core_functions(meta) do
    %{
      typecheck: typecheck,
      version_hash: version_hash,
      field_names: field_names,
      embed_names: embed_names,
      required: required
    } = meta

    quote do
      @doc false
      def __chz__?, do: true

      @doc false
      def __chz_fields__ do
        ChzEx.Schema.__maybe_add_typecheck__(__MODULE__)
      end

      @doc false
      def __chz_embeds__, do: ChzEx.Schema.__attr_list__(__MODULE__, :chz_embeds)

      @doc false
      def __chz_validators__, do: ChzEx.Schema.__validators__(__MODULE__)

      @doc false
      def __chz_parents__, do: ChzEx.Schema.__attr_list__(__MODULE__, :chz_parents)

      @doc false
      def __chz_version__, do: unquote(version_hash)

      @doc false
      def __chz_typecheck__, do: unquote(typecheck)

      @doc """
      Create a changeset for this schema.
      """
      def changeset(struct \\ %__MODULE__{}, params) do
        struct
        |> cast(params, unquote(field_names -- embed_names))
        |> validate_required(unquote(required))
        |> ChzEx.Schema.__cast_embeds__(__chz_embeds__())
        |> ChzEx.Schema.__run_validators__(__chz_fields__(), __chz_validators__())
      end
    end
  end

  defp maybe_generate_inspect_impl(false), do: nil

  defp maybe_generate_inspect_impl(true) do
    quote do
      defimpl Inspect, for: __MODULE__ do
        def inspect(struct, _opts) do
          Inspect.Algebra.string(ChzEx.Pretty.format(struct, false))
        end
      end
    end
  end

  defp compile_schema_metadata(env) do
    fields = Module.get_attribute(env.module, :chz_fields) |> Enum.reverse()
    embeds = Module.get_attribute(env.module, :chz_embeds) |> Enum.reverse()
    typecheck = Module.get_attribute(env.module, :chz_schema_typecheck) || false
    version = Module.get_attribute(env.module, :chz_schema_version)
    include_inspect = not String.contains?(env.file || "", "/test/")
    allow_inspect = include_inspect and not Protocol.consolidated?(Inspect)
    version_hash = ChzEx.Schema.version_hash_for_fields(fields)

    validate_version!(version, version_hash, env.module)

    field_names = Keyword.keys(fields)
    embed_names = Enum.map(embeds, fn {name, _type, _schema, _opts} -> name end)
    required = required_fields(fields)

    %{
      fields: fields,
      embeds: embeds,
      typecheck: typecheck,
      version_hash: version_hash,
      field_names: field_names,
      embed_names: embed_names,
      required: required,
      include_inspect: allow_inspect
    }
  end

  defp validate_version!(nil, _version_hash, _module), do: :ok

  defp validate_version!(version, version_hash, module) do
    if version != version_hash do
      raise ArgumentError,
            "Schema version #{inspect(version)} does not match #{inspect(version_hash)} for #{inspect(module)}"
    end

    :ok
  end

  defp required_fields(fields) do
    fields
    |> Enum.filter(fn {_, field} -> ChzEx.Field.required?(field) and is_nil(field.embed_type) end)
    |> Keyword.keys()
  end

  @doc false
  def __cast_embeds__(changeset, embeds) do
    Enum.reduce(embeds, changeset, &do_cast_embed/2)
  end

  defp do_cast_embed({name, _type, _schema, opts}, cs) do
    if Keyword.get(opts, :polymorphic, false), do: cs, else: Ecto.Changeset.cast_embed(cs, name)
  end

  @doc false
  def __run_validators__(changeset, fields, schema_validators) do
    changeset
    |> run_field_validators(fields)
    |> run_schema_validators(schema_validators)
  end

  defp run_field_validators(changeset, fields) do
    Enum.reduce(fields, changeset, &apply_field_validators/2)
  end

  defp apply_field_validators({name, field}, cs) do
    Enum.reduce(field.validators, cs, fn validator, c ->
      apply_field_validator(c, name, validator)
    end)
  end

  defp apply_field_validator(%{valid?: false} = cs, _name, _validator), do: cs

  defp apply_field_validator(cs, name, validator) do
    case validator.(Ecto.Changeset.apply_changes(cs), name) do
      :ok -> cs
      {:error, msg} -> Ecto.Changeset.add_error(cs, name, msg)
    end
  end

  defp run_schema_validators(changeset, validators) do
    Enum.reduce(validators, changeset, &apply_schema_validator/2)
  end

  defp apply_schema_validator(_validator, %{valid?: false} = cs), do: cs

  defp apply_schema_validator(validator, cs) do
    case validator.(Ecto.Changeset.apply_changes(cs)) do
      :ok -> cs
      {:error, field, msg} -> Ecto.Changeset.add_error(cs, field, msg)
    end
  end

  @doc false
  def __attr_list__(module, attr) when is_atom(module) and is_atom(attr) do
    module.__info__(:attributes)
    |> Keyword.get_values(attr)
    |> List.flatten()
  end

  @doc false
  def __attr_map__(module, attr) do
    module
    |> __attr_list__(attr)
    |> Map.new()
  end

  @doc false
  def __maybe_add_typecheck__(module) do
    fields = __attr_map__(module, :chz_fields)

    if module.__chz_typecheck__() do
      add_typecheck_validators(fields)
    else
      fields
    end
  end

  defp add_typecheck_validators(fields) do
    Enum.into(fields, %{}, fn {name, field} ->
      {name, %{field | validators: [(&ChzEx.Validator.typecheck/2) | field.validators]}}
    end)
  end

  @doc false
  def __validators__(module) do
    module
    |> __attr_list__(:chz_validate)
    |> Enum.map(fn name ->
      fn struct -> apply(module, name, [struct]) end
    end)
  end

  @doc """
  Compute the version hash for a schema module.
  """
  def version_hash(module) when is_atom(module) do
    module.__chz_fields__()
    |> version_hash_for_fields()
  end

  @doc false
  def version_hash_for_fields(fields) when is_list(fields) do
    payload =
      fields
      |> Enum.sort_by(fn {name, _field} -> Atom.to_string(name) end)
      |> Enum.map(&field_version_key/1)
      |> :erlang.term_to_binary()

    payload
    |> then(&:crypto.hash(:sha, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp field_version_key({name, field}) do
    default_key =
      if is_nil(field.default) do
        ""
      else
        inspect(field.default)
      end

    default_factory_key =
      case field.default_factory do
        nil -> ""
        fun when is_function(fun) -> function_key(fun)
        _ -> "unknown"
      end

    {Atom.to_string(name), type_key(field.raw_type), default_key, default_factory_key}
  end

  defp type_key(type), do: ChzEx.Type.type_repr(type)

  defp function_key(fun) do
    info = Function.info(fun)
    module = Keyword.get(info, :module)
    name = Keyword.get(info, :name)
    arity = Keyword.get(info, :arity)

    if is_atom(module) and is_atom(name) and is_integer(arity) do
      "#{ChzEx.Type.type_repr(module)}.#{name}/#{arity}"
    else
      "anonymous"
    end
  end

  @doc """
  Check if a module or struct is a ChzEx schema.
  """
  def chz?(module) when is_atom(module) do
    function_exported?(module, :__chz__?, 0) and module.__chz__?()
  end

  def chz?(%{__struct__: module}), do: chz?(module)
  def chz?(_), do: false
end
