# Getting Started

This guide walks you through building your first HTN (Hierarchical Task Network)
planning system with Operator. By the end, you'll have an NPC that can plan and
execute behaviors based on world state.

## Installation

Add Operator to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:operator, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Core Concepts

Before writing code, understand the HTN hierarchy:

```
Goals (high-level objectives)
  └── Tasks (abstract steps)
       └── Primitives (executable actions)
```

- **Goals** - What the agent wants to achieve ("patrol area", "attack enemy")
- **Tasks** - How to achieve it, decomposed into subtasks
- **Primitives** - Actual actions your game executes ("move", "fire", "wait")

## Your First Behavior Module

Create a behavior module that defines what your NPC can do:

```elixir
defmodule MyGame.GuardBehavior do
  use Operator.HTN.DSL

  # A goal that decomposes into tasks
  goal :patrol do
    precond fn facts ->
      Operator.HTN.Facts.get(facts, {:self, :energy}, 0) > 20
    end

    decompose do
      task :move_to, :waypoint_1
      task :look_around
      task :move_to, :waypoint_2
      task :look_around
    end

    metadata priority: 3, domain: :routine
  end

  # Primitives are the leaf actions
  primitive :move_to, destination do
    run fn actor, _facts ->
      # Your game's movement logic here
      IO.puts("#{actor.name} moving to #{destination}")
      {:ok, actor}
    end
  end

  primitive :look_around do
    run fn actor, _facts ->
      IO.puts("#{actor.name} scanning area...")
      {:ok, actor}
    end
  end
end
```

## Understanding Facts

Facts represent the agent's knowledge about the world:

```elixir
alias Operator.HTN.Facts

# Create facts from perception data
facts = Facts.from_perception(%{
  self: %{
    health: 100,
    energy: 80,
    position: {10, 20}
  },
  world: %{
    threat_level: :low,
    time_of_day: :day
  },
  social: %{
    faction: :guards
  }
})

# Query facts in preconditions
Facts.has?(facts, {:self, :health})      # => true
Facts.get(facts, {:self, :health})       # => 100
Facts.get(facts, {:self, :ammo}, 0)      # => 0 (default)
```

## Generating Plans

Use the Planner to create a plan for a goal:

```elixir
alias Operator.HTN.Planner

# Build facts from your game state
facts = Facts.from_perception(%{
  self: %{energy: 80}
})

# Traits influence goal selection and costs
traits = %{archetype: :guard}

# Generate a plan
case Planner.run(:patrol, facts, traits) do
  {:ok, plan} ->
    IO.inspect(plan.tasks)
    # => [{:move_to, [:waypoint_1]}, {:look_around, []}, ...]

  {:error, :preconditions_not_met} ->
    IO.puts("Guard doesn't have enough energy to patrol")

  {:error, :goal_not_found} ->
    IO.puts("Unknown goal")
end
```

## Executing Plans

Execute plans step-by-step or all at once:

```elixir
alias Operator.HTN.Executor

actor = %{name: "Guard #1", id: 1}

# Execute one step at a time (good for game loops)
case Executor.step(plan, actor, facts) do
  {:ok, :continue, updated_actor, updated_facts, remaining_plan} ->
    # Store remaining_plan for next tick
    {:continue, updated_actor, remaining_plan}

  {:ok, :completed, final_actor, final_facts, _plan} ->
    # Plan finished!
    {:done, final_actor}

  {:error, reason, actor, facts, plan} ->
    # Task failed, might need to replan
    {:failed, reason}
end

# Or execute entire plan at once
{:ok, final_actor, final_facts} = Executor.run_plan(plan, actor, facts)
```

## Game Loop Integration

Here's a typical integration pattern:

```elixir
defmodule MyGame.AISystem do
  alias Operator.HTN.{Executor, Facts, GoalSelector, Planner}

  def tick(entity, world_state) do
    facts = build_facts(entity, world_state)
    traits = entity.genome

    case entity.current_plan do
      nil ->
        # No plan - pick a goal and plan
        case GoalSelector.pick_goal(facts, traits) do
          {:ok, goal} ->
            case Planner.run(goal, facts, traits) do
              {:ok, plan} -> %{entity | current_plan: plan}
              {:error, _} -> entity
            end
          :none ->
            entity  # No valid goals
        end

      plan ->
        # Have a plan - execute next step
        case Executor.step(plan, entity, facts) do
          {:ok, :completed, updated, _facts, _plan} ->
            %{updated | current_plan: nil}

          {:ok, :continue, updated, _facts, remaining} ->
            %{updated | current_plan: remaining}

          {:error, _reason, entity, _facts, _plan} ->
            # Invalidate plan, will replan next tick
            %{entity | current_plan: nil}
        end
    end
  end

  defp build_facts(entity, world_state) do
    Facts.from_perception(%{
      self: %{
        health: entity.health,
        energy: entity.energy,
        position: entity.position
      },
      world: Map.take(world_state, [:threat_level, :time_of_day])
    })
  end
end
```

## Adding Preconditions

Preconditions control when goals and tasks are available:

```elixir
goal :attack do
  # Simple precondition
  precond fn facts ->
    Facts.has?(facts, {:self, :weapon}) and
    Facts.get(facts, {:self, :ammo}, 0) > 0
  end

  decompose do
    task :aim_at_target
    task :fire_weapon
  end
end
```

Use logical operators for complex conditions:

```elixir
alias Operator.HTN.Precondition

# OR: has weapon OR near weapon pickup
{:any, [
  fn facts -> Facts.has?(facts, {:self, :weapon}) end,
  fn facts -> Facts.has?(facts, {:world, :weapon_nearby}) end
]}

# Negation
{:not, fn facts -> Facts.get(facts, {:self, :stunned}, false) end}
```

## Using Effects

Effects update world state during planning:

```elixir
alias Operator.HTN.Effect

primitive :unlock_door do
  effects [
    Effect.new(:plan_and_execute, {:world, :door_locked}, false)
  ]

  run fn actor, _facts ->
    {:ok, actor}
  end
end
```

Effect types:
- `:plan_only` - Only applied during planning (hypothetical)
- `:plan_and_execute` - Applied during planning AND execution
- `:permanent` - Applied at execution, persists beyond plan

## Next Steps

- Read the [How-To Guides](howto.html) for specific recipes
- Check the [Cheatsheet](cheatsheet.html) for quick reference
- Explore the [API Reference](api-reference.html) for details
- See the `examples/` directory for complete implementations
