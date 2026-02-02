defmodule Operator.HTN.ExecutorTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Effect, Executor, Facts, Plan, Registry, Task}

  setup do
    Registry.reset()
    :ok
  end

  describe "step/4" do
    test "returns completed when plan has no tasks" do
      plan = Plan.new(:test, [])
      actor = %{id: 1}
      facts = Facts.new()

      {:ok, :completed, returned_actor, returned_facts, returned_plan} =
        Executor.step(plan, actor, facts)

      assert returned_actor == actor
      assert returned_facts == facts
      assert returned_plan.validity == :completed
    end

    test "executes primitive and returns continue when more tasks remain" do
      # Register a primitive
      primitive = %Task{
        name: :test_action,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn actor, _facts -> {:ok, Map.put(actor, :executed, true)} end}
      }

      registry = %{
        goals: %{},
        tasks: %{},
        primitives: %{test_action: primitive},
        axioms: %{}
      }

      plan = Plan.new(:test, [{:test_action, []}, {:test_action, []}])
      actor = %{id: 1}
      facts = Facts.new()

      {:ok, :continue, updated_actor, _updated_facts, remaining_plan} =
        Executor.step(plan, actor, facts, registry: registry)

      assert updated_actor.executed == true
      assert length(remaining_plan.tasks) == 1
    end

    test "executes last primitive and returns completed" do
      primitive = %Task{
        name: :final_action,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn actor, _facts -> {:ok, Map.put(actor, :done, true)} end}
      }

      registry = %{
        goals: %{},
        tasks: %{},
        primitives: %{final_action: primitive},
        axioms: %{}
      }

      plan = Plan.new(:test, [{:final_action, []}])
      actor = %{id: 1}
      facts = Facts.new()

      {:ok, :completed, updated_actor, _facts, completed_plan} =
        Executor.step(plan, actor, facts, registry: registry)

      assert updated_actor.done == true
      assert completed_plan.validity == :completed
    end

    test "returns error when primitive not found" do
      registry = %{goals: %{}, tasks: %{}, primitives: %{}, axioms: %{}}
      plan = Plan.new(:test, [{:nonexistent, []}])
      actor = %{id: 1}
      facts = Facts.new()

      {:error, :primitive_not_found, returned_actor, returned_facts, returned_plan} =
        Executor.step(plan, actor, facts, registry: registry)

      assert returned_actor == actor
      assert returned_facts == facts
      assert returned_plan == plan
    end
  end

  describe "run_plan/4" do
    test "executes all tasks to completion" do
      primitive = %Task{
        name: :increment,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn actor, _facts -> {:ok, Map.update(actor, :count, 1, &(&1 + 1))} end}
      }

      registry = %{
        goals: %{},
        tasks: %{},
        primitives: %{increment: primitive},
        axioms: %{}
      }

      plan = Plan.new(:test, [{:increment, []}, {:increment, []}, {:increment, []}])
      actor = %{count: 0}
      facts = Facts.new()

      {:ok, final_actor, _final_facts} = Executor.run_plan(plan, actor, facts, registry: registry)

      assert final_actor.count == 3
    end

    test "stops on error and returns remaining plan" do
      success_primitive = %Task{
        name: :succeed,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn actor, _facts -> {:ok, actor} end}
      }

      fail_primitive = %Task{
        name: :fail,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn _actor, _facts -> {:error, :intentional_failure} end}
      }

      registry = %{
        goals: %{},
        tasks: %{},
        primitives: %{succeed: success_primitive, fail: fail_primitive},
        axioms: %{}
      }

      plan = Plan.new(:test, [{:succeed, []}, {:fail, []}, {:succeed, []}])
      actor = %{id: 1}
      facts = Facts.new()

      {:error, :intentional_failure, _actor, _facts, remaining_plan} =
        Executor.run_plan(plan, actor, facts, registry: registry)

      # The failing task and subsequent task should remain
      assert length(remaining_plan.tasks) == 2
    end

    test "respects max_steps option" do
      primitive = %Task{
        name: :step,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn actor, _facts -> {:ok, actor} end}
      }

      registry = %{
        goals: %{},
        tasks: %{},
        primitives: %{step: primitive},
        axioms: %{}
      }

      # Create plan with more steps than max
      tasks = for _ <- 1..10, do: {:step, []}
      plan = Plan.new(:test, tasks)
      actor = %{id: 1}
      facts = Facts.new()

      {:error, :max_steps_exceeded, _actor, _facts, remaining_plan} =
        Executor.run_plan(plan, actor, facts, registry: registry, max_steps: 5)

      # Should have 5 tasks remaining (10 - 5 executed)
      assert length(remaining_plan.tasks) == 5
    end

    test "calls on_task_complete callback" do
      test_pid = self()

      primitive = %Task{
        name: :tracked,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn actor, _facts -> {:ok, actor} end}
      }

      registry = %{
        goals: %{},
        tasks: %{},
        primitives: %{tracked: primitive},
        axioms: %{}
      }

      plan = Plan.new(:test, [{:tracked, [:a]}, {:tracked, [:b]}])
      actor = %{id: 1}
      facts = Facts.new()

      callback = fn task, _actor, _facts ->
        send(test_pid, {:completed, task})
      end

      {:ok, _actor, _facts} =
        Executor.run_plan(plan, actor, facts, registry: registry, on_task_complete: callback)

      assert_receive {:completed, {:tracked, [:a]}}
      assert_receive {:completed, {:tracked, [:b]}}
    end
  end

  describe "execute_task/4" do
    test "executes primitive and returns updated actor and facts" do
      primitive = %Task{
        name: :action,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        effects: [Effect.new(:plan_and_execute, {:self, :acted}, true)],
        metadata: %{run: fn actor, _facts -> {:ok, Map.put(actor, :acted, true)} end}
      }

      registry = %{
        goals: %{},
        tasks: %{},
        primitives: %{action: primitive},
        axioms: %{}
      }

      actor = %{id: 1}
      facts = Facts.new()

      {:ok, updated_actor, updated_facts} =
        Executor.execute_task({:action, []}, actor, facts, registry: registry)

      assert updated_actor.acted == true
      assert Facts.get(updated_facts, {:self, :acted}) == true
    end

    test "returns error when primitive not found" do
      registry = %{goals: %{}, tasks: %{}, primitives: %{}, axioms: %{}}
      actor = %{id: 1}
      facts = Facts.new()

      result = Executor.execute_task({:missing, []}, actor, facts, registry: registry)

      assert result == {:error, :primitive_not_found}
    end
  end

  describe "execute_primitive/4" do
    test "executes run function and returns updated actor" do
      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn actor, _facts -> {:ok, Map.put(actor, :ran, true)} end}
      }

      actor = %{id: 1}
      facts = Facts.new()

      {:ok, updated_actor} = Executor.execute_primitive(primitive, actor, facts)

      assert updated_actor.ran == true
    end

    test "handles compiled function references" do
      run_fn = fn actor, _facts -> {:ok, Map.put(actor, :compiled, true)} end

      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: run_fn}
      }

      actor = %{id: 1}
      facts = Facts.new()

      {:ok, updated_actor} = Executor.execute_primitive(primitive, actor, facts)

      assert updated_actor.compiled == true
    end

    test "returns error when run function missing" do
      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{}
      }

      actor = %{id: 1}
      facts = Facts.new()

      result = Executor.execute_primitive(primitive, actor, facts)

      assert result == {:error, :no_run_function}
    end

    test "returns error for invalid run function" do
      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: "not a function"}
      }

      actor = %{id: 1}
      facts = Facts.new()

      result = Executor.execute_primitive(primitive, actor, facts)

      assert result == {:error, :invalid_run_function}
    end

    test "catches execution errors" do
      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn _actor, _facts -> raise "boom" end}
      }

      actor = %{id: 1}
      facts = Facts.new()

      {:error, {:execution_failed, error}} = Executor.execute_primitive(primitive, actor, facts)

      assert %RuntimeError{message: "boom"} = error
    end

    test "handles unexpected return values" do
      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn _actor, _facts -> :unexpected end}
      }

      actor = %{id: 1}
      facts = Facts.new()

      {:error, {:unexpected_return, :unexpected}} =
        Executor.execute_primitive(primitive, actor, facts)
    end

    test "returns error for invalid primitive (not a Task struct)" do
      actor = %{id: 1}
      facts = Facts.new()

      result = Executor.execute_primitive(:not_a_task, actor, facts)

      assert result == {:error, :invalid_primitive}
    end

    test "returns error for nil primitive" do
      actor = %{id: 1}
      facts = Facts.new()

      result = Executor.execute_primitive(nil, actor, facts)

      assert result == {:error, :invalid_primitive}
    end

    test "handles quoted AST run function" do
      # Create a primitive with quoted AST for the run function
      run_ast = quote do: fn actor, _facts -> {:ok, Map.put(actor, :from_ast, true)} end

      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: run_ast}
      }

      actor = %{id: 1}
      facts = Facts.new()

      {:ok, updated_actor} = Executor.execute_primitive(primitive, actor, facts)

      assert updated_actor.from_ast == true
    end

    test "handles throw in run function" do
      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn _actor, _facts -> throw(:thrown_value) end}
      }

      actor = %{id: 1}
      facts = Facts.new()

      {:error, {:execution_failed, {:throw, :thrown_value}}} =
        Executor.execute_primitive(primitive, actor, facts)
    end

    test "handles error return from run function" do
      primitive = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        metadata: %{run: fn _actor, _facts -> {:error, :custom_error} end}
      }

      actor = %{id: 1}
      facts = Facts.new()

      result = Executor.execute_primitive(primitive, actor, facts)

      assert result == {:error, :custom_error}
    end
  end

  describe "execution_effects/1" do
    test "returns empty list for task with empty effects" do
      task = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        effects: [],
        metadata: %{}
      }

      assert Executor.execution_effects(task) == []
    end

    test "returns execution effects excluding plan_only" do
      task = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        effects: [
          Effect.new(:plan_only, {:self, :planning}, true),
          Effect.new(:plan_and_execute, {:self, :executing}, true),
          Effect.new(:permanent, {:self, :permanent}, true)
        ],
        metadata: %{}
      }

      effects = Executor.execution_effects(task)

      assert length(effects) == 2
      assert Enum.all?(effects, fn e -> e.type != :plan_only end)
    end

    test "returns empty list when no effects" do
      task = %Task{
        name: :test,
        type: :primitive,
        preconditions: [],
        decompose: nil,
        cost: 1.0,
        effects: nil,
        metadata: %{}
      }

      assert Executor.execution_effects(task) == []
    end
  end
end
