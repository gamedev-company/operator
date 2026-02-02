defmodule Operator.HTN.PlannerTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Facts, Plan, Planner, Registry, Task}

  setup do
    Registry.reset()
    :ok
  end

  describe "run/3" do
    test "generates plan for valid goal" do
      registry = %{
        goals: %{
          test_goal: %{
            name: :test_goal,
            precond: nil,
            decompose: fn _facts -> [{:action, []}] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{
          action: %Task{
            name: :action,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        },
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      {:ok, plan} = Planner.run(:test_goal, facts, traits)

      assert plan.goal == :test_goal
      assert plan.tasks == [{:action, []}]
      assert Plan.valid?(plan)
    end

    test "returns error for missing goal" do
      Registry.reset()
      facts = Facts.new()
      traits = %{}

      result = Planner.run(:nonexistent, facts, traits)

      assert result == {:error, :goal_not_found}
    end

    test "returns error when preconditions not met" do
      registry = %{
        goals: %{
          guarded: %{
            name: :guarded,
            precond: fn _facts -> false end,
            decompose: fn _facts -> [] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      result = Planner.run(:guarded, facts, traits)

      assert result == {:error, :preconditions_not_met}
    end

    test "annotates plan with rationalization metadata" do
      registry = %{
        goals: %{
          annotated: %{
            name: :annotated,
            precond: nil,
            decompose: fn _facts -> [{:task, []}] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{
          task: %Task{
            name: :task,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        },
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      {:ok, plan} = Planner.run(:annotated, facts, traits)

      # Should have rationalization metadata
      assert Map.has_key?(plan.metadata, :plan_id)
      assert Map.has_key?(plan.metadata, :explanation)
    end

    test "returns error when budget exceeded" do
      registry = %{
        goals: %{
          test_goal: %{
            name: :test_goal,
            precond: nil,
            decompose: fn _facts -> [{:action, []}] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{
          action: %Task{
            name: :action,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        },
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      result = Planner.run(:test_goal, facts, traits, budget: [max_tasks: 0])

      assert result == {:error, {:budget_exceeded, :max_tasks}}
    end
  end

  describe "explain/3" do
    test "returns structured explanation for valid goal" do
      registry = %{
        goals: %{
          patrol: %{
            name: :patrol,
            precond: fn _facts -> true end,
            decompose: fn _facts -> [{:wait, []}] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{
          wait: %Task{
            name: :wait,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{run: fn actor, _facts -> {:ok, actor} end, args: []}
          }
        },
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      result = Planner.explain(:patrol, facts, %{})

      assert result.result == :ok
      assert result.preconditions_met == true
      assert result.plan.goal == :patrol
    end

    test "returns error details for missing goal" do
      :persistent_term.put({Registry, :registry}, %{goals: %{}, tasks: %{}, primitives: %{}, axioms: %{}})
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      result = Planner.explain(:missing_goal, facts, %{})

      assert result.result == :error
      assert result.reason == :goal_not_found
      assert result.plan == nil
    end
  end

  describe "tick/4" do
    setup do
      registry = %{
        goals: %{
          tick_goal: %{
            name: :tick_goal,
            precond: nil,
            decompose: fn _facts -> [{:tick_action, []}] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{
          tick_action: %Task{
            name: :tick_action,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        },
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      :ok
    end

    test "creates new plan when nil" do
      facts = Facts.new()
      traits = %{}

      plan = Planner.tick(nil, facts, traits, :tick_goal)

      assert plan != nil
      assert plan.goal == :tick_goal
    end

    test "returns existing plan when valid" do
      existing_plan = Plan.new(:tick_goal, [{:tick_action, []}])
      facts = Facts.new()
      traits = %{}

      plan = Planner.tick(existing_plan, facts, traits, :tick_goal)

      assert plan == existing_plan
    end

    test "replans when plan is invalid" do
      invalid_plan = Plan.new(:tick_goal, [{:tick_action, []}]) |> Plan.invalidate()
      facts = Facts.new()
      traits = %{}

      plan = Planner.tick(invalid_plan, facts, traits, :tick_goal)

      assert plan != invalid_plan
      assert Plan.valid?(plan)
    end

    test "replans when plan is completed" do
      completed_plan = Plan.new(:tick_goal, []) |> Plan.complete()
      facts = Facts.new()
      traits = %{}

      plan = Planner.tick(completed_plan, facts, traits, :tick_goal)

      assert plan != completed_plan
      assert Plan.valid?(plan)
    end

    test "returns nil when planning fails" do
      Registry.reset()
      facts = Facts.new()
      traits = %{}

      plan = Planner.tick(nil, facts, traits, :nonexistent_goal)

      assert plan == nil
    end

    test "keeps invalid plan when replanning fails" do
      # Set up registry with a goal that will fail
      registry = %{
        goals: %{
          failing_goal: %{
            name: :failing_goal,
            precond: fn _facts -> false end,
            decompose: fn _facts -> [] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)

      invalid_plan = Plan.new(:old_goal, [{:old_task, []}]) |> Plan.invalidate()
      facts = Facts.new()
      traits = %{}

      plan = Planner.tick(invalid_plan, facts, traits, :failing_goal)

      # Should return the old plan since replanning failed
      assert plan == invalid_plan
    end
  end

  describe "needs_replan?/2" do
    test "returns true for nil plan" do
      assert Planner.needs_replan?(nil, Facts.new())
    end

    test "returns false for active plan" do
      plan = Plan.new(:test, [{:task, []}])

      refute Planner.needs_replan?(plan, Facts.new())
    end

    test "returns true for invalid plan" do
      plan = Plan.new(:test, [{:task, []}]) |> Plan.invalidate()

      assert Planner.needs_replan?(plan, Facts.new())
    end

    test "returns true for completed plan" do
      plan = Plan.new(:test, []) |> Plan.complete()

      assert Planner.needs_replan?(plan, Facts.new())
    end
  end

  describe "run_with_registry/4" do
    test "uses provided registry instead of global" do
      # Global registry has nothing
      Registry.reset()

      # Custom registry has our goal
      custom_registry = %{
        goals: %{
          custom_goal: %{
            name: :custom_goal,
            precond: nil,
            decompose: fn _facts -> [{:custom_action, []}] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{
          custom_action: %Task{
            name: :custom_action,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        },
        axioms: %{}
      }

      facts = Facts.new()
      traits = %{}

      # This should work with custom registry
      {:ok, plan} = Planner.run_with_registry(:custom_goal, facts, traits, custom_registry)

      assert plan.goal == :custom_goal
      assert plan.tasks == [{:custom_action, []}]

      # But fail with global registry
      result = Planner.run(:custom_goal, facts, traits)
      assert result == {:error, :goal_not_found}
    end
  end
end
