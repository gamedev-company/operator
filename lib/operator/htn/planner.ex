defmodule Operator.HTN.Planner do
  @moduledoc """
  High-level API for HTN plan generation.

  The Planner is your primary interface for generating plans. It wraps the
  Engine with telemetry, rationalization, and convenience functions for
  tick-based game loops.

  ## Basic Usage

      alias Operator.HTN.{Facts, Planner}

      facts = Facts.from_perception(%{
        self: %{location: :lobby, has_keycard: true},
        world: %{target: :server_room, threat_level: :low}
      })

      traits = %{archetype: :infiltrator, traits: [:stealthy, :tech_savvy]}

      case Planner.run(:infiltrate_building, facts, traits) do
        {:ok, plan} ->
          IO.inspect(plan.tasks)
          # => [{:move_to, [:server_room]}, {:hack_terminal, []}, {:download_data, []}]

        {:error, :preconditions_not_met} ->
          # Goal preconditions not satisfied - wait or choose different goal
          :retry_later

        {:error, :goal_not_found} ->
          # Goal not registered - check your DSL module
          :unknown_goal
      end

  ## Integration with Game Loops

  For continuous simulations, the Planner provides tick-based helpers:

      defmodule MyGame.AISystem do
        alias Operator.HTN.{Executor, Facts, Planner}

        def update(entity, world) do
          facts = build_facts(entity, world)
          traits = entity.genome

          case entity.plan do
            nil ->
              # No plan - generate one
              plan = Planner.tick(nil, facts, traits, :default_goal)
              %{entity | plan: plan}

            plan ->
              # Have plan - check if still valid, execute or replan
              if Planner.needs_replan?(plan, facts) do
                new_plan = Planner.tick(plan, facts, traits, :default_goal)
                %{entity | plan: new_plan}
              else
                # Execute current plan
                case Executor.step(plan, entity, facts) do
                  {:ok, :completed, entity, _facts, _plan} ->
                    %{entity | plan: nil}

                  {:ok, :continue, entity, _facts, remaining} ->
                    %{entity | plan: remaining}

                  {:error, _reason, entity, _facts, _plan} ->
                    %{entity | plan: nil}  # Will replan next tick
                end
              end
          end
        end
      end

  ## What Happens During Planning

  1. **Goal lookup** - Find the goal in the Registry
  2. **Precondition check** - Verify goal preconditions pass
  3. **Decomposition** - Expand goal into task sequence
  4. **Recursive expansion** - Expand abstract tasks into primitives
  5. **Effect simulation** - Apply effects to working facts copy
  6. **Annotation** - Add narrative metadata via Rationalization
  7. **Telemetry** - Emit planning metrics

  ## Telemetry Events

  Each successful `run/3` emits `Telemetry.emit_htn_plan_generated/3` with:
  - Goal name
  - Task count
  - Planning duration (ms)

  ## See Also

  * `Operator.HTN.Engine` - Low-level expansion logic
  * `Operator.HTN.Executor` - Running generated plans
  * `Operator.HTN.GoalSelector` - Automatic goal selection
  * `Operator.HTN.Plan` - The plan data structure

  """

  alias Operator.HTN.{Engine, Facts, Plan, Registry}
  alias Operator.{Rationalization, Telemetry}

  @doc """
  Generate a plan for a goal.

  This is the primary planning function. It expands the goal into a sequence
  of primitive tasks, annotates the plan with narrative metadata, and emits
  telemetry.

  ## Parameters

  * `goal_name` - The goal atom to plan for (must be registered)
  * `facts` - Current world state (`Facts.t()`)
  * `traits` - Agent traits/genome map for cost heuristics

  ## Returns

  * `{:ok, plan}` - Successfully generated plan with tasks
  * `{:error, :goal_not_found}` - Goal not in Registry
  * `{:error, :preconditions_not_met}` - Goal preconditions failed
  * `{:error, {:budget_exceeded, reason}}` - Planning exceeded configured budget

  ## Examples

      # Successful planning
      {:ok, plan} = Planner.run(:patrol, facts, traits)
      plan.tasks
      #=> [{:walk_to, [:waypoint_1]}, {:scan, []}, {:walk_to, [:waypoint_2]}]

      # Goal doesn't exist
      {:error, :goal_not_found} = Planner.run(:nonexistent, facts, traits)

      # Preconditions failed (e.g., attack requires weapon)
      facts_unarmed = Facts.from_perception(%{self: %{armed: false}})
      {:error, :preconditions_not_met} = Planner.run(:attack, facts_unarmed, traits)

      # Budgeted planning
      Planner.run(:patrol, facts, traits, budget: [max_tasks: 50, timeout_ms: 5])

  """
  @spec run(atom(), Facts.t(), map(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def run(goal_name, facts, traits, opts \\ []) do
    run_with_registry(goal_name, facts, traits, Registry.all(), opts)
  end

  @doc """
  Explain plan generation for a specific goal.

  Returns a structured map for debugging or UI tooling. Unlike tracing,
  this gives you a deterministic, inspectable payload.

  ## Example

      result = Planner.explain(:patrol, facts, traits)
      result.result
      #=> :ok

      result.plan.tasks
      #=> [{:move_to, [:waypoint_1]}, {:look_around, []}]

  """
  @spec explain(atom(), Facts.t(), map()) :: map()
  def explain(goal_name, facts, traits) do
    started_at = System.monotonic_time(:millisecond)
    goal = Registry.get_goal(goal_name)
    missing_facts = Facts.missing_keys(facts, required_fact_keys(goal))

    cond do
      goal == nil ->
        %{
          goal: goal_name,
          result: :error,
          reason: :goal_not_found,
          preconditions_met: false,
          missing_facts: missing_facts,
          plan: nil,
          duration_ms: System.monotonic_time(:millisecond) - started_at
        }

      not goal_precond_met?(goal, facts) ->
        %{
          goal: goal_name,
          result: :error,
          reason: :preconditions_not_met,
          preconditions_met: false,
          missing_facts: missing_facts,
          plan: nil,
          duration_ms: System.monotonic_time(:millisecond) - started_at
        }

      true ->
        case run(goal_name, facts, traits) do
          {:ok, plan} ->
            %{
              goal: goal_name,
              result: :ok,
              reason: nil,
              preconditions_met: true,
              missing_facts: missing_facts,
              plan: plan,
              metadata: plan.metadata,
              duration_ms: System.monotonic_time(:millisecond) - started_at
            }

          {:error, reason} ->
            %{
              goal: goal_name,
              result: :error,
              reason: reason,
              preconditions_met: true,
              missing_facts: missing_facts,
              plan: nil,
              duration_ms: System.monotonic_time(:millisecond) - started_at
            }
        end
    end
  end

  @doc """
  Update or create a plan on each game tick.

  Convenience function for tick-based game loops. Handles the common pattern
  of "create plan if none exists, replan if invalid, keep if valid".

  ## Parameters

  * `plan` - Current plan (or `nil` if none)
  * `facts` - Current world state
  * `traits` - Agent traits/genome
  * `goal_name` - Goal to plan for if replanning needed

  ## Returns

  * `%Plan{}` - The current or newly generated plan
  * `nil` - Planning failed and no valid plan exists

  ## Behavior

  | Current Plan | Plan Valid? | Result                    |
  |--------------|-------------|---------------------------|
  | `nil`        | N/A         | Generate new plan         |
  | `%Plan{}`    | Yes         | Return existing plan      |
  | `%Plan{}`    | No          | Generate new plan         |

  ## Examples

      # In your game loop
      def update_ai(entity, world) do
        facts = build_facts(entity, world)
        plan = Planner.tick(entity.plan, facts, entity.traits, :default_goal)
        %{entity | plan: plan}
      end

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
  Check if a plan needs replanning.

  Returns `true` if the plan is missing, invalid, or completed.
  Use this to decide whether to call `run/3` or continue with
  the current plan.

  ## Parameters

  * `plan` - Current plan (or `nil`)
  * `facts` - Current world state (reserved for future validation)

  ## Returns

  * `true` - Plan is `nil`, `:invalid`, or `:completed`
  * `false` - Plan is `:active` and ready for execution

  ## Examples

      Planner.needs_replan?(nil, facts)
      #=> true

      active_plan = Plan.new(:goal, [{:task, []}])
      Planner.needs_replan?(active_plan, facts)
      #=> false

      completed = Plan.complete(active_plan)
      Planner.needs_replan?(completed, facts)
      #=> true

  """
  @spec needs_replan?(Plan.t() | nil, Facts.t()) :: boolean()
  def needs_replan?(%Plan{} = plan, _facts) do
    not Plan.valid?(plan)
  end

  def needs_replan?(_plan, _facts), do: true

  @doc """
  Generate a plan using a specific registry.

  Primarily useful for testing with isolated registries or when you need
  to plan against a subset of behaviors.

  ## Parameters

  * `goal_name` - The goal atom to plan for
  * `facts` - Current world state
  * `traits` - Agent traits/genome
  * `htn_registry` - Registry map (from `Registry.all()` or custom)

  ## Returns

  Same as `run/3`.

  ## Examples

      # Testing with isolated registry
      test "my goal generates correct plan" do
        registry = %{
          goals: %{test_goal: %{name: :test_goal, decompose: ...}},
          tasks: %{},
          primitives: %{test_action: %Task{...}},
          axioms: %{}
        }

        {:ok, plan} = Planner.run_with_registry(:test_goal, facts, %{}, registry)
        assert [{:test_action, []}] = plan.tasks
      end

  """
  @spec run_with_registry(atom(), Facts.t(), map(), map(), keyword()) ::
          {:ok, Plan.t()} | {:error, term()}
  def run_with_registry(goal_name, facts, traits, htn_registry, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    case Engine.expand(goal_name, facts, traits, htn_registry, opts) do
      {:ok, plan} ->
        finalize_plan(plan, goal_name, start_time)

      error ->
        error
    end
  end

  defp goal_precond_met?(%{precond: nil}, _facts), do: true
  defp goal_precond_met?(%{precond: fun}, facts) when is_function(fun, 1), do: fun.(facts)
  defp goal_precond_met?(_, _facts), do: true

  defp required_fact_keys(nil), do: []

  defp required_fact_keys(goal) do
    goal
    |> Map.get(:metadata, %{})
    |> Map.get(:requires_facts, [])
  end

  defp finalize_plan(plan, goal_name, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time
    annotation = Rationalization.annotate_plan(plan)
    annotated_plan = %{plan | metadata: Map.merge(plan.metadata, annotation)}
    Telemetry.emit_htn_plan_generated(goal_name, length(plan.tasks), duration)
    {:ok, annotated_plan}
  end
end
