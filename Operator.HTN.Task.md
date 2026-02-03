# `Operator.HTN.Task`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/task.ex#L1)

A task in the HTN hierarchy.

Tasks are the building blocks of HTN planning. They form a hierarchy where
high-level objectives decompose into lower-level actions, ultimately reaching
executable primitives.

## Task Types

* **Abstract** - High-level tasks that decompose into subtasks. They represent
  "what to do" without specifying exactly how. Abstract tasks have a `decompose`
  function that breaks them down further.

* **Primitive** - Leaf-level tasks that are directly executable. They represent
  concrete actions your game can perform (move, attack, interact, etc.).

## Task Anatomy

Every task has these components:

| Component       | Required | Description                                      |
|-----------------|----------|--------------------------------------------------|
| `name`          | Yes      | Atom identifier (`:attack`, `:move_to`)          |
| `type`          | Yes      | `:abstract` or `:primitive`                      |
| `preconditions` | No       | List of conditions that must be true             |
| `decompose`     | No*      | Function returning subtask list (abstract only)  |
| `effects`       | No       | World state changes when task completes          |
| `cost`          | No       | Planning heuristic (number or function)          |
| `metadata`      | No       | Arbitrary data (animations, sounds, tags)        |

*Abstract tasks without decomposition are treated as primitives during planning.

## Preconditions

Preconditions gate whether a task can be planned. They're evaluated against
the current (or projected) world state during planning.

    preconditions: [
      fn facts -> Facts.has?(facts, {:self, :weapon}) end,
      fn facts -> Facts.get(facts, {:self, :ammo}, 0) > 0 end
    ]

See `Operator.HTN.Precondition` for logical operators (`:any`, `:all`, etc.).

## Effects

Effects represent world state changes that result from task execution. During
planning, effects are applied to a working copy of world state so the planner
can reason about future states and validate downstream preconditions.

For example, if `:unlock_door` has effect `door_unlocked: true`, then a
subsequent `:enter_room` task with precondition `door_unlocked == true` will
pass during planning.

See `Operator.HTN.Effect` for effect types and usage.

## Cost Functions

Costs influence which plan the planner prefers when multiple valid plans exist.
They can be:

* **Static** - A simple number: `cost: 5.0`
* **Dynamic** - Based on world state: `cost: fn facts -> distance_factor(facts) end`
* **Trait-aware** - Influenced by agent personality:
  `cost: fn facts, traits -> base_cost(facts) * aggression_modifier(traits) end`

## Examples

### Abstract Task with Decomposition

    task = Task.new(:travel_to, :abstract,
      preconditions: [fn facts -> Facts.has?(facts, {:self, :can_move}) end],
      decompose: fn facts ->
        destination = Facts.get(facts, {:self, :destination})
        [{:pathfind, [destination]}, {:walk_path, []}]
      end,
      cost: 5.0
    )

### Primitive Task with Effects

    task = Task.new(:attack, :primitive,
      preconditions: [fn facts -> Facts.has?(facts, {:self, :has_weapon}) end],
      effects: [
        Effect.new(:plan_and_execute, {:self, :in_combat}, true),
        Effect.new(:plan_and_execute, {:self, :ammo}, :decrement)
      ],
      cost: fn facts, traits ->
        base = Facts.get(facts, {:world, :enemy_threat_level}, 1.0)
        aggression = Map.get(traits, :aggression, 1.0)
        base / aggression  # Aggressive agents find attacking "cheaper"
      end,
      metadata: %{animation: "attack_01", sound: "sword_swing.wav"}
    )

## See Also

* `Operator.HTN.DSL` - Declarative task definition
* `Operator.HTN.Effect` - World state modifications
* `Operator.HTN.Precondition` - Logical operators
* `Operator.HTN.Executor` - Task execution at runtime

# `t`

```elixir
@type t() :: %Operator.HTN.Task{
  cost: number() | function() | nil,
  decompose: function() | nil,
  effects: [Operator.HTN.Effect.t()] | nil,
  metadata: map(),
  name: atom(),
  preconditions: [Operator.HTN.Precondition.condition()],
  type: task_type()
}
```

The Task struct representing a node in the HTN hierarchy.

## Fields

* `:name` - Atom identifier for the task
* `:type` - Either `:abstract` or `:primitive`
* `:preconditions` - List of conditions that must be satisfied
* `:decompose` - Function returning subtask list (abstract tasks only)
* `:effects` - List of `Effect` structs applied on completion
* `:cost` - Static number or function for planning heuristics
* `:metadata` - Arbitrary map for game-specific data

# `task_type`

```elixir
@type task_type() :: :abstract | :primitive
```

The type of task in the HTN hierarchy.

* `:abstract` - Decomposes into subtasks
* `:primitive` - Directly executable leaf node

# `abstract?`

```elixir
@spec abstract?(t()) :: boolean()
```

Check if this task is abstract (decomposes into subtasks).

Abstract tasks represent high-level objectives that break down into
lower-level tasks during planning.

## Examples

    iex> task = Task.new(:patrol, :abstract)
    iex> Task.abstract?(task)
    true

    iex> task = Task.new(:fire, :primitive)
    iex> Task.abstract?(task)
    false

# `calculate_cost`

```elixir
@spec calculate_cost(t(), Operator.HTN.Facts.t(), map()) :: number()
```

Calculate task cost for planning heuristics.

Cost influences plan selection when multiple valid plans exist. Lower cost
plans are generally preferred.

## Cost Types

* **Static number** - Fixed cost regardless of world state
* **Arity-1 function** - `fn facts -> number end`
* **Arity-2 function** - `fn facts, traits -> number end`

## Parameters

* `task` - The Task struct
* `facts` - Current world state
* `traits` - Agent traits/genome for personality-influenced costs

## Returns

A number representing the task's cost. Defaults to `1.0` if no cost specified.

## Examples

    # Static cost
    task = Task.new(:walk, :primitive, cost: 5.0)
    Task.calculate_cost(task, facts, traits)
    #=> 5.0

    # Dynamic cost based on distance
    task = Task.new(:travel, :abstract,
      cost: fn facts ->
        Facts.get(facts, {:world, :distance_to_target}, 10) * 0.5
      end
    )

    # Trait-influenced cost (aggressive NPCs find combat "cheaper")
    task = Task.new(:attack, :primitive,
      cost: fn _facts, traits ->
        10.0 / Map.get(traits, :aggression, 1.0)
      end
    )

# `new`

```elixir
@spec new(atom(), task_type(), keyword()) :: t()
```

Create a new task.

While the DSL is the recommended way to define tasks, this function provides
programmatic task creation for dynamic scenarios or testing.

## Parameters

* `name` - Atom identifier for the task
* `type` - Either `:abstract` or `:primitive`
* `opts` - Keyword list of options

## Options

* `:preconditions` - List of predicate functions (default: `[]`)
* `:decompose` - Function returning subtask list (default: `nil`)
* `:effects` - List of Effect structs (default: `[]`)
* `:cost` - Static cost or cost function (default: `1.0`)
* `:metadata` - Arbitrary metadata (default: `%{}`)

## Examples

    # Simple primitive
    Task.new(:wait, :primitive)

    # Abstract with decomposition
    Task.new(:patrol, :abstract,
      decompose: fn _facts -> [{:walk_to, [:waypoint_1]}, {:look_around, []}] end
    )

    # Full-featured primitive
    Task.new(:fire_weapon, :primitive,
      preconditions: [
        fn facts -> Facts.get(facts, {:self, :ammo}, 0) > 0 end
      ],
      effects: [
        Effect.new(:plan_and_execute, {:self, :fired_weapon}, true)
      ],
      cost: 2.0,
      metadata: %{animation: "shoot", cooldown_ms: 500}
    )

# `preconditions_satisfied?`

```elixir
@spec preconditions_satisfied?(t(), Operator.HTN.Facts.t(), map()) :: boolean()
```

Check if all preconditions are satisfied.

Preconditions can be:
- Simple functions: `fn facts -> boolean end` or `fn facts, traits -> boolean end`
- Logical operators: `{:any, [fns]}`, `{:all, [fns]}`, `{:first, [fns]}`, `{:not, fn}`

All preconditions in the list are combined with AND semantics.

## Examples

    # Simple function
    preconditions: [fn facts -> Facts.has?(facts, {:self, :ready}) end]

    # OR operator: has weapon OR near pickup
    preconditions: [
      {:any, [
        fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
        fn facts -> Facts.has?(facts, {:world, :weapon_nearby}) end
      ]}
    ]

    # Combined: ready AND (armed OR near weapon)
    preconditions: [
      fn facts -> Facts.has?(facts, {:self, :ready}) end,
      {:any, [
        fn facts -> Facts.has?(facts, {:self, :armed}) end,
        fn facts -> Facts.has?(facts, {:world, :weapon_nearby}) end
      ]}
    ]

# `primitive?`

```elixir
@spec primitive?(t()) :: boolean()
```

Check if this task is primitive (directly executable).

Primitive tasks are the leaf nodes of the HTN tree - they don't decompose
further and are executed directly by the `Executor`.

## Examples

    iex> task = Task.new(:attack, :primitive)
    iex> Task.primitive?(task)
    true

    iex> task = Task.new(:combat_sequence, :abstract)
    iex> Task.primitive?(task)
    false

---

*Consult [api-reference.md](api-reference.md) for complete listing*
