defmodule ChzEx do
  @moduledoc """
  ChzEx - Configuration management with CLI parsing.
  """

  alias ChzEx.{Blueprint, Parser}

  @doc """
  Parse argv and construct a configuration.
  Returns `{:ok, struct}` or `{:error, reason}`.
  """
  def entrypoint(module, argv \\ System.argv(), opts \\ []) do
    Blueprint.new(module)
    |> Blueprint.make_from_argv(argv, opts)
  end

  @doc """
  Parse argv and construct a configuration.
  Raises on error.
  """
  def entrypoint!(module, argv \\ System.argv(), opts \\ []) do
    case entrypoint(module, argv, opts) do
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
  Entrypoint for functions that take a ChzEx struct.
  """
  def nested_entrypoint(main_fn, module, argv \\ System.argv(), opts \\ [])
      when is_function(main_fn, 1) do
    case entrypoint(module, argv, opts) do
      {:ok, config} -> {:ok, main_fn.(config)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Entrypoint that dispatches to methods defined on a module.
  """
  def methods_entrypoint(target, argv \\ System.argv(), opts \\ []) when is_atom(target) do
    argv = argv || System.argv()
    allow_hyphens = Keyword.get(opts, :allow_hyphens, false)

    case argv do
      [] ->
        raise ChzEx.HelpError, message: methods_help(target, nil)

      ["--help"] ->
        raise ChzEx.HelpError, message: methods_help(target, nil)

      [method | rest] ->
        dispatch_method(target, method, rest, allow_hyphens, opts)
    end
  end

  @doc """
  Entrypoint that dispatches to one of many targets.
  """
  def dispatch_entrypoint(targets, argv \\ System.argv(), opts \\ []) when is_map(targets) do
    argv = argv || System.argv()

    case argv do
      [] ->
        raise ChzEx.HelpError, message: dispatch_help(targets, nil)

      ["--help"] ->
        raise ChzEx.HelpError, message: dispatch_help(targets, nil)

      [command | rest] ->
        case fetch_target(targets, command) do
          {:ok, target} ->
            entrypoint(target, rest, opts)

          :error ->
            raise ChzEx.HelpError, message: dispatch_help(targets, "Unknown command #{command}")
        end
    end
  end

  defp dispatch_method(target, method_str, argv, allow_hyphens, opts) do
    case resolve_method(target, method_str) do
      {:ok, {method, arity}} ->
        transform = Keyword.get(opts, :transform)
        command_spec = method_spec(target, method, method_str)

        with {:ok, args} <-
               parse_method_argv(target, method, command_spec, argv, allow_hyphens),
             {:ok, {config_args, method_args}} <- split_method_args(args, command_spec),
             {:ok, config} <- build_method_config(target, config_args, transform, method_str) do
          apply_method(target, method, arity, config, method_args)
        end

      :error ->
        raise ChzEx.HelpError, message: methods_help(target, "Unknown command #{method_str}")
    end
  end

  defp parse_method_argv(target, method, command_spec, argv, allow_hyphens) do
    case Parser.parse(argv, allow_hyphens: allow_hyphens) do
      {:ok, args} ->
        if Parser.help_requested?(args) do
          raise ChzEx.HelpError, message: method_help(target, method, command_spec)
        end

        {:ok, Map.delete(args, :__help__)}

      {:error, reason} ->
        {:error, %ChzEx.Error{type: :invalid_value, message: reason}}
    end
  end

  defp apply_method(target, method, 1, config, _args) do
    {:ok, apply(target, method, [config])}
  end

  defp apply_method(target, method, 2, config, args) do
    {:ok, apply(target, method, [config, args])}
  end

  defp apply_method(_target, _method, _arity, _config, _args) do
    {:error, %ChzEx.Error{type: :invalid_value, message: "Method arity must be 1 or 2"}}
  end

  defp build_method_config(target, args, transform, method_str) do
    bp = Blueprint.new(target)
    bp = if is_function(transform, 3), do: transform.(bp, target, method_str), else: bp

    bp
    |> Blueprint.apply(args)
    |> Blueprint.make()
  end

  defp split_method_args(args, nil), do: {:ok, {args, []}}

  defp split_method_args(args, {_name, _doc, spec}) do
    spec_map =
      spec
      |> Enum.into(%{}, fn {name, type} -> {to_string(name), type} end)

    {method_args, config_args} = Map.split(args, Map.keys(spec_map))

    with {:ok, method_kw} <- cast_method_args(method_args, spec_map) do
      {:ok, {config_args, method_kw}}
    end
  end

  defp cast_method_args(args, spec_map) do
    spec_map
    |> Enum.reduce_while({:ok, []}, fn {name, type}, {:ok, acc} ->
      case cast_method_arg(args, name, type) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> finalize_method_args()
  end

  defp cast_method_arg(args, name, type) do
    case Map.fetch(args, name) do
      {:ok, %ChzEx.Blueprint.Castable{value: value}} ->
        case ChzEx.Cast.try_cast(value, type) do
          {:ok, casted} -> {:ok, {String.to_atom(name), casted}}
          {:error, reason} -> {:error, %ChzEx.Error{type: :cast_error, message: reason}}
        end

      {:ok, _} ->
        {:error, %ChzEx.Error{type: :invalid_value, message: "Invalid value for #{name}"}}

      :error ->
        {:error, %ChzEx.Error{type: :missing_required, path: name}}
    end
  end

  defp finalize_method_args({:ok, kw}), do: {:ok, Enum.reverse(kw)}
  defp finalize_method_args({:error, _} = err), do: err

  defp resolve_method(target, method_str) do
    target.__info__(:functions)
    |> Enum.find(fn {name, arity} ->
      Atom.to_string(name) == method_str and arity in [1, 2]
    end)
    |> case do
      nil -> :error
      {name, arity} -> {:ok, {name, arity}}
    end
  end

  defp method_spec(target, method, method_str) do
    if function_exported?(target, :__chz_commands__, 0) do
      target.__chz_commands__()
      |> Enum.find(fn {name, _doc, _spec} ->
        name == method or to_string(name) == method_str
      end)
    else
      nil
    end
  end

  defp methods_help(target, warning) do
    header = "Entry point: methods of #{inspect(target)}"

    entries =
      if function_exported?(target, :__chz_commands__, 0) do
        target.__chz_commands__()
        |> Enum.map(fn {name, doc, _spec} -> "  #{name}  #{doc}" end)
      else
        target.__info__(:functions)
        |> Enum.filter(fn {name, arity} -> arity in [1, 2] and not hidden_method?(name) end)
        |> Enum.map(fn {name, arity} -> "  #{name}/#{arity}" end)
      end

    warning_text =
      if warning do
        "WARNING: #{warning}\n\n"
      else
        ""
      end

    warning_text <> header <> "\n\nAvailable methods:\n" <> Enum.join(entries, "\n") <> "\n"
  end

  defp method_help(target, method, {_name, _doc, spec}) do
    args =
      Enum.map_join(spec, "\n", fn {name, type} ->
        "  #{name}  #{ChzEx.Type.type_repr(type)}"
      end)

    "Method: #{method}\n\nArguments:\n" <>
      args <> "\n\n" <> (Blueprint.new(target) |> Blueprint.get_help())
  end

  defp method_help(target, _method, nil) do
    Blueprint.new(target) |> Blueprint.get_help()
  end

  defp dispatch_help(targets, warning) do
    entries =
      targets
      |> Enum.map(fn {name, _target} -> "  #{to_string(name)}" end)
      |> Enum.sort()

    warning_text =
      if warning do
        "WARNING: #{warning}\n\n"
      else
        ""
      end

    warning_text <> "Available commands:\n" <> Enum.join(entries, "\n") <> "\n"
  end

  defp fetch_target(targets, command) do
    case Map.fetch(targets, command) do
      {:ok, target} ->
        {:ok, target}

      :error ->
        targets
        |> Enum.find(fn {name, _} ->
          is_atom(name) and Atom.to_string(name) == command
        end)
        |> case do
          nil -> :error
          {_name, target} -> {:ok, target}
        end
    end
  end

  defp hidden_method?(name), do: String.starts_with?(Atom.to_string(name), "_")

  @doc """
  Check if a value is a ChzEx struct.
  """
  defdelegate chz?(value), to: ChzEx.Schema

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
    if chz?(struct) do
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
