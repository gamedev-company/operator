defmodule Operator.HTN.Trace do
  @moduledoc """
  Detailed tracing for HTN planning operations.

  The Trace system lets you observe every step of the planning process -
  which goals are being expanded, which preconditions pass or fail, how
  tasks decompose, and what effects are applied. Essential for debugging
  complex HTN behaviors.

  ## Inspiration

  Inspired by Decima's HTN translator (Horizon Zero Dawn, Death Stranding)
  which inserts logging at key points: ON_START_PRED, ON_RETRY_PRED,
  ON_BIND, ON_END_PRED. This module provides similar hooks for Elixir.

  ## Quick Start

      # 1. Implement a trace handler
      defmodule MyApp.HTNTraceHandler do
        @behaviour Operator.HTN.Trace.Handler

        @impl true
        def on_goal_start(goal_name, _facts, _opts) do
          IO.puts("[HTN] Goal start: \#{goal_name}")
        end

        @impl true
        def on_goal_end(goal_name, result, _opts) do
          IO.puts("[HTN] Goal end: \#{goal_name} -> \#{result}")
        end

        @impl true
        def on_precondition_eval(context, result, _opts) do
          name = context[:goal] || context[:task]
          IO.puts("[HTN] Precondition \#{name}: \#{result}")
        end

        @impl true
        def on_task_expand(task_name, args, _facts, _opts) do
          IO.puts("[HTN] Expand: \#{task_name} \#{inspect(args)}")
        end

        @impl true
        def on_task_complete(task_name, result_tasks, status, _opts) do
          IO.puts("[HTN] Complete: \#{task_name} -> \#{status} (\#{length(result_tasks)} tasks)")
        end

        @impl true
        def on_effect_apply(effect, _facts, _opts) do
          IO.puts("[HTN] Effect: \#{inspect(effect.key)} = \#{inspect(effect.value)}")
        end

        @impl true
        def on_branch_select(task_name, branch_id, _opts) do
          IO.puts("[HTN] Branch: \#{task_name} selected \#{branch_id}")
        end
      end

      # 2. Enable tracing
      Operator.HTN.Trace.set_handler(MyApp.HTNTraceHandler)

      # 3. Run planner - trace events fire
      Planner.run(:my_goal, facts, traits)
      # [HTN] Goal start: my_goal
      # [HTN] Precondition my_goal: true
      # [HTN] Expand: subtask_a []
      # [HTN] Effect: {:self, :armed} = true
      # [HTN] Complete: subtask_a -> success (1 tasks)
      # [HTN] Goal end: my_goal -> success

  ## Configuration

      # In config/config.exs
      config :operator, trace_handler: MyApp.HTNTraceHandler

      # Or at runtime (takes precedence)
      Operator.HTN.Trace.set_handler(MyApp.HTNTraceHandler)

  ## Trace Events

  | Event              | When                                  | Key Data                    |
  |--------------------|---------------------------------------|-----------------------------|
  | `goal_start`       | Beginning goal expansion              | goal_name, facts            |
  | `goal_end`         | Goal expansion complete               | goal_name, :success/:failure|
  | `precondition_eval`| Precondition checked                  | context map, result boolean |
  | `task_expand`      | Starting task decomposition           | task_name, args, facts      |
  | `task_complete`    | Task decomposition done               | task_name, result_tasks     |
  | `effect_apply`     | Effect applied to working facts       | effect struct, facts        |
  | `branch_select`    | Decomposition branch chosen           | task_name, branch_id        |

  ## Production Performance

  When no trace handler is configured (`nil`), all trace operations are
  no-ops with minimal overhead (one `persistent_term` lookup that returns
  `nil`, then immediate return). Safe to leave trace calls in production
  code.

  ## Built-in Console Handler

  For quick debugging, use the provided console handler:

      Operator.HTN.Trace.set_handler(Operator.HTN.Trace.ConsoleHandler)

  ## See Also

  * `Operator.HTN.Trace.Handler` - Behaviour for trace handlers
  * `Operator.HTN.Trace.ConsoleHandler` - Built-in console output handler
  * `Operator.HTN.Engine` - Where trace events are emitted

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
  Behaviour for HTN trace handlers.

  Implement this behaviour to receive detailed tracing events during
  HTN planning. All callbacks are optional - implement only the events
  you care about.

  ## Example Implementation

      defmodule MyApp.DetailedTracer do
        @behaviour Operator.HTN.Trace.Handler

        @impl true
        def on_goal_start(goal_name, facts, _opts) do
          Logger.debug("Planning goal: \#{goal_name}")
          Logger.debug("Facts: \#{inspect(facts, pretty: true)}")
        end

        @impl true
        def on_precondition_eval(%{goal: goal}, false, _opts) do
          Logger.warning("Goal \#{goal} precondition FAILED")
        end

        def on_precondition_eval(_context, _result, _opts), do: :ok

        # ... implement other callbacks as needed
      end

  ## Callback Summary

  | Callback               | When Called                      |
  |------------------------|----------------------------------|
  | `on_goal_start/3`      | Goal expansion begins            |
  | `on_goal_end/3`        | Goal expansion ends              |
  | `on_precondition_eval/3`| Precondition evaluated          |
  | `on_task_expand/4`     | Task decomposition starts        |
  | `on_task_complete/4`   | Task decomposition ends          |
  | `on_effect_apply/3`    | Effect applied to facts          |
  | `on_branch_select/3`   | Decomposition branch chosen      |

  All callbacks are optional via `@optional_callbacks`.

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
