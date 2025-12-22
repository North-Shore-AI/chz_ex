defmodule ChzEx.Validate do
  @moduledoc """
  Macro helpers for defining class-level validators.
  """

  @doc """
  Define a class-level validator and register it for the schema.
  """
  defmacro validate(name, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :chz_validate, unquote(name))

      def unquote(name)(var!(struct)) do
        unquote(block)
      end
    end
  end
end
