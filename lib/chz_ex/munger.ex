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

  @doc """
  Apply a value-only transform function.
  """
  def transform(fun) when is_function(fun, 1) do
    fn value, _struct -> fun.(value) end
  end

  @doc """
  Replace nil values with a default.
  """
  def default(default_value) do
    fn value, _struct ->
      if is_nil(value), do: default_value, else: value
    end
  end

  @doc """
  Compose multiple mungers in order.
  """
  def compose(mungers) when is_list(mungers) do
    fn value, struct ->
      Enum.reduce(mungers, value, fn munger, acc ->
        munger.(acc, struct)
      end)
    end
  end

  @doc """
  Attempt to coerce a value to a target type.
  """
  def coerce(type) do
    fn value, _struct ->
      case ChzEx.Cast.try_cast(to_string(value), type) do
        {:ok, coerced} -> coerced
        {:error, _} -> value
      end
    end
  end
end
