defmodule Operator.HTN.TestHelpersTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Facts, Plan, Registry, TestHelpers}

  describe "reset_registry/1" do
    test "resets registry to empty state" do
      # Put something in the registry first
      :persistent_term.put({Registry, :modules}, MapSet.new([:some_module]))

      :persistent_term.put({Registry, :registry}, %{
        goals: %{test: %{}},
        tasks: %{},
        primitives: %{},
        axioms: %{}
      })

      # Reset it
      assert TestHelpers.reset_registry() == :ok

      # Verify it's empty
      assert Registry.list_goal_names() == []
      assert Registry.modules() == []
    end

    test "accepts context argument for ExUnit setup" do
      assert TestHelpers.reset_registry(%{}) == :ok
    end
  end

  describe "register_modules/1" do
    setup do
      TestHelpers.reset_registry()
      :ok
    end

    test "registers a single module" do
      defmodule SingleTestBehavior do
        use Operator.HTN.DSL, auto_register: false

        goal :single_test_goal do
          decompose do
            task :single_action
          end
        end

        primitive :single_action do
          run fn actor, _facts -> {:ok, actor} end
        end
      end

      assert TestHelpers.register_modules(SingleTestBehavior) == :ok
      assert :single_test_goal in Registry.list_goal_names()
    end

    test "registers a list of modules" do
      defmodule ListTestBehavior1 do
        use Operator.HTN.DSL, auto_register: false

        goal :list_goal_1 do
          decompose do
            task :list_action_1
          end
        end

        primitive :list_action_1 do
          run fn actor, _facts -> {:ok, actor} end
        end
      end

      defmodule ListTestBehavior2 do
        use Operator.HTN.DSL, auto_register: false

        goal :list_goal_2 do
          decompose do
            task :list_action_2
          end
        end

        primitive :list_action_2 do
          run fn actor, _facts -> {:ok, actor} end
        end
      end

      assert TestHelpers.register_modules([ListTestBehavior1, ListTestBehavior2]) == :ok
      assert :list_goal_1 in Registry.list_goal_names()
      assert :list_goal_2 in Registry.list_goal_names()
    end
  end

  describe "setup_htn/1" do
    test "resets and registers modules in one call" do
      defmodule SetupTestBehavior do
        use Operator.HTN.DSL, auto_register: false

        goal :setup_test_goal do
          decompose do
            task :setup_action
          end
        end

        primitive :setup_action do
          run fn actor, _facts -> {:ok, actor} end
        end
      end

      # Put some junk in registry first
      :persistent_term.put({Registry, :registry}, %{
        goals: %{old_junk: %{}},
        tasks: %{},
        primitives: %{},
        axioms: %{}
      })

      assert TestHelpers.setup_htn([SetupTestBehavior]) == :ok

      # Old stuff should be gone
      refute :old_junk in Registry.list_goal_names()
      # New stuff should be there
      assert :setup_test_goal in Registry.list_goal_names()
    end
  end

  describe "with_registry/2" do
    setup do
      TestHelpers.reset_registry()
      :ok
    end

    test "runs function with isolated registry" do
      defmodule IsolatedBehavior do
        use Operator.HTN.DSL, auto_register: false

        goal :isolated_goal do
          decompose do
            task :isolated_action
          end
        end

        primitive :isolated_action do
          run fn actor, _facts -> {:ok, actor} end
        end
      end

      # Register something globally first
      defmodule GlobalBehavior do
        use Operator.HTN.DSL, auto_register: false

        goal :global_goal do
          decompose do
            task :global_action
          end
        end

        primitive :global_action do
          run fn actor, _facts -> {:ok, actor} end
        end
      end

      TestHelpers.register_modules([GlobalBehavior])
      assert :global_goal in Registry.list_goal_names()

      # Run with isolated registry
      result =
        TestHelpers.with_registry([IsolatedBehavior], fn ->
          # Inside, only isolated module should be registered
          assert :isolated_goal in Registry.list_goal_names()
          refute :global_goal in Registry.list_goal_names()
          :returned_value
        end)

      assert result == :returned_value

      # After, global should be restored
      assert :global_goal in Registry.list_goal_names()
    end
  end

  describe "test_facts/1" do
    test "creates Facts struct from map" do
      facts = TestHelpers.test_facts(%{self: %{health: 100}, world: %{zone: :forest}})

      assert Facts.get(facts, {:self, :health}) == 100
      assert Facts.get(facts, {:world, :zone}) == :forest
    end

    test "creates empty Facts with default" do
      facts = TestHelpers.test_facts()

      refute Facts.has?(facts, {:self, :anything})
    end
  end

  describe "assert_has_task/3" do
    test "passes when plan contains task by name" do
      plan = Plan.new(:test, [{:move_to, [:waypoint]}, {:attack, [:enemy]}])

      assert TestHelpers.assert_has_task(plan, :move_to) == true
      assert TestHelpers.assert_has_task(plan, :attack) == true
    end

    test "passes when plan contains task with exact args" do
      plan = Plan.new(:test, [{:move_to, [:waypoint_1]}, {:attack, [:enemy_a]}])

      assert TestHelpers.assert_has_task(plan, :move_to, [:waypoint_1]) == true
      assert TestHelpers.assert_has_task(plan, :attack, [:enemy_a]) == true
    end

    test "raises when task not found" do
      plan = Plan.new(:test, [{:move_to, [:waypoint]}])

      assert_raise ExUnit.AssertionError, fn ->
        TestHelpers.assert_has_task(plan, :nonexistent)
      end
    end

    test "raises when task found but args don't match" do
      plan = Plan.new(:test, [{:move_to, [:waypoint_1]}])

      assert_raise ExUnit.AssertionError, fn ->
        TestHelpers.assert_has_task(plan, :move_to, [:different_waypoint])
      end
    end
  end
end
