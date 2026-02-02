# Operator Cheatsheet

Quick reference for HTN planning with Operator.

## DSL Basics

```elixir
defmodule MyBehavior do
  use Operator.HTN.DSL

  # Goal: high-level objective
  goal :name do
    precond fn facts -> ... end
    decompose do
      task :task_name, arg1, arg2
    end
    metadata key: value
  end

  # Task: abstract, decomposes further
  task :name, arg1 do
    precond fn facts -> ... end
    decompose fn facts -> [{:subtask, []}] end
    cost 2.0
    metadata key: value
  end

  # Primitive: executable action
  primitive :name, arg1 do
    run fn actor, facts -> {:ok, actor} end
    effects [Effect.new(:plan_and_execute, {:key}, value)]
    metadata key: value
  end

  # Axiom: reusable query
  axiom :name do
    fn facts, args -> boolean end
  end
end
```

## Facts

```elixir
alias Operator.HTN.Facts

# Create
facts = Facts.from_perception(%{
  self: %{health: 100},
  world: %{time: :day},
  social: %{faction: :guards}
})
facts = Facts.new()  # Empty

# Query
Facts.has?(facts, {:self, :health})       # => true
Facts.get(facts, {:self, :health})        # => 100
Facts.get(facts, {:self, :mana}, 0)       # => 0 (default)

# Modify (returns new struct)
facts = Facts.put(facts, {:self, :health}, 80)
facts = Facts.delete(facts, {:self, :temp})
facts = Facts.merge(facts, %{self: %{mana: 50}})
```

## Preconditions

```elixir
# Simple function
precond fn facts -> Facts.has?(facts, {:self, :ready}) end

# With traits (arity-2)
precond fn facts, traits -> :brave in traits.traits end

# Logical operators
{:all, [fn1, fn2]}           # AND (all must pass)
{:any, [fn1, fn2]}           # OR (one must pass)
{:not, fn}                   # Negate
{:none, [fn1, fn2]}          # None pass
{:first, [fn1, fn2]}         # First match (ordered OR)

# Axiom reference
{:axiom, :name}
{:axiom, :name, arg: value}

# Nested
{:all, [fn1, {:any, [fn2, fn3]}]}
```

## Effects

```elixir
alias Operator.HTN.Effect

# Types
Effect.new(:plan_only, key, value)        # Planning only
Effect.new(:plan_and_execute, key, value) # Planning + execution
Effect.new(:permanent, key, value)        # Execution, persists

# In primitives
primitive :unlock do
  effects [
    Effect.new(:plan_and_execute, {:world, :door_locked}, false)
  ]
end

# Special values
Effect.new(:plan_and_execute, {:self, :ammo}, :decrement)
Effect.new(:plan_and_execute, {:self, :ammo}, :increment)
```

## Planning

```elixir
alias Operator.HTN.{Planner, GoalSelector}

# Generate plan for specific goal
{:ok, plan} = Planner.run(:goal_name, facts, traits)
{:error, :preconditions_not_met}
{:error, :goal_not_found}

# Replan decision
Planner.needs_replan?(plan, facts)

# Auto-select best goal
{:ok, goal} = GoalSelector.pick_goal(facts, traits)
:none  # No valid goals

# Options
GoalSelector.pick_goal(facts, traits,
  trait_weights: %{{:aggressive, :attack} => 10},
  goal_order: [:preferred, :fallback],
  priority_bonus: 5
)

# Score a goal without selecting it
GoalSelector.score_goal(:goal_name, facts, traits)
```

## Execution

```elixir
alias Operator.HTN.Executor

# Step-by-step (for game loops)
case Executor.step(plan, actor, facts) do
  {:ok, :continue, actor, facts, remaining_plan} -> ...
  {:ok, :completed, actor, facts, plan} -> ...
  {:error, reason, actor, facts, plan} -> ...
end

# Run entire plan
{:ok, actor, facts} = Executor.run_plan(plan, actor, facts)
{:error, reason, actor, facts, remaining_plan}

# Options
Executor.run_plan(plan, actor, facts,
  max_steps: 100,
  on_task_complete: fn task, actor, facts -> :ok end
)
```

## Plans

```elixir
alias Operator.HTN.Plan

plan.goal        # Goal name atom
plan.tasks       # [{:task, [args]}, ...]
plan.validity    # :active | :invalid | :completed

Plan.task_count(plan)
Plan.has_tasks?(plan)
Plan.valid?(plan)
Plan.next_task(plan)  # {task_tuple, remaining_plan}
Plan.add_metadata(plan, :source, "manual")
Plan.get_metadata(plan, :source)
```

## Registry

```elixir
alias Operator.HTN.Registry

Registry.all()                    # Full registry map
Registry.get_goal(:name)          # Goal definition
Registry.get_task(:name)          # Task struct
Registry.get_primitive(:name)     # Primitive struct
Registry.get_axiom(:name)         # Axiom struct

Registry.list_goal_names()
Registry.list_task_names()
Registry.list_primitive_names()
Registry.list_axiom_names()

Registry.stats()    # %{goals: n, tasks: n, ...}
Registry.reset()    # Clear all (for tests)
```

## Tracing

```elixir
alias Operator.HTN.Trace
alias Operator.HTN.Trace.ConsoleHandler

Trace.set_handler(ConsoleHandler)  # Enable console output
Trace.enabled?()                   # Check if active
Trace.get_handler()                # Current handler
Trace.reset()                      # Disable tracing
```

## Director

```elixir
alias Operator.Director

# Start
{:ok, pid} = Director.start_link(
  storyteller: MyStoryteller,
  on_event: fn event -> ... end,
  name: :my_director
)

# Tick
Director.tick(world_state)              # Async
event = Director.tick_sync(world_state) # Sync (returns event)

# Control
Director.current_tick()
Director.change_storyteller(NewModule)
Director.get_state()
```

## Storyteller Behaviour

```elixir
defmodule MyStoryteller do
  @behaviour Operator.Storyteller

  @impl true
  def init(_opts), do: %{state: :initial}

  @impl true
  def pick_event(tick, world_state, state) do
    # Return {event_map, new_state} or {nil, state}
    {%{type: :event}, state}
  end
end
```

## Storage

```elixir
alias Operator.HTN.Storage

Storage.persist_plan(entity_id, plan)
Storage.fetch_plan(entity_id)
Storage.clear_plan(entity_id)
Storage.list_plans()
Storage.clear_all()
Storage.stats()
```

## Testing

```elixir
alias Operator.HTN.TestHelpers

# In test setup
setup do
  TestHelpers.reset_registry()
  :ok
end

# Register specific modules
TestHelpers.register_modules([MyBehavior])
TestHelpers.setup_htn([Mod1, Mod2])  # Reset + register

# Isolated registry scope
TestHelpers.with_registry([MyBehavior], fn ->
  # Only MyBehavior registered here
end)

# Create test facts
facts = TestHelpers.test_facts(%{self: %{hp: 100}})

# Assertions
TestHelpers.assert_has_task(plan, :task_name)
TestHelpers.assert_has_task(plan, :task_name, [:expected_arg])
```

## Configuration

```elixir
# config/config.exs
config :operator,
  storage_module: MyApp.Storage,
  telemetry_module: MyApp.Telemetry,
  rationalization_module: MyApp.Rationalization,
  traits_module: MyApp.Traits
```

## Common Patterns

```elixir
# Game loop integration
def tick(entity, world) do
  facts = build_facts(entity, world)

  case entity.plan do
    nil -> maybe_create_plan(entity, facts)
    plan -> execute_or_replan(entity, plan, facts)
  end
end

# Conditional decomposition
task :approach do
  decompose fn facts ->
    if Facts.has?(facts, {:self, :vehicle}) do
      [{:drive_to, [target]}]
    else
      [{:walk_to, [target]}]
    end
  end
end

# Priority-based goal selection
goal :critical do
  metadata priority: 10  # Higher = more important
end

goal :idle do
  metadata priority: 1
end
```
