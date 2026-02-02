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
    # IMPORTANT: Use full module paths in precond/decompose functions!
    # Aliases from your module header don't work here - these functions
    # are evaluated at runtime in a different scope.
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

> **Heads up:** Functions inside `precond` and `decompose` blocks are evaluated at runtime, which means your module's `alias` statements won't work inside them. Always use full module paths like `Operator.HTN.Facts.get(...)` instead of `Facts.get(...)`.

### Making Plans Happen

```elixir
alias Operator.HTN.{Facts, Plan, Planner}

# What does your NPC know about the world?
facts = Facts.from_perception(%{
  self: %{can_move: true, has_data: false},
  world: %{nearest_terminal: :server_room}
})

# Or start with empty facts
facts = Facts.new()

# What kind of NPC is this?
traits = %{archetype: :infiltrator, traits: [:stealthy]}

# Let's see what we've got
case Planner.run(:acquire_data, facts, traits) do
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

### Executing Plans

Plans are just data - sequences of primitives to execute. The `Executor` module handles the messy business of actually running them:

```elixir
alias Operator.HTN.{Executor, Planner}

# Generate a plan
{:ok, plan} = Planner.run(:patrol, facts, traits)

# Execute step by step (recommended for game loops)
case Executor.step(plan, npc, facts) do
  {:ok, :completed, npc, facts, _plan} ->
    # All done!
    {:idle, npc, facts}

  {:ok, :continue, npc, facts, remaining_plan} ->
    # More to do - store remaining plan for next tick
    {:running, %{npc | plan: remaining_plan}, facts}

  {:error, reason, npc, facts, _plan} ->
    # Something went wrong - maybe replan
    {:failed, %{npc | plan: nil}, facts}
end

# Or run the whole plan at once (useful for turn-based games)
case Executor.run_plan(plan, npc, facts) do
  {:ok, npc, facts} ->
    # Everything worked
    :done

  {:error, reason, npc, facts, remaining} ->
    # Failed partway through
    :partial_failure
end
```

### Effects: The Secret Sauce

Here's where it gets spicy. When the planner is figuring out what to do, it can *simulate* the effects of actions. Your NPC can reason about unlocking a door *before* it tries to walk through it.

```elixir
defmodule MyGame.DoorBehavior do
  use Operator.HTN.DSL

  goal :enter_locked_room do
    precond fn facts ->
      not Operator.HTN.Facts.get(facts, {:world, :in_room}, false)
    end

    decompose do
      task :unlock_door
      task :enter_room
    end
  end

  primitive :unlock_door do
    run fn actor, _facts ->
      # Unlock animation, key consumption, etc.
      {:ok, actor}
    end

    # This effect is applied DURING PLANNING so :enter_room knows
    # the door will be unlocked by the time it runs
    effect Operator.HTN.Effect.new(:plan_and_execute, {:world, :door_unlocked}, true)
  end

  primitive :enter_room do
    # This precondition passes during planning because :unlock_door's
    # effect has already been applied to the planning state
    precond fn facts ->
      Operator.HTN.Facts.get(facts, {:world, :door_unlocked}, false)
    end

    run fn actor, _facts ->
      {:ok, %{actor | location: :room}}
    end

    effect Operator.HTN.Effect.new(:plan_and_execute, {:world, :in_room}, true)
  end
end
```

**Effect flavors:**
- `:plan_only` - "Let's pretend this happened" (planning only, ignored during execution)
- `:plan_and_execute` - "This will actually happen" (applied during both planning and execution)
- `:permanent` - "This happened and nothing can undo it" (persists even on task failure)

### Automatic Goal Selection

Don't want to micromanage which goal your NPC pursues? Let the `GoalSelector` handle it:

```elixir
alias Operator.HTN.{GoalSelector, Planner}

case GoalSelector.pick_goal(facts, traits) do
  {:ok, goal_name} ->
    Planner.run(goal_name, facts, traits)

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

### Director + HTN Integration

The Director generates world events; HTN planning lets NPCs react to them:

```elixir
defmodule MyGame.AILoop do
  alias Operator.HTN.{Executor, Facts, GoalSelector, Planner}

  def tick(entity, world_state, director_events) do
    # Build facts from perception + any director events
    facts = build_facts(entity, world_state, director_events)
    traits = entity.traits

    case entity.current_plan do
      nil ->
        # No plan - pick a goal and make one
        case GoalSelector.pick_goal(facts, traits) do
          {:ok, goal} ->
            case Planner.run(goal, facts, traits) do
              {:ok, plan} -> %{entity | current_plan: plan}
              {:error, _} -> entity
            end

          :none ->
            entity  # Idle
        end

      plan ->
        # Execute one step of current plan
        case Executor.step(plan, entity, facts) do
          {:ok, :completed, entity, _facts, _plan} ->
            %{entity | current_plan: nil}

          {:ok, :continue, entity, _facts, remaining} ->
            %{entity | current_plan: remaining}

          {:error, _reason, entity, _facts, _plan} ->
            # Plan failed - will replan next tick
            %{entity | current_plan: nil}
        end
    end
  end
end
```

## Registry API

The registry stores all registered goals, tasks, primitives, and axioms:

```elixir
alias Operator.HTN.Registry

# Get specific items by name
goal = Registry.get_goal(:patrol)
task = Registry.get_task(:move_to)
primitive = Registry.get_primitive(:attack)
axiom = Registry.get_axiom(:enemy_nearby)

# List all registered names
Registry.list_goal_names()      # => [:patrol, :attack, :flee]
Registry.list_primitive_names() # => [:move, :strike, :block]

# Get the full registry map
registry = Registry.all()
# => %{goals: %{...}, tasks: %{...}, primitives: %{...}, axioms: %{...}}

# Stats
Registry.stats()
# => %{goals: 5, tasks: 12, primitives: 8, axioms: 3}
```

## Testing

The Registry uses `persistent_term` for fast lookups, which means tests need some care:

```elixir
defmodule MyApp.BehaviorTest do
  use ExUnit.Case, async: false  # Important!

  import Operator.HTN.TestHelpers

  alias Operator.HTN.{Facts, Plan, Planner}

  # Reset registry before each test
  setup :reset_registry

  # Register your behavior module(s)
  setup do
    register_modules([MyApp.NPCBehavior])
    :ok
  end

  test "patrol goal generates valid plan" do
    facts = Facts.from_perception(%{
      self: %{on_duty: true, can_move: true}
    })

    {:ok, plan} = Planner.run(:patrol, facts, %{})

    assert Plan.has_tasks?(plan)
    assert_has_task(plan, :walk_to_waypoint)
  end
end
```

Key points:
- Use `async: false` - the Registry is global state
- Call `reset_registry` in setup to ensure clean state
- Use `register_modules/1` to register your behavior modules
- See `Operator.HTN.TestHelpers` for more utilities

```bash
mix test
```

141 tests. All green. We checked.

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

## Module Index

**Core HTN:**
- `Operator.HTN.DSL` - Macro-based DSL for defining behaviors
- `Operator.HTN.Facts` - World state representation
- `Operator.HTN.Plan` - Generated plan structure
- `Operator.HTN.Planner` - High-level planning API
- `Operator.HTN.Executor` - Plan and task execution
- `Operator.HTN.Engine` - Low-level plan expansion
- `Operator.HTN.Registry` - Goal/task/primitive storage
- `Operator.HTN.Effect` - World state modifications
- `Operator.HTN.Task` - Task definitions
- `Operator.HTN.Axiom` - Reusable query patterns
- `Operator.HTN.Precondition` - Logical operators
- `Operator.HTN.GoalSelector` - Automatic goal selection
- `Operator.HTN.TestHelpers` - Testing utilities

**Director:**
- `Operator.Director` - Event orchestration GenServer
- `Operator.Storyteller` - Storyteller behaviour

**Integration:**
- `Operator.Telemetry` - Metrics callbacks
- `Operator.Traits` - Personality/genome integration
- `Operator.Storage` - Plan persistence
- `Operator.Rationalization` - Plan annotation

## Why "Operator"?

Because your NPCs are finally going to operate like they have a brain cell or two. Also it sounds cool.

## License

MIT. Do whatever you want. Make something great.
