defmodule Operator.HTN.DSLTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Facts, Registry}

  setup do
    Registry.reset()
    :ok
  end

  describe "DSL module definition" do
    test "defines goals" do
      defmodule GoalDSL do
        use Operator.HTN.DSL, auto_register: false

        goal :test_goal do
          precond(fn _facts -> true end)

          decompose do
            task(:step_one)
            task(:step_two, "arg")
          end

          metadata(priority: 5, domain: :test)
        end
      end

      htn = GoalDSL.__htn__()

      assert length(htn.goals) == 1
      [goal] = htn.goals
      assert goal.name == :test_goal
      # Precond is stored as quoted AST before normalization
      assert goal.precond != nil
      # Decompose is stored as {:static_tasks, [...]} before normalization
      assert match?({:static_tasks, _}, goal.decompose)
      assert goal.metadata == %{priority: 5, domain: :test}
    end

    test "defines tasks" do
      defmodule TaskDSL do
        use Operator.HTN.DSL, auto_register: false

        task :simple_task do
          precond(fn facts -> Facts.has?(facts, {:self, :ready}) end)
          cost(2.5)
        end
      end

      htn = TaskDSL.__htn__()

      assert length(htn.tasks) == 1

      simple = hd(htn.tasks)
      assert simple.name == :simple_task
      assert simple.type == :abstract
      assert length(simple.preconditions) == 1
      assert simple.cost == 2.5
    end

    test "task decompose supports static and dynamic forms" do
      defmodule TaskDecomposeDSL do
        use Operator.HTN.DSL, auto_register: false

        task :static_task do
          decompose do
            task(:a)
            task(:b, 1)
          end
        end

        task :dynamic_task do
          decompose fn _facts ->
            [{:move_to, [:target]}]
          end

          metadata %{kind: :dynamic}
        end
      end

      htn = TaskDecomposeDSL.__htn__()

      static_task = Enum.find(htn.tasks, &(&1.name == :static_task))
      dynamic_task = Enum.find(htn.tasks, &(&1.name == :dynamic_task))

      assert match?({:static_tasks, _}, static_task.decompose)
      assert is_tuple(dynamic_task.decompose)
      assert dynamic_task.metadata.kind == :dynamic
    end

    test "defines primitives" do
      defmodule PrimitiveDSL do
        use Operator.HTN.DSL, auto_register: false

        primitive :attack do
          run(fn _actor, _facts -> {:ok, :attacked} end)
          metadata(damage: 10)
        end
      end

      htn = PrimitiveDSL.__htn__()

      assert length(htn.primitives) == 1

      attack = hd(htn.primitives)
      assert attack.name == :attack
      assert attack.type == :primitive
      assert attack.metadata[:damage] == 10
    end

    test "primitive supports map metadata and run function" do
      defmodule PrimitiveMetaDSL do
        use Operator.HTN.DSL, auto_register: false

        primitive :heal do
          run(fn _actor, _facts -> {:ok, :ok} end)
          metadata %{kind: :support, amount: 5}
        end
      end

      htn = PrimitiveMetaDSL.__htn__()
      heal = hd(htn.primitives)

      assert heal.metadata.kind == :support
      assert heal.metadata.amount == 5
      assert is_tuple(heal.metadata.run)
    end

    test "auto-registers by default" do
      defmodule AutoRegister do
        use Operator.HTN.DSL

        goal :auto_goal do
          precond(fn _facts -> true end)

          decompose do
            task(:auto_task)
          end
        end
      end

      # Force compilation to trigger @after_compile
      Code.ensure_compiled!(AutoRegister)

      # Give the registry time to update
      Process.sleep(10)

      assert Registry.get_goal(:auto_goal) != nil
    end

    test "can disable auto-registration" do
      defmodule NoAutoRegister do
        use Operator.HTN.DSL, auto_register: false

        goal :no_auto_goal do
          precond(fn _facts -> true end)

          decompose do
            task(:no_auto_task)
          end
        end
      end

      # This should NOT be in the registry
      assert Registry.get_goal(:no_auto_goal) == nil
    end
  end

  describe "goal decomposition via Registry" do
    test "decompose block becomes function after registration" do
      defmodule DecomposeTest do
        use Operator.HTN.DSL

        goal :decompose_goal do
          precond(fn _facts -> true end)

          decompose do
            task(:first_task)
            task(:second_task, "with_arg")
          end
        end
      end

      Code.ensure_compiled!(DecomposeTest)
      Process.sleep(10)

      # After registration, the goal's decompose should be a function
      goal = Registry.get_goal(:decompose_goal)
      assert goal != nil
      assert is_function(goal.decompose, 1)

      facts = Facts.from_perception(%{})
      tasks = goal.decompose.(facts)

      assert tasks == [
               {:first_task, []},
               {:second_task, ["with_arg"]}
             ]
    end
  end

  describe "precondition via Registry" do
    test "precondition becomes callable function after registration" do
      defmodule PrecondTest do
        use Operator.HTN.DSL

        # Note: Must use full module names in DSL since the code is evaluated
        # at runtime without access to compile-time aliases
        goal :precond_goal do
          precond(fn facts -> Operator.HTN.Facts.has?(facts, {:self, :armed}) end)

          decompose do
            task(:attack)
          end
        end
      end

      Code.ensure_compiled!(PrecondTest)
      Process.sleep(10)

      goal = Registry.get_goal(:precond_goal)
      assert goal != nil
      assert is_function(goal.precond, 1)

      armed_facts = Facts.from_perception(%{self: %{armed: true}})
      unarmed_facts = Facts.from_perception(%{})

      assert goal.precond.(armed_facts)
      refute goal.precond.(unarmed_facts)
    end
  end

  describe "integration with registry" do
    test "registered module's goals can be looked up" do
      defmodule RegistryIntegration do
        use Operator.HTN.DSL

        goal :registry_goal do
          precond(fn _facts -> true end)

          decompose do
            task(:registry_task)
          end

          metadata(domain: :test)
        end
      end

      Code.ensure_compiled!(RegistryIntegration)
      Process.sleep(10)

      goal = Registry.get_goal(:registry_goal)
      assert goal != nil
      assert goal.name == :registry_goal
      assert goal.metadata == %{domain: :test}
    end
  end
end
