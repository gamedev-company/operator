# Operator

Welcome to Operator. We're done here.

Just kidding. But seriously, if you've ever watched an NPC walk into a wall for six hours because someone forgot to tell it that doors exist, you know why this library exists. We built Operator because game AI deserves better than a pile of if-statements held together with prayers and energy drinks.

Operator gives you two things:

- **HTN Planning** - Your NPCs will actually *think*. Goals break down into tasks, tasks break down into actions, and suddenly your village blacksmith stops trying to forge swords in the middle of a lake.
- **Director** - A narrative orchestration system that decides when interesting things should happen. Think Left 4 Dead's AI Director, but you're the one holding the reins.

## Installation

```elixir
def deps do
  [
    {:operator, "~> 0.1.0"}
  ]
end
```

That's it. No C dependencies. No NIFs that only compile on a full moon. Just pure Elixir.

## HTN Planning (or: Teaching Rocks to Think)

HTN stands for Hierarchical Task Network. The idea came from some very smart people who got tired of writing behavior trees that looked like spaghetti painted by Jackson Pollock.

Here's the deal: you define **goals** (what the NPC wants), **tasks** (how to break that down), and **primitives** (the actual buttons to press). The planner figures out the rest.

### Defining Behavior

```elixir
defmodule MyGame.NPCBehavior do
  use Operator.HTN.DSL

  # "I want data and I want it now"
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

  # "Getting there is half the battle"
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

  # "The part where things actually happen"
  primitive :download_data, target do
    run fn actor, _facts ->
      # Your game logic here. We're not picky.
      {:ok, actor}
    end

    metadata action_type: :interact
  end
end
```

### Making Plans Happen

```elixir
# What does your NPC know about the world?
facts = Operator.HTN.Facts.from_perception(%{
  self: %{can_move: true, has_data: false},
  world: %{nearest_terminal: :server_room}
})

# What kind of NPC is this?
traits = %{archetype: :infiltrator, traits: [:stealthy]}

# Let's see what we've got
case Operator.HTN.Planner.run(:acquire_data, facts, traits) do
  {:ok, plan} ->
    IO.inspect(plan.tasks)
    # => [{:move_to, [:server_room]}, {:download_data, ["target_server"]}]
    # Look at that. A real plan. Made by a computer.

  {:error, :preconditions_not_met} ->
    # Can't get blood from a stone
    :retry_later

  {:error, :goal_not_found} ->
    # You asked for a goal that doesn't exist. Classic.
    :unknown_goal
end
```

### The Secret Sauce: Planning-Time Effects

Here's where it gets spicy. When the planner is figuring out what to do, it can *simulate* the effects of actions. Your NPC can reason about unlocking a door *before* it tries to walk through it. Revolutionary stuff.

```elixir
alias Operator.HTN.{Effect, Task}

task = Task.new(:unlock_door, :primitive,
  preconditions: [fn facts -> Facts.has?(facts, {:self, :has_key}) end],
  effects: [
    Effect.new(:plan_and_execute, {:world, :door_unlocked}, true)
  ]
)

# Now this task's precondition will pass during planning:
enter_task = Task.new(:enter_room, :primitive,
  preconditions: [fn facts -> Facts.get(facts, {:world, :door_unlocked}) end]
)
```

**Effect flavors:**
- `:plan_only` - "Let's pretend this happened" (planning only)
- `:plan_and_execute` - "This will actually happen" (planning + execution)
- `:permanent` - "This happened and nothing can undo it" (persists even on failure)

### Automatic Goal Selection

Don't want to micromanage which goal your NPC pursues? Let the `GoalSelector` handle it:

```elixir
case Operator.HTN.GoalSelector.pick_goal(facts, traits) do
  {:ok, goal_name} ->
    Operator.HTN.Planner.run(goal_name, facts, traits)

  :none ->
    # Nothing to do. Time to stand around looking mysterious.
    :idle
end
```

## The Director (or: Playing God, Responsibly)

Ever play a game where nothing happens for twenty minutes and then everything happens at once? That's bad directing. The Director system lets you control the *pacing* of your simulation.

You write a **Storyteller** that decides when and what events should fire based on the current world state. Tension too low? Spawn a wandering merchant. Tension too high? Maybe hold off on that dragon attack.

### Writing a Storyteller

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
      {nil, state}  # Sometimes the best event is no event
    end
  end

  defp pick_location(world_state) do
    %{district: "downtown"}  # Your logic here
  end
end
```

### Running the Show

```elixir
{:ok, _pid} = Operator.Director.start_link(
  storyteller: MyGame.DramaticStoryteller,
  on_event: fn event ->
    MyGame.EventHandler.process(event)
  end
)

# Every tick, feed it the world state
Operator.Director.tick(%{
  tick: current_tick,
  tension: world_tension,
  summary: %{total_entities: 150}
})
```

## Configuration

Operator is pluggable. Don't like how we do something? Swap it out.

```elixir
config :operator,
  telemetry_module: MyApp.OperatorTelemetry,      # Your metrics, your way
  traits_module: MyApp.OperatorTraits,            # Custom genome/personality system
  storage_module: Operator.HTN.Storage,           # Where plans live (default: ETS)
  rationalization_module: MyApp.OperatorRationalization,  # Plan annotation

  # Weight certain trait+goal combinations
  htn_trait_weights: %{
    {:aggressive, :attack} => 5,
    {:cautious, :scout} => 3
  }
```

## Behaviours

We expose several behaviours so you can integrate Operator with whatever bizarre architecture you've already committed to.

### Telemetry

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

### Traits

```elixir
defmodule MyApp.OperatorTraits do
  @behaviour Operator.Traits

  @impl true
  def traits(genome), do: Map.get(genome, :traits, [])

  @impl true
  def trait_affinity_score(genome, metadata) do
    # How much does this agent want to do this thing?
    0
  end

  @impl true
  def archetype_affinity_score(genome, metadata) do
    # Warriors gonna war, healers gonna heal
    0
  end
end
```

### Storage

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

## Examples

Check out the `examples/` directory. We've got:

- **game_npc** - Combat, patrol, survival behaviors
- **web_scraper** - Yes, you can use HTN for web scraping. We won't judge.
- **job_worker** - Background job orchestration
- **chatbot** - Conversation flow management
- **simulation** - Multi-agent chaos with the Director

## Testing

```bash
mix test
```

141 tests. All green. We checked.

## Why "Operator"?

Because your NPCs are finally going to operate like they have a brain cell or two. Also it sounds cool.

## License

MIT. Do whatever you want. Make something great.
