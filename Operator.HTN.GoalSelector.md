# `Operator.HTN.GoalSelector`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/goal_selector.ex#L1)

Automatic goal selection for agents based on world state and personality.

The GoalSelector answers the question "What should this NPC do right now?"
by evaluating all registered goals and picking the best match based on:

1. **Preconditions** - Goals whose preconditions fail are filtered out
2. **Base priority** - From goal metadata (`:priority` key)
3. **Trait affinity** - How well agent traits match the goal
4. **Archetype affinity** - Class/role bonuses (warrior prefers combat, etc.)
5. **World context** - Environmental modifiers (tension, location type)

## Scoring Formula

```
score = base_priority
      + config_trait_bonus      # From :htn_trait_weights config
      + metadata_trait_score    # From goal metadata trait_weights
      + archetype_score         # From goal metadata archetype_weights
      + world_context_bonus     # Based on tension and land_use
      + priority_bonus          # From options
```

## Basic Usage

    facts = Facts.from_perception(%{
      self: %{health: 80, armed: true},
      world: %{tension: 0.7, land_use: :corporate}
    })

    traits = %{
      archetype: :street_sam,
      traits: [:aggressive, :territorial]
    }

    case GoalSelector.pick_goal(facts, traits) do
      {:ok, goal_name} ->
        Planner.run(goal_name, facts, traits)

      :none ->
        # No eligible goals - agent idles
        :idle
    end

## Goal Metadata for Selection

Goals can include metadata that influences selection:

    goal :attack_enemy do
      precond fn facts -> Facts.has?(facts, {:world, :enemy_visible}) end

      decompose do
        task :engage
      end

      metadata(
        priority: 8,                           # Base priority
        domain: :combat,                       # World context domain
        required_traits: [:aggressive],        # Must have one of these
        trait_weights: %{aggressive: 2},       # Bonus for traits
        archetype_weights: %{warrior: 3}       # Bonus for archetypes
      )
    end

## Configuration

Global trait-goal weights can be configured:

    config :operator,
      htn_trait_weights: %{
        {:aggressive, :attack} => 5,
        {:cautious, :scout} => 3,
        {:greedy, :loot} => 4
      }

## Tie-Breaking

When goals have equal scores, you can provide a deterministic order:

    GoalSelector.pick_goal(facts, traits,
      goal_order: [:defend, :patrol, :idle]
    )

Goals in the list are preferred over goals not in the list.

## Debugging Selection

Use `score_goal/4` to understand why a goal was or wasn't selected:

    GoalSelector.score_goal(:attack, facts, traits)
    #=> 12.5

    GoalSelector.score_goal(:flee, facts, traits)
    #=> 8.0

## World Context Bonuses

The selector applies environmental modifiers based on domain and location:

| Domain     | Location    | Tension Multiplier |
|------------|-------------|-------------------|
| :security  | :corporate  | 0.5               |
| :security  | :industrial | 0.4               |
| :street    | :barrens    | 0.6               |
| :street    | :mixed      | 0.3               |
| (other)    | (other)     | 0.1               |

## See Also

* `Operator.HTN.Planner` - Generates plans for selected goals
* `Operator.Traits` - Trait/archetype system
* `Operator.Telemetry` - Goal selection events

# `explain`

```elixir
@spec explain(Operator.HTN.Facts.t(), map(), keyword()) :: map()
```

Explain goal selection with scores and eligibility.

Returns a map with the selected goal, eligible/ineligible goals, and
scoring details. This is intended for debugging and UI tooling.

## Example

    result = GoalSelector.explain(facts, traits)
    result.selected
    #=> :patrol

    Enum.map(result.eligible, & &1.goal)
    #=> [:patrol, :idle]

# `pick_goal`

```elixir
@spec pick_goal(Operator.HTN.Facts.t(), map(), keyword()) :: {:ok, atom()} | :none
```

Selects the highest-priority eligible goal for an agent.

Evaluates all registered goals, filters by preconditions and trait
requirements, scores the remainder, and returns the best match.

## Parameters

* `facts` - Current world state (`Facts.t()`)
* `traits` - Agent traits/genome map
* `opts` - Options (see below)

## Options

* `:trait_weights` - Map of `{trait, goal}` to integer bonuses.
  Overrides the global `:htn_trait_weights` config.
* `:goal_order` - List of goal atoms for deterministic tie-breaking.
  Goals earlier in the list win ties.
* `:priority_bonus` - Scalar added to every goal's score.

## Returns

* `{:ok, goal_name}` - The highest-scoring eligible goal
* `:none` - No goals passed preconditions

## Examples

    # Basic usage
    case GoalSelector.pick_goal(facts, traits) do
      {:ok, :patrol} -> Planner.run(:patrol, facts, traits)
      :none -> :idle
    end

    # With options
    GoalSelector.pick_goal(facts, traits,
      trait_weights: %{{:aggressive, :attack} => 10},
      goal_order: [:defend, :attack, :patrol],
      priority_bonus: 2
    )

## Telemetry

Emits `Telemetry.emit_goal_selected/3` with the selected goal and score.

# `score_goal`

```elixir
@spec score_goal(atom(), Operator.HTN.Facts.t(), map(), keyword()) :: number() | nil
```

Score a specific goal for an agent without selecting it.

Useful for debugging goal selection or building custom selection logic.

## Parameters

* `goal_name` - The goal atom to score
* `facts` - Current world state
* `traits` - Agent traits/genome
* `opts` - Same options as `pick_goal/3`

## Returns

* `number()` - The computed score
* `nil` - Goal not found in registry

## Examples

    # Debug why one goal beats another
    attack_score = GoalSelector.score_goal(:attack, facts, traits)
    #=> 12.5

    flee_score = GoalSelector.score_goal(:flee, facts, traits)
    #=> 8.0

    # Attack wins because aggressive trait gives +5 bonus

---

*Consult [api-reference.md](api-reference.md) for complete listing*
