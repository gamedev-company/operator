# Game NPC Example

A complete example of using Operator for game NPC AI, demonstrating:

- Multiple behavior domains (patrol, combat, survival)
- Dynamic goal selection based on world state
- Effects system for planning future states
- Trait-based behavior customization

## Overview

This example implements an NPC guard that can:

1. **Patrol** waypoints when on duty
2. **Investigate** disturbances
3. **Engage** enemies in combat
4. **Flee** when health is critical
5. **Heal** at supply stations

## Running

```bash
cd examples/game_npc
mix deps.get
iex -S mix

# Run the full example
GameNPC.Example.run()

# Or run specific scenarios
GameNPC.Example.patrol_scenario()
GameNPC.Example.combat_scenario()
GameNPC.Example.survival_scenario()
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│                 World State                      │
│  ┌─────────┐  ┌─────────┐  ┌─────────────────┐  │
│  │  Self   │  │  World  │  │     Social      │  │
│  │ health  │  │ enemies │  │ faction_standing│  │
│  │ ammo    │  │ waypts  │  │ ally_positions  │  │
│  │ position│  │ noise   │  │                 │  │
│  └─────────┘  └─────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│              Goal Selector                       │
│  Picks best goal based on:                       │
│  - Preconditions (what's possible?)             │
│  - Priority (what's urgent?)                    │
│  - Traits (what fits personality?)              │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│                 Planner                          │
│  Expands goal into executable primitives        │
│  Applies effects to simulate future states      │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│                 Executor                         │
│  Runs primitives in sequence                    │
│  Updates world state                            │
│  Handles failures and replanning                │
└─────────────────────────────────────────────────┘
```

## Code Structure

### Domain Definition (`lib/domain.ex`)

Defines all goals, tasks, and primitives using the DSL:

```elixir
goal :patrol do
  precond fn facts ->
    Facts.get(facts, {:self, :on_duty}, false) and
    not Facts.has?(facts, {:world, :threat})
  end

  decompose do
    task :move_to_waypoint
    task :scan_area
    task :patrol  # Recursive - continues until threat detected
  end

  metadata priority: 2, domain: :security
end
```

### Executor (`lib/executor.ex`)

Runs plans and manages state transitions:

```elixir
def execute_plan(plan, state) do
  case Plan.next_task(plan) do
    {{action, args}, remaining} ->
      case execute_primitive(action, args, state) do
        {:ok, new_state} ->
          execute_plan(remaining, new_state)
        {:error, reason} ->
          {:error, reason, state}
      end

    :empty ->
      {:ok, state}
  end
end
```

### Example Runner (`lib/example.ex`)

Demonstrates the full loop:

```elixir
def run do
  # Initialize world state
  state = initial_state()

  # Run simulation loop
  Enum.reduce(1..100, state, fn tick, state ->
    # Update perception
    facts = perceive(state)

    # Select and execute goal
    case GoalSelector.pick_goal(facts, state.traits) do
      {:ok, goal} ->
        {:ok, plan} = Planner.run(goal, facts, state.traits)
        {:ok, new_state} = Executor.execute_plan(plan, state)
        new_state

      :none ->
        # Idle
        state
    end
  end)
end
```

## Key Concepts Demonstrated

### 1. Goal Priority

Goals have priorities that affect selection:

```elixir
goal :flee do
  metadata priority: 10  # Highest - survival
end

goal :combat do
  metadata priority: 5   # Medium - engagement
end

goal :patrol do
  metadata priority: 2   # Low - routine
end
```

### 2. Effects System

Tasks can declare effects that modify planning state:

```elixir
primitive :heal do
  run fn actor, _facts ->
    {:ok, %{actor | health: 100}}
  end

  # During planning, assume we'll be healed
  effects [
    Effect.new(:plan_and_execute, {:self, :health}, 100)
  ]
end
```

### 3. Trait-Based Customization

Agent traits affect goal scoring:

```elixir
# Aggressive guard
traits = %{archetype: :guard, traits: [:aggressive, :vigilant]}

# Cautious guard
traits = %{archetype: :guard, traits: [:cautious, :methodical]}
```

### 4. Dynamic Decomposition

Tasks can decompose based on world state:

```elixir
task :engage_enemy do
  decompose fn facts ->
    enemy = Facts.get(facts, {:world, :nearest_enemy})
    distance = Facts.get(facts, {:world, {:distance, enemy}})

    if distance > 10 do
      [{:move_to, [enemy]}, {:attack, [enemy]}]
    else
      [{:attack, [enemy]}]
    end
  end
end
```

## Extending This Example

1. **Add new behaviors**: Create new goals for different situations
2. **Add weapons**: Implement weapon selection and switching
3. **Add squad tactics**: Use social facts for coordination
4. **Add learning**: Track successful strategies in metadata
