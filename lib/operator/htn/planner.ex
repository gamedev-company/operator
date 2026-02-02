defmodule Operator.HTN.Planner do
  @moduledoc """
  HTN planner that orchestrates goal expansion and plan generation.

  The Planner integrates the HTN Engine with optional telemetry and
  rationalization callbacks.

  ## Usage

      facts = Operator.HTN.Facts.from_perception(%{
        self: %{location: :lobby, has_keycard: true},
        world: %{target: :server_room, threat_level: :low}
      })

      traits = %{archetype: :infiltrator, traits: [:stealthy, :tech_savvy]}

      case Planner.run(:infiltrate_building, facts, traits) do
        {:ok, plan} ->
          # Execute plan tasks
          execute_plan(plan)

        {:error, :preconditions_not_met} ->
          # Wait for conditions to change
          :retry_later

        {:error, :goal_not_found} ->
          # Unknown goal
          :unknown_goal
      end

  ## Tick-Based Planning

  For continuous simulations, use `tick/4` to update plans:

      # On each planning tick
      new_plan = Planner.tick(current_plan, facts, traits, :default_goal)

  """

  alias Operator.HTN.{Engine, Facts, Plan, Registry}
  alias Operator.{Rationalization, Telemetry}

  @doc """
  Run the planner for a goal.

  Generates a plan by expanding the goal, optionally annotating it
  with rationalization metadata and emitting telemetry.

  ## Arguments

  - `goal_name` - The goal to plan for
  - `facts` - Current world state
  - `traits` - Agent traits/genome for heuristics

  ## Returns

  - `{:ok, plan}` - Successfully generated plan
  - `{:error, reason}` - Planning failed

  """
  @spec run(atom(), Facts.t(), map()) :: {:ok, Plan.t()} | {:error, term()}
  def run(goal_name, facts, traits) do
    run_with_registry(goal_name, facts, traits, Registry.all())
  end

  @doc """
  Called on planning tick to update or create a plan.

  If no plan exists, attempts to create one for the given goal.
  If a plan exists but is no longer active, attempts to replan.

  ## Arguments

  - `plan` - Current plan (or nil)
  - `facts` - Current world state
  - `traits` - Agent traits/genome
  - `goal_name` - Default goal to plan for

  ## Returns

  The updated plan, or nil if planning fails.

  """
  @spec tick(Plan.t() | nil, Facts.t(), map(), atom()) :: Plan.t() | nil
  def tick(nil, facts, traits, goal_name) do
    case run(goal_name, facts, traits) do
      {:ok, plan} -> plan
      {:error, _} -> nil
    end
  end

  def tick(%Plan{} = plan, facts, traits, goal_name) do
    if Plan.valid?(plan) do
      plan
    else
      case run(goal_name, facts, traits) do
        {:ok, new_plan} -> new_plan
        {:error, _} -> plan
      end
    end
  end

  @doc """
  Check if plan needs replanning based on validity.

  Returns true if:
  - Plan is nil
  - Plan is not active (invalid or completed)

  """
  @spec needs_replan?(Plan.t() | nil, Facts.t()) :: boolean()
  def needs_replan?(%Plan{} = plan, _facts) do
    not Plan.valid?(plan)
  end

  def needs_replan?(_plan, _facts), do: true

  @doc """
  Run the planner with a specific registry.

  Useful for testing or when using isolated registries.
  """
  @spec run_with_registry(atom(), Facts.t(), map(), map()) ::
          {:ok, Plan.t()} | {:error, term()}
  def run_with_registry(goal_name, facts, traits, htn_registry) do
    start_time = System.monotonic_time(:millisecond)

    case Engine.expand(goal_name, facts, traits, htn_registry) do
      {:ok, plan} ->
        finalize_plan(plan, goal_name, start_time)

      error ->
        error
    end
  end

  defp finalize_plan(plan, goal_name, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time
    annotation = Rationalization.annotate_plan(plan)
    annotated_plan = %{plan | metadata: Map.merge(plan.metadata, annotation)}
    Telemetry.emit_htn_plan_generated(goal_name, length(plan.tasks), duration)
    {:ok, annotated_plan}
  end
end
