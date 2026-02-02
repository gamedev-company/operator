defmodule Operator.Telemetry do
  @moduledoc """
  Behaviour for telemetry integration.

  Implement this behaviour to receive telemetry events from Operator's
  HTN planner, goal selector, and director.

  ## Configuration

      config :operator,
        telemetry_module: MyApp.OperatorTelemetry

  ## Example Implementation

      defmodule MyApp.OperatorTelemetry do
        @behaviour Operator.Telemetry

        @impl true
        def emit_goal_selected(goal_name, measurements, metadata) do
          :telemetry.execute(
            [:my_app, :htn, :goal_selected],
            measurements,
            Map.put(metadata, :goal, goal_name)
          )
        end

        @impl true
        def emit_htn_plan_generated(goal, task_count, duration_ms) do
          :telemetry.execute(
            [:my_app, :htn, :plan_generated],
            %{task_count: task_count, duration: duration_ms},
            %{goal: goal}
          )
        end

        @impl true
        def emit_director_event(event_type, tick) do
          :telemetry.execute(
            [:my_app, :director, :event],
            %{count: 1},
            %{type: event_type, tick: tick}
          )
        end
      end

  """

  @doc """
  Emit telemetry when a goal is selected.

  Called by `GoalSelector.pick_goal/3` when a goal is chosen.

  ## Arguments

  - `goal_name` - The selected goal atom (or `:none` if no goal selected)
  - `measurements` - Map containing at least `:score`
  - `metadata` - Additional context (goal_metadata, domain, etc.)

  """
  @callback emit_goal_selected(
              goal_name :: atom(),
              measurements :: map(),
              metadata :: map()
            ) :: :ok

  @doc """
  Emit telemetry when an HTN plan is generated.

  Called by `Planner.run/3` after successful plan generation.

  ## Arguments

  - `goal` - The goal that was planned
  - `task_count` - Number of tasks in the generated plan
  - `duration_ms` - Time taken to generate the plan

  """
  @callback emit_htn_plan_generated(
              goal :: atom(),
              task_count :: non_neg_integer(),
              duration_ms :: non_neg_integer()
            ) :: :ok

  @doc """
  Emit telemetry when the Director generates an event.

  Called by `Director` when a storyteller produces an event.

  ## Arguments

  - `event_type` - The type of event generated
  - `tick` - The simulation tick when the event occurred

  """
  @callback emit_director_event(
              event_type :: atom(),
              tick :: non_neg_integer()
            ) :: :ok

  @doc """
  Get the configured telemetry module, if any.
  """
  @spec get_module() :: module() | nil
  def get_module do
    Application.get_env(:operator, :telemetry_module)
  end

  @doc """
  Emit goal selected event if telemetry is configured.
  """
  @spec emit_goal_selected(atom(), map(), map()) :: :ok
  def emit_goal_selected(goal_name, measurements \\ %{}, metadata \\ %{}) do
    case get_module() do
      nil -> :ok
      module -> module.emit_goal_selected(goal_name, measurements, metadata)
    end
  end

  @doc """
  Emit plan generated event if telemetry is configured.
  """
  @spec emit_htn_plan_generated(atom(), non_neg_integer(), non_neg_integer()) :: :ok
  def emit_htn_plan_generated(goal, task_count, duration_ms) do
    case get_module() do
      nil -> :ok
      module -> module.emit_htn_plan_generated(goal, task_count, duration_ms)
    end
  end

  @doc """
  Emit director event if telemetry is configured.
  """
  @spec emit_director_event(atom(), non_neg_integer()) :: :ok
  def emit_director_event(event_type, tick) do
    case get_module() do
      nil -> :ok
      module -> module.emit_director_event(event_type, tick)
    end
  end
end
