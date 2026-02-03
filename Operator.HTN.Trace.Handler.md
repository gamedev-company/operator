# `Operator.HTN.Trace.Handler`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/trace.ex#L221)

Behaviour for HTN trace handlers.

Implement this behaviour to receive detailed tracing events during
HTN planning. All callbacks are optional - implement only the events
you care about.

## Example Implementation

    defmodule MyApp.DetailedTracer do
      @behaviour Operator.HTN.Trace.Handler

      @impl true
      def on_goal_start(goal_name, facts, _opts) do
        Logger.debug("Planning goal: #{goal_name}")
        Logger.debug("Facts: #{inspect(facts, pretty: true)}")
      end

      @impl true
      def on_precondition_eval(%{goal: goal}, false, _opts) do
        Logger.warning("Goal #{goal} precondition FAILED")
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

# `on_branch_select`
*optional* 

```elixir
@callback on_branch_select(
  task_name :: atom(),
  branch_id :: atom() | integer(),
  opts :: keyword()
) :: :ok
```

Called when a decomposition branch is selected.

# `on_effect_apply`
*optional* 

```elixir
@callback on_effect_apply(effect :: struct(), facts :: map(), opts :: keyword()) :: :ok
```

Called when an effect is applied.

# `on_goal_end`
*optional* 

```elixir
@callback on_goal_end(
  goal_name :: atom(),
  result :: :success | :failure,
  opts :: keyword()
) :: :ok
```

Called when goal expansion ends.

# `on_goal_start`
*optional* 

```elixir
@callback on_goal_start(goal_name :: atom(), facts :: map(), opts :: keyword()) :: :ok
```

Called when goal expansion starts.

# `on_precondition_eval`
*optional* 

```elixir
@callback on_precondition_eval(context :: map(), result :: boolean(), opts :: keyword()) ::
  :ok
```

Called when a precondition is evaluated.

# `on_task_complete`
*optional* 

```elixir
@callback on_task_complete(
  task_name :: atom(),
  result_tasks :: list(),
  status :: :success | :failure,
  opts :: keyword()
) :: :ok
```

Called when task expansion completes.

# `on_task_expand`
*optional* 

```elixir
@callback on_task_expand(
  task_name :: atom(),
  args :: list(),
  facts :: map(),
  opts :: keyword()
) :: :ok
```

Called when task expansion begins.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
