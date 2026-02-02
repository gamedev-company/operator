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

  alias Operator.HTN.{Effect, Facts, Plan, Task, Registry, Trace}

  @doc """
  Expand a goal into a plan.

  ## Arguments

  - `goal_name` - The goal atom to expand
  - `facts` - Current world state
  - `traits` - Agent traits/genome for cost calculations
  - `htn_registry` - Optional registry (defaults to `Registry.all()`)

  ## Returns

  - `{:ok, plan}` - Successfully expanded plan
  - `{:error, :goal_not_found}` - Goal not in registry
  - `{:error, :preconditions_not_met}` - Goal preconditions failed

  """
  @spec expand(atom(), Facts.t(), map(), map()) :: {:ok, Plan.t()} | {:error, term()}
  def expand(goal_name, facts, traits, htn_registry \\ Registry.all()) do
    goal = Registry.get_goal(goal_name, htn_registry)

    if goal do
      Trace.goal_start(goal_name, facts)

      precond_met = goal_preconditions_met?(goal, facts)
      Trace.precondition_eval(%{goal: goal_name}, precond_met)

      if precond_met do
        # Pass facts through decomposition, collecting effects
        {tasks, _final_facts} = decompose_goal(goal, facts, traits, htn_registry)
        plan = Plan.new(goal_name, tasks)
        Trace.goal_end(goal_name, :success)
        {:ok, plan}
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

  defp decompose_goal(goal, facts, traits, htn_registry) do
    case goal.decompose do
      nil ->
        {[], facts}

      decompose_fun when is_function(decompose_fun) ->
        task_specs = decompose_fun.(facts)

        # Expand each task in sequence, threading facts through
        # so effects from earlier tasks affect later preconditions
        Enum.reduce(task_specs, {[], facts}, fn task_spec, {acc_tasks, acc_facts} ->
          {new_tasks, new_facts} = expand_task(task_spec, acc_facts, traits, htn_registry)
          {acc_tasks ++ new_tasks, new_facts}
        end)

      _ ->
        {[], facts}
    end
  end

  defp expand_task({task_name, args}, facts, traits, htn_registry) do
    task = Registry.get_task(task_name, htn_registry)

    if task do
      Trace.task_expand(task_name, args, facts)

      precond_met = Task.preconditions_satisfied?(task, facts, traits)
      Trace.precondition_eval(%{task: task_name}, precond_met)

      if precond_met do
        case task.decompose do
          nil ->
            # Leaf task - apply effects and return
            new_facts = apply_task_effects(task, facts, task_name)
            Trace.task_complete(task_name, [{task_name, args}], :success)
            {[{task_name, args}], new_facts}

          decompose_fun when is_function(decompose_fun) ->
            subtasks = decompose_fun.(facts)

            # Expand subtasks in sequence
            {result_tasks, final_facts} =
              Enum.reduce(subtasks, {[], facts}, fn subtask, {acc_tasks, acc_facts} ->
                {new_tasks, new_facts} = expand_task(subtask, acc_facts, traits, htn_registry)
                {acc_tasks ++ new_tasks, new_facts}
              end)

            Trace.task_complete(task_name, result_tasks, :success)
            {result_tasks, final_facts}
        end
      else
        Trace.task_complete(task_name, [], :failure)
        {[], facts}
      end
    else
      # Check if it's a primitive
      primitive = Registry.get_primitive(task_name, htn_registry)

      if primitive do
        Trace.task_expand(task_name, args, facts)
        # Apply primitive's effects to planning state
        new_facts = apply_task_effects(primitive, facts, task_name)
        Trace.task_complete(task_name, [{task_name, args}], :success)
        {[{task_name, args}], new_facts}
      else
        {[], facts}
      end
    end
  end

  defp expand_task(task_name, facts, traits, htn_registry)
       when is_atom(task_name) do
    expand_task({task_name, []}, facts, traits, htn_registry)
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
end
