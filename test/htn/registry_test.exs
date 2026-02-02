defmodule Operator.HTN.RegistryTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.Registry

  setup do
    Registry.reset()
    :ok
  end

  describe "all/0" do
    test "returns empty registry by default" do
      registry = Registry.all()

      assert registry == %{goals: %{}, tasks: %{}, primitives: %{}, axioms: %{}}
    end
  end

  describe "register/1" do
    test "registers a module with __htn__/0" do
      defmodule TestHTN do
        def __htn__ do
          %{
            goals: [%{name: :test_goal, precond: nil, decompose: nil, metadata: %{}}],
            tasks: [],
            primitives: []
          }
        end
      end

      Registry.register(TestHTN)

      assert Registry.get_goal(:test_goal) != nil
    end

    test "ignores modules without __htn__/0" do
      defmodule NonHTN do
        def other_function, do: :ok
      end

      assert Registry.register(NonHTN) == :ok
      assert Registry.all() == %{goals: %{}, tasks: %{}, primitives: %{}, axioms: %{}}
    end
  end

  describe "get_goal/2" do
    test "returns goal by name" do
      defmodule GoalModule do
        def __htn__ do
          %{
            goals: [%{name: :my_goal, precond: nil, decompose: nil, metadata: %{priority: 5}}],
            tasks: [],
            primitives: []
          }
        end
      end

      Registry.register(GoalModule)

      goal = Registry.get_goal(:my_goal)

      assert goal.name == :my_goal
      assert goal.metadata == %{priority: 5}
    end

    test "returns nil for unknown goal" do
      assert Registry.get_goal(:unknown) == nil
    end
  end

  describe "get_task/2" do
    test "returns task by name" do
      defmodule TaskModule do
        def __htn__ do
          %{
            goals: [],
            tasks: [
              %Operator.HTN.Task{
                name: :my_task,
                type: :abstract,
                preconditions: [],
                decompose: nil,
                cost: 1.0,
                metadata: %{}
              }
            ],
            primitives: []
          }
        end
      end

      Registry.register(TaskModule)

      task = Registry.get_task(:my_task)

      assert task.name == :my_task
      assert task.type == :abstract
    end
  end

  describe "get_primitive/2" do
    test "returns primitive by name" do
      defmodule PrimitiveModule do
        def __htn__ do
          %{
            goals: [],
            tasks: [],
            primitives: [
              %Operator.HTN.Task{
                name: :my_primitive,
                type: :primitive,
                preconditions: [],
                decompose: nil,
                cost: 1.0,
                metadata: %{}
              }
            ]
          }
        end
      end

      Registry.register(PrimitiveModule)

      primitive = Registry.get_primitive(:my_primitive)

      assert primitive.name == :my_primitive
      assert primitive.type == :primitive
    end
  end

  describe "merge/1" do
    test "merges multiple registries" do
      registry1 = %{
        goals: %{goal1: %{name: :goal1}},
        tasks: %{},
        primitives: %{}
      }

      registry2 = %{
        goals: %{goal2: %{name: :goal2}},
        tasks: %{task1: %{name: :task1}},
        primitives: %{}
      }

      merged = Registry.merge([registry1, registry2])

      assert Map.has_key?(merged.goals, :goal1)
      assert Map.has_key?(merged.goals, :goal2)
      assert Map.has_key?(merged.tasks, :task1)
    end
  end

  describe "stats/0" do
    test "returns counts for each category" do
      defmodule StatsModule do
        def __htn__ do
          %{
            goals: [
              %{name: :goal1, precond: nil, decompose: nil, metadata: %{}},
              %{name: :goal2, precond: nil, decompose: nil, metadata: %{}}
            ],
            tasks: [
              %Operator.HTN.Task{
                name: :task1,
                type: :abstract,
                preconditions: [],
                decompose: nil,
                cost: 1.0,
                metadata: %{}
              }
            ],
            primitives: []
          }
        end
      end

      Registry.register(StatsModule)

      stats = Registry.stats()

      assert stats.goals == 2
      assert stats.tasks == 1
      assert stats.primitives == 0
    end
  end

  describe "list_*_names/0" do
    test "lists registered names" do
      defmodule ListModule do
        def __htn__ do
          %{
            goals: [%{name: :list_goal, precond: nil, decompose: nil, metadata: %{}}],
            tasks: [
              %Operator.HTN.Task{
                name: :list_task,
                type: :abstract,
                preconditions: [],
                decompose: nil,
                cost: 1.0,
                metadata: %{}
              }
            ],
            primitives: [
              %Operator.HTN.Task{
                name: :list_primitive,
                type: :primitive,
                preconditions: [],
                decompose: nil,
                cost: 1.0,
                metadata: %{}
              }
            ]
          }
        end
      end

      Registry.register(ListModule)

      assert :list_goal in Registry.list_goal_names()
      assert :list_task in Registry.list_task_names()
      assert :list_primitive in Registry.list_primitive_names()
    end
  end
end
