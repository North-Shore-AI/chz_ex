defmodule ChzEx.Blueprint.Reference do
  @moduledoc "A reference to another parameter."

  defstruct [:ref]

  @type t :: %__MODULE__{ref: String.t()}

  def new(ref) when is_binary(ref) do
    if String.contains?(ref, "...") do
      raise ArgumentError, "Reference target cannot contain wildcards"
    end

    %__MODULE__{ref: ref}
  end
end
