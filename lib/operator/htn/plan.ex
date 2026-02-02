defmodule Operator.HTN.Plan do
  @moduledoc """
  Represents a generated plan from HTN expansion.

  A Plan is the output of the HTN planning process - a sequence of primitive
  tasks that, when executed in order, should achieve the original goal.

  ## Plan Structure

      %Plan{
        goal: :acquire_data,
        tasks: [
          {:move_to, [:server_room]},
          {:hack_terminal, ["mainframe"]},
          {:download, [:target_file]}
        ],
        validity: :active,
        created_at: 1699999999,
        metadata: %{estimated_cost: 15.0}
      }

  ## Plan Lifecycle

  Plans have a validity state that tracks their lifecycle:

  * `:active` - Plan is valid and can be executed
  * `:invalid` - Plan is no longer valid (world changed)
  * `:completed` - All tasks have been executed

  ## Usage

  ### Creating Plans

  Plans are typically created by the Engine or Planner:

      {:ok, plan} = Operator.HTN.Planner.run(:my_goal, facts, traits)

  ### Executing Plans

      case Plan.next_task(plan) do
        {{:move_to, [location]}, remaining_plan} ->
          execute_move(location)
          # Continue with remaining_plan

        :empty ->
          Plan.complete(plan)
      end

  ### Invalidation

  Plans should be invalidated when the world changes in ways that affect
  preconditions:

      plan = Plan.invalidate(plan)
      # plan.validity is now :invalid

  ## Metadata

  Plans can carry arbitrary metadata for debugging, cost tracking, or
  integration with external systems:

      plan = Plan.add_metadata(plan, :source, "GoalSelector")
      plan = Plan.add_metadata(plan, :planning_time_ms, 5)

  ## See Also

  * `Operator.HTN.Engine` - Generates plans
  * `Operator.HTN.Planner` - High-level planning API
  * `Operator.HTN.Task` - Individual task definitions

  """

  defstruct [
    :goal,
    :tasks,
    :validity,
    :created_at,
    :metadata
  ]

  @typedoc """
  Plan validity states.

  * `:active` - Plan is valid and executable
  * `:invalid` - Plan preconditions no longer hold
  * `:completed` - All tasks have been executed

  """
  @type validity :: :active | :invalid | :completed

  @typedoc """
  A task tuple with name and arguments.

  ## Examples

      {:move_to, [:lobby]}
      {:attack, [:enemy_1, :melee]}
      {:wait, [5000]}

  """
  @type task_tuple :: {atom(), list()}

  @typedoc """
  The Plan struct.

  ## Fields

  * `:goal` - The goal this plan achieves
  * `:tasks` - List of primitive task tuples
  * `:validity` - Current plan validity
  * `:created_at` - Unix timestamp of creation
  * `:metadata` - Arbitrary metadata map

  """
  @type t :: %__MODULE__{
          goal: atom(),
          tasks: [task_tuple()],
          validity: validity(),
          created_at: integer(),
          metadata: map()
        }

  @doc """
  Create a new plan.

  ## Parameters

  * `goal` - The goal atom this plan achieves
  * `tasks` - List of `{task_name, args}` tuples
  * `opts` - Optional keyword list:
    * `:metadata` - Initial metadata map
    * `:validity` - Initial validity (default: `:active`)

  ## Examples

      iex> plan = Plan.new(:patrol, [{:walk_to, [:waypoint_1]}, {:scan, []}])
      iex> plan.goal
      :patrol
      iex> plan.validity
      :active

      iex> plan = Plan.new(:attack, [{:strike, []}], metadata: %{priority: :high})
      iex> plan.metadata.priority
      :high

  """
  @spec new(atom(), [task_tuple()], keyword()) :: t()
  def new(goal, tasks, opts \\ []) do
    %__MODULE__{
      goal: goal,
      tasks: tasks,
      validity: Keyword.get(opts, :validity, :active),
      created_at: System.os_time(:second),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Get the next task to execute.

  Returns `{task_tuple, remaining_plan}` or `:empty` if no tasks remain.

  ## Examples

      iex> plan = Plan.new(:test, [{:a, []}, {:b, [1]}])
      iex> {{:a, []}, remaining} = Plan.next_task(plan)
      iex> remaining.tasks
      [{:b, [1]}]

      iex> empty_plan = Plan.new(:test, [])
      iex> Plan.next_task(empty_plan)
      :empty

  """
  @spec next_task(t()) :: {task_tuple(), t()} | :empty
  def next_task(%__MODULE__{tasks: []}), do: :empty

  def next_task(%__MODULE__{tasks: [next | rest]} = plan) do
    {next, %{plan | tasks: rest}}
  end

  @doc """
  Check if the plan has remaining tasks.

  ## Examples

      iex> plan = Plan.new(:test, [{:task, []}])
      iex> Plan.has_tasks?(plan)
      true

      iex> empty = Plan.new(:test, [])
      iex> Plan.has_tasks?(empty)
      false

  """
  @spec has_tasks?(t()) :: boolean()
  def has_tasks?(%__MODULE__{tasks: []}), do: false
  def has_tasks?(%__MODULE__{tasks: _}), do: true

  @doc """
  Mark a plan as completed.

  ## Examples

      iex> plan = Plan.new(:test, [])
      iex> completed = Plan.complete(plan)
      iex> completed.validity
      :completed

  """
  @spec complete(t()) :: t()
  def complete(%__MODULE__{} = plan) do
    %{plan | validity: :completed}
  end

  @doc """
  Mark a plan as invalid.

  Use this when world state changes in a way that invalidates plan
  preconditions.

  ## Examples

      iex> plan = Plan.new(:test, [{:task, []}])
      iex> invalid = Plan.invalidate(plan)
      iex> invalid.validity
      :invalid

  """
  @spec invalidate(t()) :: t()
  def invalidate(%__MODULE__{} = plan) do
    %{plan | validity: :invalid}
  end

  @doc """
  Check if plan is still valid for execution.

  ## Examples

      iex> plan = Plan.new(:test, [])
      iex> Plan.valid?(plan)
      true

      iex> invalid = Plan.invalidate(plan)
      iex> Plan.valid?(invalid)
      false

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{validity: :active}), do: true
  def valid?(%__MODULE__{}), do: false

  @doc """
  Get the number of remaining tasks.

  ## Examples

      iex> plan = Plan.new(:test, [{:a, []}, {:b, []}, {:c, []}])
      iex> Plan.task_count(plan)
      3

  """
  @spec task_count(t()) :: non_neg_integer()
  def task_count(%__MODULE__{tasks: tasks}), do: length(tasks)

  @doc """
  Add metadata to a plan.

  ## Examples

      iex> plan = Plan.new(:test, [])
      iex> plan = Plan.add_metadata(plan, :source, "manual")
      iex> plan.metadata.source
      "manual"

  """
  @spec add_metadata(t(), atom(), any()) :: t()
  def add_metadata(%__MODULE__{metadata: metadata} = plan, key, value) do
    %{plan | metadata: Map.put(metadata, key, value)}
  end

  @doc """
  Get metadata value from a plan.

  ## Examples

      iex> plan = Plan.new(:test, [], metadata: %{priority: 5})
      iex> Plan.get_metadata(plan, :priority)
      5

      iex> Plan.get_metadata(plan, :missing, :default)
      :default

  """
  @spec get_metadata(t(), atom(), any()) :: any()
  def get_metadata(%__MODULE__{metadata: metadata}, key, default \\ nil) do
    Map.get(metadata, key, default)
  end
end
