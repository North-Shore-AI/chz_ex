defmodule ChzEx.Field do
  @moduledoc """
  Field specification for ChzEx schemas.
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
          meta_factory: struct() | module() | nil,
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
  """
  def new(name, type, opts \\ []) when is_atom(name) do
    validate_opts!(opts)
    meta_factory = Keyword.get(opts, :meta_factory)

    # When meta_factory is :disabled, polymorphism is explicitly disabled
    polymorphic =
      if meta_factory == :disabled do
        false
      else
        Keyword.get(opts, :polymorphic, false)
      end

    # Store nil for :disabled to indicate no factory should be used
    meta_factory = if meta_factory == :disabled, do: nil, else: meta_factory

    %__MODULE__{
      name: name,
      type: normalize_type(type),
      raw_type: Keyword.get(opts, :raw_type, type),
      default: Keyword.get(opts, :default),
      default_factory: Keyword.get(opts, :default_factory),
      munger: normalize_munger(Keyword.get(opts, :munger)),
      validators: normalize_validators(opts),
      meta_factory: meta_factory,
      blueprint_cast: Keyword.get(opts, :blueprint_cast),
      embed_type: Keyword.get(opts, :embed_type),
      polymorphic: polymorphic,
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

  def get_default(%__MODULE__{default_factory: factory}) when is_function(factory, 0),
    do: factory.()

  def get_default(%__MODULE__{}), do: nil

  @doc """
  Check if field is required (no default).
  """
  def required?(%__MODULE__{munger: nil} = field), do: not has_default?(field)
  def required?(%__MODULE__{munger: _}), do: false

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

  defp normalize_munger(other) do
    raise ArgumentError, "munger must be a 2-arity function, got: #{inspect(other)}"
  end
end
