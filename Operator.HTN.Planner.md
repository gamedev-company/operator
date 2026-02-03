# `Operator.HTN.Planner`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/planner.ex#L1)

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

# `explain`

```elixir
@spec explain(atom(), Operator.HTN.Facts.t(), map()) :: map()
```

Explain plan generation for a specific goal.

Returns a structured map for debugging or UI tooling. Unlike tracing,
this gives you a deterministic, inspectable payload.

## Example

    result = Planner.explain(:patrol, facts, traits)
    result.result
    #=> :ok

    result.plan.tasks
    #=> [{:move_to, [:waypoint_1]}, {:look_around, []}]

# `needs_replan?`

```elixir
@spec needs_replan?(Operator.HTN.Plan.t() | nil, Operator.HTN.Facts.t()) :: boolean()
```

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

# `run`

```elixir
@spec run(atom(), Operator.HTN.Facts.t(), map(), keyword()) ::
  {:ok, Operator.HTN.Plan.t()} | {:error, term()}
```

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

# `run_with_registry`

```elixir
@spec run_with_registry(atom(), Operator.HTN.Facts.t(), map(), map(), keyword()) ::
  {:ok, Operator.HTN.Plan.t()} | {:error, term()}
```

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

# `tick`

```elixir
@spec tick(Operator.HTN.Plan.t() | nil, Operator.HTN.Facts.t(), map(), atom()) ::
  Operator.HTN.Plan.t() | nil
```

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

---

*Consult [api-reference.md](api-reference.md) for complete listing*
