defmodule ChzEx.Factory.Function do
  @moduledoc """
  Meta-factory for selecting functions as factories.
  """

  @behaviour ChzEx.Factory

  defstruct [
    :annotation,
    :default_module,
    :unspecified,
    :arity
  ]

  @type t :: %__MODULE__{
          annotation: any(),
          default_module: module() | String.t() | nil,
          unspecified: fun() | nil,
          arity: non_neg_integer() | nil
        }

  @doc """
  Create a new function meta-factory.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      annotation: opts[:annotation],
      default_module: opts[:default_module],
      unspecified: opts[:unspecified],
      arity: opts[:arity]
    }
  end

  @impl true
  def unspecified_factory(%__MODULE__{unspecified: unspecified}), do: unspecified

  @impl true
  def from_string(%__MODULE__{} = factory, factory_str) when is_binary(factory_str) do
    case resolve_function(factory, factory_str) do
      {:ok, {module, fun, arity}} -> {:ok, Function.capture(module, fun, arity)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def perform_cast(%__MODULE__{annotation: annotation}, value) do
    ChzEx.Cast.try_cast(value, annotation)
  end

  @impl true
  def registered_factories(%__MODULE__{}), do: %{}

  @impl true
  def serialize(%__MODULE__{}, fun) when is_function(fun) do
    info = :erlang.fun_info(fun)
    module = info[:module]
    name = info[:name]
    arity = info[:arity]

    module_name =
      module
      |> Atom.to_string()
      |> String.replace_prefix("Elixir.", "")

    {:ok, "#{module_name}:#{name}/#{arity}"}
  end

  def serialize(%__MODULE__{}, _value), do: :error

  defp resolve_function(%__MODULE__{arity: default_arity} = factory, factory_str) do
    case String.split(factory_str, ":", parts: 2) do
      [module_str, fun_spec] ->
        with {:ok, module} <- ChzEx.Registry.lookup_module(module_str),
             {:ok, {fun, arity}} <- parse_fun_spec(fun_spec, default_arity),
             {:ok, fun_atom} <- to_existing_function(fun),
             :ok <- ensure_exported(module, fun_atom, arity) do
          {:ok, {module, fun_atom, arity}}
        end

      [fun_spec] ->
        with {:ok, module} <- resolve_default_module(factory),
             {:ok, {fun, arity}} <- parse_fun_spec(fun_spec, default_arity),
             {:ok, fun_atom} <- to_existing_function(fun),
             :ok <- ensure_exported(module, fun_atom, arity) do
          {:ok, {module, fun_atom, arity}}
        end
    end
  end

  defp resolve_default_module(%__MODULE__{default_module: nil}),
    do: {:error, "No default module configured"}

  defp resolve_default_module(%__MODULE__{default_module: module}) when is_atom(module),
    do: {:ok, module}

  defp resolve_default_module(%__MODULE__{default_module: module_str})
       when is_binary(module_str) do
    ChzEx.Registry.lookup_module(module_str)
  end

  defp parse_fun_spec(fun_spec, default_arity) do
    case String.split(fun_spec, "/", parts: 2) do
      [fun, arity_str] ->
        case Integer.parse(arity_str) do
          {arity, ""} -> {:ok, {fun, arity}}
          _ -> {:error, "Invalid function arity: #{arity_str}"}
        end

      [fun] ->
        if is_integer(default_arity) do
          {:ok, {fun, default_arity}}
        else
          {:error, "Function arity is required"}
        end
    end
  end

  defp to_existing_function(fun) do
    {:ok, String.to_existing_atom(fun)}
  rescue
    ArgumentError -> {:error, "Unknown function: #{fun}"}
  end

  defp ensure_exported(module, fun, arity) do
    if function_exported?(module, fun, arity) do
      :ok
    else
      {:error, "Function #{inspect(module)}.#{fun}/#{arity} is not available"}
    end
  end
end
