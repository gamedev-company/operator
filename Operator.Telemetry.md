# `Operator.Telemetry`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/behaviours/telemetry.ex#L1)

Behaviour for telemetry and metrics integration.

The Telemetry behaviour allows you to instrument Operator with your
observability stack. Track goal selections, plan generation times,
and Director events for debugging and performance analysis.

## Configuration

    config :operator,
      telemetry_module: MyApp.OperatorTelemetry

## Events

Operator emits three types of events:

| Event                | When                          | Key Measurements        |
|----------------------|-------------------------------|-------------------------|
| `goal_selected`      | GoalSelector picks a goal     | `:score`                |
| `htn_plan_generated` | Planner creates a plan        | `:task_count`, duration |
| `director_event`     | Director fires an event       | `:count`                |

## Example Implementation

Using the standard `:telemetry` library:

    defmodule MyApp.OperatorTelemetry do
      @behaviour Operator.Telemetry

      @impl true
      def emit_goal_selected(goal_name, measurements, metadata) do
        :telemetry.execute(
          [:my_app, :operator, :goal_selected],
          measurements,
          Map.put(metadata, :goal, goal_name)
        )
      end

      @impl true
      def emit_htn_plan_generated(goal, task_count, duration_ms) do
        :telemetry.execute(
          [:my_app, :operator, :plan_generated],
          %{task_count: task_count, duration_ms: duration_ms},
          %{goal: goal}
        )
      end

      @impl true
      def emit_director_event(event_type, tick) do
        :telemetry.execute(
          [:my_app, :operator, :director_event],
          %{count: 1},
          %{event_type: event_type, tick: tick}
        )
      end
    end

## Attaching Handlers

With `:telemetry`, attach handlers in your application startup:

    def start(_type, _args) do
      :telemetry.attach_many(
        "operator-metrics",
        [
          [:my_app, :operator, :goal_selected],
          [:my_app, :operator, :plan_generated],
          [:my_app, :operator, :director_event]
        ],
        &MyApp.TelemetryHandler.handle_event/4,
        nil
      )

      # ... rest of supervision tree
    end

## Prometheus Example

If using `telemetry_metrics` with Prometheus:

    def metrics do
      [
        counter("my_app.operator.goal_selected.count",
          tags: [:goal, :domain]
        ),
        distribution("my_app.operator.plan_generated.duration_ms",
          tags: [:goal],
          buckets: [1, 5, 10, 25, 50, 100]
        ),
        counter("my_app.operator.director_event.count",
          tags: [:event_type]
        )
      ]
    end

## No-Op Default

If no telemetry module is configured, Operator silently skips emission.
This has zero overhead in production when telemetry isn't needed.

## See Also

* `Operator.HTN.GoalSelector` - Emits `goal_selected`
* `Operator.HTN.Planner` - Emits `htn_plan_generated`
* `Operator.Director` - Emits `director_event`

# `emit_director_event`

```elixir
@callback emit_director_event(
  event_type :: atom(),
  tick :: non_neg_integer()
) :: :ok
```

Emit telemetry when the Director generates an event.

Called by `Director` when a storyteller produces an event.

## Arguments

- `event_type` - The type of event generated
- `tick` - The simulation tick when the event occurred

# `emit_goal_selected`

```elixir
@callback emit_goal_selected(
  goal_name :: atom(),
  measurements :: map(),
  metadata :: map()
) :: :ok
```

Emit telemetry when a goal is selected.

Called by `GoalSelector.pick_goal/3` when a goal is chosen.

## Arguments

- `goal_name` - The selected goal atom (or `:none` if no goal selected)
- `measurements` - Map containing at least `:score`
- `metadata` - Additional context (goal_metadata, domain, etc.)

# `emit_htn_plan_generated`

```elixir
@callback emit_htn_plan_generated(
  goal :: atom(),
  task_count :: non_neg_integer(),
  duration_ms :: non_neg_integer()
) :: :ok
```

Emit telemetry when an HTN plan is generated.

Called by `Planner.run/3` after successful plan generation.

## Arguments

- `goal` - The goal that was planned
- `task_count` - Number of tasks in the generated plan
- `duration_ms` - Time taken to generate the plan

# `emit_director_event`

```elixir
@spec emit_director_event(atom(), non_neg_integer()) :: :ok
```

Emit director event if telemetry is configured.

# `emit_goal_selected`

```elixir
@spec emit_goal_selected(atom(), map(), map()) :: :ok
```

Emit goal selected event if telemetry is configured.

# `emit_htn_plan_generated`

```elixir
@spec emit_htn_plan_generated(atom(), non_neg_integer(), non_neg_integer()) :: :ok
```

Emit plan generated event if telemetry is configured.

# `get_module`

```elixir
@spec get_module() :: module() | nil
```

Get the configured telemetry module, if any.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
