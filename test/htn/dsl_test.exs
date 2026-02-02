defmodule Operator.HTN.DSLTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Effect, Facts, Planner, Precondition, Registry, Task}

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
    test "precondition is normalized and evaluated after registration" do
      defmodule PrecondTest do
        use Operator.HTN.DSL

        # Note: Must use full module names in DSL since the code is evaluated
        # at runtime without access to compile-time aliases
        goal :precond_goal do
          precond({:any,
            [
              fn facts -> Operator.HTN.Facts.has?(facts, {:self, :armed}) end,
              fn facts -> Operator.HTN.Facts.has?(facts, {:self, :has_backup}) end
            ]
          })

          decompose do
            task(:attack)
          end
        end
      end

      Code.ensure_compiled!(PrecondTest)
      Process.sleep(10)

      goal = Registry.get_goal(:precond_goal)
      assert goal != nil
      assert is_list(goal.precond)

      armed_facts = Facts.from_perception(%{self: %{armed: true}})
      unarmed_facts = Facts.from_perception(%{})

      assert Precondition.all_satisfied?(goal.precond, armed_facts, %{})
      refute Precondition.all_satisfied?(goal.precond, unarmed_facts, %{})
    end
  end

  describe "effects and cost normalization via Registry" do
    test "primitive effects are normalized to Effect structs" do
      defmodule EffectsPrimitiveDSL do
        use Operator.HTN.DSL

        primitive :wait do
          run(fn actor, _facts -> {:ok, actor} end)

          effects [
            Operator.HTN.Effect.new(:plan_and_execute, {:self, :rested}, true)
          ]
        end
      end

      Code.ensure_compiled!(EffectsPrimitiveDSL)
      Process.sleep(10)

      primitive = Registry.get_primitive(:wait)
      assert primitive != nil
      assert is_list(primitive.effects)
      assert [%Effect{}] = primitive.effects
    end

    test "task cost function is normalized and callable" do
      defmodule CostTaskDSL do
        use Operator.HTN.DSL

        task :expensive do
          cost(fn _facts -> 7.5 end)
        end
      end

      Code.ensure_compiled!(CostTaskDSL)
      Process.sleep(10)

      task = Registry.get_task(:expensive)
      assert task != nil
      assert is_function(task.cost)
      assert Task.calculate_cost(task, Facts.from_perception(%{}), %{}) == 7.5
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

  describe "goal preconditions via Planner" do
    test "goal preconditions with logical operators and axioms are enforced" do
      defmodule PrecondGoalDSL do
        use Operator.HTN.DSL, auto_register: false

        axiom :is_hungry do
          fn facts, args ->
            threshold = Keyword.get(args, :threshold, 0)
            Operator.HTN.Facts.get(facts, {:self, :hunger}, 0) >= threshold
          end
        end

        axiom :prey_visible do
          fn facts, _args ->
            Operator.HTN.Facts.get(facts, {:world, :prey_nearby}, false)
          end
        end

        goal :hunt_prey do
          precond {:all,
            [
              fn facts ->
                Operator.HTN.Facts.get(facts, {:self, :is_predator}, false)
              end,
              {:axiom, :is_hungry, threshold: 40},
              {:axiom, :prey_visible}
            ]
          }

          decompose do
            task :move_stealthily
            task :pounce_attack
          end
        end

        primitive :move_stealthily do
          run fn actor, _facts -> {:ok, actor} end
        end

        primitive :pounce_attack do
          run fn actor, _facts -> {:ok, actor} end
        end
      end

      Code.ensure_compiled!(PrecondGoalDSL)
      Registry.register(PrecondGoalDSL)
      assert Registry.get_axiom(:is_hungry) != nil
      assert Registry.get_axiom(:prey_visible) != nil
      goal = Registry.get_goal(:hunt_prey)
      assert is_list(goal.precond)
      assert [{:all, [cond1 | _rest]}] = goal.precond
      assert is_function(cond1, 1)
      assert Operator.HTN.Axiom.evaluate(Registry.get_axiom(:is_hungry), Facts.from_perception(%{self: %{hunger: 80}}), threshold: 40)
      assert Operator.HTN.Axiom.evaluate(Registry.get_axiom(:prey_visible), Facts.from_perception(%{world: %{prey_nearby: true}}), []) == true
      assert Operator.HTN.Precondition.all_satisfied?(goal.precond, Facts.from_perception(%{self: %{is_predator: true, hunger: 80}, world: %{prey_nearby: true}}), %{})

      failing_facts =
        Facts.from_perception(%{
          self: %{is_predator: false, hunger: 80},
          world: %{prey_nearby: true}
        })

      assert {:error, :preconditions_not_met} = Planner.run(:hunt_prey, failing_facts, %{})

      passing_facts =
        Facts.from_perception(%{
          self: %{is_predator: true, hunger: 80},
          world: %{prey_nearby: true}
        })

      assert {:ok, _plan} = Planner.run(:hunt_prey, passing_facts, %{})
    end
  end
end
