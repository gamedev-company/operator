defmodule Operator.HTN.Trace.ConsoleHandlerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Operator.HTN.{Effect, Facts, Trace}
  alias Operator.HTN.Trace.ConsoleHandler

  describe "on_goal_start/3" do
    test "prints goal start message" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_goal_start(:test_goal, Facts.new(), [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "GOAL"
      assert output =~ "test_goal"
    end
  end

  describe "on_goal_end/3" do
    test "prints goal end with success" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_goal_end(:test_goal, :success, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "GOAL"
      assert output =~ "test_goal"
      assert output =~ "SUCCESS"
    end

    test "prints goal end with failure" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_goal_end(:test_goal, :failure, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "GOAL"
      assert output =~ "test_goal"
      assert output =~ "FAILURE"
    end
  end

  describe "on_precondition_eval/3" do
    test "prints precondition pass" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_precondition_eval(%{goal: :test}, true, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "Precondition"
      assert output =~ "passed"
    end

    test "prints precondition fail" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_precondition_eval(%{task: :test_task}, false, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "Precondition"
      assert output =~ "failed"
    end
  end

  describe "on_task_expand/4" do
    test "prints task expansion" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_task_expand(:move_to, [:waypoint], Facts.new(), [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "TASK"
      assert output =~ "move_to"
      assert output =~ "[:waypoint]"
    end

    test "prints task expansion with empty args" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_task_expand(:wait, [], Facts.new(), [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "TASK"
      assert output =~ "wait"
    end
  end

  describe "on_task_complete/4" do
    test "prints task completion with success" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_task_complete(:move_to, [{:step, []}], :success, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "TASK"
      assert output =~ "move_to"
      assert output =~ "1 subtask"
    end

    test "prints task completion with failure" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_task_complete(:attack, [], :failure, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "TASK"
      assert output =~ "attack"
      assert output =~ "FAILED"
    end
  end

  describe "on_effect_apply/3" do
    test "prints effect application" do
      effect = Effect.new(:plan_and_execute, {:self, :armed}, true)

      output =
        capture_io(fn ->
          ConsoleHandler.on_effect_apply(effect, Facts.new(), [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "Effect"
      assert output =~ "{:self, :armed}"
      assert output =~ "true"
    end
  end

  describe "on_branch_select/3" do
    test "prints branch selection" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_branch_select(:decide_action, :aggressive_path, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "Branch"
      assert output =~ "decide_action"
      assert output =~ "aggressive_path"
    end

    test "handles integer branch id" do
      output =
        capture_io(fn ->
          ConsoleHandler.on_branch_select(:multi_choice, 2, [])
        end)

      assert output =~ "[HTN]"
      assert output =~ "Branch"
      assert output =~ "multi_choice"
      assert output =~ "2"
    end
  end

  describe "integration with Trace" do
    setup do
      # Remember original handler
      original = Trace.get_handler()

      on_exit(fn ->
        if original do
          Trace.set_handler(original)
        else
          Trace.reset()
        end
      end)

      :ok
    end

    test "can be set as trace handler" do
      Trace.set_handler(ConsoleHandler)

      assert Trace.get_handler() == ConsoleHandler
      assert Trace.enabled?()
    end

    test "receives events through Trace module" do
      Trace.set_handler(ConsoleHandler)

      output =
        capture_io(fn ->
          Trace.goal_start(:integration_test, Facts.new())
          Trace.goal_end(:integration_test, :success)
        end)

      assert output =~ "integration_test"
      assert output =~ "GOAL"
      assert output =~ "SUCCESS"
    end
  end
end
