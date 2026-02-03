# `Operator.HTN.TestHelpers`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/test_helpers.ex#L1)

Test utilities for working with Operator's HTN system.

This module provides helper functions for setting up and tearing down
HTN test fixtures, particularly around Registry isolation.

## Why Test Helpers?

Operator's Registry uses `persistent_term` for fast lookups, which means:

1. **Global state** - Registered modules persist across tests
2. **No automatic cleanup** - You must explicitly reset between tests
3. **Async conflicts** - Tests using Registry should use `async: false`

## Quick Start

    defmodule MyApp.BehaviorTest do
      use ExUnit.Case, async: false

      # Import the helpers
      import Operator.HTN.TestHelpers

      # Use the setup helper
      setup :reset_registry

      # Or use the full setup with module registration
      setup do
        setup_htn([MyApp.NPCBehavior, MyApp.EnemyBehavior])
      end

      test "my behavior works" do
        facts = Operator.HTN.Facts.new()
        {:ok, plan} = Operator.HTN.Planner.run(:my_goal, facts, %{})
        assert Plan.has_tasks?(plan)
      end
    end

## Setup Functions

The module provides several setup patterns:

### reset_registry/1

ExUnit setup callback that resets the registry before each test:

    setup :reset_registry

### setup_htn/1

Full setup that resets registry and registers modules:

    setup do
      setup_htn([MyBehavior])
    end

### with_registry/2

Runs a function with specific modules registered, then cleans up:

    test "isolated test" do
      with_registry [TestBehavior], fn ->
        # Test code here - registry only contains TestBehavior
      end
      # Registry is reset after block
    end

## Module Registration

When testing HTN modules, you need to ensure they're registered:

    setup do
      # Reset first to ensure clean state
      Operator.HTN.Registry.reset()

      # Ensure module is compiled
      Code.ensure_loaded!(MyBehavior)

      # Register it
      Operator.HTN.Registry.register(MyBehavior)

      :ok
    end

Or use the helper:

    setup do
      setup_htn([MyBehavior])
    end

## Async Tests

Because the Registry is global, tests that use it cannot run in parallel:

    # WRONG - will cause flaky tests
    use ExUnit.Case, async: true

    # CORRECT
    use ExUnit.Case, async: false

Tests that don't touch the Registry (e.g., pure Facts manipulation) can
safely use `async: true`.

## Examples

### Basic Test Setup

    defmodule MyApp.CombatBehaviorTest do
      use ExUnit.Case, async: false
      import Operator.HTN.TestHelpers

      alias Operator.HTN.{Facts, Plan, Planner}

      setup :reset_registry

      setup do
        # Register our behavior module
        register_modules([MyApp.CombatBehavior])
        :ok
      end

      test "attack goal generates plan when armed" do
        facts = Facts.from_perception(%{
          self: %{armed: true, ammo: 10},
          world: %{enemy_visible: true}
        })

        assert {:ok, plan} = Planner.run(:attack_enemy, facts, %{})
        assert Plan.has_tasks?(plan)
      end
    end

### Testing Multiple Behaviors

    defmodule MyApp.IntegrationTest do
      use ExUnit.Case, async: false
      import Operator.HTN.TestHelpers

      setup do
        setup_htn([
          MyApp.CombatBehavior,
          MyApp.MovementBehavior,
          MyApp.SocialBehavior
        ])
      end

      test "behaviors can reference each other" do
        # Test cross-behavior task references
      end
    end

### Isolated Test with with_registry

    defmodule MyApp.IsolatedTest do
      use ExUnit.Case, async: false
      import Operator.HTN.TestHelpers

      test "test A uses BehaviorA" do
        with_registry [BehaviorA], fn ->
          # Only BehaviorA is registered
          assert Registry.get_goal(:goal_a) != nil
          assert Registry.get_goal(:goal_b) == nil
        end
      end

      test "test B uses BehaviorB" do
        with_registry [BehaviorB], fn ->
          # Only BehaviorB is registered
          assert Registry.get_goal(:goal_a) == nil
          assert Registry.get_goal(:goal_b) != nil
        end
      end
    end

# `assert_has_task`

```elixir
@spec assert_has_task(Operator.HTN.Plan.t(), atom(), list() | nil) :: true
```

Assert that a plan contains a specific task.

## Parameters

* `plan` - The Plan struct
* `task_name` - Expected task name atom
* `args` - Optional expected arguments (if nil, only checks task name)

## Examples

    plan = Planner.run!(:attack, facts, traits)
    assert_has_task(plan, :fire_weapon)
    assert_has_task(plan, :move_to, [:enemy_position])

# `register_modules`

```elixir
@spec register_modules(module() | [module()]) :: :ok
```

Register one or more HTN modules with the Registry.

Ensures each module is loaded and then registers it.

## Parameters

* `modules` - Single module or list of modules to register

## Examples

    setup do
      reset_registry(%{})
      register_modules([MyApp.Behavior])
      :ok
    end

# `reset_registry`

```elixir
@spec reset_registry(map()) :: :ok
```

ExUnit setup callback that resets the Registry.

Use in your test module's setup:

    setup :reset_registry

This ensures each test starts with a clean, empty registry.

## Returns

Always returns `:ok`.

# `setup_htn`

```elixir
@spec setup_htn([module()]) :: :ok
```

Full setup that resets registry and registers modules.

Convenience function combining `reset_registry/1` and `register_modules/1`.

## Parameters

* `modules` - List of modules to register

## Returns

Returns `:ok` for use in ExUnit setup blocks.

## Examples

    setup do
      setup_htn([MyApp.NPCBehavior])
    end

# `test_facts`

```elixir
@spec test_facts(map()) :: Operator.HTN.Facts.t()
```

Create a test Facts struct from a simple map.

Shorthand for `Facts.from_perception/1` with a cleaner test syntax.

## Parameters

* `data` - Map with `:self`, `:world`, and/or `:social` keys

## Examples

    facts = test_facts(%{
      self: %{health: 100, armed: true},
      world: %{enemies: [:goblin]}
    })

# `with_registry`

```elixir
@spec with_registry([module()], (-&gt; any())) :: any()
```

Run a function with specific modules registered, then reset.

Useful for tests that need complete isolation from other tests.

## Parameters

* `modules` - Modules to register for the duration
* `fun` - Zero-arity function to execute

## Returns

The return value of `fun`.

## Examples

    test "isolated behavior test" do
      result = with_registry [TestBehavior], fn ->
        {:ok, plan} = Planner.run(:test_goal, facts, traits)
        plan
      end

      assert Plan.has_tasks?(result)
    end

---

*Consult [api-reference.md](api-reference.md) for complete listing*
