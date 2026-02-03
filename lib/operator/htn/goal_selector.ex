defmodule Operator.HTN.GoalSelector do
  @moduledoc """
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

      config :ex_operator,
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

  """

  alias Operator.HTN.{Facts, Precondition, Registry}
  alias Operator.{Telemetry, Traits}

  @doc """
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

  """
  @spec pick_goal(Facts.t(), map(), keyword()) :: {:ok, atom()} | :none
  def pick_goal(facts, traits, opts \\ []) do
    goals = Registry.all() |> Map.get(:goals, %{})
    trait_weights = Keyword.get(opts, :trait_weights, default_trait_weights())
    goal_order = Keyword.get(opts, :goal_order, [])

    goals
    |> Enum.map(fn {name, goal} ->
      {score(goal, trait_weights, traits, opts, facts), name, goal}
    end)
    |> Enum.filter(fn {_score, _name, goal} ->
      precond_ok?(goal, facts, traits)
    end)
    |> Enum.sort(&goal_sort(&1, &2, goal_order))
    |> case do
      [{score, name, goal} | _rest] ->
        emit_goal_selection(name, goal, score)
        {:ok, name}

      [] ->
        Telemetry.emit_goal_selected(:none, %{score: 0})
        :none
    end
  end

  @doc """
  Explain goal selection with scores and eligibility.

  Returns a map with the selected goal, eligible/ineligible goals, and
  scoring details. This is intended for debugging and UI tooling.

  ## Example

      result = GoalSelector.explain(facts, traits)
      result.selected
      #=> :patrol

      Enum.map(result.eligible, & &1.goal)
      #=> [:patrol, :idle]

  """
  @spec explain(Facts.t(), map(), keyword()) :: map()
  def explain(facts, traits, opts \\ []) do
    goals = Registry.all() |> Map.get(:goals, %{})
    trait_weights = Keyword.get(opts, :trait_weights, default_trait_weights())
    goal_order = Keyword.get(opts, :goal_order, [])

    scored =
      goals
      |> Enum.map(fn {name, goal} ->
        score = score(goal, trait_weights, traits, opts, facts)
        eligibility = eligibility(goal, facts, traits)
        {score, name, goal, eligibility}
      end)

    {eligible, ineligible} =
      Enum.split_with(scored, fn {_score, _name, _goal, eligibility} ->
        eligibility == :ok
      end)

    eligible_sorted =
      eligible
      |> Enum.sort(fn {score_a, name_a, _goal_a, _},
                     {score_b, name_b, _goal_b, _} ->
        goal_sort({score_a, name_a, nil}, {score_b, name_b, nil}, goal_order)
      end)

    selected =
      case eligible_sorted do
        [{_score, name, _goal, _} | _] -> name
        [] -> nil
      end

    %{
      selected: selected,
      eligible:
        Enum.map(eligible_sorted, fn {score, name, goal, _} ->
          missing_facts = missing_required_facts(goal, facts)
          %{
            goal: name,
            score: score,
            metadata: Map.get(goal, :metadata, %{}),
            missing_facts: missing_facts
          }
        end),
      ineligible:
        Enum.map(ineligible, fn {_score, name, goal, reason} ->
          missing_facts = missing_required_facts(goal, facts)
          %{
            goal: name,
            reason: reason,
            metadata: Map.get(goal, :metadata, %{}),
            missing_facts: missing_facts
          }
        end),
      options: %{
        goal_order: goal_order,
        priority_bonus: Keyword.get(opts, :priority_bonus),
        trait_weights: trait_weights
      }
    }
  end

  @doc """
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

  """
  @spec score_goal(atom(), Facts.t(), map(), keyword()) :: number() | nil
  def score_goal(goal_name, facts, traits, opts \\ []) do
    goals = Registry.all() |> Map.get(:goals, %{})
    goal = Map.get(goals, goal_name)

    if goal do
      trait_weights = Keyword.get(opts, :trait_weights, default_trait_weights())
      score(goal, trait_weights, traits, opts, facts)
    else
      nil
    end
  end

  # Private helpers

  defp score(goal, trait_weights, traits, opts, facts) do
    metadata = Map.get(goal, :metadata, %{})
    base = Map.get(metadata, :priority, 1)
    config_bonus = trait_bonus(goal.name, trait_weights, traits)
    metadata_bonus = metadata_trait_score(metadata, traits)
    env_bonus = world_context_bonus(goal, facts)

    base + config_bonus + metadata_bonus + env_bonus + Keyword.get(opts, :priority_bonus, 0)
  end

  defp trait_bonus(goal_name, weights, traits) do
    Traits.traits(traits)
    |> Enum.reduce(0, fn trait, acc ->
      acc + Map.get(weights, {trait, goal_name}, 0)
    end)
  end

  defp default_trait_weights do
    Application.get_env(:ex_operator, :htn_trait_weights, %{})
  end

  defp metadata_trait_score(metadata, traits) do
    Traits.trait_affinity_score(traits, metadata) +
      Traits.archetype_affinity_score(traits, metadata)
  end

  defp emit_goal_selection(:none, _goal, _score), do: :ok

  defp emit_goal_selection(goal_name, goal, score) do
    metadata = Map.get(goal, :metadata, %{})
    payload = %{goal_metadata: metadata, domain: Map.get(metadata, :domain)}

    Telemetry.emit_goal_selected(goal_name, %{score: score}, payload)
  end

  defp goal_sort({score_a, name_a, _}, {score_b, name_b, _}, goal_order) do
    cond do
      score_a > score_b -> true
      score_a < score_b -> false
      true -> goal_index(name_a, goal_order) <= goal_index(name_b, goal_order)
    end
  end

  defp goal_index(name, goal_order) do
    case Enum.find_index(goal_order, fn candidate -> candidate == name end) do
      nil -> length(goal_order) + :erlang.phash2(name)
      index -> index
    end
  end

  defp precond_ok?(goal, facts, traits) do
    precond_met?(goal, facts, traits) and trait_requirement_met?(goal, traits)
  end

  defp missing_required_facts(goal, facts) do
    metadata = Map.get(goal, :metadata, %{})
    required = Map.get(metadata, :requires_facts, [])

    case required do
      [] -> []
      keys -> Facts.missing_keys(facts, keys)
    end
  end

  defp eligibility(goal, facts, traits) do
    cond do
      not precond_met?(goal, facts, traits) -> :preconditions_not_met
      not trait_requirement_met?(goal, traits) -> :traits_not_met
      true -> :ok
    end
  end

  defp precond_met?(%{precond: nil}, _facts, _traits), do: true

  defp precond_met?(%{precond: conditions}, facts, traits) when is_list(conditions) do
    Precondition.all_satisfied?(conditions, facts, traits)
  end

  defp precond_met?(%{precond: condition}, facts, traits) do
    Precondition.satisfied?(condition, facts, traits)
  end

  defp trait_requirement_met?(goal, traits) do
    required = Map.get(goal, :metadata, %{}) |> Map.get(:required_traits, [])
    agent_traits = Traits.traits(traits)

    case required do
      [] -> true
      reqs -> Enum.any?(reqs, &(&1 in agent_traits))
    end
  end

  defp world_context_bonus(goal, facts) do
    tension = Facts.get(facts, {:world, :tension}, 0.5)
    land_use = Facts.get(facts, {:world, :land_use}, :mixed)
    meta = Map.get(goal, :metadata, %{})
    domain = Map.get(meta, :domain)

    case {domain, land_use} do
      {:security, :corporate} -> tension * 0.5
      {:security, :industrial} -> tension * 0.4
      {:street, :barrens} -> tension * 0.6
      {:street, :mixed} -> tension * 0.3
      _ -> tension * 0.1
    end
  end
end
