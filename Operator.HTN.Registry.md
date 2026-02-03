# `Operator.HTN.Registry`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/registry.ex#L1)

Central storage for HTN goals, tasks, primitives, and axioms.

The Registry aggregates all HTN behavior modules into a single lookup table,
enabling the planner and executor to find definitions by name. It uses
`persistent_term` for essentially free read access after initialization.

## How It Works

1. **Compile time**: Modules using `Operator.HTN.DSL` define goals/tasks/primitives
2. **After compile**: The `@after_compile` hook calls `register/1`
3. **Runtime**: The planner calls `get_goal/2`, `get_primitive/2`, etc.

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  MyBehavior.ex   │     │  EnemyAI.ex      │     │  PatrolBehavior  │
│  use HTN.DSL     │     │  use HTN.DSL     │     │  use HTN.DSL     │
└────────┬─────────┘     └────────┬─────────┘     └────────┬─────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  ▼
                       ┌──────────────────────┐
                       │      Registry        │
                       │  (persistent_term)   │
                       │                      │
                       │  goals: %{...}       │
                       │  tasks: %{...}       │
                       │  primitives: %{...}  │
                       │  axioms: %{...}      │
                       └──────────────────────┘
```

## Auto-Registration

Modules using `Operator.HTN.DSL` are automatically registered after compilation.
To disable this (useful for testing):

    use Operator.HTN.DSL, auto_register: false

## Manual Registration

    # Register a single module
    Operator.HTN.Registry.register(MyHTNModule)

    # Force refresh from all registered modules
    Operator.HTN.Registry.refresh()

## Lookup Functions

    # Get the full registry map
    registry = Registry.all()
    #=> %{goals: %{...}, tasks: %{...}, primitives: %{...}, axioms: %{...}}

    # Get specific items by name
    goal = Registry.get_goal(:acquire_data)
    task = Registry.get_task(:move_to)
    primitive = Registry.get_primitive(:attack)
    axiom = Registry.get_axiom(:enemy_nearby)

    # List all registered names
    Registry.list_goal_names()
    #=> [:patrol, :attack, :flee, :idle]

    # Get statistics
    Registry.stats()
    #=> %{goals: 5, tasks: 12, primitives: 8, axioms: 3}

## Testing Considerations

The Registry uses `persistent_term`, which is global state. For test isolation:

1. Use `async: false` on test modules that touch the Registry
2. Call `Registry.reset()` in setup to ensure clean state
3. Use `Operator.HTN.TestHelpers` for convenient setup functions

    defmodule MyTest do
      use ExUnit.Case, async: false
      import Operator.HTN.TestHelpers

      setup :reset_registry

      setup do
        register_modules([MyBehavior])
        :ok
      end
    end

## Performance

* **Reads**: O(1) via `persistent_term` - essentially free
* **Writes**: Relatively expensive (copies data), but only happens at registration
* **Memory**: All registered modules share a single persistent_term entry

## See Also

* `Operator.HTN.DSL` - How modules define HTN structures
* `Operator.HTN.TestHelpers` - Test utilities including `reset_registry/1`
* `Operator.HTN.Planner` - Uses Registry to look up goals

# `registry`

```elixir
@type registry() :: %{goals: map(), tasks: map(), primitives: map(), axioms: map()}
```

The registry map containing all HTN definitions.

## Fields

* `:goals` - Map of goal name atoms to goal definitions
* `:tasks` - Map of task name atoms to `%Task{}` structs
* `:primitives` - Map of primitive name atoms to `%Task{}` structs
* `:axioms` - Map of axiom name atoms to `%Axiom{}` structs

# `all`

```elixir
@spec all() :: registry()
```

Returns the merged registry containing all registered definitions.

This is the primary read function - it returns everything in one map
for efficient batch access by the planner.

## Returns

A map with `:goals`, `:tasks`, `:primitives`, and `:axioms` keys.

## Examples

    registry = Registry.all()
    goal = registry.goals[:patrol]
    primitive = registry.primitives[:fire_weapon]

# `get_axiom`

```elixir
@spec get_axiom(atom(), registry()) :: Operator.HTN.Axiom.t() | nil
```

Get an axiom by name.

Axioms are reusable query patterns for preconditions.

## Parameters

* `name` - The axiom atom (e.g., `:enemy_nearby`, `:has_weapon`)
* `registry` - Optional registry map (defaults to `all()`)

## Returns

The `%Axiom{}` struct if found, `nil` otherwise.

## Examples

    axiom = Registry.get_axiom(:enemy_in_range)
    #=> %Axiom{name: :enemy_in_range, query_fn: #Function<...>}

    # Evaluate axiom
    Axiom.evaluate(axiom, facts, max_range: 10)
    #=> true

# `get_goal`

```elixir
@spec get_goal(atom(), registry()) :: map() | nil
```

Get a goal definition by name.

Goals are high-level objectives that decompose into task sequences.

## Parameters

* `name` - The goal atom (e.g., `:patrol`, `:attack`)
* `registry` - Optional registry map (defaults to `all()`)

## Returns

The goal map if found, `nil` otherwise.

## Examples

    goal = Registry.get_goal(:infiltrate)
    #=> %{name: :infiltrate, precond: #Function<...>, decompose: [...]}

    Registry.get_goal(:nonexistent)
    #=> nil

# `get_primitive`

```elixir
@spec get_primitive(atom(), registry()) :: Operator.HTN.Task.t() | nil
```

Get a primitive by name.

Primitives are directly executable actions - the leaf nodes of the HTN tree.

## Parameters

* `name` - The primitive atom (e.g., `:attack`, `:wait`, `:move`)
* `registry` - Optional registry map (defaults to `all()`)

## Returns

The `%Task{}` struct (with `type: :primitive`) if found, `nil` otherwise.

## Examples

    primitive = Registry.get_primitive(:fire_weapon)
    #=> %Task{name: :fire_weapon, type: :primitive, metadata: %{run: ...}}

    # Use with Executor
    {:ok, actor} = Executor.execute_primitive(primitive, actor, facts)

# `get_task`

```elixir
@spec get_task(atom(), registry()) :: Operator.HTN.Task.t() | nil
```

Get an abstract task by name.

Tasks are intermediate steps that decompose into subtasks or primitives.

## Parameters

* `name` - The task atom (e.g., `:move_to`, `:prepare_weapon`)
* `registry` - Optional registry map (defaults to `all()`)

## Returns

The `%Task{}` struct if found, `nil` otherwise.

## Examples

    task = Registry.get_task(:travel_to)
    #=> %Task{name: :travel_to, type: :abstract, ...}

# `list_axiom_names`

```elixir
@spec list_axiom_names() :: [atom()]
```

List all registered axiom names.

## Returns

List of axiom atom names.

## Examples

    Registry.list_axiom_names()
    #=> [:enemy_nearby, :has_ammo, :in_cover]

# `list_goal_names`

```elixir
@spec list_goal_names() :: [atom()]
```

List all registered goal names.

## Returns

List of goal atom names.

## Examples

    Registry.list_goal_names()
    #=> [:patrol, :attack, :flee, :idle]

# `list_primitive_names`

```elixir
@spec list_primitive_names() :: [atom()]
```

List all registered primitive names.

## Returns

List of primitive atom names.

## Examples

    Registry.list_primitive_names()
    #=> [:walk, :fire, :reload, :wait]

# `list_task_names`

```elixir
@spec list_task_names() :: [atom()]
```

List all registered abstract task names.

## Returns

List of task atom names.

## Examples

    Registry.list_task_names()
    #=> [:move_to, :prepare_weapon, :find_cover]

# `merge`

```elixir
@spec merge([map()]) :: registry()
```

Merge multiple registry fragments into one.

Used internally to combine definitions from multiple modules. Later entries
override earlier ones if names conflict.

## Parameters

* `registries` - List of registry maps

## Returns

A single merged registry map.

# `modules`

```elixir
@spec modules() :: [module()]
```

Returns the list of currently registered modules.

Useful for debugging or saving/restoring registry state in tests.

## Returns

List of module atoms.

## Examples

    Registry.modules()
    #=> [MyGame.CombatBehavior, MyGame.PatrolBehavior]

# `refresh`

```elixir
@spec refresh(Enum.t()) :: :ok
```

Forces a refresh of the registry from registered modules.

Reloads all module definitions and rebuilds the merged registry. This is
called automatically by `register/1` but can be called manually if you
suspect the registry is stale.

## Parameters

* `modules` - Optional module list (defaults to all registered modules)

## Returns

`:ok` after rebuilding the registry.

# `register`

```elixir
@spec register(module()) :: :ok
```

Registers an HTN module and refreshes the merged registry.

The module must export `__htn__/0`, which is automatically generated by
`use Operator.HTN.DSL`. This function is typically called automatically
via `@after_compile`, but can be called manually for dynamic registration.

## Parameters

* `module` - The module atom to register

## Returns

`:ok` on success. Silently succeeds if module doesn't export `__htn__/0`.

## Examples

    # Manual registration (usually not needed)
    Operator.HTN.Registry.register(MyGame.CombatBehavior)

    # Verify registration
    Registry.list_goal_names()
    #=> [:attack, :defend, :flee]

# `reset`

```elixir
@spec reset() :: :ok
```

Resets the registry to empty state.

Clears all registered modules and definitions. Essential for test isolation
since the registry uses global `persistent_term` storage.

## Returns

`:ok` after clearing.

## Examples

    # In test setup
    setup do
      Operator.HTN.Registry.reset()
      :ok
    end

## See Also

* `Operator.HTN.TestHelpers.reset_registry/1` - ExUnit-friendly wrapper

# `stats`

```elixir
@spec stats() :: %{
  goals: non_neg_integer(),
  tasks: non_neg_integer(),
  primitives: non_neg_integer(),
  axioms: non_neg_integer()
}
```

Return counts for each category.

Useful for debugging and monitoring registry state.

## Returns

Map with counts for goals, tasks, primitives, and axioms.

## Examples

    Registry.stats()
    #=> %{goals: 5, tasks: 12, primitives: 8, axioms: 3}

---

*Consult [api-reference.md](api-reference.md) for complete listing*
