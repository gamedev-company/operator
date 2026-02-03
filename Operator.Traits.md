# `Operator.Traits`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/behaviours/traits.ex#L1)

Behaviour for agent personality and genome integration.

The Traits system allows you to influence HTN goal selection based on
agent-specific attributes like personality traits, genetic makeup, or
character class. This creates emergent behavior where aggressive NPCs
prefer combat goals while cautious ones prefer stealth.

## How It Works

During goal selection, the `GoalSelector` calls trait functions to compute
bonus scores for each goal. Goals with higher affinity for an agent's
traits score higher and are more likely to be selected.

```
Goal Score = base_priority + trait_bonus + archetype_bonus + ...
```

## Configuration

    config :operator,
      traits_module: MyApp.OperatorTraits

## Implementing the Behaviour

    defmodule MyApp.OperatorTraits do
      @behaviour Operator.Traits

      @impl true
      def traits(genome) do
        # Extract trait atoms from your genome/personality data
        # Genome can be any data structure your game uses
        Map.get(genome, :traits, [])
      end

      @impl true
      def trait_affinity_score(genome, goal_metadata) do
        # Return a numeric bonus based on trait-goal compatibility
        # Higher scores make the goal more attractive
        weights = Map.get(goal_metadata, :trait_weights, %{})
        my_traits = traits(genome)

        Enum.reduce(my_traits, 0, fn trait, acc ->
          acc + Map.get(weights, trait, 0)
        end)
      end

      @impl true
      def archetype_affinity_score(genome, goal_metadata) do
        # Archetype is a higher-level categorization (warrior, mage, etc.)
        archetype = Map.get(genome, :archetype)
        weights = Map.get(goal_metadata, :archetype_weights, %{})
        Map.get(weights, archetype, 0)
      end
    end

## Example: Combat vs Stealth Goals

Define goals with trait weights in metadata:

    goal :frontal_assault do
      decompose do
        task :charge_enemy
        task :melee_attack
      end
      metadata trait_weights: %{aggressive: 3, brave: 2}
    end

    goal :sneak_attack do
      decompose do
        task :find_shadows
        task :backstab
      end
      metadata trait_weights: %{sneaky: 3, patient: 2}
    end

Now an agent with `traits: [:aggressive, :brave]` will score +5 for
`:frontal_assault` but +0 for `:sneak_attack`, making them prefer
direct combat.

## Archetype System

Archetypes are coarser categories than traits. A "warrior" archetype
might encompass both "aggressive" and "brave" traits:

    goal :defend_ally do
      metadata archetype_weights: %{warrior: 5, paladin: 7}
    end

## Default Implementation

If no traits module is configured, Operator uses sensible defaults:

* `traits/1` - Returns `genome[:traits]` or empty list
* `trait_affinity_score/2` - Uses `metadata[:trait_weights]`
* `archetype_affinity_score/2` - Uses `metadata[:archetype_weights]`

## See Also

* `Operator.HTN.GoalSelector` - Uses traits for goal scoring
* `Operator.HTN.DSL` - Define trait weights in goal metadata

# `genome`

```elixir
@type genome() :: map() | nil
```

# `metadata`

```elixir
@type metadata() :: map() | nil
```

# `archetype_affinity_score`

```elixir
@callback archetype_affinity_score(genome(), metadata()) :: number()
```

Score archetype-specific affinity.

Archetypes are higher-level categorizations (e.g., "warrior", "thief")
that can influence goal selection.

# `trait_affinity_score`

```elixir
@callback trait_affinity_score(genome(), metadata()) :: number()
```

Score how well an agent's traits match goal metadata.

Returns a numeric bonus to add to goal priority scoring.

# `traits`

```elixir
@callback traits(genome()) :: [atom()]
```

Return the list of trait atoms for a genome.

Traits are used in goal selection to weight certain goals higher
for agents with matching traits.

# `archetype_affinity_score`

```elixir
@spec archetype_affinity_score(genome(), metadata()) :: number()
```

Calculate archetype affinity score, using configured module or defaults.

# `get_module`

```elixir
@spec get_module() :: module() | nil
```

Get the configured traits module.

# `trait_affinity_score`

```elixir
@spec trait_affinity_score(genome(), metadata()) :: number()
```

Calculate trait affinity score, using configured module or defaults.

# `traits`

```elixir
@spec traits(genome()) :: [atom()]
```

Get traits for a genome, using configured module or defaults.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
