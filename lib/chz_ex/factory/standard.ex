defmodule ChzEx.Factory.Standard do
  @moduledoc """
  Standard meta-factory for polymorphic construction.
  """

  @behaviour ChzEx.Factory

  defstruct [
    :annotation,
    :unspecified,
    :default_module,
    :namespace
  ]

  def new(opts \\ []) do
    %__MODULE__{
      annotation: opts[:annotation],
      unspecified: opts[:unspecified],
      default_module: opts[:default_module],
      namespace: opts[:namespace]
    }
  end

  @impl true
  def unspecified_factory(%__MODULE__{unspecified: nil, annotation: annotation}) do
    if ChzEx.Schema.is_chz?(annotation), do: annotation, else: nil
  end

  def unspecified_factory(%__MODULE__{unspecified: unspecified}), do: unspecified

  @impl true
  def from_string(%__MODULE__{} = factory, factory_str) do
    cond do
      String.contains?(factory_str, ":") ->
        [module_str, func_str] = String.split(factory_str, ":", parts: 2)

        with {:ok, module} <- ChzEx.Registry.lookup_module(module_str),
             {:ok, value} <- get_module_attr(module, func_str) do
          {:ok, value}
        else
          {:error, reason} -> {:error, reason}
          :error -> {:error, "Unknown module: #{module_str}"}
        end

      factory.namespace != nil ->
        case ChzEx.Registry.lookup(factory.namespace, factory_str) do
          {:ok, module} -> {:ok, module}
          :error -> {:error, "Unknown factory: #{factory_str}"}
        end

      true ->
        {:error, "Unknown factory: #{factory_str}"}
    end
  end

  @impl true
  def perform_cast(%__MODULE__{annotation: annotation}, value) do
    ChzEx.Cast.try_cast(value, annotation)
  end

  defp get_module_attr(module, attr_str) do
    attrs = String.split(attr_str, ".")

    Enum.reduce_while(attrs, {:ok, module}, fn attr, {:ok, current} ->
      try do
        attr_atom = String.to_existing_atom(attr)

        if function_exported?(current, attr_atom, 0) do
          {:cont, {:ok, apply(current, attr_atom, [])}}
        else
          {:halt, {:error, "No function #{attr} on #{inspect(current)}"}}
        end
      rescue
        ArgumentError ->
          {:halt, {:error, "Unknown attribute: #{attr_str}"}}
      end
    end)
  end
end
