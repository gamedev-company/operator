defmodule Operator.HTN.Engine do
  @moduledoc """
  HTN engine for goal expansion, precondition evaluation, and plan generation.

  The engine implements **total-order forward decomposition**, the HTN planning
  approach described in GameAIPro. This means:

  1. Tasks are expanded in order (total-order)
  2. Planning proceeds forward from the current state
  3. Effects are applied during planning to simulate future states

  ## Planning Algorithm

  1. Look up the goal in the registry
  2. Check goal preconditions against current facts
  3. Decompose goal into tasks via its decompose function
  4. For each task:
     - If abstract: check preconditions, decompose recursively
     - If primitive: check preconditions, collect into plan, apply effects
  5. Return the plan (list of primitive tasks)

  ## Effects During Planning

  A key feature of HTN planning is that effects are applied to a working copy
  of world state during planning. This allows downstream tasks to have their
  preconditions validated against the expected future state.

  For example, if task A has effect "has_key=true" and task B has precondition
  "has_key", then B's precondition will be satisfied when planning A before B.

  ## Usage

      facts = Operator.HTN.Facts.from_perception(%{
        self: %{location: :lobby},
        world: %{target: :server_room}
      })

      case Engine.expand(:infiltrate, facts, %{}) do
        {:ok, plan} ->
          # plan.tasks contains the sequence of primitives
          IO.inspect(plan.tasks)

        {:error, :preconditions_not_met} ->
          # Goal preconditions failed
          :retry_later

        {:error, :goal_not_found} ->
          # Goal not registered
          :unknown_goal
      end

  """

  alias Operator.HTN.{Effect, Facts, Plan, Registry, Task, Trace}

  @doc """
  Expand a goal into a plan.

  ## Arguments

  - `goal_name` - The goal atom to expand
  - `facts` - Current world state
  - `traits` - Agent traits/genome for cost calculations
  - `htn_registry` - Optional registry (defaults to `Registry.all()`)
  - `opts` - Options:
    - `:budget` - Budget limits (e.g., `[max_tasks: 100, max_expansions: 200, max_depth: 20, timeout_ms: 5]`)

  ## Returns

  - `{:ok, plan}` - Successfully expanded plan
  - `{:error, :goal_not_found}` - Goal not in registry
  - `{:error, :preconditions_not_met}` - Goal preconditions failed

  """
  @spec expand(atom(), Facts.t(), map(), map(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def expand(goal_name, facts, traits, htn_registry \\ Registry.all(), opts \\ []) do
    goal = Registry.get_goal(goal_name, htn_registry)
    budget = init_budget(opts)

    if goal do
      Trace.goal_start(goal_name, facts)

      precond_met = goal_preconditions_met?(goal, facts)
      Trace.precondition_eval(%{goal: goal_name}, precond_met)

      if precond_met do
        # Pass facts through decomposition, collecting effects
        case decompose_goal(goal, facts, traits, htn_registry, budget, 0) do
          {:ok, tasks, _final_facts, _budget} ->
            plan = Plan.new(goal_name, tasks)
            Trace.goal_end(goal_name, :success)
            {:ok, plan}

          {:error, reason} ->
            Trace.goal_end(goal_name, :failure)
            {:error, reason}
        end
      else
        Trace.goal_end(goal_name, :failure)
        {:error, :preconditions_not_met}
      end
    else
      {:error, :goal_not_found}
    end
  end

  @doc """
  Check if a goal's preconditions are met.
  """
  @spec goal_preconditions_met?(map(), Facts.t()) :: boolean()
  def goal_preconditions_met?(goal, facts) do
    case goal do
      %{precond: nil} -> true
      %{precond: precond} when is_function(precond, 1) -> precond.(facts)
      _ -> true
    end
  end

  # Private helpers

  defp decompose_goal(goal, facts, traits, htn_registry, budget, depth) do
    case goal.decompose do
      nil ->
        {:ok, [], facts, budget}

      decompose_fun when is_function(decompose_fun) ->
        task_specs = decompose_fun.(facts)

        # Expand each task in sequence, threading facts through
        # so effects from earlier tasks affect later preconditions
        Enum.reduce_while(task_specs, {:ok, [], facts, budget}, fn task_spec,
                                                                  {:ok, acc_tasks, acc_facts,
                                                                   acc_budget} ->
          case expand_task(task_spec, acc_facts, traits, htn_registry, acc_budget, depth + 1) do
            {:ok, new_tasks, new_facts, new_budget} ->
              {:cont, {:ok, acc_tasks ++ new_tasks, new_facts, new_budget}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      _ ->
        {:ok, [], facts, budget}
    end
  end

  defp expand_task({task_name, args}, facts, traits, htn_registry, budget, depth) do
    with {:ok, budget} <- budget_check(budget, depth),
         {:ok, budget} <- budget_bump_expansions(budget) do
      expand_task_after_budget({task_name, args}, facts, traits, htn_registry, budget, depth)
    end
  end

  defp expand_task(task_name, facts, traits, htn_registry, budget, depth)
       when is_atom(task_name) do
    expand_task({task_name, []}, facts, traits, htn_registry, budget, depth)
  end

  defp expand_task_after_budget({task_name, args}, facts, traits, htn_registry, budget, depth) do
    task = Registry.get_task(task_name, htn_registry)

    cond do
      task != nil ->
        expand_abstract_task(task, task_name, args, facts, traits, htn_registry, budget, depth)

      primitive = Registry.get_primitive(task_name, htn_registry) ->
        expand_primitive_task(primitive, task_name, args, facts, budget)

      true ->
        {:ok, [], facts, budget}
    end
  end

  defp expand_abstract_task(task, task_name, args, facts, traits, htn_registry, budget, depth) do
    Trace.task_expand(task_name, args, facts)

    precond_met = Task.preconditions_satisfied?(task, facts, traits)
    Trace.precondition_eval(%{task: task_name}, precond_met)

    if precond_met do
      expand_task_decompose(task, task_name, args, facts, traits, htn_registry, budget, depth)
    else
      Trace.task_complete(task_name, [], :failure)
      {:ok, [], facts, budget}
    end
  end

  defp expand_task_decompose(task, task_name, args, facts, traits, htn_registry, budget, depth) do
    case task.decompose do
      nil ->
        new_facts = apply_task_effects(task, facts, task_name)
        Trace.task_complete(task_name, [{task_name, args}], :success)
        with {:ok, budget} <- budget_bump_tasks(budget) do
          {:ok, [{task_name, args}], new_facts, budget}
        end

      decompose_fun when is_function(decompose_fun) ->
        subtasks = decompose_fun.(facts)
        case expand_subtasks(subtasks, facts, traits, htn_registry, budget, depth + 1) do
          {:ok, result_tasks, final_facts, new_budget} ->
            Trace.task_complete(task_name, result_tasks, :success)
            {:ok, result_tasks, final_facts, new_budget}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp expand_primitive_task(primitive, task_name, args, facts, budget) do
    Trace.task_expand(task_name, args, facts)
    new_facts = apply_task_effects(primitive, facts, task_name)
    Trace.task_complete(task_name, [{task_name, args}], :success)
    with {:ok, budget} <- budget_bump_tasks(budget) do
      {:ok, [{task_name, args}], new_facts, budget}
    end
  end

  defp expand_subtasks(subtasks, facts, traits, htn_registry, budget, depth) do
    Enum.reduce_while(subtasks, {:ok, [], facts, budget}, fn subtask,
                                                            {:ok, acc_tasks, acc_facts,
                                                             acc_budget} ->
      case expand_task(subtask, acc_facts, traits, htn_registry, acc_budget, depth + 1) do
        {:ok, new_tasks, new_facts, new_budget} ->
          {:cont, {:ok, acc_tasks ++ new_tasks, new_facts, new_budget}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Apply task effects to facts during planning
  defp apply_task_effects(%Task{effects: nil}, facts, _task_name), do: facts
  defp apply_task_effects(%Task{effects: []}, facts, _task_name), do: facts

  defp apply_task_effects(%Task{effects: effects}, facts, _task_name) do
    # During planning, apply all effects (including plan_only)
    planning_effects = Effect.planning_effects(effects)

    # Trace each effect application
    Enum.each(planning_effects, fn effect ->
      Trace.effect_apply(effect, facts)
    end)

    Effect.apply_all(planning_effects, facts)
  end

  # Handle tasks without effects field (e.g., from DSL)
  defp apply_task_effects(_task, facts, _task_name), do: facts

  defp init_budget(opts) do
    budget_opts = Keyword.get(opts, :budget, [])
    budget =
      case budget_opts do
        %{} -> Map.to_list(budget_opts)
        _ -> budget_opts
      end

    %{
      max_tasks: Keyword.get(budget, :max_tasks),
      max_expansions: Keyword.get(budget, :max_expansions),
      max_depth: Keyword.get(budget, :max_depth),
      timeout_ms: Keyword.get(budget, :timeout_ms),
      tasks: 0,
      expansions: 0,
      started_at: System.monotonic_time(:millisecond),
      enabled:
        Keyword.has_key?(budget, :max_tasks) or Keyword.has_key?(budget, :max_expansions) or
          Keyword.has_key?(budget, :max_depth) or Keyword.has_key?(budget, :timeout_ms)
    }
  end

  defp budget_check(%{enabled: false} = budget, _depth), do: {:ok, budget}

  defp budget_check(budget, depth) do
    cond do
      budget.max_depth && depth > budget.max_depth ->
        {:error, {:budget_exceeded, :max_depth}}

      budget.timeout_ms &&
          System.monotonic_time(:millisecond) - budget.started_at > budget.timeout_ms ->
        {:error, {:budget_exceeded, :timeout_ms}}

      budget.max_expansions && budget.expansions >= budget.max_expansions ->
        {:error, {:budget_exceeded, :max_expansions}}

      budget.max_tasks && budget.tasks >= budget.max_tasks ->
        {:error, {:budget_exceeded, :max_tasks}}

      true ->
        {:ok, budget}
    end
  end

  defp budget_bump_expansions(%{enabled: false} = budget), do: {:ok, budget}

  defp budget_bump_expansions(budget) do
    budget
    |> Map.update!(:expansions, &(&1 + 1))
    |> then(&budget_check(&1, 0))
  end

  defp budget_bump_tasks(%{enabled: false} = budget), do: {:ok, budget}

  defp budget_bump_tasks(budget) do
    budget
    |> Map.update!(:tasks, &(&1 + 1))
    |> then(&budget_check(&1, 0))
  end
end
