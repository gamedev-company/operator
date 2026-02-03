# `Operator.HTN.Trace`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/trace.ex#L1)

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
        IO.puts("[HTN] Goal start: #{goal_name}")
      end

      @impl true
      def on_goal_end(goal_name, result, _opts) do
        IO.puts("[HTN] Goal end: #{goal_name} -> #{result}")
      end

      @impl true
      def on_precondition_eval(context, result, _opts) do
        name = context[:goal] || context[:task]
        IO.puts("[HTN] Precondition #{name}: #{result}")
      end

      @impl true
      def on_task_expand(task_name, args, _facts, _opts) do
        IO.puts("[HTN] Expand: #{task_name} #{inspect(args)}")
      end

      @impl true
      def on_task_complete(task_name, result_tasks, status, _opts) do
        IO.puts("[HTN] Complete: #{task_name} -> #{status} (#{length(result_tasks)} tasks)")
      end

      @impl true
      def on_effect_apply(effect, _facts, _opts) do
        IO.puts("[HTN] Effect: #{inspect(effect.key)} = #{inspect(effect.value)}")
      end

      @impl true
      def on_branch_select(task_name, branch_id, _opts) do
        IO.puts("[HTN] Branch: #{task_name} selected #{branch_id}")
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

# `branch_select`

```elixir
@spec branch_select(atom(), atom() | integer(), keyword()) :: :ok
```

Trace branch selection in decomposition.

# `effect_apply`

```elixir
@spec effect_apply(Operator.HTN.Effect.t(), Operator.HTN.Facts.t(), keyword()) :: :ok
```

Trace effect application.

# `enabled?`

```elixir
@spec enabled?() :: boolean()
```

Check if tracing is enabled.

# `get_handler`

```elixir
@spec get_handler() :: module() | nil
```

Get the current trace handler, if any.

# `goal_end`

```elixir
@spec goal_end(atom(), :success | :failure, keyword()) :: :ok
```

Trace the end of goal expansion.

# `goal_start`

```elixir
@spec goal_start(atom(), Operator.HTN.Facts.t(), keyword()) :: :ok
```

Trace the start of goal expansion.

# `precondition_eval`

```elixir
@spec precondition_eval(map(), boolean(), keyword()) :: :ok
```

Trace precondition evaluation.

Context is a map with:
- `:goal` or `:task` - The current goal/task name
- `:precondition_index` - Index in preconditions list
- `:precondition_type` - `:function`, `:axiom`, `:operator`, etc.

# `reset`

```elixir
@spec reset() :: :ok
```

Reset trace handler (useful for tests).

# `set_handler`

```elixir
@spec set_handler(module() | nil) :: :ok
```

Set the trace handler module.

# `task_complete`

```elixir
@spec task_complete(atom(), list(), :success | :failure, keyword()) :: :ok
```

Trace task expansion completion.

# `task_expand`

```elixir
@spec task_expand(atom(), list(), Operator.HTN.Facts.t(), keyword()) :: :ok
```

Trace task expansion start.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
