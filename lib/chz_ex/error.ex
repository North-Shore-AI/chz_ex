defmodule ChzEx.Error do
  @moduledoc """
  Structured error information for ChzEx.
  """

  defexception [
    :type,
    :path,
    :message,
    :cause,
    :context,
    suggestions: [],
    layer: nil
  ]

  @impl Exception
  def exception(opts) when is_list(opts), do: struct!(__MODULE__, opts)

  @impl Exception
  def message(%__MODULE__{} = error), do: format(error)

  @doc """
  Format an error for display.
  """
  def format(message) when is_binary(message), do: message

  def format(%__MODULE__{type: :missing_required, path: path}) do
    "Missing required argument: #{path}"
  end

  def format(%__MODULE__{type: :extraneous, message: message})
      when is_binary(message) do
    message
  end

  def format(%__MODULE__{type: :extraneous, path: path, suggestions: suggestions}) do
    base = "Unknown argument: #{path}"

    case suggestions do
      [] -> base
      _ -> base <> " (Did you mean: #{Enum.join(suggestions, ", ")})"
    end
  end

  def format(%__MODULE__{type: :construction_error, message: message, context: context})
      when is_binary(message) do
    if is_binary(context) do
      "Construction error: #{message} (#{context})"
    else
      "Construction error: #{message}"
    end
  end

  def format(%__MODULE__{type: :validation_error, path: path, message: message}) do
    "Validation error for #{path}: #{message}"
  end

  def format(%__MODULE__{type: :cast_error, path: path, message: message}) do
    "Could not cast #{path}: #{message}"
  end

  def format(%__MODULE__{type: :cycle, message: message}) do
    "Detected cyclic reference: #{message}"
  end

  def format(%__MODULE__{type: :invalid_reference, message: message}) when is_binary(message) do
    message
  end

  def format(%__MODULE__{message: message}) when is_binary(message), do: message
  def format(%__MODULE__{}), do: "Unknown error"

  @doc """
  Wrap an exception with construction context.
  """
  def wrap(error, context) do
    %__MODULE__{
      type: :construction_error,
      message: Exception.message(error),
      cause: error,
      context: context
    }
  end
end
