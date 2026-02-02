defmodule Operator.HTN.GoalSelector do
  @moduledoc """
  Picks the highest-priority eligible goal for an agent.

  Goal selection considers:
  - Goal preconditions (must be satisfied)
  - Base priority from goal metadata
  - Trait affinity (how well agent traits match goal)
  - Archetype affinity (how well agent archetype matches goal)
  - World context (environmental modifiers)

  ## Usage

      facts = Operator.HTN.Facts.from_perception(%{
        self: %{health: 80},
        world: %{tension: 0.7, land_use: :corporate}
      })

      traits = %{
        archetype: :street_sam,
        traits: [:aggressive, :territorial]
      }

      case GoalSelector.pick_goal(facts, traits) do
        {:ok, :patrol_territory} ->
          Planner.run(:patrol_territory, facts, traits)

        :none ->
          # No eligible goals found
          :idle
      end

  ## Options

      GoalSelector.pick_goal(facts, traits,
        trait_weights: %{{:aggressive, :attack} => 5},
        goal_order: [:defend, :patrol, :idle],
        priority_bonus: 0
      )

  """

  alias Operator.HTN.{Facts, Registry}
  alias Operator.{Telemetry, Traits}

  @doc """
  Selects the highest-priority eligible goal.

  ## Arguments

  - `facts` - Current world state
  - `traits` - Agent traits/genome
  - `opts` - Options (see below)

  ## Options

  - `:trait_weights` - Map of `{trait, goal}` to integer bonuses
  - `:goal_order` - Deterministic tie-breaker list of goal atoms
  - `:priority_bonus` - Scalar added to every score

  ## Returns

  - `{:ok, goal_name}` - Best eligible goal
  - `:none` - No eligible goals found

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
  Score a specific goal for an agent.

  Useful for debugging goal selection.
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
    Application.get_env(:operator, :htn_trait_weights, %{})
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
    precond_met?(goal, facts) and trait_requirement_met?(goal, traits)
  end

  defp precond_met?(%{precond: nil}, _facts), do: true
  defp precond_met?(%{precond: fun}, facts) when is_function(fun, 1), do: fun.(facts)
  defp precond_met?(_, _), do: true

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
