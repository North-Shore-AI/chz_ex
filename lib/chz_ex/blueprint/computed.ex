defmodule ChzEx.Blueprint.Computed do
  @moduledoc "A value computed from other parameters."

  defstruct [:sources, :compute]

  @type t :: %__MODULE__{
          sources: %{String.t() => ChzEx.Blueprint.Reference.t()},
          compute: (map() -> any())
        }
end
