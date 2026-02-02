defmodule Operator.HTN.PlanTest do
  use ExUnit.Case, async: true

  alias Operator.HTN.Plan

  doctest Operator.HTN.Plan

  describe "new/3" do
    test "creates plan with goal and tasks" do
      plan = Plan.new(:infiltrate, [{:move_to, [:lobby]}, {:hack, [:terminal]}])

      assert plan.goal == :infiltrate
      assert plan.tasks == [{:move_to, [:lobby]}, {:hack, [:terminal]}]
      assert plan.validity == :active
      assert is_integer(plan.created_at)
      assert plan.metadata == %{}
    end

    test "accepts validity option" do
      plan = Plan.new(:test, [], validity: :completed)

      assert plan.validity == :completed
    end

    test "accepts metadata option" do
      plan = Plan.new(:test, [], metadata: %{source: :test})

      assert plan.metadata == %{source: :test}
    end

    test "auto-generates created_at timestamp" do
      before = System.os_time(:second)
      plan = Plan.new(:test, [])
      after_time = System.os_time(:second)

      assert plan.created_at >= before
      assert plan.created_at <= after_time
    end
  end

  describe "valid?/1" do
    test "returns true for active plans" do
      plan = Plan.new(:test, [])

      assert Plan.valid?(plan)
    end

    test "returns false for invalid plans" do
      plan = Plan.new(:test, [], validity: :invalid)

      refute Plan.valid?(plan)
    end

    test "returns false for completed plans" do
      plan = Plan.new(:test, [], validity: :completed)

      refute Plan.valid?(plan)
    end
  end

  describe "invalidate/1" do
    test "marks plan as invalid" do
      plan = Plan.new(:test, [])

      invalidated = Plan.invalidate(plan)

      assert invalidated.validity == :invalid
      refute Plan.valid?(invalidated)
    end
  end

  describe "complete/1" do
    test "marks plan as completed" do
      plan = Plan.new(:test, [])

      completed = Plan.complete(plan)

      assert completed.validity == :completed
      refute Plan.valid?(completed)
    end
  end

  describe "next_task/1" do
    test "returns first task and updated plan" do
      plan = Plan.new(:test, [{:task_a, []}, {:task_b, []}])

      {task, remaining} = Plan.next_task(plan)

      assert task == {:task_a, []}
      assert remaining.tasks == [{:task_b, []}]
    end

    test "returns :empty for empty plan" do
      plan = Plan.new(:test, [])

      assert Plan.next_task(plan) == :empty
    end

    test "preserves plan metadata when popping tasks" do
      plan = Plan.new(:test, [{:a, []}], metadata: %{source: :planner})

      {_task, remaining} = Plan.next_task(plan)

      assert remaining.metadata == %{source: :planner}
    end
  end

  describe "task_count/1" do
    test "returns number of remaining tasks" do
      plan = Plan.new(:test, [{:a, []}, {:b, []}, {:c, []}])

      assert Plan.task_count(plan) == 3
    end

    test "returns 0 for empty plan" do
      plan = Plan.new(:test, [])

      assert Plan.task_count(plan) == 0
    end
  end

  describe "has_tasks?/1" do
    test "returns true when tasks exist" do
      plan = Plan.new(:test, [{:a, []}])

      assert Plan.has_tasks?(plan)
    end

    test "returns false when no tasks" do
      plan = Plan.new(:test, [])

      refute Plan.has_tasks?(plan)
    end
  end

  describe "add_metadata/3" do
    test "adds a key-value pair to metadata" do
      plan = Plan.new(:test, [])

      updated = Plan.add_metadata(plan, :debug, true)

      assert updated.metadata == %{debug: true}
    end

    test "merges with existing metadata" do
      plan = Plan.new(:test, [], metadata: %{source: :planner})

      updated = Plan.add_metadata(plan, :priority, 5)

      assert updated.metadata == %{source: :planner, priority: 5}
    end
  end

  describe "get_metadata/3" do
    test "returns value for existing key" do
      plan = Plan.new(:test, [], metadata: %{priority: 5})

      assert Plan.get_metadata(plan, :priority) == 5
    end

    test "returns default for missing key" do
      plan = Plan.new(:test, [])

      assert Plan.get_metadata(plan, :missing, :default) == :default
    end

    test "returns nil by default for missing key" do
      plan = Plan.new(:test, [])

      assert Plan.get_metadata(plan, :missing) == nil
    end
  end
end
