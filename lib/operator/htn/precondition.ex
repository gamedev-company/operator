defmodule Operator.HTN.Precondition do
  @moduledoc """
  Logical operators for HTN preconditions.

  Inspired by the Decima engine's HTN implementation, this module provides
  logical combinators for preconditions beyond simple conjunction (AND).

  ## Supported Operators

  - `:all` (AND) - All conditions must be true (default behavior)
  - `:any` (OR) - At least one condition must be true
  - `:first` (ALT) - Use first matching condition with preference order
  - `:not` - Negate a condition
  - `:none` - No conditions match (equivalent to not-any)
  - `:axiom` - Reference a registered axiom

  ## Usage

  Preconditions can be:
  - A simple function: `fn facts -> boolean end`
  - A tuple with operator: `{:any, [fn1, fn2, fn3]}`
  - Nested operators: `{:all, [fn1, {:any, [fn2, fn3]}]}`
  - An axiom reference: `{:axiom, :axiom_name}` or `{:axiom, :axiom_name, args}`

  ## Examples

      # OR: Player has weapon OR is near weapon pickup
      {:any, [
        fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
        fn facts -> Facts.has?(facts, {:world, :weapon_nearby}) end
      ]}

      # ALT: Prefer ranged attack, fallback to melee
      {:first, [
        fn facts -> Facts.has?(facts, {:self, :has_ranged_weapon}) end,
        fn facts -> Facts.has?(facts, {:self, :has_melee_weapon}) end
      ]}

      # Negation: Not in combat
      {:not, fn facts -> Facts.get(facts, {:self, :in_combat}, false) end}

      # Axiom reference with arguments
      {:axiom, :nearby_enemy, max_distance: 10.0}

      # Nested: Has cover AND (has weapon OR has grenade)
      {:all, [
        fn facts -> Facts.has?(facts, {:self, :has_cover}) end,
        {:any, [
          fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
          fn facts -> Facts.has?(facts, {:self, :has_grenade}) end
        ]}
      ]}

  """

  alias Operator.HTN.{Axiom, Facts, Registry}

  @type condition :: function() | {operator(), [condition()]} | {operator(), condition()}
  @type operator :: :all | :any | :first | :not | :none

  @doc """
  Evaluate a precondition against facts and traits.

  Returns `{true, bindings}` on success or `{false, nil}` on failure.
  Bindings are currently unused but reserved for future unification support.
  """
  @spec evaluate(condition(), Facts.t(), map()) :: {boolean(), map() | nil}
  def evaluate(condition, facts, traits) do
    result = do_evaluate(condition, facts, traits)
    {result, if(result, do: %{}, else: nil)}
  end

  @doc """
  Simple boolean evaluation of a precondition.
  """
  @spec satisfied?(condition(), Facts.t(), map()) :: boolean()
  def satisfied?(condition, facts, traits) do
    do_evaluate(condition, facts, traits)
  end

  @doc """
  Evaluate a list of preconditions with AND semantics.

  This is the default behavior matching Task.preconditions_satisfied?/3.
  """
  @spec all_satisfied?([condition()], Facts.t(), map()) :: boolean()
  def all_satisfied?([], _facts, _traits), do: true

  def all_satisfied?(conditions, facts, traits) when is_list(conditions) do
    Enum.all?(conditions, &do_evaluate(&1, facts, traits))
  end

  # Private evaluation logic

  # Simple function (arity 1 or 2)
  defp do_evaluate(fun, facts, _traits) when is_function(fun, 1) do
    fun.(facts)
  end

  defp do_evaluate(fun, facts, traits) when is_function(fun, 2) do
    fun.(facts, traits)
  end

  # :all (AND) - All conditions must pass
  defp do_evaluate({:all, conditions}, facts, traits) when is_list(conditions) do
    Enum.all?(conditions, &do_evaluate(&1, facts, traits))
  end

  # :any (OR) - At least one condition must pass
  defp do_evaluate({:any, conditions}, facts, traits) when is_list(conditions) do
    Enum.any?(conditions, &do_evaluate(&1, facts, traits))
  end

  # :first (ALT) - Return true if any matches, but preserves order preference
  # This is semantically similar to :any but signals intent that order matters
  defp do_evaluate({:first, conditions}, facts, traits) when is_list(conditions) do
    Enum.any?(conditions, &do_evaluate(&1, facts, traits))
  end

  # :not (negation) - Invert the result
  defp do_evaluate({:not, condition}, facts, traits) do
    not do_evaluate(condition, facts, traits)
  end

  # :none - No conditions match (like NOT ANY)
  defp do_evaluate({:none, conditions}, facts, traits) when is_list(conditions) do
    not Enum.any?(conditions, &do_evaluate(&1, facts, traits))
  end

  # :axiom - Reference a registered axiom with no args
  defp do_evaluate({:axiom, name}, facts, _traits) when is_atom(name) do
    case Registry.get_axiom(name) do
      %Axiom{} = axiom -> Axiom.evaluate(axiom, facts, [])
      nil -> false
    end
  end

  # :axiom - Reference a registered axiom with args
  defp do_evaluate({:axiom, name, args}, facts, _traits) when is_atom(name) do
    case Registry.get_axiom(name) do
      %Axiom{} = axiom -> Axiom.evaluate(axiom, facts, args)
      nil -> false
    end
  end

  # Unknown condition type - fail safe
  defp do_evaluate(_unknown, _facts, _traits), do: false

  @doc """
  Find the first matching alternative in an ALT list.

  Unlike `:first` which just returns true/false, this returns
  `{:ok, index}` with the index of the first matching condition,
  or `:none` if nothing matches.

  Useful for branch selection in decomposition.
  """
  @spec find_first_match([condition()], Facts.t(), map()) :: {:ok, non_neg_integer()} | :none
  def find_first_match(conditions, facts, traits) do
    conditions
    |> Enum.with_index()
    |> Enum.find_value(:none, fn {condition, index} ->
      if do_evaluate(condition, facts, traits) do
        {:ok, index}
      end
    end)
  end

  @doc """
  Find all matching alternatives.

  Returns a list of indices for all conditions that match.
  Useful for OR semantics where you want to know all valid options.
  """
  @spec find_all_matches([condition()], Facts.t(), map()) :: [non_neg_integer()]
  def find_all_matches(conditions, facts, traits) do
    conditions
    |> Enum.with_index()
    |> Enum.filter(fn {condition, _index} -> do_evaluate(condition, facts, traits) end)
    |> Enum.map(fn {_condition, index} -> index end)
  end
end
