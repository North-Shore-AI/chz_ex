defmodule ChzEx.Blueprint.Castable do
  @moduledoc "A string value that needs type-aware casting."

  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  def new(value) when is_binary(value), do: %__MODULE__{value: value}
end
