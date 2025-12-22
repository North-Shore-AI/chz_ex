defmodule ChzEx.CLI do
  @moduledoc """
  CLI helpers for wrapping ChzEx entrypoints with error handling.
  """

  @doc """
  Wrap an entrypoint and handle errors with consistent exit codes.

  Options:
  - `:halt?` (boolean): call `System.halt/1` on error/help (default: true)
  """
  def with_error_handling(fun, opts \\ []) when is_function(fun, 0) do
    halt? = Keyword.get(opts, :halt?, true)

    try do
      case fun.() do
        {:ok, value} -> value
        {:error, %ChzEx.Error{} = error} -> handle_error(error, halt?)
        {:error, error} -> handle_error(error, halt?)
        other -> other
      end
    rescue
      e in [ChzEx.HelpError] ->
        handle_help(e, halt?)
    end
  end

  defp handle_help(%ChzEx.HelpError{message: message}, halt?) do
    IO.puts(message)

    if halt? do
      System.halt(0)
    else
      {:help, message}
    end
  end

  defp handle_error(%ChzEx.Error{} = error, halt?) do
    IO.puts(:stderr, "Error:")
    IO.puts(:stderr, ChzEx.Error.format(error))

    if halt? do
      System.halt(1)
    else
      {:error, error}
    end
  end

  defp handle_error(error, halt?) do
    message =
      cond do
        is_exception(error) -> Exception.message(error)
        is_binary(error) -> error
        true -> inspect(error)
      end

    IO.puts(:stderr, "Error:")
    IO.puts(:stderr, message)

    if halt? do
      System.halt(1)
    else
      {:error, error}
    end
  end
end
