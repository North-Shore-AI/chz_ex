defmodule ChzEx.Registry do
  @moduledoc """
  Registry for polymorphic type resolution.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Register a module under a namespace with a short name.
  """
  def register(namespace, short_name, module)
      when is_atom(namespace) and is_binary(short_name) and is_atom(module) do
    GenServer.call(__MODULE__, {:register, namespace, short_name, module})
  end

  @doc """
  Look up a module by namespace and short name.
  """
  def lookup(namespace, short_name) do
    GenServer.call(__MODULE__, {:lookup, namespace, short_name})
  end

  @doc """
  Find a module by its short name within a base type's namespace.
  """
  def find_by_name(_base_type, name) do
    GenServer.call(__MODULE__, {:find_by_name, name})
  end

  @doc """
  Register a module as allowed for polymorphic construction.
  """
  def register_module(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:register_module, module})
  end

  @doc """
  Look up a module by its string name.
  """
  def lookup_module(module_str) when is_binary(module_str) do
    GenServer.call(__MODULE__, {:lookup_module, module_str})
  end

  @impl true
  def init(_) do
    {:ok, %{namespaces: %{}, modules: MapSet.new()}}
  end

  @impl true
  def handle_call({:register, namespace, short_name, module}, _from, state) do
    namespaces =
      state.namespaces
      |> Map.update(namespace, %{short_name => module}, &Map.put(&1, short_name, module))

    modules = MapSet.put(state.modules, module)

    {:reply, :ok, %{state | namespaces: namespaces, modules: modules}}
  end

  @impl true
  def handle_call({:lookup, namespace, short_name}, _from, state) do
    result =
      case get_in(state.namespaces, [namespace, short_name]) do
        nil -> :error
        module -> {:ok, module}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:find_by_name, name}, _from, state) do
    result =
      state.namespaces
      |> Enum.find_value(fn {_ns, modules} ->
        case Map.get(modules, name) do
          nil -> nil
          module -> {:ok, module}
        end
      end)
      |> case do
        nil -> :error
        value -> value
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:register_module, module}, _from, state) do
    {:reply, :ok, %{state | modules: MapSet.put(state.modules, module)}}
  end

  @impl true
  def handle_call({:lookup_module, module_str}, _from, state) do
    module =
      try do
        String.to_existing_atom("Elixir." <> module_str)
      rescue
        ArgumentError -> nil
      end

    if module && MapSet.member?(state.modules, module) do
      {:reply, {:ok, module}, state}
    else
      {:reply, :error, state}
    end
  end
end
