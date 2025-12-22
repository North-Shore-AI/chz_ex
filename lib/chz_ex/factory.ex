defmodule ChzEx.Factory do
  @moduledoc """
  Behaviour for meta-factories that describe how to construct values.
  """

  @callback unspecified_factory(struct()) :: module() | nil
  @callback from_string(struct(), String.t()) :: {:ok, module() | fun()} | {:error, String.t()}
  @callback perform_cast(struct(), String.t()) :: {:ok, any()} | {:error, String.t()}
end
