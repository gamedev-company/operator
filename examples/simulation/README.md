# Simulation Example

Using Operator for agent-based simulation with the Director
for emergent narrative events.

## Use Case

A city simulation where:
- Multiple agent types pursue goals autonomously
- The Director injects narrative events based on world state
- Agents react to events and each other
- Emergent stories arise from interactions

## Key Concepts

### Director for Event Orchestration

```elixir
defmodule CityStoryteller do
  @behaviour Operator.Storyteller

  @impl true
  def init(opts) do
    %{
      tension: 0.0,
      last_event_tick: 0,
      event_cooldown: Keyword.get(opts, :cooldown, 100)
    }
  end

  @impl true
  def pick_event(tick, world_state, state) do
    cond do
      # High crime -> police response
      world_state.crime_rate > 0.7 ->
        {%{type: :police_raid, district: highest_crime_district(world_state)}, state}

      # Economic collapse -> riots
      world_state.unemployment > 0.5 and state.tension > 0.8 ->
        {%{type: :riot, severity: :major}, reset_tension(state)}

      # Gradual tension buildup
      tick - state.last_event_tick > state.event_cooldown ->
        {maybe_ambient_event(world_state), update_tension(state, world_state)}

      true ->
        {nil, state}
    end
  end
end
```

### Multiple Agent Types

```elixir
# Citizen agents
goal :go_to_work do
  precond fn facts ->
    Facts.get(facts, {:self, :employed}, false) and
    time_for_work?(facts)
  end
  # ...
end

# Police agents
goal :patrol_district do
  precond fn facts ->
    Facts.get(facts, {:self, :role}) == :police and
    Facts.get(facts, {:self, :on_shift}, false)
  end
  # ...
end

# Criminal agents
goal :commit_crime do
  precond {:all, [
    fn facts -> Facts.get(facts, {:self, :desperate}, false) end,
    fn facts -> opportunity_present?(facts) end,
    {:not, {:axiom, :police_nearby}}
  ]}
  # ...
end
```

### Event Reactions

Agents can have goals that respond to Director events:

```elixir
goal :flee_riot do
  precond fn facts ->
    Facts.get(facts, {:world, :active_event}) == :riot and
    Facts.get(facts, {:self, :in_affected_area}, false)
  end

  decompose do
    task :find_safe_route
    task :evacuate
    task :notify_family
  end

  metadata priority: 10
end
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Director                              │
│  ┌───────────────────────────────────────────────────┐  │
│  │              CityStoryteller                       │  │
│  │  - Monitors world state                           │  │
│  │  - Injects narrative events                       │  │
│  │  - Manages tension/pacing                         │  │
│  └───────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────┘
                            │ events
                            ▼
┌─────────────────────────────────────────────────────────┐
│                  World State                             │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │
│  │District │  │District │  │District │  │District │    │
│  │Downtown │  │ Harbor  │  │ Suburbs │  │Industrial│    │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘    │
│       │            │            │            │          │
│       ▼            ▼            ▼            ▼          │
│  [Agents]     [Agents]     [Agents]     [Agents]       │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                 Agent Loop (per tick)                    │
│  1. Perceive world state                                │
│  2. Select goal (GoalSelector)                          │
│  3. Generate plan (Planner)                             │
│  4. Execute next primitive                              │
│  5. Update world state                                  │
└─────────────────────────────────────────────────────────┘
```

## Emergent Narratives

The combination of:
- Agent goals (local decision making)
- Director events (global narrative injection)
- World state (shared context)

Creates emergent stories:

> "The unemployment rate in Harbor district reached 60%. Tension had been
> building for weeks. When the Director triggered a riot event, citizen
> agents began fleeing while police agents converged on the area. A criminal
> agent used the chaos to pursue their heist goal unnoticed. The story
> emerged from the interaction of autonomous agents and narrative direction."

## Running

```bash
cd examples/simulation
mix deps.get
iex -S mix

Simulation.Example.run_city(ticks: 1000)
```
