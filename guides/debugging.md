# Debugging

This guide focuses on getting signal when your plans fail or behave oddly.

## Enable Trace Output

Tracing shows the planner's choices and is the fastest way to understand why
a goal was or was not selected.

```elixir
alias Operator.HTN.Trace
alias Operator.HTN.Trace.ConsoleHandler

Trace.set_handler(ConsoleHandler)
{:ok, plan} = Operator.HTN.Planner.run(:patrol, facts, traits)
Trace.reset()
```

## Read The Plan

A plan is just data. Print it and inspect it.

```elixir
IO.inspect(plan.goal)
IO.inspect(plan.tasks)
IO.inspect(plan.validity)
```

## Explain Goal Selection

Use `GoalSelector.explain/3` to see why a goal was selected.

```elixir
result = Operator.HTN.GoalSelector.explain(facts, traits)
IO.inspect(result.selected)
IO.inspect(result.eligible)
IO.inspect(result.ineligible)
IO.inspect(result.ineligible |> Enum.map(& &1.missing_facts))
```

## Explain Plan Generation

Use `Planner.explain/3` for a structured payload of the plan and checks.

```elixir
result = Operator.HTN.Planner.explain(:patrol, facts, traits)
IO.inspect(result.result)
IO.inspect(result.reason)
IO.inspect(result.plan)
IO.inspect(result.missing_facts)
```

## Check Preconditions Manually

If a goal does not appear, the precondition is likely failing.

```elixir
goal = Operator.HTN.Registry.get_goal(:patrol)
Operator.HTN.Precondition.all_satisfied?(goal.precond, facts, traits)
```

## Validate Registry State

The Registry must know about your behavior module.

```elixir
Operator.HTN.Registry.list_goal_names()
Operator.HTN.Registry.list_task_names()
```

## Use `Planner.needs_replan?/2`

If an agent keeps repeating bad plans, check when you should replan.

```elixir
if Operator.HTN.Planner.needs_replan?(plan, facts) do
  {:ok, new_plan} = Operator.HTN.Planner.run(plan.goal, facts, traits)
  new_plan
else
  plan
end
```

## Debug One Step At A Time

`Executor.step/3` returns a full tuple with remaining plan state.

```elixir
case Operator.HTN.Executor.step(plan, actor, facts) do
  {:ok, :continue, actor, facts, remaining} -> remaining
  {:ok, :completed, actor, facts, _plan} -> :done
  {:error, reason, actor, facts, _plan} -> {:failed, reason}
end
```

## Custom Trace Handlers

You can implement a structured logger to send traces to your telemetry stack.

```elixir
defmodule MyGame.HTNLogger do
  require Logger

  def on_goal_start(goal, _facts, _opts), do: Logger.debug("[HTN] start #{goal}")
  def on_goal_end(goal, result, _opts), do: Logger.debug("[HTN] end #{goal}: #{result}")
  def on_task_expand(task, args, _facts, _opts), do: Logger.debug("[HTN] task #{task} #{inspect(args)}")
end

Operator.HTN.Trace.set_handler(MyGame.HTNLogger)
```

## Checklist

- Registry has the expected modules.
- Facts contain the keys your preconditions read.
- Preconditions return the values you expect.
- Trace output shows the exact failure point.
