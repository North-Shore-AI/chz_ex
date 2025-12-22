defmodule ChzEx.Factory.Subclass do
  @moduledoc """
  Meta-factory for behaviour-based polymorphic construction.
  """

  @behaviour ChzEx.Factory

  defstruct [
    :annotation,
    :default,
    :namespace,
    discriminator: :module
  ]

  @type t :: %__MODULE__{
          annotation: module() | [module()] | nil,
          default: module() | nil,
          namespace: atom() | nil,
          discriminator: atom()
        }

  @doc """
  Create a new subclass meta-factory.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      annotation: opts[:annotation],
      default: opts[:default],
      namespace: opts[:namespace],
      discriminator: opts[:discriminator] || :module
    }
  end

  @impl true
  def unspecified_factory(%__MODULE__{default: default}), do: default

  @impl true
  def from_string(%__MODULE__{} = factory, name) when is_binary(name) do
    candidates = candidate_modules(factory)

    matches =
      candidates
      |> Enum.filter(fn module -> match_discriminator?(module, factory.discriminator, name) end)

    case matches do
      [module] -> {:ok, module}
      [] -> {:error, "Unknown subtype: #{name}"}
      _ -> {:error, "Multiple subtypes matched: #{name}"}
    end
  end

  @impl true
  def perform_cast(%__MODULE__{annotation: annotation}, value) do
    ChzEx.Cast.try_cast(value, annotation)
  end

  @impl true
  def registered_factories(%__MODULE__{} = factory) do
    factory
    |> candidate_modules()
    |> Enum.reduce(%{}, fn module, acc ->
      name = discriminator_value(module, factory.discriminator)
      Map.put(acc, name, module)
    end)
  end

  @impl true
  def serialize(%__MODULE__{} = factory, module) when is_atom(module) do
    factory
    |> registered_factories()
    |> Enum.find(fn {_name, value} -> value == module end)
    |> case do
      {name, _module} -> {:ok, name}
      nil -> :error
    end
  end

  def serialize(%__MODULE__{}, _value), do: :error

  defp candidate_modules(%__MODULE__{namespace: namespace} = factory) do
    modules =
      if is_atom(namespace) and not is_nil(namespace) do
        namespace
        |> ChzEx.Registry.all_in_namespace()
        |> Map.values()
      else
        ChzEx.Registry.registered_modules()
      end

    modules
    |> Enum.uniq()
    |> Enum.filter(&matches_annotation?(&1, factory.annotation))
  end

  defp matches_annotation?(_module, nil), do: true

  defp matches_annotation?(module, annotation) when is_list(annotation) do
    Enum.any?(annotation, fn behaviour -> matches_annotation?(module, behaviour) end)
  end

  defp matches_annotation?(module, behaviour) when is_atom(behaviour) do
    behaviours =
      module.__info__(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()
      |> Kernel.++(
        module.__info__(:attributes)
        |> Keyword.get_values(:behavior)
        |> List.flatten()
      )

    behaviour in behaviours
  end

  defp match_discriminator?(module, discriminator, name) do
    discriminator_value(module, discriminator) == name
  end

  defp discriminator_value(module, :module), do: short_name(module)
  defp discriminator_value(module, :__module__), do: short_name(module)
  defp discriminator_value(module, :__struct__), do: short_name(module)

  defp discriminator_value(module, discriminator) when is_atom(discriminator) do
    if function_exported?(module, discriminator, 0) do
      module |> apply(discriminator, []) |> to_string()
    else
      short_name(module)
    end
  end

  defp short_name(module) do
    module
    |> Module.split()
    |> List.last()
  end
end
