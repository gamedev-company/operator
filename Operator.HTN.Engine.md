# `Operator.HTN.Engine`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/engine.ex#L1)

HTN engine for goal expansion, precondition evaluation, and plan generation.

The engine implements **total-order forward decomposition**, the HTN planning
approach described in GameAIPro. This means:

1. Tasks are expanded in order (total-order)
2. Planning proceeds forward from the current state
3. Effects are applied during planning to simulate future states

## Planning Algorithm

1. Look up the goal in the registry
2. Check goal preconditions against current facts
3. Decompose goal into tasks via its decompose function
4. For each task:
   - If abstract: check preconditions, decompose recursively
   - If primitive: check preconditions, collect into plan, apply effects
5. Return the plan (list of primitive tasks)

## Effects During Planning

A key feature of HTN planning is that effects are applied to a working copy
of world state during planning. This allows downstream tasks to have their
preconditions validated against the expected future state.

For example, if task A has effect "has_key=true" and task B has precondition
"has_key", then B's precondition will be satisfied when planning A before B.

## Usage

    facts = Operator.HTN.Facts.from_perception(%{
      self: %{location: :lobby},
      world: %{target: :server_room}
    })

    case Engine.expand(:infiltrate, facts, %{}) do
      {:ok, plan} ->
        # plan.tasks contains the sequence of primitives
        IO.inspect(plan.tasks)

      {:error, :preconditions_not_met} ->
        # Goal preconditions failed
        :retry_later

      {:error, :goal_not_found} ->
        # Goal not registered
        :unknown_goal
    end

# `expand`

```elixir
@spec expand(atom(), Operator.HTN.Facts.t(), map(), map(), keyword()) ::
  {:ok, Operator.HTN.Plan.t()} | {:error, term()}
```

Expand a goal into a plan.

## Arguments

- `goal_name` - The goal atom to expand
- `facts` - Current world state
- `traits` - Agent traits/genome for cost calculations
- `htn_registry` - Optional registry (defaults to `Registry.all()`)
- `opts` - Options:
  - `:budget` - Budget limits (e.g., `[max_tasks: 100, max_expansions: 200, max_depth: 20, timeout_ms: 5]`)

## Returns

- `{:ok, plan}` - Successfully expanded plan
- `{:error, :goal_not_found}` - Goal not in registry
- `{:error, :preconditions_not_met}` - Goal preconditions failed

# `goal_preconditions_met?`

```elixir
@spec goal_preconditions_met?(map(), Operator.HTN.Facts.t(), map()) :: boolean()
```

Check if a goal's preconditions are met.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
