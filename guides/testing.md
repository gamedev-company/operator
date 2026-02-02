# Testing

This guide is ruthless about keeping tests deterministic when using HTN planning.

## The Core Rule

The HTN Registry is global state. Treat it like a singleton cache that must be
reset or isolated for every test that touches it.

## Safe Defaults

Use these defaults unless you have a strong reason not to.

- `async: false` for any test that touches the Registry or plans.
- `Operator.HTN.TestHelpers.reset_registry/0` in setup.
- `Operator.HTN.TestHelpers.register_modules/1` for the behaviors under test.

```elixir
defmodule MyGame.BehaviorTest do
  use ExUnit.Case, async: false

  import Operator.HTN.TestHelpers
  alias Operator.HTN.{Facts, Planner}

  setup :reset_registry

  setup do
    register_modules([MyGame.GuardBehavior])
    :ok
  end

  test "patrol goal produces tasks" do
    facts = Facts.from_perception(%{self: %{energy: 50}})
    {:ok, plan} = Planner.run(:patrol, facts, %{})
    assert length(plan.tasks) > 0
  end
end
```

## Isolating One Test

Use `with_registry/2` to scope the Registry to only the modules you need.

```elixir
test "single behavior isolated" do
  Operator.HTN.TestHelpers.with_registry([MyGame.GuardBehavior], fn ->
    assert :patrol in Operator.HTN.Registry.list_goal_names()
  end)
end
```

## Common Test Patterns

Plan generation pattern:

```elixir
facts = Operator.HTN.TestHelpers.test_facts(%{self: %{can_move: true}})
{:ok, plan} = Operator.HTN.Planner.run(:patrol, facts, %{})
Operator.HTN.TestHelpers.assert_has_task(plan, :move_to)
```

Executor step pattern:

```elixir
actor = %{id: 1, position: :start}
{:ok, plan} = Operator.HTN.Planner.run(:patrol, facts, %{})
{:ok, :continue, actor, _facts, remaining} = Operator.HTN.Executor.step(plan, actor, facts)
assert length(remaining.tasks) >= 0
```

## Doctests

Doctests are great for verifying examples. Keep them deterministic and minimal.

- Do not rely on random data in doctests.
- Do not rely on global Registry state without explicit setup.
- Keep outputs simple and stable.

## Checklist

- Registry is reset.
- Behaviors are registered.
- Facts are deterministic.
- Tests are `async: false` when needed.
- Trace is disabled by default.
