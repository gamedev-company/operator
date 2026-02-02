defmodule Operator.HTN.TaskTest do
  use ExUnit.Case, async: true

  alias Operator.HTN.{Effect, Facts, Task}

  describe "new/3" do
    test "creates task with name and type" do
      task = Task.new(:test_task, :primitive)

      assert task.name == :test_task
      assert task.type == :primitive
    end

    test "creates abstract task" do
      task = Task.new(:high_level, :abstract)

      assert task.name == :high_level
      assert task.type == :abstract
    end

    test "sets default values" do
      task = Task.new(:test, :primitive)

      assert task.preconditions == []
      assert task.decompose == nil
      assert task.effects == []
      assert task.cost == 1.0
      assert task.metadata == %{}
    end

    test "accepts preconditions option" do
      precond = fn _facts -> true end
      task = Task.new(:test, :primitive, preconditions: [precond])

      assert length(task.preconditions) == 1
    end

    test "accepts decompose option" do
      decompose_fn = fn _facts -> [{:subtask, []}] end
      task = Task.new(:test, :abstract, decompose: decompose_fn)

      assert task.decompose == decompose_fn
    end

    test "accepts effects option" do
      effects = [Effect.new(:plan_and_execute, {:self, :key}, true)]
      task = Task.new(:test, :primitive, effects: effects)

      assert task.effects == effects
    end

    test "accepts cost option" do
      task = Task.new(:test, :primitive, cost: 5.0)

      assert task.cost == 5.0
    end

    test "accepts metadata option" do
      task = Task.new(:test, :primitive, metadata: %{animation: "walk"})

      assert task.metadata == %{animation: "walk"}
    end

    test "accepts all options together" do
      precond = fn _facts -> true end
      decompose_fn = fn _facts -> [{:subtask, []}] end
      effects = [Effect.new(:plan_and_execute, {:self, :done}, true)]

      task =
        Task.new(:complete, :abstract,
          preconditions: [precond],
          decompose: decompose_fn,
          effects: effects,
          cost: 10.0,
          metadata: %{priority: :high}
        )

      assert task.name == :complete
      assert task.type == :abstract
      assert length(task.preconditions) == 1
      assert task.decompose == decompose_fn
      assert task.effects == effects
      assert task.cost == 10.0
      assert task.metadata == %{priority: :high}
    end
  end

  describe "preconditions_satisfied?/3" do
    test "returns true for empty preconditions list" do
      task = Task.new(:test, :primitive, preconditions: [])
      facts = Facts.new()
      traits = %{}

      assert Task.preconditions_satisfied?(task, facts, traits) == true
    end

    test "returns true for nil preconditions" do
      task = %Task{name: :test, type: :primitive, preconditions: nil}
      facts = Facts.new()
      traits = %{}

      assert Task.preconditions_satisfied?(task, facts, traits) == true
    end

    test "evaluates single precondition" do
      facts = Facts.from_perception(%{self: %{ready: true}})
      traits = %{}

      passing_task =
        Task.new(:test, :primitive,
          preconditions: [fn facts -> Facts.has?(facts, {:self, :ready}) end]
        )

      failing_task =
        Task.new(:test, :primitive,
          preconditions: [fn facts -> Facts.has?(facts, {:self, :missing}) end]
        )

      assert Task.preconditions_satisfied?(passing_task, facts, traits) == true
      assert Task.preconditions_satisfied?(failing_task, facts, traits) == false
    end

    test "all preconditions must pass (AND semantics)" do
      facts = Facts.from_perception(%{self: %{ready: true, armed: false}})
      traits = %{}

      task =
        Task.new(:test, :primitive,
          preconditions: [
            fn facts -> Facts.has?(facts, {:self, :ready}) end,
            fn facts -> Facts.get(facts, {:self, :armed}) == true end
          ]
        )

      # First passes, second fails -> overall fails
      assert Task.preconditions_satisfied?(task, facts, traits) == false
    end

    test "passes when all preconditions true" do
      facts = Facts.from_perception(%{self: %{ready: true, armed: true}})
      traits = %{}

      task =
        Task.new(:test, :primitive,
          preconditions: [
            fn facts -> Facts.has?(facts, {:self, :ready}) end,
            fn facts -> Facts.get(facts, {:self, :armed}) == true end
          ]
        )

      assert Task.preconditions_satisfied?(task, facts, traits) == true
    end

    test "handles arity-2 preconditions with traits" do
      facts = Facts.from_perception(%{})
      traits = %{traits: [:aggressive]}

      task =
        Task.new(:test, :primitive,
          preconditions: [
            fn _facts, traits -> :aggressive in Map.get(traits, :traits, []) end
          ]
        )

      assert Task.preconditions_satisfied?(task, facts, traits) == true
    end

    test "handles :any logical operator" do
      facts = Facts.from_perception(%{self: %{ranged: true}})
      traits = %{}

      task =
        Task.new(:test, :primitive,
          preconditions: [
            {:any,
             [
               fn facts -> Facts.has?(facts, {:self, :melee}) end,
               fn facts -> Facts.has?(facts, {:self, :ranged}) end
             ]}
          ]
        )

      # Only ranged is true, but :any should pass
      assert Task.preconditions_satisfied?(task, facts, traits) == true
    end

    test "handles :all logical operator" do
      facts = Facts.from_perception(%{self: %{health: 100, stamina: 50}})
      traits = %{}

      task =
        Task.new(:test, :primitive,
          preconditions: [
            {:all,
             [
               fn facts -> Facts.get(facts, {:self, :health}, 0) > 0 end,
               fn facts -> Facts.get(facts, {:self, :stamina}, 0) > 0 end
             ]}
          ]
        )

      assert Task.preconditions_satisfied?(task, facts, traits) == true
    end

    test "handles :not logical operator" do
      facts = Facts.from_perception(%{self: %{stunned: false}})
      traits = %{}

      task =
        Task.new(:test, :primitive,
          preconditions: [
            {:not, fn facts -> Facts.get(facts, {:self, :stunned}) == true end}
          ]
        )

      assert Task.preconditions_satisfied?(task, facts, traits) == true
    end
  end

  describe "calculate_cost/3" do
    test "returns 1.0 for nil cost" do
      task = %Task{name: :test, type: :primitive, cost: nil}
      facts = Facts.new()
      traits = %{}

      assert Task.calculate_cost(task, facts, traits) == 1.0
    end

    test "returns static number cost" do
      task = Task.new(:test, :primitive, cost: 5.0)
      facts = Facts.new()
      traits = %{}

      assert Task.calculate_cost(task, facts, traits) == 5.0
    end

    test "returns integer cost" do
      task = Task.new(:test, :primitive, cost: 10)
      facts = Facts.new()
      traits = %{}

      assert Task.calculate_cost(task, facts, traits) == 10
    end

    test "evaluates arity-1 cost function" do
      task =
        Task.new(:test, :primitive,
          cost: fn facts -> Facts.get(facts, {:world, :distance}, 5) * 2 end
        )

      facts = Facts.from_perception(%{world: %{distance: 10}})
      traits = %{}

      assert Task.calculate_cost(task, facts, traits) == 20
    end

    test "evaluates arity-2 cost function with traits" do
      task =
        Task.new(:test, :primitive,
          cost: fn _facts, traits ->
            aggression = Map.get(traits, :aggression, 1.0)
            10.0 / aggression
          end
        )

      facts = Facts.new()
      traits = %{aggression: 2.0}

      assert Task.calculate_cost(task, facts, traits) == 5.0
    end

    test "returns 1.0 for invalid cost function arity" do
      # This is an edge case - cost function with wrong arity
      task = Task.new(:test, :primitive, cost: fn -> :no_args end)
      facts = Facts.new()
      traits = %{}

      assert Task.calculate_cost(task, facts, traits) == 1.0
    end

    test "returns 1.0 for non-number, non-function cost" do
      task = %Task{name: :test, type: :primitive, cost: "invalid"}
      facts = Facts.new()
      traits = %{}

      assert Task.calculate_cost(task, facts, traits) == 1.0
    end
  end

  describe "abstract?/1" do
    test "returns true for abstract task" do
      task = Task.new(:high_level, :abstract)

      assert Task.abstract?(task) == true
    end

    test "returns false for primitive task" do
      task = Task.new(:action, :primitive)

      assert Task.abstract?(task) == false
    end

    test "returns false for non-task values" do
      assert Task.abstract?(nil) == false
      assert Task.abstract?(%{}) == false
      assert Task.abstract?(:atom) == false
    end
  end

  describe "primitive?/1" do
    test "returns true for primitive task" do
      task = Task.new(:action, :primitive)

      assert Task.primitive?(task) == true
    end

    test "returns false for abstract task" do
      task = Task.new(:high_level, :abstract)

      assert Task.primitive?(task) == false
    end

    test "returns false for non-task values" do
      assert Task.primitive?(nil) == false
      assert Task.primitive?(%{}) == false
      assert Task.primitive?(:atom) == false
    end
  end

  describe "struct defaults" do
    test "can create task with struct syntax" do
      task = %Task{name: :manual, type: :primitive}

      assert task.name == :manual
      assert task.type == :primitive
      assert task.preconditions == nil
      assert task.decompose == nil
      assert task.effects == nil
      assert task.cost == nil
      assert task.metadata == nil
    end
  end
end
