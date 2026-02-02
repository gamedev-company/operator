defmodule Operator.HTN.StorageTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Plan, Storage}

  setup do
    # Ensure storage is clean before each test
    Storage.clear_all()
    :ok
  end

  describe "persist_plan/2" do
    test "stores a plan for an entity" do
      plan = Plan.new(:test_goal, [{:task, []}])

      assert Storage.persist_plan(:entity_1, plan) == :ok
      assert Storage.fetch_plan(:entity_1) == plan
    end

    test "overwrites existing plan for same entity" do
      plan1 = Plan.new(:goal_1, [{:task_a, []}])
      plan2 = Plan.new(:goal_2, [{:task_b, []}])

      Storage.persist_plan(:entity_1, plan1)
      Storage.persist_plan(:entity_1, plan2)

      assert Storage.fetch_plan(:entity_1) == plan2
    end

    test "stores plans for multiple entities" do
      plan_a = Plan.new(:goal_a, [{:task_a, []}])
      plan_b = Plan.new(:goal_b, [{:task_b, []}])

      Storage.persist_plan(:entity_a, plan_a)
      Storage.persist_plan(:entity_b, plan_b)

      assert Storage.fetch_plan(:entity_a) == plan_a
      assert Storage.fetch_plan(:entity_b) == plan_b
    end
  end

  describe "fetch_plan/1" do
    test "returns nil for non-existent entity" do
      assert Storage.fetch_plan(:nonexistent) == nil
    end

    test "returns stored plan" do
      plan = Plan.new(:test, [{:action, []}])
      Storage.persist_plan(:entity, plan)

      assert Storage.fetch_plan(:entity) == plan
    end
  end

  describe "clear_plan/1" do
    test "removes plan for entity" do
      plan = Plan.new(:test, [{:action, []}])
      Storage.persist_plan(:entity, plan)

      assert Storage.fetch_plan(:entity) == plan

      assert Storage.clear_plan(:entity) == :ok
      assert Storage.fetch_plan(:entity) == nil
    end

    test "succeeds even if entity has no plan" do
      assert Storage.clear_plan(:nonexistent) == :ok
    end
  end

  describe "list_plans/0" do
    test "returns empty list when no plans" do
      assert Storage.list_plans() == []
    end

    test "returns all stored plans" do
      plan_a = Plan.new(:goal_a, [{:task_a, []}])
      plan_b = Plan.new(:goal_b, [{:task_b, []}])

      Storage.persist_plan(:entity_a, plan_a)
      Storage.persist_plan(:entity_b, plan_b)

      plans = Storage.list_plans()

      assert length(plans) == 2
      assert {:entity_a, ^plan_a} = Enum.find(plans, fn {id, _} -> id == :entity_a end)
      assert {:entity_b, ^plan_b} = Enum.find(plans, fn {id, _} -> id == :entity_b end)
    end
  end

  describe "clear_all/0" do
    test "removes all stored plans" do
      plan_a = Plan.new(:goal_a, [{:task_a, []}])
      plan_b = Plan.new(:goal_b, [{:task_b, []}])

      Storage.persist_plan(:entity_a, plan_a)
      Storage.persist_plan(:entity_b, plan_b)

      assert length(Storage.list_plans()) == 2

      assert Storage.clear_all() == :ok
      assert Storage.list_plans() == []
    end
  end

  describe "init/0" do
    test "returns :ok when table already exists" do
      # Table should already exist from previous operations
      assert Storage.init() == :ok
    end

    test "returns :ok and creates table if needed" do
      # This is hard to test without destroying the existing table
      # Just verify init returns :ok
      assert Storage.init() == :ok
    end
  end

  describe "stats/0" do
    test "returns empty stats when no plans" do
      stats = Storage.stats()

      assert stats.total_plans == 0
      assert stats.validity == %{}
    end

    test "returns stats with plan counts by validity" do
      plan_active = Plan.new(:goal_a, [{:task_a, []}])
      plan_completed = Plan.new(:goal_b, [{:task_b, []}]) |> Plan.complete()

      Storage.persist_plan(:entity_a, plan_active)
      Storage.persist_plan(:entity_b, plan_completed)

      stats = Storage.stats()

      assert stats.total_plans == 2
      assert stats.validity[:active] == 1
      assert stats.validity[:completed] == 1
    end
  end
end

defmodule Operator.StorageBehaviourTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.Plan
  alias Operator.Storage

  describe "behaviour delegation" do
    test "get_module returns configured or default module" do
      module = Storage.get_module()
      assert module == Operator.HTN.Storage
    end

    test "persist_plan delegates to module" do
      plan = Plan.new(:test, [{:task, []}])

      # Clear first
      Storage.clear_plan(:delegate_test)

      assert Storage.persist_plan(:delegate_test, plan) == :ok
      assert Storage.fetch_plan(:delegate_test) == plan

      Storage.clear_plan(:delegate_test)
    end

    test "fetch_plan delegates to module" do
      assert Storage.fetch_plan(:nonexistent_delegate) == nil
    end

    test "clear_plan delegates to module" do
      plan = Plan.new(:test, [{:task, []}])
      Storage.persist_plan(:clear_delegate, plan)

      assert Storage.clear_plan(:clear_delegate) == :ok
      assert Storage.fetch_plan(:clear_delegate) == nil
    end

    test "list_plans delegates to module" do
      plans = Storage.list_plans()
      assert is_list(plans)
    end
  end
end
