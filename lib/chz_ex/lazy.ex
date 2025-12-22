defmodule ChzEx.Lazy do
  @moduledoc """
  Lazy evaluation types for blueprint construction.
  """

  defmodule Value do
    @moduledoc "A concrete value."
    defstruct [:value]

    @type t :: %__MODULE__{value: any()}
  end

  defmodule ParamRef do
    @moduledoc "A reference to another parameter."
    defstruct [:ref]

    @type t :: %__MODULE__{ref: String.t()}
  end

  defmodule Thunk do
    @moduledoc "A deferred function call."
    defstruct [:fn, :kwargs]

    @type t :: %__MODULE__{
            fn: (map() -> any()),
            kwargs: %{atom() => ParamRef.t()}
          }
  end

  @type ref_path :: String.t()
  @type value_mapping :: %{ref_path() => evaluatable()}
  @type cache :: %{ref_path() => any()}
  @type in_progress :: %{ref_path() => true}

  @type evaluatable :: Value.t() | ParamRef.t() | Thunk.t()

  @doc """
  Evaluate a value mapping, resolving all references and thunks.
  """
  @spec evaluate(value_mapping()) :: any()
  def evaluate(value_mapping) when is_map(value_mapping) do
    unless Map.has_key?(value_mapping, "") do
      raise ArgumentError, "value_mapping must contain root entry ''"
    end

    {value, _cache} = do_evaluate("", value_mapping, %{}, %{}, [])
    value
  end

  @spec do_evaluate(ref_path(), value_mapping(), cache(), in_progress(), [ref_path()]) ::
          {any(), cache()}
  defp do_evaluate(ref, value_mapping, cache, in_progress, stack) do
    case Map.fetch(cache, ref) do
      {:ok, value} ->
        {value, cache}

      :error ->
        evaluate_uncached(ref, value_mapping, cache, in_progress, stack)
    end
  end

  defp evaluate_uncached(ref, value_mapping, cache, in_progress, stack) do
    if Map.has_key?(in_progress, ref) do
      cycle = Enum.reverse([ref | stack]) |> Enum.join(" -> ")
      raise RuntimeError, "Detected cyclic reference: #{cycle}"
    end

    in_progress = Map.put(in_progress, ref, true)
    stack = [ref | stack]
    evaluate_ref(ref, value_mapping, cache, in_progress, stack)
  end

  defp evaluate_ref(ref, value_mapping, cache, in_progress, stack) do
    case Map.get(value_mapping, ref) do
      %Value{value: value} ->
        {value, Map.put(cache, ref, value)}

      %ParamRef{ref: target} ->
        with_context("when dereferencing #{inspect(target)}", fn ->
          {value, cache} = do_evaluate(target, value_mapping, cache, in_progress, stack)
          {value, Map.put(cache, ref, value)}
        end)

      %Thunk{fn: func, kwargs: kwargs} ->
        with_context("when evaluating #{inspect(ref)}", fn ->
          evaluate_thunk(ref, func, kwargs, value_mapping, cache, in_progress, stack)
        end)

      nil ->
        raise RuntimeError, "Reference #{inspect(ref)} not found in value_mapping"
    end
  end

  defp evaluate_thunk(ref, func, kwargs, value_mapping, cache, in_progress, stack) do
    {resolved_kwargs, cache} =
      Enum.reduce(kwargs, {%{}, cache}, fn {key, %ParamRef{ref: target}}, {acc, c} ->
        {value, c} = do_evaluate(target, value_mapping, c, in_progress, stack)
        {Map.put(acc, key, value), c}
      end)

    result = func.(resolved_kwargs)
    {result, Map.put(cache, ref, result)}
  end

  defp with_context(context, fun) do
    fun.()
  rescue
    err in [ChzEx.Error] ->
      reraise err, __STACKTRACE__

    err in [RuntimeError] ->
      message = Exception.message(err)

      if String.starts_with?(message, "Detected cyclic reference: ") do
        reraise err, __STACKTRACE__
      else
        reraise ChzEx.Error.wrap(err, context), __STACKTRACE__
      end

    err ->
      reraise ChzEx.Error.wrap(err, context), __STACKTRACE__
  end

  @doc """
  Check that all reference targets exist.
  """
  @spec check_reference_targets(value_mapping(), [ref_path()]) :: :ok | {:error, term()}
  def check_reference_targets(value_mapping, param_paths) do
    paths = MapSet.new(param_paths)

    invalid =
      value_mapping
      |> Enum.flat_map(fn {param_path, evaluatable} ->
        collect_refs(evaluatable)
        |> Enum.filter(fn ref -> not MapSet.member?(paths, ref) end)
        |> Enum.map(fn ref -> {ref, param_path} end)
      end)
      |> Enum.group_by(fn {ref, _} -> ref end, fn {_, path} -> path end)

    if map_size(invalid) > 0 do
      errors =
        Enum.map(invalid, fn {ref, referrers} ->
          suggestions = suggest_similar(ref, param_paths)
          "Invalid reference target #{inspect(ref)} from #{inspect(referrers)}#{suggestions}"
        end)

      {:error, %ChzEx.Error{type: :invalid_reference, message: Enum.join(errors, "\n\n")}}
    else
      :ok
    end
  end

  defp collect_refs(%ParamRef{ref: ref}), do: [ref]

  defp collect_refs(%Thunk{kwargs: kwargs}) do
    Enum.flat_map(kwargs, fn {_, param_ref} -> collect_refs(param_ref) end)
  end

  defp collect_refs(_), do: []

  defp suggest_similar(ref, param_paths) do
    matches =
      param_paths
      |> Enum.map(fn path -> {path, ChzEx.Wildcard.approximate(ref, path)} end)
      |> Enum.sort_by(fn {_path, {score, _}} -> -score end)

    case matches do
      [] -> ""
      [{_path, {_score, suggestion}} | _] -> "\nDid you mean #{inspect(suggestion)}?"
    end
  end
end
