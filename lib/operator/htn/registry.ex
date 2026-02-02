defmodule Operator.HTN.Registry do
  @moduledoc """
  Discovers and aggregates all HTN modules so planners can look up goals/tasks.

  The registry uses `persistent_term` for fast read access, making lookups
  essentially free after initial registration.

  ## Registration

  Modules using `Operator.HTN.DSL` are automatically registered after compilation
  via `@after_compile`. You can also manually register modules:

      Operator.HTN.Registry.register(MyHTNModule)

  ## Lookup

      # Get all registered goals/tasks
      registry = Registry.all()

      # Get specific items
      goal = Registry.get_goal(:acquire_data)
      task = Registry.get_task(:move_to)
      primitive = Registry.get_primitive(:attack)

  """

  alias Operator.HTN.{Axiom, Task}

  @registry_key {__MODULE__, :registry}
  @modules_key {__MODULE__, :modules}

  @type registry :: %{goals: map(), tasks: map(), primitives: map(), axioms: map()}

  @doc """
  Returns the merged registry containing all goals, tasks, and primitives.
  """
  @spec all() :: registry()
  def all do
    :persistent_term.get(@registry_key, empty_registry())
  end

  @doc """
  Registers an HTN module and refreshes the merged registry.

  The module must export `__htn__/0` which returns the module's goals,
  tasks, and primitives.
  """
  @spec register(module()) :: :ok
  def register(module) when is_atom(module) do
    if function_exported?(module, :__htn__, 0) do
      modules =
        @modules_key
        |> :persistent_term.get(MapSet.new())
        |> MapSet.put(module)

      :persistent_term.put(@modules_key, modules)
      refresh(modules)
    else
      :ok
    end
  end

  @doc """
  Forces a refresh of the registry, optionally with an explicit module set.
  """
  @spec refresh(Enum.t()) :: :ok
  def refresh(modules \\ modules()) do
    data =
      modules
      |> Enum.map(&module_registry/1)
      |> merge()

    :persistent_term.put(@registry_key, data)
    :ok
  end

  @doc """
  Resets the registry (useful for tests).
  """
  @spec reset() :: :ok
  def reset do
    :persistent_term.put(@modules_key, MapSet.new())
    :persistent_term.put(@registry_key, empty_registry())
    :ok
  end

  @doc """
  Returns the currently registered modules.
  """
  @spec modules() :: [module()]
  def modules do
    @modules_key
    |> :persistent_term.get(MapSet.new())
    |> MapSet.to_list()
  end

  @doc """
  Get a goal by name.
  """
  @spec get_goal(atom(), registry()) :: map() | nil
  def get_goal(name, registry \\ all()) do
    Map.get(registry.goals, name)
  end

  @doc """
  Get a task by name.
  """
  @spec get_task(atom(), registry()) :: Task.t() | nil
  def get_task(name, registry \\ all()) do
    Map.get(registry.tasks, name)
  end

  @doc """
  Get a primitive by name.
  """
  @spec get_primitive(atom(), registry()) :: Task.t() | nil
  def get_primitive(name, registry \\ all()) do
    Map.get(registry.primitives, name)
  end

  @doc """
  Get an axiom by name.
  """
  @spec get_axiom(atom(), registry()) :: Axiom.t() | nil
  def get_axiom(name, registry \\ all()) do
    Map.get(registry.axioms, name)
  end

  @doc """
  Merge multiple registry fragments.
  """
  @spec merge([map()]) :: registry()
  def merge(registries) do
    Enum.reduce(registries, empty_registry(), fn registry, acc ->
      %{
        goals: Map.merge(acc.goals, registry[:goals] || %{}),
        tasks: Map.merge(acc.tasks, registry[:tasks] || %{}),
        primitives: Map.merge(acc.primitives, registry[:primitives] || %{}),
        axioms: Map.merge(acc.axioms, registry[:axioms] || %{})
      }
    end)
  end

  @doc """
  List all registered goal names.
  """
  @spec list_goal_names() :: [atom()]
  def list_goal_names, do: Map.keys(all().goals)

  @doc """
  List all registered task names.
  """
  @spec list_task_names() :: [atom()]
  def list_task_names, do: Map.keys(all().tasks)

  @doc """
  List all registered primitive names.
  """
  @spec list_primitive_names() :: [atom()]
  def list_primitive_names, do: Map.keys(all().primitives)

  @doc """
  List all registered axiom names.
  """
  @spec list_axiom_names() :: [atom()]
  def list_axiom_names, do: Map.keys(all().axioms)

  @doc """
  Return counts for each category.
  """
  @spec stats() :: %{
          goals: non_neg_integer(),
          tasks: non_neg_integer(),
          primitives: non_neg_integer(),
          axioms: non_neg_integer()
        }
  def stats do
    registry = all()

    %{
      goals: map_size(registry.goals),
      tasks: map_size(registry.tasks),
      primitives: map_size(registry.primitives),
      axioms: map_size(registry.axioms)
    }
  end

  # Private helpers

  defp empty_registry do
    %{goals: %{}, tasks: %{}, primitives: %{}, axioms: %{}}
  end

  defp module_registry(module) do
    case safe_htn(module) do
      {:ok, data} -> normalize_registry(data)
      :error -> empty_registry()
    end
  end

  defp safe_htn(module) do
    case safe_apply(module, :__htn__, []) do
      {:ok, data} -> {:ok, data}
      _ -> :error
    end
  end

  defp safe_apply(module, fun, args) do
    try do
      {:ok, apply(module, fun, args)}
    rescue
      _ -> {:error, :rescue}
    catch
      _, _ -> {:error, :catch}
    end
  end

  defp normalize_registry(%{goals: goals, tasks: tasks, primitives: primitives} = data) do
    %{
      goals: map_by_name(goals),
      tasks: map_by_name(tasks),
      primitives: map_by_name(primitives),
      axioms: map_by_name(Map.get(data, :axioms, []))
    }
  end

  defp normalize_registry(_), do: empty_registry()

  defp map_by_name(list) when is_list(list) do
    Enum.into(list, %{}, fn item ->
      name = name_from_item(item)
      data = normalize_runtime_item(item)
      {name, data}
    end)
  end

  defp map_by_name(_), do: %{}

  defp name_from_item(%{name: name}), do: name
  defp name_from_item({name, _}) when is_atom(name), do: name
  defp name_from_item(item), do: item

  defp normalize_runtime_item(%{precond: precond, decompose: decompose} = item) do
    %{
      item
      | precond: maybe_eval_function(precond),
        decompose: normalize_decompose(decompose)
    }
  end

  defp normalize_runtime_item(%{precond: precond} = item) do
    %{item | precond: maybe_eval_function(precond)}
  end

  # Axiom normalization - convert AST to runtime Axiom struct
  defp normalize_runtime_item(%{name: name, query_fn: query_fn_ast} = item)
       when is_tuple(query_fn_ast) do
    query_fn = safe_eval_function(query_fn_ast)
    Axiom.new(name, query_fn, metadata: Map.get(item, :metadata, %{}))
  end

  defp normalize_runtime_item(item) when is_map(item), do: item
  defp normalize_runtime_item(item), do: item

  defp normalize_decompose({:static_tasks, tasks}) do
    # Convert static task list to a function
    fn _facts -> tasks end
  end

  defp normalize_decompose({:fn, _, _} = quoted) do
    # Evaluate quoted function AST
    safe_eval_function(quoted)
  end

  defp normalize_decompose(value), do: value

  defp maybe_eval_function({:fn, _, _} = quoted), do: safe_eval_function(quoted)

  defp maybe_eval_function(funs) when is_list(funs) do
    # List of preconditions - evaluate each and combine into single function
    evaluated = Enum.map(funs, &maybe_eval_function/1)

    fn facts ->
      Enum.all?(evaluated, fn
        fun when is_function(fun, 1) -> fun.(facts)
        _ -> true
      end)
    end
  end

  defp maybe_eval_function(value), do: value

  defp safe_eval_function(quoted) do
    try do
      {result, _bindings} = Code.eval_quoted(quoted)
      result
    rescue
      _ -> quoted
    catch
      _, _ -> quoted
    end
  end
end
