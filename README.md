# Operator

A pluggable AI planning and narrative orchestration library for games and simulations.

Operator provides two main subsystems:

- **HTN (Hierarchical Task Network)** - Goal-based planning with declarative DSL
- **Director** - Narrative event orchestration with pluggable Storyteller strategies

## Installation

Add `operator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:operator, "~> 0.1.0"}
  ]
end
```

## HTN Planning

HTN is a planning paradigm where goals decompose into tasks, which can further decompose into subtasks, until reaching primitive (directly executable) actions.

### Defining Goals and Tasks

```elixir
defmodule MyGame.NPCBehavior do
  use Operator.HTN.DSL

  # Goals are high-level objectives
  goal :acquire_data do
    precond fn facts ->
      not Operator.HTN.Facts.has?(facts, {:self, :has_data})
    end

    decompose do
      task :go_to_terminal
      task :download_data, "target_server"
    end

    metadata priority: 5, domain: :infiltration
  end

  # Tasks can decompose into subtasks
  task :go_to_terminal do
    precond fn facts ->
      Operator.HTN.Facts.has?(facts, {:self, :can_move})
    end

    decompose fn facts ->
      terminal = Operator.HTN.Facts.get(facts, {:world, :nearest_terminal})
      [{:move_to, [terminal]}]
    end

    cost 2.0
  end

  # Primitives are directly executable actions
  primitive :download_data, target do
    run fn actor, _facts ->
      # Execute the action in your game
      {:ok, actor}
    end

    metadata action_type: :interact
  end
end
```

### Running the Planner

```elixir
# Create facts from perception
facts = Operator.HTN.Facts.from_perception(%{
  self: %{can_move: true, has_data: false},
  world: %{nearest_terminal: :server_room}
})

# Agent traits for scoring/cost calculations
traits = %{archetype: :infiltrator, traits: [:stealthy]}

# Generate a plan
case Operator.HTN.Planner.run(:acquire_data, facts, traits) do
  {:ok, plan} ->
    # plan.tasks contains the sequence of primitives
    IO.inspect(plan.tasks)
    # => [{:move_to, [:server_room]}, {:download_data, ["target_server"]}]

  {:error, :preconditions_not_met} ->
    # Goal preconditions failed
    :retry_later

  {:error, :goal_not_found} ->
    # Goal not registered
    :unknown_goal
end
```

### Effects During Planning

A key feature of HTN planning (from GameAIPro) is that effects modify world state
during planning. This allows the planner to reason about future states:

```elixir
alias Operator.HTN.{Effect, Task}

# Create a task with effects
task = Task.new(:unlock_door, :primitive,
  preconditions: [fn facts -> Facts.has?(facts, {:self, :has_key}) end],
  effects: [
    # This effect is applied during planning AND execution
    Effect.new(:plan_and_execute, {:world, :door_unlocked}, true)
  ]
)

# Later tasks can have preconditions that depend on this effect:
enter_task = Task.new(:enter_room, :primitive,
  preconditions: [fn facts -> Facts.get(facts, {:world, :door_unlocked}) end]
)
```

**Effect Types:**
- `:plan_only` - Applied during planning, ignored during execution
- `:plan_and_execute` - Applied during planning AND when task completes
- `:permanent` - Applied during planning, persists regardless of task success

### Goal Selection

For NPCs without explicit goals, the `GoalSelector` picks the best eligible goal:

```elixir
case Operator.HTN.GoalSelector.pick_goal(facts, traits) do
  {:ok, goal_name} ->
    Operator.HTN.Planner.run(goal_name, facts, traits)

  :none ->
    # No eligible goals found
    :idle
end
```

## Director - Narrative Orchestration

The Director manages high-level event generation using pluggable Storyteller strategies.

### Implementing a Storyteller

```elixir
defmodule MyGame.DramaticStoryteller do
  @behaviour Operator.Storyteller

  @impl true
  def init(opts) do
    %{
      last_event_tick: 0,
      tension_threshold: Map.get(opts, :tension_threshold, 0.7)
    }
  end

  @impl true
  def pick_event(tick, world_state, state) do
    tension = Map.get(world_state, :tension, 0.0)

    if tension > state.tension_threshold do
      event = %{
        type: :dramatic_confrontation,
        location: pick_location(world_state),
        severity: 4
      }
      {event, %{state | last_event_tick: tick}}
    else
      {nil, state}
    end
  end

  defp pick_location(world_state) do
    # Your logic here
    %{district: "downtown"}
  end
end
```

### Using the Director

```elixir
# Start with your storyteller
{:ok, _pid} = Operator.Director.start_link(
  storyteller: MyGame.DramaticStoryteller,
  on_event: fn event ->
    # Handle generated events
    MyGame.EventHandler.process(event)
  end
)

# On each simulation tick
Operator.Director.tick(%{
  tick: current_tick,
  tension: world_tension,
  summary: %{total_entities: 150}
})
```

## Configuration

Operator supports optional integration modules via configuration:

```elixir
config :operator,
  # Custom telemetry integration
  telemetry_module: MyApp.OperatorTelemetry,

  # Custom traits/genome integration
  traits_module: MyApp.OperatorTraits,

  # Custom plan storage (default: ETS)
  storage_module: Operator.HTN.Storage,

  # Custom plan annotation
  rationalization_module: MyApp.OperatorRationalization,

  # Trait weights for goal scoring
  htn_trait_weights: %{
    {:aggressive, :attack} => 5,
    {:cautious, :scout} => 3
  }
```

## Behaviours

Operator defines several behaviours for integration:

### `Operator.Telemetry`

```elixir
defmodule MyApp.OperatorTelemetry do
  @behaviour Operator.Telemetry

  @impl true
  def emit_goal_selected(goal_name, measurements, metadata) do
    :telemetry.execute([:my_app, :htn, :goal_selected], measurements, metadata)
  end

  @impl true
  def emit_htn_plan_generated(goal, task_count, duration_ms) do
    :telemetry.execute([:my_app, :htn, :plan_generated],
      %{task_count: task_count, duration: duration_ms},
      %{goal: goal})
  end

  @impl true
  def emit_director_event(event_type, tick) do
    :telemetry.execute([:my_app, :director, :event],
      %{count: 1},
      %{type: event_type, tick: tick})
  end
end
```

### `Operator.Traits`

```elixir
defmodule MyApp.OperatorTraits do
  @behaviour Operator.Traits

  @impl true
  def traits(genome) do
    Map.get(genome, :traits, [])
  end

  @impl true
  def trait_affinity_score(genome, metadata) do
    # Score how well agent traits match goal metadata
    0
  end

  @impl true
  def archetype_affinity_score(genome, metadata) do
    # Score archetype-specific affinity
    0
  end
end
```

### `Operator.Storage`

```elixir
defmodule MyApp.PlanStorage do
  @behaviour Operator.Storage

  @impl true
  def persist_plan(entity_id, plan) do
    MyApp.Cache.put({:plan, entity_id}, plan)
    :ok
  end

  @impl true
  def fetch_plan(entity_id) do
    MyApp.Cache.get({:plan, entity_id})
  end

  @impl true
  def clear_plan(entity_id) do
    MyApp.Cache.delete({:plan, entity_id})
    :ok
  end

  @impl true
  def list_plans do
    MyApp.Cache.list_by_prefix(:plan)
  end
end
```

## Testing

```bash
mix test
```

## License

MIT
