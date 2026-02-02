defmodule Operator.HTN.Effect do
  @moduledoc """
  Effects represent world state changes that result from task execution.

  HTN planners use effects in two key ways:

  1. **During planning** - Effects are applied to a working copy of world state
     so the planner can reason about future states and validate downstream
     preconditions.

  2. **During execution** - Effects are re-applied to actual world state when
     tasks complete successfully.

  ## Effect Types

  Based on the GameAIPro HTN patterns, there are three effect types:

  - `:plan_only` - Applied during planning, removed before execution. Used for
    temporary planning assumptions that the execution system will handle differently.

  - `:plan_and_execute` - Applied during planning AND re-applied when task completes.
    The standard effect type for most actions.

  - `:permanent` - Applied during planning and persists regardless of task success.
    Use sparingly for effects that can't be undone.

  ## Example

      # Effect that sets a fact during planning and execution
      effect = Effect.new(:plan_and_execute, {:self, :has_data}, true)

      # Apply effect to facts
      updated_facts = Effect.apply(effect, facts)

      # Apply multiple effects
      updated_facts = Effect.apply_all(effects, facts)

  """

  alias Operator.HTN.Facts

  defstruct [:type, :key, :value]

  @type effect_type :: :plan_only | :plan_and_execute | :permanent

  @type t :: %__MODULE__{
          type: effect_type(),
          key: Facts.fact_key(),
          value: any()
        }

  @doc """
  Create a new effect.

  ## Arguments

  - `type` - One of `:plan_only`, `:plan_and_execute`, `:permanent`
  - `key` - The fact key to modify, e.g. `{:self, :has_weapon}`
  - `value` - The new value to set

  """
  @spec new(effect_type(), Facts.fact_key(), any()) :: t()
  def new(type, key, value) when type in [:plan_only, :plan_and_execute, :permanent] do
    %__MODULE__{
      type: type,
      key: key,
      value: value
    }
  end

  @doc """
  Apply an effect to facts, updating the world state.
  """
  # Named apply_effect to avoid conflict with Kernel.apply/2
  @spec apply_effect(t(), Facts.t()) :: Facts.t()
  def apply_effect(%__MODULE__{key: key, value: value}, facts) do
    Facts.put(facts, key, value)
  end

  @doc """
  Apply multiple effects to facts.
  """
  @spec apply_all([t()], Facts.t()) :: Facts.t()
  def apply_all(effects, facts) do
    Enum.reduce(effects, facts, fn effect, acc ->
      apply_effect(effect, acc)
    end)
  end

  @doc """
  Filter effects by type.
  """
  @spec filter_by_type([t()], effect_type()) :: [t()]
  def filter_by_type(effects, type) do
    Enum.filter(effects, &(&1.type == type))
  end

  @doc """
  Get only effects that should be applied during execution.

  Excludes `:plan_only` effects.
  """
  @spec execution_effects([t()]) :: [t()]
  def execution_effects(effects) do
    Enum.filter(effects, &(&1.type != :plan_only))
  end

  @doc """
  Get only effects applied during planning.

  All effect types are applied during planning.
  """
  @spec planning_effects([t()]) :: [t()]
  def planning_effects(effects), do: effects
end
