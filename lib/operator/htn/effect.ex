defmodule Operator.HTN.Effect do
  @moduledoc """
  Effects represent world state changes that result from task execution.

  Effects are the bridge between planning and reality. They let the planner
  reason about future states, enabling complex plans where early actions
  create conditions needed by later actions.

  ## Why Effects Matter

  Consider an NPC that needs to enter a locked room:

  1. Without effects, the planner checks `:enter_room`'s precondition
     (`door_unlocked == true`), finds it false, and gives up.

  2. With effects, the planner:
     - Plans `:unlock_door` first
     - Applies its effect (`door_unlocked = true`) to a working copy of facts
     - Now `:enter_room`'s precondition passes against the projected state
     - Generates plan: `[{:unlock_door, []}, {:enter_room, []}]`

  This is the essence of HTN planning - reasoning about sequences of actions
  and their cumulative effects on world state.

  ## Effect Types

  Based on GameAIPro HTN patterns, there are three effect types:

  | Type               | Planning | Execution | Use Case                           |
  |--------------------|----------|-----------|-----------------------------------|
  | `:plan_only`       | ✓        | ✗         | Temporary planning assumptions     |
  | `:plan_and_execute`| ✓        | ✓         | Standard effects (most common)     |
  | `:permanent`       | ✓        | ✓*        | Effects that persist on failure    |

  *Permanent effects are applied even if subsequent tasks fail.

  ### `:plan_only`

  Applied during planning but NOT during execution. Use when:
  - The execution system handles the effect differently
  - You need to "pretend" something is true for planning purposes
  - Simulating optimistic assumptions

      # Assume we'll find ammo during the mission (planning only)
      Effect.new(:plan_only, {:self, :has_ammo}, true)

  ### `:plan_and_execute`

  Applied during both planning AND execution. This is the standard type for
  most game actions.

      # Door is unlocked after picking the lock
      Effect.new(:plan_and_execute, {:world, :door_unlocked}, true)

      # Health consumed after healing
      Effect.new(:plan_and_execute, {:self, :health_potion_count}, 0)

  ### `:permanent`

  Applied during planning and persists regardless of task success/failure.
  Use sparingly - these represent irreversible actions.

      # Alert triggered - can't un-ring that bell
      Effect.new(:permanent, {:world, :alarm_triggered}, true)

      # Resource consumed even if subsequent actions fail
      Effect.new(:permanent, {:self, :grenade_count}, :decrement)

  ## Working with Effects

  ### Creating Effects

      effect = Effect.new(:plan_and_execute, {:self, :armed}, true)

  ### Applying Effects

      # Single effect
      updated_facts = Effect.apply_effect(effect, facts)

      # Multiple effects
      updated_facts = Effect.apply_all(effects, facts)

  ### Filtering Effects

      # Get effects for execution (excludes :plan_only)
      execution_effects = Effect.execution_effects(task.effects)

      # Get effects by specific type
      permanent_only = Effect.filter_by_type(effects, :permanent)

  ## Integration with Tasks

  Effects are typically defined on primitives in the DSL:

      primitive :unlock_door do
        run fn actor, _facts ->
          {:ok, %{actor | picked_lock: true}}
        end

        effect Effect.new(:plan_and_execute, {:world, :door_unlocked}, true)
      end

  The `Executor` automatically applies execution effects after successful
  primitive completion.

  ## See Also

  * `Operator.HTN.Task` - Where effects are attached
  * `Operator.HTN.Engine` - Applies effects during planning
  * `Operator.HTN.Executor` - Applies effects during execution
  * `Operator.HTN.Facts` - The world state effects modify

  """

  alias Operator.HTN.Facts

  defstruct [:type, :key, :value]

  @typedoc """
  The effect type determining when the effect is applied.

  * `:plan_only` - Planning phase only
  * `:plan_and_execute` - Both planning and execution
  * `:permanent` - Persists even on task failure

  """
  @type effect_type :: :plan_only | :plan_and_execute | :permanent

  @typedoc """
  The Effect struct.

  ## Fields

  * `:type` - When the effect is applied
  * `:key` - The fact key to modify (e.g., `{:self, :armed}`)
  * `:value` - The new value to set

  """
  @type t :: %__MODULE__{
          type: effect_type(),
          key: Facts.fact_key(),
          value: any()
        }

  @doc """
  Create a new effect.

  ## Parameters

  * `type` - When the effect is applied:
    * `:plan_only` - Planning phase only
    * `:plan_and_execute` - Both planning and execution (most common)
    * `:permanent` - Persists even on task failure
  * `key` - The fact key to modify (e.g., `{:self, :has_weapon}`)
  * `value` - The new value to set

  ## Examples

      iex> alias Operator.HTN.Effect
      iex> # Standard effect - door unlocked after picking lock
      iex> Effect.new(:plan_and_execute, {:world, :door_locked}, false)

      iex> # Planning assumption - assume we'll find resources
      iex> Effect.new(:plan_only, {:self, :has_keycard}, true)

      iex> # Permanent - alert can't be un-triggered
      iex> Effect.new(:permanent, {:world, :security_alerted}, true)

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

  This function modifies the facts by setting the effect's key to its value.
  Named `apply_effect` to avoid conflict with `Kernel.apply/2`.

  ## Parameters

  * `effect` - The Effect struct to apply
  * `facts` - The current Facts struct

  ## Returns

  A new Facts struct with the effect applied.

  ## Examples

      iex> alias Operator.HTN.{Effect, Facts}
      iex> facts = Facts.from_perception(%{self: %{armed: false}})
      iex> effect = Effect.new(:plan_and_execute, {:self, :armed}, true)
      iex> updated_facts = Effect.apply_effect(effect, facts)
      iex> Facts.get(updated_facts, {:self, :armed})
      true

  """
  @spec apply_effect(t(), Facts.t()) :: Facts.t()
  def apply_effect(%__MODULE__{key: key, value: value}, facts) do
    Facts.put(facts, key, value)
  end

  @doc """
  Apply multiple effects to facts in sequence.

  Effects are applied in list order, so later effects can override earlier ones
  if they modify the same key.

  ## Parameters

  * `effects` - List of Effect structs
  * `facts` - The current Facts struct

  ## Returns

  A new Facts struct with all effects applied.

  ## Examples

      iex> alias Operator.HTN.{Effect, Facts}
      iex> effects = [
      ...>   Effect.new(:plan_and_execute, {:self, :armed}, true),
      ...>   Effect.new(:plan_and_execute, {:self, :in_combat}, true)
      ...> ]
      iex> updated_facts = Effect.apply_all(effects, Facts.new())
      iex> Facts.get(updated_facts, {:self, :armed})
      true

  """
  @spec apply_all([t()], Facts.t()) :: Facts.t()
  def apply_all(effects, facts) do
    Enum.reduce(effects, facts, fn effect, acc ->
      apply_effect(effect, acc)
    end)
  end

  @doc """
  Filter effects by type.

  ## Parameters

  * `effects` - List of Effect structs
  * `type` - The effect type to filter for

  ## Returns

  List of effects matching the specified type.

  ## Examples

      iex> alias Operator.HTN.Effect
      iex> effects = [
      ...>   Effect.new(:plan_only, {:self, :assumed_safe}, true),
      ...>   Effect.new(:plan_and_execute, {:self, :armed}, true),
      ...>   Effect.new(:permanent, {:world, :alerted}, true)
      ...> ]
      iex> length(Effect.filter_by_type(effects, :plan_only))
      1

  """
  @spec filter_by_type([t()], effect_type()) :: [t()]
  def filter_by_type(effects, type) do
    Enum.filter(effects, &(&1.type == type))
  end

  @doc """
  Get only effects that should be applied during execution.

  Excludes `:plan_only` effects, which are only used during planning.
  Returns both `:plan_and_execute` and `:permanent` effects.

  ## Parameters

  * `effects` - List of Effect structs

  ## Returns

  List of effects suitable for execution (excludes `:plan_only`).

  ## Examples

      iex> alias Operator.HTN.Effect
      iex> effects = [
      ...>   Effect.new(:plan_only, {:self, :optimistic_assumption}, true),
      ...>   Effect.new(:plan_and_execute, {:self, :armed}, true)
      ...> ]
      iex> Enum.map(Effect.execution_effects(effects), & &1.type)
      [:plan_and_execute]

  """
  @spec execution_effects([t()]) :: [t()]
  def execution_effects(effects) do
    Enum.filter(effects, &(&1.type != :plan_only))
  end

  @doc """
  Get only effects applied during planning.

  All effect types are applied during planning, so this returns the full list.
  This function exists for API symmetry with `execution_effects/1`.

  ## Parameters

  * `effects` - List of Effect structs

  ## Returns

  The input list unchanged (all effects apply during planning).

  ## Examples

      iex> alias Operator.HTN.Effect
      iex> effects = [
      ...>   Effect.new(:plan_only, {:self, :assumed}, true),
      ...>   Effect.new(:plan_and_execute, {:self, :real}, true)
      ...> ]
      iex> Effect.planning_effects(effects) == effects
      true

  """
  @spec planning_effects([t()]) :: [t()]
  def planning_effects(effects), do: effects
end
