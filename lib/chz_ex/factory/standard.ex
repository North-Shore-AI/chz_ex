defmodule ChzEx.Factory.Standard do
  @moduledoc """
  Standard meta-factory for polymorphic construction.
  """

  @behaviour ChzEx.Factory

  defstruct [
    :annotation,
    :unspecified,
    :default_module,
    :namespace,
    aliases: %{}
  ]

  def new(opts \\ []) do
    %__MODULE__{
      annotation: opts[:annotation],
      unspecified: opts[:unspecified],
      default_module: opts[:default_module],
      namespace: opts[:namespace],
      aliases: opts[:aliases] || %{}
    }
  end

  @impl true
  def unspecified_factory(%__MODULE__{unspecified: nil, annotation: annotation}) do
    if ChzEx.Schema.chz?(annotation), do: annotation, else: nil
  end

  def unspecified_factory(%__MODULE__{unspecified: unspecified}), do: unspecified

  @impl true
  def from_string(%__MODULE__{} = factory, factory_str) do
    if String.contains?(factory_str, ":") do
      resolve_qualified(factory_str)
    else
      lookup_name = resolve_alias(factory, factory_str)
      resolve_unqualified(factory, lookup_name)
    end
  end

  @impl true
  def registered_factories(%__MODULE__{namespace: nil}), do: %{}

  def registered_factories(%__MODULE__{} = factory) do
    registry_map = ChzEx.Registry.all_in_namespace(factory.namespace)

    Enum.reduce(factory.aliases, registry_map, fn {alias_name, target}, acc ->
      case Map.get(registry_map, target) do
        nil -> acc
        module -> Map.put(acc, alias_name, module)
      end
    end)
  end

  @impl true
  def serialize(%__MODULE__{} = factory, module) when is_atom(module) do
    factory
    |> registered_factories()
    |> Enum.filter(fn {_name, value} -> value == module end)
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.sort()
    |> case do
      [name | _] -> {:ok, name}
      [] -> :error
    end
  end

  def serialize(%__MODULE__{}, _value), do: :error

  defp resolve_alias(%__MODULE__{aliases: aliases}, name) when is_binary(name) do
    if String.contains?(name, ":") do
      name
    else
      Map.get(aliases, name, name)
    end
  end

  defp resolve_default_module(%__MODULE__{default_module: nil}), do: :error

  defp resolve_default_module(%__MODULE__{default_module: module}) when is_atom(module),
    do: {:ok, module}

  defp resolve_default_module(%__MODULE__{default_module: module_str})
       when is_binary(module_str) do
    ChzEx.Registry.lookup_module(module_str)
  end

  defp resolve_qualified(factory_str) do
    [module_str, attr_str] = String.split(factory_str, ":", parts: 2)

    with {:ok, module} <- ChzEx.Registry.lookup_module(module_str),
         {:ok, value} <- resolve_attr_path(module, attr_str) do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, "Unknown module: #{module_str}"}
    end
  end

  defp resolve_unqualified(%__MODULE__{namespace: nil} = factory, name) do
    case resolve_default_module(factory) do
      {:ok, module} -> resolve_attr_path(module, name)
      :error -> {:error, "Unknown factory: #{name}"}
    end
  end

  defp resolve_unqualified(%__MODULE__{} = factory, name) do
    case ChzEx.Registry.lookup(factory.namespace, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, "Unknown factory: #{name}"}
    end
  end

  @impl true
  def perform_cast(%__MODULE__{annotation: annotation}, value) do
    ChzEx.Cast.try_cast(value, annotation)
  end

  defp resolve_attr_path(module, attr_str) when is_atom(module) and is_binary(attr_str) do
    attrs = String.split(attr_str, ".", trim: true)

    Enum.reduce_while(attrs, {:ok, module}, fn attr, {:ok, current} ->
      case resolve_attr(current, attr) do
        {:ok, value} -> {:cont, {:ok, value}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp resolve_attr(current, attr) when is_atom(current) do
    attr_atom = String.to_existing_atom(attr)

    if function_exported?(current, attr_atom, 0) do
      {:ok, apply(current, attr_atom, [])}
    else
      {:error, "No function #{attr} on #{inspect(current)}"}
    end
  rescue
    ArgumentError -> {:error, "Unknown attribute: #{attr}"}
  end

  defp resolve_attr(current, attr) when is_map(current) do
    if Map.has_key?(current, attr) do
      {:ok, Map.get(current, attr)}
    else
      attr_atom = String.to_existing_atom(attr)

      if Map.has_key?(current, attr_atom) do
        {:ok, Map.get(current, attr_atom)}
      else
        {:error, "Unknown attribute: #{attr}"}
      end
    end
  rescue
    ArgumentError -> {:error, "Unknown attribute: #{attr}"}
  end

  defp resolve_attr(_current, attr), do: {:error, "Unknown attribute: #{attr}"}
end
