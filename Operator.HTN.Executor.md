# `Operator.HTN.Executor`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/executor.ex#L1)

Executes HTN plans and primitive tasks.

The Executor bridges the gap between plan generation and actual execution.
While the HTN planner generates plans (sequences of primitive tasks), the
Executor handles running those tasks against your game/simulation state.

## Quick Start

    # Generate a plan
    {:ok, plan} = Operator.HTN.Planner.run(:my_goal, facts, traits)

    # Execute step by step
    case Executor.step(plan, actor, facts) do
      {:ok, :completed, updated_actor, updated_facts} ->
        # Plan finished successfully
        handle_completion(updated_actor)

      {:ok, :continue, updated_actor, updated_facts, remaining_plan} ->
        # More tasks to execute
        loop_execution(remaining_plan, updated_actor, updated_facts)

      {:error, reason, actor, facts, plan} ->
        # Task failed - decide whether to replan or abort
        handle_failure(reason, actor, facts, plan)
    end

    # Or execute entire plan at once
    case Executor.run_plan(plan, actor, facts) do
      {:ok, final_actor, final_facts} ->
        # All tasks completed
        :done

      {:error, reason, actor, facts, remaining_plan} ->
        # Failed mid-execution
        :failed
    end

## Primitive Execution

Primitives defined via the DSL store their `run` function as quoted AST.
The Executor handles compiling and invoking these functions:

    # Direct primitive execution
    primitive = Registry.get_primitive(:attack)
    {:ok, updated_actor} = Executor.execute_primitive(primitive, actor, facts)

## Task Tuples

Plans contain task tuples of the form `{task_name, args}`:

    plan.tasks
    #=> [{:move_to, [:lobby]}, {:hack_terminal, ["server_1"]}, {:extract, []}]

Execute individual task tuples:

    {:ok, actor} = Executor.execute_task({:attack, [:enemy]}, actor, facts)

## Error Handling

Execution functions return tagged tuples:

* `{:ok, actor}` - Task succeeded, returns updated actor
* `{:error, reason}` - Task failed with reason

Common failure reasons:
* `:primitive_not_found` - No primitive registered with that name
* `:no_run_function` - Primitive missing `run` in metadata
* `:execution_failed` - The run function raised or returned error

## Effects

When tasks complete successfully, their `:plan_and_execute` and `:permanent`
effects should be applied to world state. The Executor provides helpers:

    # Get effects to apply after successful execution
    effects = Executor.execution_effects(primitive)
    updated_facts = Operator.HTN.Effect.apply_all(effects, facts)

## Integration with Game Loop

Typical integration pattern:

    defmodule MyGame.AISystem do
      alias Operator.HTN.{Executor, Planner, Facts}

      def tick(entity, world_state) do
        facts = build_facts(entity, world_state)
        traits = entity.genome

        case entity.current_plan do
          nil ->
            # No plan - try to create one
            case Planner.run(pick_goal(entity), facts, traits) do
              {:ok, plan} -> %{entity | current_plan: plan}
              {:error, _} -> entity
            end

          plan ->
            # Have a plan - execute next step
            case Executor.step(plan, entity, facts) do
              {:ok, :completed, updated_entity, _facts, _plan} ->
                %{updated_entity | current_plan: nil}

              {:ok, :continue, updated_entity, _facts, remaining_plan} ->
                %{updated_entity | current_plan: remaining_plan}

              {:error, _reason, entity, _facts, _plan} ->
                %{entity | current_plan: nil}  # Replan next tick
            end
        end
      end
    end

# `plan_result`

```elixir
@type plan_result() ::
  {:ok, any(), Operator.HTN.Facts.t()}
  | {:error, any(), any(), Operator.HTN.Facts.t(), Operator.HTN.Plan.t()}
```

Result of running a complete plan.

* `{:ok, actor, facts}` - All tasks completed successfully
* `{:error, reason, actor, facts, remaining_plan}` - Failed mid-execution

# `step_result`

```elixir
@type step_result() ::
  {:ok, :completed, any(), Operator.HTN.Facts.t(), Operator.HTN.Plan.t()}
  | {:ok, :continue, any(), Operator.HTN.Facts.t(), Operator.HTN.Plan.t()}
  | {:error, any(), any(), Operator.HTN.Facts.t(), Operator.HTN.Plan.t()}
```

Result of a plan execution step.

* `{:ok, :completed, actor, facts, plan}` - Plan finished
* `{:ok, :continue, actor, facts, plan}` - More tasks remain
* `{:error, reason, actor, facts, plan}` - Task failed

# `task_result`

```elixir
@type task_result() :: {:ok, any()} | {:error, atom() | {atom(), any()}}
```

Result of executing a single task.

* `{:ok, actor}` - Success with updated actor state
* `{:error, reason}` - Failure with reason atom or tuple

# `execute_primitive`

```elixir
@spec execute_primitive(Operator.HTN.Task.t(), any(), Operator.HTN.Facts.t(), list()) ::
  task_result()
```

Execute a primitive's run function.

Handles the complexity of extracting and compiling the run function from
the primitive's metadata.

## Parameters

* `primitive` - The primitive Task struct from the registry
* `actor` - Current actor state
* `facts` - Current world state
* `args` - Arguments from the task tuple (default: [])

## Returns

* `{:ok, updated_actor}` - Execution succeeded
* `{:error, reason}` - Execution failed

## Examples

    primitive = Registry.get_primitive(:fire_weapon)
    {:ok, updated_soldier} = Executor.execute_primitive(primitive, soldier, facts)

## Notes

The run function in primitives is stored as quoted AST in `primitive.metadata.run`.
This function handles compiling and invoking it. If the run function is already
compiled (a function reference), it's called directly.

# `execute_task`

```elixir
@spec execute_task(
  Operator.HTN.Plan.task_tuple(),
  any(),
  Operator.HTN.Facts.t(),
  keyword()
) ::
  {:ok, any(), Operator.HTN.Facts.t()} | {:error, any()}
```

Execute a single task tuple.

Looks up the primitive in the registry and executes its run function.

## Parameters

* `task_tuple` - Tuple of `{task_name, args}`
* `actor` - Current actor state
* `facts` - Current world state
* `opts` - Options (reserved for future use)

## Returns

* `{:ok, updated_actor, updated_facts}` - Task succeeded
* `{:error, reason}` - Task failed

## Examples

    case Executor.execute_task({:attack, [:enemy_1]}, warrior, facts) do
      {:ok, warrior, facts} ->
        IO.puts("Attack successful!")

      {:error, :primitive_not_found} ->
        IO.puts("No :attack primitive defined")

      {:error, {:execution_failed, :no_ammo}} ->
        IO.puts("Out of ammo!")
    end

# `execution_effects`

```elixir
@spec execution_effects(Operator.HTN.Task.t()) :: [Operator.HTN.Effect.t()]
```

Get the effects that should be applied after successful task execution.

Returns only `:plan_and_execute` and `:permanent` effects (excludes `:plan_only`).

## Parameters

* `task` - The Task struct

## Returns

List of Effect structs to apply.

## Examples

    primitive = Registry.get_primitive(:unlock_door)
    effects = Executor.execution_effects(primitive)
    # => [%Effect{type: :plan_and_execute, key: {:world, :door_locked}, value: false}]

    updated_facts = Effect.apply_all(effects, facts)

# `run_plan`

```elixir
@spec run_plan(Operator.HTN.Plan.t(), any(), Operator.HTN.Facts.t(), keyword()) ::
  plan_result()
```

Execute an entire plan to completion.

Runs all tasks in sequence until either the plan completes or a task fails.

## Parameters

* `plan` - The plan to execute
* `actor` - Initial actor state
* `facts` - Initial world state
* `opts` - Options:
  * `:on_task_complete` - Callback `fn task_tuple, actor, facts -> :ok end`
  * `:max_steps` - Maximum tasks to execute (default: 1000)

## Returns

* `{:ok, final_actor, final_facts}` - All tasks completed
* `{:error, reason, actor, facts, remaining_plan}` - Failed mid-execution

## Examples

    {:ok, plan} = Planner.run(:build_house, facts, traits)

    case Executor.run_plan(plan, builder, facts) do
      {:ok, builder, facts} ->
        IO.puts("House built!")

      {:error, :no_materials, builder, facts, remaining} ->
        IO.puts("Ran out of materials with #{Plan.task_count(remaining)} tasks left")
    end

# `step`

```elixir
@spec step(Operator.HTN.Plan.t(), any(), Operator.HTN.Facts.t(), keyword()) ::
  step_result()
```

Execute a single step of a plan.

Pops the next task from the plan, executes it, and returns the result
along with the remaining plan.

## Parameters

* `plan` - The plan to execute
* `actor` - Current actor state (passed to primitive run functions)
* `facts` - Current world state
* `opts` - Options (currently unused, reserved for future use)

## Returns

* `{:ok, :completed, actor, facts, plan}` - No more tasks, plan complete
* `{:ok, :continue, actor, facts, remaining_plan}` - Task succeeded, more remain
* `{:error, reason, actor, facts, plan}` - Task failed

## Examples

    {:ok, plan} = Planner.run(:patrol, facts, traits)

    case Executor.step(plan, npc, facts) do
      {:ok, :completed, npc, facts, _plan} ->
        IO.puts("Patrol complete!")
        {npc, facts}

      {:ok, :continue, npc, facts, remaining} ->
        # Store remaining plan for next tick
        {%{npc | plan: remaining}, facts}

      {:error, :primitive_not_found, npc, facts, plan} ->
        IO.puts("Missing primitive - aborting plan")
        {%{npc | plan: nil}, facts}
    end

---

*Consult [api-reference.md](api-reference.md) for complete listing*
