defmodule ChzEx.Munger do
  @moduledoc """
  Post-init field transforms.
  """

  @doc """
  If value is nil, replace with result of function.
  """
  def if_none(replacement_fn) when is_function(replacement_fn, 1) do
    fn value, struct ->
      if is_nil(value), do: replacement_fn.(struct), else: value
    end
  end

  @doc """
  If value is nil, use another attribute.
  """
  def attr_if_none(replacement_attr) when is_atom(replacement_attr) do
    fn value, struct ->
      if is_nil(value), do: Map.get(struct, replacement_attr), else: value
    end
  end

  @doc """
  Create a munger from a simple function.
  """
  def from_function(fun) when is_function(fun, 2) do
    fn value, struct -> fun.(struct, value) end
  end
end
