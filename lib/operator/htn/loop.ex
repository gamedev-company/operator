defmodule Operator.HTN.Loop do
  @moduledoc """
  Convenience helpers for integrating HTN planning into tick-based loops.

  The goal is to reduce boilerplate: plan if needed, execute one step, and
  return a structured result.

  ## Example

      alias Operator.HTN.{Facts, Loop}

      facts = Facts.from_perception(%{self: %{energy: 50}})
      traits = %{archetype: :guard}

      result = Loop.tick(nil, actor, facts, traits,
        goal: :patrol
      )

      case result.status do
        :idle -> :no_plan
        :continue -> result.plan
        :completed -> :done
        :failed -> result.reason
      end

  """

  alias Operator.HTN.{Executor, Facts, GoalSelector, Plan, Planner}

  @type status :: :idle | :continue | :completed | :failed

  @type result :: %{
          status: status(),
          actor: term(),
          facts: Facts.t(),
          plan: Plan.t() | nil,
          goal: atom() | nil,
          reason: term() | nil
        }

  @doc """
  Tick the AI loop once.

  - If there is no plan (or it needs replan), a new plan is created.
  - If no goal is available, returns `:idle`.
  - Otherwise, executes one step of the plan.

  ## Options

  - `:goal` - specific goal atom to plan for (skips goal selection)
  - `:select_goal` - custom goal selector (default: `GoalSelector.pick_goal/2`)
  - `:planner_opts` - options passed to `Planner.run/4` (budgets, etc.)

  """
  @spec tick(Plan.t() | nil, term(), Facts.t(), map(), keyword()) :: result()
  def tick(plan, actor, facts, traits, opts \\ []) do
    planner_opts = Keyword.get(opts, :planner_opts, [])
    select_goal = Keyword.get(opts, :select_goal, &GoalSelector.pick_goal/2)
    goal_opt = Keyword.get(opts, :goal)

    plan = ensure_plan(plan, facts, traits, goal_opt, select_goal, planner_opts)
    execute_plan(plan, actor, facts)
  end

  defp ensure_plan(plan, facts, traits, goal_opt, select_goal, planner_opts) do
    if plan == nil or Planner.needs_replan?(plan, facts) do
      case resolve_goal(goal_opt, select_goal, facts, traits) do
        {:ok, goal_name} ->
          case Planner.run(goal_name, facts, traits, planner_opts) do
            {:ok, new_plan} -> new_plan
            {:error, _} -> nil
          end

        _ ->
          nil
      end
    else
      plan
    end
  end

  defp execute_plan(nil, actor, facts) do
    %{status: :idle, actor: actor, facts: facts, plan: nil, goal: nil, reason: nil}
  end

  defp execute_plan(%Plan{} = plan, actor, facts) do
    case Executor.step(plan, actor, facts) do
      {:ok, :continue, actor, facts, remaining} ->
        %{status: :continue, actor: actor, facts: facts, plan: remaining, goal: plan.goal, reason: nil}

      {:ok, :completed, actor, facts, _plan} ->
        %{status: :completed, actor: actor, facts: facts, plan: nil, goal: plan.goal, reason: nil}

      {:error, reason, actor, facts, _plan} ->
        %{status: :failed, actor: actor, facts: facts, plan: nil, goal: plan.goal, reason: reason}
    end
  end

  defp resolve_goal(nil, select_goal, facts, traits), do: select_goal.(facts, traits)
  defp resolve_goal(goal, _select_goal, _facts, _traits), do: {:ok, goal}
end
