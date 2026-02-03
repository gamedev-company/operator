# `Operator.HTN.Loop`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/loop.ex#L1)

Convenience helpers for integrating HTN planning into tick-based loops.

The goal is to reduce boilerplate: plan if needed, execute one step, and
return a structured result.

## Example

    alias Operator.HTN.{Facts, Loop}

    facts = Facts.from_perception(%{self: %{energy: 50}})
    traits = %{archetype: :guard}

    result = Loop.tick(nil, actor, facts, traits,
      goal: :patrol
    )

    case result.status do
      :idle -> :no_plan
      :continue -> result.plan
      :completed -> :done
      :failed -> result.reason
    end

# `result`

```elixir
@type result() :: %{
  status: status(),
  actor: term(),
  facts: Operator.HTN.Facts.t(),
  plan: Operator.HTN.Plan.t() | nil,
  goal: atom() | nil,
  reason: term() | nil
}
```

# `status`

```elixir
@type status() :: :idle | :continue | :completed | :failed
```

# `tick`

```elixir
@spec tick(
  Operator.HTN.Plan.t() | nil,
  term(),
  Operator.HTN.Facts.t(),
  map(),
  keyword()
) :: result()
```

Tick the AI loop once.

- If there is no plan (or it needs replan), a new plan is created.
- If no goal is available, returns `:idle`.
- Otherwise, executes one step of the plan.

## Options

- `:goal` - specific goal atom to plan for (skips goal selection)
- `:select_goal` - custom goal selector (default: `GoalSelector.pick_goal/2`)
- `:planner_opts` - options passed to `Planner.run/4` (budgets, etc.)

---

*Consult [api-reference.md](api-reference.md) for complete listing*
