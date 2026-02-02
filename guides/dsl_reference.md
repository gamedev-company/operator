# HTN DSL Reference

This is a full reference to the HTN DSL macros.

## `use Operator.HTN.DSL`

The entry point for HTN definitions.

```elixir
defmodule MyGame.Behavior do
  use Operator.HTN.DSL
end
```

Use `auto_register: false` if you want manual control of Registry registration.

```elixir
use Operator.HTN.DSL, auto_register: false
```

## `goal`

Goals are top-level objectives. They decompose into tasks.

```elixir
goal :patrol do
  precond fn facts ->
    Operator.HTN.Facts.get(facts, {:self, :energy}, 0) > 10
  end

  decompose do
    task :move_to, :waypoint_1
    task :look_around
  end

  metadata priority: 3, domain: :routine
end
```

## `task`

Tasks are abstract steps that can decompose into other tasks or primitives.

```elixir
task :travel_to, destination do
  precond fn facts ->
    Operator.HTN.Facts.has?(facts, {:self, :can_move})
  end

  decompose fn facts ->
    has_vehicle = Operator.HTN.Facts.has?(facts, {:self, :vehicle})
    if has_vehicle, do: [{:drive_to, [destination]}], else: [{:walk_to, [destination]}]
  end

  cost 2.0
  metadata kind: :movement
end
```

## `primitive`

Primitives are executable actions. They must define `run`.

```elixir
primitive :move_to, destination do
  run fn actor, _facts ->
    {:ok, %{actor | position: destination}}
  end

  effects [
    Operator.HTN.Effect.new(:plan_and_execute, {:self, :position}, destination)
  ]

  metadata kind: :movement
end
```

## `axiom`

Axioms are reusable precondition helpers.

```elixir
axiom :enemy_in_range do
  fn facts, args ->
    max_range = Keyword.get(args, :range, 10)
    dist = Operator.HTN.Facts.get(facts, {:world, :enemy_distance}, 999)
    dist <= max_range
  end
end
```

Use them in preconditions.

```elixir
goal :ranged_attack do
  precond {:axiom, :enemy_in_range, range: 20}
  decompose do
    task :aim
    task :fire
  end
end
```

## `precond`

Preconditions control eligibility. You can use anonymous functions or logical
operators. Preconditions are stored as a list of conditions and evaluated at
runtime via `Operator.HTN.Precondition`.

```elixir
precond fn facts ->
  Operator.HTN.Facts.has?(facts, {:self, :weapon})
end
```

Logical operators:

```elixir
{:all, [fn1, fn2]}
{:any, [fn1, fn2]}
{:not, fn1}
{:none, [fn1, fn2]}
{:first, [fn1, fn2]}
{:axiom, :enemy_in_range, range: 10}

To evaluate goal preconditions manually:

```elixir
goal = Operator.HTN.Registry.get_goal(:patrol)
Operator.HTN.Precondition.all_satisfied?(goal.precond, facts, traits)
```
```

## `decompose`

Decomposition can be a static block or a function.

```elixir
decompose do
  task :move_to, :door
  task :open_door
end
```

```elixir
decompose fn facts ->
  if Operator.HTN.Facts.has?(facts, {:self, :has_key}) do
    [{:unlock, []}, {:enter, []}]
  else
    [{:find_key, []}]
  end
end
```

## `cost`

Costs influence plan selection when multiple options are valid.

```elixir
cost 1.0
```

```elixir
cost fn facts ->
  danger = Operator.HTN.Facts.get(facts, {:world, :danger}, 1.0)
  5.0 * danger
end
```

## `effects`

Effects describe how world state changes.

```elixir
effects [
  Operator.HTN.Effect.new(:plan_and_execute, {:world, :door_unlocked}, true)
]
```

Effect types:

- `:plan_only`
- `:plan_and_execute`
- `:permanent`

## `metadata`

Attach arbitrary metadata for goal selection and analytics.

```elixir
metadata priority: 5, domain: :combat, required_traits: [:aggressive]
```

You can also declare required fact keys for validation and diagnostics:

```elixir
metadata requires_facts: [{:self, :energy}, {:world, :threat_level}]
```

## DSL Gotchas

- `precond` and `decompose` run at runtime, not compile time.
- Use fully qualified module names in those functions.
- Keep side effects out of preconditions.
