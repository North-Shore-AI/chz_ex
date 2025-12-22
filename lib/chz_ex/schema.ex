defmodule ChzEx.Schema do
  @moduledoc """
  Macro for defining ChzEx configuration schemas.
  """

  defmacro chz_schema(do: block) do
    block = rewrite_schema_block(block)

    quote do
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
      import ChzEx.Schema, only: [chz_schema: 1]

      @primary_key false
      @before_compile ChzEx.Schema

      Module.register_attribute(__MODULE__, :chz_fields, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :chz_embeds, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :chz_validate, accumulate: true, persist: true)
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
    fields = Module.get_attribute(env.module, :chz_fields) |> Enum.reverse()
    embeds = Module.get_attribute(env.module, :chz_embeds) |> Enum.reverse()
    field_names = Keyword.keys(fields)
    embed_names = Enum.map(embeds, fn {name, _type, _schema, _opts} -> name end)

    required =
      fields
      |> Enum.filter(fn {_, f} -> ChzEx.Field.required?(f) and is_nil(f.embed_type) end)
      |> Keyword.keys()

    quote do
      @doc false
      def __chz__?, do: true

      @doc false
      def __chz_fields__, do: ChzEx.Schema.__attr_map__(__MODULE__, :chz_fields)

      @doc false
      def __chz_embeds__, do: ChzEx.Schema.__attr_list__(__MODULE__, :chz_embeds)

      @doc false
      def __chz_validators__, do: ChzEx.Schema.__validators__(__MODULE__)

      @doc """
      Create a changeset for this schema.
      """
      def changeset(struct \\ %__MODULE__{}, params) do
        struct
        |> cast(params, unquote(field_names -- embed_names))
        |> validate_required(unquote(required))
        |> cast_embeds(__chz_embeds__())
        |> run_chz_validators(__chz_fields__())
      end

      defp cast_embeds(changeset, embeds) do
        Enum.reduce(embeds, changeset, fn {name, _type, _schema, opts}, cs ->
          if Keyword.get(opts, :polymorphic, false) do
            cs
          else
            cast_embed(cs, name)
          end
        end)
      end

      defp run_chz_validators(changeset, fields) do
        changeset =
          Enum.reduce(fields, changeset, fn {name, field}, cs ->
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
  def __validators__(module) do
    module
    |> __attr_list__(:chz_validate)
    |> Enum.map(fn name ->
      fn struct -> apply(module, name, [struct]) end
    end)
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
