defmodule Operator.HTN.EngineTest do
  use ExUnit.Case, async: true

  alias Operator.HTN.{Engine, Facts, Plan}

  describe "expand/4" do
    test "expands a goal with decomposition" do
      registry = %{
        goals: %{
          test_goal: %{
            name: :test_goal,
            precond: fn _facts -> true end,
            decompose: fn _facts ->
              [{:task_a, [:arg1]}, {:task_b, []}]
            end
          }
        },
        tasks: %{},
        primitives: %{
          task_a: %Operator.HTN.Task{
            name: :task_a,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          },
          task_b: %Operator.HTN.Task{
            name: :task_b,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:test_goal, facts, %{}, registry)

      assert plan.goal == :test_goal
      assert plan.tasks == [{:task_a, [:arg1]}, {:task_b, []}]
      assert Plan.valid?(plan)
    end

    test "returns error when goal not found" do
      registry = %{goals: %{}, tasks: %{}, primitives: %{}}
      facts = Facts.from_perception(%{})

      result = Engine.expand(:nonexistent, facts, %{}, registry)

      assert result == {:error, :goal_not_found}
    end

    test "returns error when preconditions not met" do
      registry = %{
        goals: %{
          guarded_goal: %{
            name: :guarded_goal,
            precond: fn _facts -> false end,
            decompose: fn _facts -> [] end
          }
        },
        tasks: %{},
        primitives: %{}
      }

      facts = Facts.from_perception(%{})

      result = Engine.expand(:guarded_goal, facts, %{}, registry)

      assert result == {:error, :preconditions_not_met}
    end

    test "handles nil precondition" do
      registry = %{
        goals: %{
          no_precond: %{
            name: :no_precond,
            precond: nil,
            decompose: fn _facts -> [{:action, []}] end
          }
        },
        tasks: %{},
        primitives: %{
          action: %Operator.HTN.Task{
            name: :action,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:no_precond, facts, %{}, registry)

      assert plan.tasks == [{:action, []}]
    end

    test "recursively expands abstract tasks" do
      registry = %{
        goals: %{
          main_goal: %{
            name: :main_goal,
            precond: nil,
            decompose: fn _facts -> [{:abstract_task, []}] end
          }
        },
        tasks: %{
          abstract_task: %Operator.HTN.Task{
            name: :abstract_task,
            type: :abstract,
            preconditions: [],
            decompose: fn _facts -> [{:primitive_a, []}, {:primitive_b, []}] end,
            cost: 1.0,
            metadata: %{}
          }
        },
        primitives: %{
          primitive_a: %Operator.HTN.Task{
            name: :primitive_a,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          },
          primitive_b: %Operator.HTN.Task{
            name: :primitive_b,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:main_goal, facts, %{}, registry)

      assert plan.tasks == [{:primitive_a, []}, {:primitive_b, []}]
    end

    test "respects task preconditions" do
      registry = %{
        goals: %{
          conditional_goal: %{
            name: :conditional_goal,
            precond: nil,
            decompose: fn _facts -> [{:guarded_task, []}, {:always_task, []}] end
          }
        },
        tasks: %{
          guarded_task: %Operator.HTN.Task{
            name: :guarded_task,
            type: :abstract,
            preconditions: [fn _facts -> false end],
            decompose: fn _facts -> [{:should_not_appear, []}] end,
            cost: 1.0,
            metadata: %{}
          }
        },
        primitives: %{
          always_task: %Operator.HTN.Task{
            name: :always_task,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          },
          should_not_appear: %Operator.HTN.Task{
            name: :should_not_appear,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:conditional_goal, facts, %{}, registry)

      # guarded_task should be skipped due to failed precondition
      assert plan.tasks == [{:always_task, []}]
    end

    test "handles goal with nil decompose" do
      registry = %{
        goals: %{
          empty_goal: %{
            name: :empty_goal,
            precond: nil,
            decompose: nil
          }
        },
        tasks: %{},
        primitives: %{}
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:empty_goal, facts, %{}, registry)

      assert plan.tasks == []
    end

    test "handles invalid decompose function" do
      registry = %{
        goals: %{
          bad_goal: %{
            name: :bad_goal,
            precond: nil,
            decompose: "not a function"
          }
        },
        tasks: %{},
        primitives: %{}
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:bad_goal, facts, %{}, registry)

      assert plan.tasks == []
    end

    test "applies effects during planning" do
      registry = %{
        goals: %{
          effect_goal: %{
            name: :effect_goal,
            precond: nil,
            decompose: fn _facts -> [{:unlock, []}, {:enter, []}] end
          }
        },
        tasks: %{},
        primitives: %{
          unlock: %Operator.HTN.Task{
            name: :unlock,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            effects: [Operator.HTN.Effect.new(:plan_only, {:world, :door_unlocked}, true)],
            cost: 1.0,
            metadata: %{}
          },
          enter: %Operator.HTN.Task{
            name: :enter,
            type: :primitive,
            preconditions: [fn facts -> Facts.get(facts, {:world, :door_unlocked}) == true end],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{world: %{}})

      {:ok, plan} = Engine.expand(:effect_goal, facts, %{}, registry)

      # Enter should be in plan because unlock's effect makes its precondition pass
      assert plan.tasks == [{:unlock, []}, {:enter, []}]
    end

    test "handles abstract task without decompose function" do
      registry = %{
        goals: %{
          test_goal: %{
            name: :test_goal,
            precond: nil,
            decompose: fn _facts -> [{:no_decompose_task, [:arg]}] end
          }
        },
        tasks: %{
          no_decompose_task: %Operator.HTN.Task{
            name: :no_decompose_task,
            type: :abstract,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        },
        primitives: %{}
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:test_goal, facts, %{}, registry)

      # Task without decompose is treated like a leaf and added directly
      assert plan.tasks == [{:no_decompose_task, [:arg]}]
    end

    test "evaluates quoted decompose with task argument bindings" do
      registry = %{
        goals: %{
          test_goal: %{
            name: :test_goal,
            precond: nil,
            decompose: fn _facts -> [{:move_to, [:door]}] end
          }
        },
        tasks: %{
          move_to: %Operator.HTN.Task{
            name: :move_to,
            type: :abstract,
            preconditions: [],
            decompose:
              quote do
                fn _facts -> [{:walk, [destination]}] end
              end,
            cost: 1.0,
            metadata: %{args: [{:destination, [], nil}]}
          }
        },
        primitives: %{
          walk: %Operator.HTN.Task{
            name: :walk,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:test_goal, facts, %{}, registry)

      assert plan.tasks == [{:walk, [:door]}]
    end

    test "handles unknown tasks by skipping them" do
      registry = %{
        goals: %{
          test_goal: %{
            name: :test_goal,
            precond: nil,
            decompose: fn _facts -> [{:unknown_task, []}, {:known_task, []}] end
          }
        },
        tasks: %{},
        primitives: %{
          known_task: %Operator.HTN.Task{
            name: :known_task,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:test_goal, facts, %{}, registry)

      # Unknown task is skipped, known task remains
      assert plan.tasks == [{:known_task, []}]
    end

    test "handles task atom without args" do
      registry = %{
        goals: %{
          test_goal: %{
            name: :test_goal,
            precond: nil,
            decompose: fn _facts -> [:simple_task] end
          }
        },
        tasks: %{},
        primitives: %{
          simple_task: %Operator.HTN.Task{
            name: :simple_task,
            type: :primitive,
            preconditions: [],
            decompose: nil,
            cost: 1.0,
            metadata: %{}
          }
        }
      }

      facts = Facts.from_perception(%{})

      {:ok, plan} = Engine.expand(:test_goal, facts, %{}, registry)

      assert plan.tasks == [{:simple_task, []}]
    end
  end

  describe "goal_preconditions_met?/3" do
    test "returns true for nil precondition" do
      goal = %{precond: nil}
      facts = Facts.from_perception(%{})

      assert Engine.goal_preconditions_met?(goal, facts, %{})
    end

    test "evaluates precondition function" do
      goal = %{precond: fn facts -> Facts.has?(facts, {:self, :ready}) end}

      ready_facts = Facts.from_perception(%{self: %{ready: true}})
      not_ready_facts = Facts.from_perception(%{})

      assert Engine.goal_preconditions_met?(goal, ready_facts, %{})
      refute Engine.goal_preconditions_met?(goal, not_ready_facts, %{})
    end

    test "returns false for non-function precondition" do
      goal = %{precond: "not a function"}
      facts = Facts.from_perception(%{})

      assert Engine.goal_preconditions_met?(goal, facts, %{}) == false
    end

    test "returns true for goal without precond key" do
      goal = %{name: :test}
      facts = Facts.from_perception(%{})

      assert Engine.goal_preconditions_met?(goal, facts, %{})
    end
  end
end
