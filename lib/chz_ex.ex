defmodule ChzEx do
  @moduledoc """
  ChzEx - Configuration management with CLI parsing.
  """

  alias ChzEx.Blueprint

  @doc """
  Parse argv and construct a configuration.
  Returns `{:ok, struct}` or `{:error, reason}`.
  """
  def entrypoint(module, argv \\ System.argv()) do
    Blueprint.new(module)
    |> Blueprint.make_from_argv(argv)
  end

  @doc """
  Parse argv and construct a configuration.
  Raises on error.
  """
  def entrypoint!(module, argv \\ System.argv()) do
    case entrypoint(module, argv) do
      {:ok, config} -> config
      {:error, errors} -> raise ChzEx.ConfigError, errors: errors
    end
  end

  @doc """
  Construct a configuration from a map of arguments.
  """
  def make(module, args) when is_map(args) do
    Blueprint.new(module)
    |> Blueprint.apply(args)
    |> Blueprint.make()
  end

  @doc """
  Construct a configuration from a map of arguments.
  Raises on error.
  """
  def make!(module, args) when is_map(args) do
    case make(module, args) do
      {:ok, config} -> config
      {:error, errors} -> raise ChzEx.ConfigError, errors: errors
    end
  end

  @doc """
  Check if a value is a ChzEx struct.
  """
  defdelegate is_chz?(value), to: ChzEx.Schema

  @doc """
  Get the field specifications for a ChzEx struct or module.
  """
  def chz_fields(struct) when is_struct(struct) do
    struct.__struct__.__chz_fields__()
  end

  def chz_fields(module) when is_atom(module) do
    module.__chz_fields__()
  end

  @doc """
  Replace fields in a ChzEx struct.
  """
  def replace(struct, changes) when is_struct(struct) and is_map(changes) do
    struct.__struct__.changeset(struct, changes)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Convert a ChzEx struct to a map.
  """
  def asdict(struct, opts \\ []) do
    shallow = Keyword.get(opts, :shallow, false)
    include_type = Keyword.get(opts, :include_type, false)

    do_asdict(struct, shallow, include_type)
  end

  defp do_asdict(struct, shallow, include_type) when is_struct(struct) do
    if is_chz?(struct) do
      base =
        struct
        |> Map.from_struct()
        |> Enum.map(fn {k, v} ->
          {k, if(shallow, do: v, else: do_asdict(v, shallow, include_type))}
        end)
        |> Map.new()

      if include_type do
        Map.put(base, :__chz_type__, struct.__struct__)
      else
        base
      end
    else
      struct
    end
  end

  defp do_asdict(list, shallow, include_type) when is_list(list) do
    Enum.map(list, &do_asdict(&1, shallow, include_type))
  end

  defp do_asdict(map, shallow, include_type) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, do_asdict(v, shallow, include_type)} end)
  end

  defp do_asdict(value, _shallow, _include_type), do: value
end

defmodule ChzEx.ConfigError do
  defexception [:errors]

  @impl true
  def message(%{errors: errors}) when is_list(errors) do
    "Configuration error:\n" <> Enum.join(errors, "\n")
  end

  def message(%{errors: error}) do
    "Configuration error: #{inspect(error)}"
  end
end
