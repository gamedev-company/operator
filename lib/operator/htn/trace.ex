defmodule Operator.HTN.Trace do
  @moduledoc """
  Detailed tracing for HTN planning operations.

  Inspired by Decima's HTN translator which inserts logging at key points
  (ON_START_PRED, ON_RETRY_PRED, ON_BIND, ON_END_PRED), this module provides
  hooks for observing the planning process in detail.

  ## Usage

  Enable tracing by setting a trace handler:

      # In config
      config :operator, trace_handler: MyApp.HTNTraceHandler

      # Or at runtime
      Operator.HTN.Trace.set_handler(MyApp.HTNTraceHandler)

  ## Handler Behaviour

  Trace handlers receive events via callbacks:

      defmodule MyApp.HTNTraceHandler do
        @behaviour Operator.HTN.Trace.Handler

        @impl true
        def on_goal_start(goal_name, facts, _opts) do
          IO.puts("Starting goal: \#{goal_name}")
        end

        @impl true
        def on_precondition_eval(context, result, _opts) do
          IO.puts("Precondition \#{context}: \#{result}")
        end

        # ... other callbacks
      end

  ## Trace Events

  The following events are emitted during planning:

  - `goal_start` - Beginning to expand a goal
  - `goal_end` - Finished expanding a goal (success or failure)
  - `precondition_eval` - Evaluating a precondition
  - `task_expand` - Expanding a task into subtasks
  - `task_complete` - Task expansion completed
  - `effect_apply` - Applying an effect to world state
  - `branch_select` - Selecting a decomposition branch

  ## Performance

  When no trace handler is configured, all trace operations are no-ops with
  minimal overhead. For production use, leave tracing disabled.

  """

  @trace_key {__MODULE__, :handler}

  @doc """
  Set the trace handler module.
  """
  @spec set_handler(module() | nil) :: :ok
  def set_handler(module) do
    :persistent_term.put(@trace_key, module)
    :ok
  end

  @doc """
  Get the current trace handler, if any.
  """
  @spec get_handler() :: module() | nil
  def get_handler do
    Application.get_env(:operator, :trace_handler) ||
      :persistent_term.get(@trace_key, nil)
  end

  @doc """
  Check if tracing is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    get_handler() != nil
  end

  @doc """
  Trace the start of goal expansion.
  """
  @spec goal_start(atom(), Operator.HTN.Facts.t(), keyword()) :: :ok
  def goal_start(goal_name, facts, opts \\ []) do
    with_handler(& &1.on_goal_start(goal_name, facts, opts))
  end

  @doc """
  Trace the end of goal expansion.
  """
  @spec goal_end(atom(), :success | :failure, keyword()) :: :ok
  def goal_end(goal_name, result, opts \\ []) do
    with_handler(& &1.on_goal_end(goal_name, result, opts))
  end

  @doc """
  Trace precondition evaluation.

  Context is a map with:
  - `:goal` or `:task` - The current goal/task name
  - `:precondition_index` - Index in preconditions list
  - `:precondition_type` - `:function`, `:axiom`, `:operator`, etc.
  """
  @spec precondition_eval(map(), boolean(), keyword()) :: :ok
  def precondition_eval(context, result, opts \\ []) do
    with_handler(& &1.on_precondition_eval(context, result, opts))
  end

  @doc """
  Trace task expansion start.
  """
  @spec task_expand(atom(), list(), Operator.HTN.Facts.t(), keyword()) :: :ok
  def task_expand(task_name, args, facts, opts \\ []) do
    with_handler(& &1.on_task_expand(task_name, args, facts, opts))
  end

  @doc """
  Trace task expansion completion.
  """
  @spec task_complete(atom(), list(), :success | :failure, keyword()) :: :ok
  def task_complete(task_name, result_tasks, status, opts \\ []) do
    with_handler(& &1.on_task_complete(task_name, result_tasks, status, opts))
  end

  @doc """
  Trace effect application.
  """
  @spec effect_apply(Operator.HTN.Effect.t(), Operator.HTN.Facts.t(), keyword()) :: :ok
  def effect_apply(effect, facts, opts \\ []) do
    with_handler(& &1.on_effect_apply(effect, facts, opts))
  end

  @doc """
  Trace branch selection in decomposition.
  """
  @spec branch_select(atom(), atom() | integer(), keyword()) :: :ok
  def branch_select(task_name, branch_id, opts \\ []) do
    with_handler(& &1.on_branch_select(task_name, branch_id, opts))
  end

  # Private helper to invoke handler if present
  defp with_handler(fun) do
    case get_handler() do
      nil -> :ok
      handler -> fun.(handler)
    end
  end

  @doc """
  Reset trace handler (useful for tests).
  """
  @spec reset() :: :ok
  def reset do
    :persistent_term.erase(@trace_key)
    :ok
  rescue
    ArgumentError -> :ok
  end
end

defmodule Operator.HTN.Trace.Handler do
  @moduledoc """
  Behaviour for trace handlers.

  Implement this behaviour to receive detailed tracing events from
  the HTN planner.
  """

  @doc "Called when goal expansion starts."
  @callback on_goal_start(goal_name :: atom(), facts :: map(), opts :: keyword()) :: :ok

  @doc "Called when goal expansion ends."
  @callback on_goal_end(goal_name :: atom(), result :: :success | :failure, opts :: keyword()) ::
              :ok

  @doc "Called when a precondition is evaluated."
  @callback on_precondition_eval(context :: map(), result :: boolean(), opts :: keyword()) :: :ok

  @doc "Called when task expansion begins."
  @callback on_task_expand(
              task_name :: atom(),
              args :: list(),
              facts :: map(),
              opts :: keyword()
            ) :: :ok

  @doc "Called when task expansion completes."
  @callback on_task_complete(
              task_name :: atom(),
              result_tasks :: list(),
              status :: :success | :failure,
              opts :: keyword()
            ) :: :ok

  @doc "Called when an effect is applied."
  @callback on_effect_apply(effect :: struct(), facts :: map(), opts :: keyword()) :: :ok

  @doc "Called when a decomposition branch is selected."
  @callback on_branch_select(
              task_name :: atom(),
              branch_id :: atom() | integer(),
              opts :: keyword()
            ) ::
              :ok

  @optional_callbacks on_goal_start: 3,
                      on_goal_end: 3,
                      on_precondition_eval: 3,
                      on_task_expand: 4,
                      on_task_complete: 4,
                      on_effect_apply: 3,
                      on_branch_select: 3
end
