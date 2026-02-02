defmodule Operator.HTN.Task do
  @moduledoc """
  A task in the HTN hierarchy.

  Tasks can be:
  - **Abstract** - Composed of subtasks via a decompose function
  - **Primitive** - Directly executable actions

  Each task has:
  - Preconditions that must be satisfied
  - Optional decomposition for abstract tasks
  - Optional cost function for planning heuristics
  - Optional effects that modify world state

  ## Effects

  Effects are world state changes that result from task execution. During planning,
  effects are applied to a working copy of world state so the planner can reason
  about future states. See `Operator.HTN.Effect` for details.

  ## Examples

      # Abstract task with decomposition
      task = Task.new(:travel_to, :abstract,
        preconditions: [fn facts -> Facts.has?(facts, {:self, :can_move}) end],
        decompose: fn facts ->
          [{:walk_to, Facts.get(facts, {:self, :destination})}]
        end,
        cost: 5.0
      )

      # Primitive task with effects
      task = Task.new(:attack, :primitive,
        preconditions: [fn facts -> Facts.has?(facts, {:self, :has_weapon}) end],
        effects: [
          Effect.new(:plan_and_execute, {:self, :in_combat}, true)
        ],
        cost: fn facts, _traits -> Facts.get(facts, {:self, :aggression}, 1.0) end
      )

  """

  alias Operator.HTN.{Facts, Precondition}

  defstruct [
    :name,
    :type,
    :preconditions,
    :decompose,
    :effects,
    :cost,
    :metadata
  ]

  @type task_type :: :abstract | :primitive

  @type t :: %__MODULE__{
          name: atom(),
          type: task_type(),
          preconditions: [Precondition.condition()],
          decompose: function() | nil,
          effects: [Operator.HTN.Effect.t()] | nil,
          cost: number() | function() | nil,
          metadata: map()
        }

  @doc """
  Create a new task.

  ## Options

  - `:preconditions` - List of predicate functions (default: `[]`)
  - `:decompose` - Function returning subtask list (default: `nil`)
  - `:effects` - List of Effect structs (default: `[]`)
  - `:cost` - Static cost or cost function (default: `1.0`)
  - `:metadata` - Arbitrary metadata (default: `%{}`)

  """
  @spec new(atom(), task_type(), keyword()) :: t()
  def new(name, type, opts \\ []) do
    struct(__MODULE__,
      name: name,
      type: type,
      preconditions: Keyword.get(opts, :preconditions, []),
      decompose: Keyword.get(opts, :decompose),
      effects: Keyword.get(opts, :effects, []),
      cost: Keyword.get(opts, :cost, 1.0),
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end

  @doc """
  Check if all preconditions are satisfied.

  Preconditions can be:
  - Simple functions: `fn facts -> boolean end` or `fn facts, traits -> boolean end`
  - Logical operators: `{:any, [fns]}`, `{:all, [fns]}`, `{:first, [fns]}`, `{:not, fn}`

  All preconditions in the list are combined with AND semantics.

  ## Examples

      # Simple function
      preconditions: [fn facts -> Facts.has?(facts, {:self, :ready}) end]

      # OR operator: has weapon OR near pickup
      preconditions: [
        {:any, [
          fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
          fn facts -> Facts.has?(facts, {:world, :weapon_nearby}) end
        ]}
      ]

      # Combined: ready AND (armed OR near weapon)
      preconditions: [
        fn facts -> Facts.has?(facts, {:self, :ready}) end,
        {:any, [
          fn facts -> Facts.has?(facts, {:self, :armed}) end,
          fn facts -> Facts.has?(facts, {:world, :weapon_nearby}) end
        ]}
      ]

  """
  @spec preconditions_satisfied?(t(), Facts.t(), map()) :: boolean()
  def preconditions_satisfied?(%__MODULE__{preconditions: []}, _facts, _traits), do: true
  def preconditions_satisfied?(%__MODULE__{preconditions: nil}, _facts, _traits), do: true

  def preconditions_satisfied?(
        %__MODULE__{preconditions: preconditions},
        facts,
        traits
      ) do
    Precondition.all_satisfied?(preconditions, facts, traits)
  end

  @doc """
  Calculate task cost, optionally using trait data.

  Cost can be:
  - A static number
  - A function of arity 1 (facts only)
  - A function of arity 2 (facts and traits)

  """
  @spec calculate_cost(t(), Facts.t(), map()) :: number()
  def calculate_cost(%__MODULE__{cost: nil}, _facts, _traits), do: 1.0

  def calculate_cost(%__MODULE__{cost: cost}, _facts, _traits)
      when is_number(cost) do
    cost
  end

  def calculate_cost(%__MODULE__{cost: cost_fun}, facts, traits)
      when is_function(cost_fun) do
    case :erlang.fun_info(cost_fun, :arity) do
      {:arity, 1} -> cost_fun.(facts)
      {:arity, 2} -> cost_fun.(facts, traits)
      _ -> 1.0
    end
  end

  def calculate_cost(%__MODULE__{}, _facts, _traits), do: 1.0

  @doc """
  Check if this task is abstract (has decomposition).
  """
  @spec abstract?(t()) :: boolean()
  def abstract?(%__MODULE__{type: :abstract}), do: true
  def abstract?(_), do: false

  @doc """
  Check if this task is primitive (directly executable).
  """
  @spec primitive?(t()) :: boolean()
  def primitive?(%__MODULE__{type: :primitive}), do: true
  def primitive?(_), do: false
end
