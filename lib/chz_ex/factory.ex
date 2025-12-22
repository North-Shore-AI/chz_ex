defmodule ChzEx.Factory do
  @moduledoc """
  Behaviour for meta-factories that describe how to construct values.
  """

  @callback unspecified_factory(struct()) :: module() | nil
  @callback from_string(struct(), String.t()) :: {:ok, module() | fun()} | {:error, String.t()}
  @callback perform_cast(struct(), String.t()) :: {:ok, any()} | {:error, String.t()}
  @callback registered_factories(struct()) :: %{String.t() => module()}
  @callback serialize(struct(), any()) :: {:ok, String.t()} | :error
end
