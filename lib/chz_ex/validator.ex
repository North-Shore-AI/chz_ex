defmodule ChzEx.Validator do
  @moduledoc """
  Validation functions for ChzEx schemas.
  """

  @doc """
  Type check validator using Ecto types.
  """
  def typecheck(struct, attr) do
    field = struct.__struct__.__chz_fields__()[attr]
    value = Map.get(struct, attr)

    case Ecto.Type.cast(field.type, value) do
      {:ok, _} -> :ok
      :error -> {:error, "Expected #{attr} to be #{inspect(field.type)}, got #{inspect(value)}"}
    end
  end

  @doc "Check value is greater than base."
  def gt(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value > base, do: :ok, else: {:error, "Expected #{attr} to be greater than #{base}"}
    end
  end

  @doc "Check value is less than base."
  def lt(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value < base, do: :ok, else: {:error, "Expected #{attr} to be less than #{base}"}
    end
  end

  @doc "Check value is greater than or equal to base."
  def ge(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value >= base, do: :ok, else: {:error, "Expected #{attr} to be >= #{base}"}
    end
  end

  @doc "Check value is less than or equal to base."
  def le(base) do
    fn struct, attr ->
      value = Map.get(struct, attr)
      if value <= base, do: :ok, else: {:error, "Expected #{attr} to be <= #{base}"}
    end
  end

  @doc "Check value is a valid regex."
  def valid_regex(struct, attr) do
    value = Map.get(struct, attr)

    case Regex.compile(value) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Invalid regex in #{attr}"}
    end
  end

  @doc "Apply validator to all fields."
  def for_all_fields(validator) do
    fn struct ->
      struct.__struct__.__chz_fields__()
      |> Enum.reduce(:ok, fn {name, _field}, acc ->
        case acc do
          :ok ->
            case validator.(struct, name) do
              :ok -> :ok
              {:error, msg} -> {:error, name, msg}
            end

          error ->
            error
        end
      end)
    end
  end
end
