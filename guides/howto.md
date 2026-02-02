# How-To Guides

Practical recipes for common HTN planning scenarios.

## Define Dynamic Decomposition

When task subtasks depend on world state:

```elixir
task :travel_to, destination do
  decompose fn facts ->
    current = Operator.HTN.Facts.get(facts, {:self, :position})
    has_vehicle = Operator.HTN.Facts.has?(facts, {:self, :vehicle})

    if has_vehicle do
      [{:enter_vehicle, []}, {:drive_to, [destination]}, {:exit_vehicle, []}]
    else
      [{:walk_to, [destination]}]
    end
  end
end
```

## Create Branching Behaviors

Use preconditions to select between approaches. Preconditions are stored as a
list of conditions and evaluated via `Operator.HTN.Precondition`.

```elixir
goal :engage_enemy do
  precond fn facts ->
    Operator.HTN.Facts.has?(facts, {:world, :enemy_visible})
  end

  decompose fn facts ->
    distance = Operator.HTN.Facts.get(facts, {:world, :enemy_distance}, 100)
    has_ammo = Operator.HTN.Facts.get(facts, {:self, :ammo}, 0) > 0

    cond do
      distance < 5 ->
        [{:melee_attack, []}]
      has_ammo ->
        [{:aim, []}, {:fire, []}]
      true ->
        [{:retreat, []}, {:find_ammo, []}]
    end
  end

  metadata priority: 8, domain: :combat
end
```

## Implement Cost-Based Planning

Make certain behaviors more or less "expensive":

```elixir
# Static cost
primitive :sprint do
  cost 3.0  # Higher cost = less preferred

  run fn actor, _facts ->
    {:ok, %{actor | stamina: actor.stamina - 20}}
  end
end

# Dynamic cost based on world state
task :attack do
  cost fn facts ->
    threat = Operator.HTN.Facts.get(facts, {:world, :threat_level}, 1.0)
    5.0 * threat  # More expensive when dangerous
  end
end

# Trait-influenced cost
task :negotiate do
  cost fn _facts, traits ->
    charisma = Map.get(traits, :charisma, 1.0)
    10.0 / charisma  # Cheaper for charismatic agents
  end
end
```

## Add Trait-Based Goal Selection

Use traits to influence which goals are selected:

```elixir
# In your behavior module
goal :aggressive_attack do
  metadata priority: 5, required_traits: [:aggressive]
  # ...
end

goal :cautious_approach do
  metadata priority: 5, required_traits: [:cautious]
  # ...
end

# When selecting goals
facts = build_facts(entity)
traits = %{traits: [:aggressive, :brave]}

{:ok, goal} = Operator.HTN.GoalSelector.pick_goal(facts, traits)
# Will prefer goals matching the entity's traits
```

## Force Goal Ordering

Sometimes you want deterministic ordering instead of scoring.

```elixir
alias Operator.HTN.GoalSelector

{:ok, goal} = GoalSelector.pick_goal(facts, traits,
  goal_order: [:emergency_flee, :heal, :attack, :idle]
)
```

## Add Plan Metadata For Diagnostics

Metadata is useful for debugging and analytics.

```elixir
plan = Operator.HTN.Plan.add_metadata(plan, :source, \"goal_selector\")
plan = Operator.HTN.Plan.add_metadata(plan, :tick, current_tick)
```

## Set Up Test Isolation

HTN Registry uses global state. Isolate tests properly:

```elixir
defmodule MyBehaviorTest do
  use ExUnit.Case, async: false  # Important!

  alias Operator.HTN.TestHelpers

  # Option 1: Reset registry in setup
  setup do
    TestHelpers.reset_registry()
    :ok
  end

  # Option 2: Use isolated registry for specific tests
  test "my behavior works" do
    TestHelpers.with_registry([MyBehavior], fn ->
      # Only MyBehavior is registered here
      assert :my_goal in Operator.HTN.Registry.list_goal_names()
    end)
  end

  # Option 3: Setup with specific modules
  setup do
    TestHelpers.setup_htn([MyBehavior, AnotherBehavior])
    :ok
  end
end
```

## Build Facts In One Place

Keep your facts builder deterministic and side-effect free.

```elixir
def build_facts(entity, world_state) do
  Operator.HTN.Facts.from_perception(%{
    self: %{energy: entity.energy, position: entity.position},
    world: %{time: world_state.time, threat: world_state.threat}
  })
end
```

## Debug Plan Generation

Use tracing to see what the planner is doing:

```elixir
alias Operator.HTN.Trace
alias Operator.HTN.Trace.ConsoleHandler

# Enable console tracing
Trace.set_handler(ConsoleHandler)

# Now plan - you'll see output like:
# [HTN] ▶ GOAL patrol
# [HTN]   ✓ Precondition passed (goal: patrol)
# [HTN]   → TASK move_to [:waypoint_1]
# [HTN]   ◀ GOAL patrol SUCCESS

{:ok, plan} = Planner.run(:patrol, facts, traits)

# Disable when done
Trace.reset()
```

Create a custom handler for structured logging:

```elixir
defmodule MyGame.HTNLogger do
  require Logger

  def on_goal_start(goal, _facts, _opts) do
    Logger.debug("[HTN] Starting goal: #{goal}")
  end

  def on_goal_end(goal, result, _opts) do
    Logger.debug("[HTN] Goal #{goal} finished: #{result}")
  end

  def on_task_expand(task, args, _facts, _opts) do
    Logger.debug("[HTN] Expanding: #{task} #{inspect(args)}")
  end

  # Implement other callbacks as needed...
end

Trace.set_handler(MyGame.HTNLogger)
```

## Implement Plan Persistence

Store plans across game saves:

```elixir
# Default storage uses ETS (in-memory)
alias Operator.HTN.Storage

# Store a plan
Storage.persist_plan(entity_id, plan)

# Retrieve later
plan = Storage.fetch_plan(entity_id)

# Clear when entity dies/despawns
Storage.clear_plan(entity_id)
```

For disk persistence, implement the Storage behaviour:

```elixir
defmodule MyGame.PersistentStorage do
  @behaviour Operator.Storage

  @impl true
  def persist_plan(entity_id, plan) do
    # Save to database/file
    MyGame.Repo.insert_or_update(%PlanRecord{
      entity_id: entity_id,
      plan_data: :erlang.term_to_binary(plan)
    })
    :ok
  end

  @impl true
  def fetch_plan(entity_id) do
    case MyGame.Repo.get(PlanRecord, entity_id) do
      nil -> nil
      record -> :erlang.binary_to_term(record.plan_data)
    end
  end

  # Implement clear_plan/1 and list_plans/0...
end

# Configure in config.exs
config :operator, storage_module: MyGame.PersistentStorage
```

## Integrate the Director for Events

Use the Director to generate narrative events:

```elixir
defmodule MyGame.TensionStoryteller do
  @behaviour Operator.Storyteller

  @impl true
  def init(_opts), do: %{last_event_tick: 0}

  @impl true
  def pick_event(tick, world_state, state) do
    tension = Map.get(world_state, :tension, 0.0)
    cooldown = tick - state.last_event_tick

    if tension > 0.7 and cooldown > 100 do
      event = %{
        type: :ambush,
        severity: round(tension * 5),
        location: pick_ambush_location(world_state)
      }
      {event, %{state | last_event_tick: tick}}
    else
      {nil, state}
    end
  end

  defp pick_ambush_location(world_state) do
    # Your location selection logic
    :random_location
  end
end

# Start the Director
{:ok, _pid} = Operator.Director.start_link(
  storyteller: MyGame.TensionStoryteller,
  on_event: &MyGame.EventHandler.process/1
)

# In your game loop
def tick(world_state) do
  Operator.Director.tick(world_state)
  # ...
end
```

## Create Reusable Axioms

Define query patterns once, use in many preconditions:

```elixir
defmodule MyGame.CommonAxioms do
  use Operator.HTN.DSL

  axiom :enemy_in_range do
    fn facts, args ->
      max_range = Keyword.get(args, :range, 10)
      enemy_dist = Operator.HTN.Facts.get(facts, {:world, :enemy_distance}, 999)
      enemy_dist <= max_range
    end
  end

  axiom :has_resource do
    fn facts, args ->
      resource = Keyword.get(args, :resource)
      min_amount = Keyword.get(args, :min, 1)
      amount = Operator.HTN.Facts.get(facts, {:self, resource}, 0)
      amount >= min_amount
    end
  end
end

# Use in preconditions
goal :ranged_attack do
  precond {:axiom, :enemy_in_range, range: 20}
  precond {:axiom, :has_resource, resource: :ammo, min: 1}
  # ...
end
```

## Handle Plan Invalidation

Detect when plans become invalid and replan:

```elixir
alias Operator.HTN.Planner

def tick(entity, world_state) do
  facts = build_facts(entity, world_state)

  case entity.current_plan do
    nil ->
      create_new_plan(entity, facts)

    plan ->
      # Check if world changed significantly
      if Planner.needs_replan?(plan, facts) do
        # Plan is stale, create new one
        create_new_plan(entity, facts)
      else
        execute_plan(entity, plan, facts)
      end
  end
end

defp create_new_plan(entity, facts) do
  case Planner.run(:default_goal, facts, entity.traits) do
    {:ok, plan} -> %{entity | current_plan: plan}
    {:error, _} -> entity
  end
end
```

## Use The Loop Helper

For game loops, the `Loop` helper reduces boilerplate:

```elixir
alias Operator.HTN.Loop

result = Loop.tick(entity.plan, entity, facts, entity.traits, goal: :patrol)

case result.status do
  :idle -> %{entity | plan: nil}
  :continue -> %{entity | plan: result.plan, current: result.actor}
  :completed -> %{entity | plan: nil, current: result.actor}
  :failed -> %{entity | plan: nil}
end
```

## Add Telemetry for Monitoring

Track HTN performance in production:

```elixir
defmodule MyGame.HTNTelemetry do
  @behaviour Operator.Telemetry

  @impl true
  def emit_goal_selected(goal, measurements, metadata) do
    :telemetry.execute(
      [:my_game, :htn, :goal_selected],
      measurements,
      Map.put(metadata, :goal, goal)
    )
  end

  @impl true
  def emit_htn_plan_generated(goal, task_count, duration_ms) do
    :telemetry.execute(
      [:my_game, :htn, :plan_generated],
      %{task_count: task_count, duration_ms: duration_ms},
      %{goal: goal}
    )
  end

  @impl true
  def emit_director_event(event_type, tick) do
    :telemetry.execute(
      [:my_game, :director, :event],
      %{count: 1},
      %{type: event_type, tick: tick}
    )
  end
end

# Configure
config :operator, telemetry_module: MyGame.HTNTelemetry

# Attach handlers in application start
:telemetry.attach_many("htn-metrics", [
  [:my_game, :htn, :goal_selected],
  [:my_game, :htn, :plan_generated]
], &MyGame.MetricsHandler.handle/4, nil)
```
