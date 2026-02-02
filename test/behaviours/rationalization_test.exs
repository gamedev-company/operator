defmodule Operator.RationalizationTest do
  use ExUnit.Case, async: false

  alias Operator.Rationalization
  alias Operator.HTN.Plan

  defmodule MockRationalization do
    @behaviour Operator.Rationalization

    @impl true
    def annotate_plan(plan) do
      %{
        custom: true,
        goal: plan.goal
      }
    end

    @impl true
    def apply(event) do
      Map.put(event, :rationalized_by, :mock)
    end
  end

  describe "get_module/0" do
    test "returns nil when not configured" do
      original = Application.get_env(:operator, :rationalization_module)
      Application.delete_env(:operator, :rationalization_module)

      assert Rationalization.get_module() == nil

      if original do
        Application.put_env(:operator, :rationalization_module, original)
      end
    end

    test "returns configured module" do
      original = Application.get_env(:operator, :rationalization_module)
      Application.put_env(:operator, :rationalization_module, MockRationalization)

      assert Rationalization.get_module() == MockRationalization

      if original do
        Application.put_env(:operator, :rationalization_module, original)
      else
        Application.delete_env(:operator, :rationalization_module)
      end
    end
  end

  describe "annotate_plan/1" do
    test "uses default annotation when no module configured" do
      original = Application.get_env(:operator, :rationalization_module)
      Application.delete_env(:operator, :rationalization_module)

      plan = Plan.new(:test_goal, [{:task1, []}, {:task2, []}])
      annotation = Rationalization.annotate_plan(plan)

      assert annotation.plan_id == :test_goal
      assert annotation.explanation =~ "test_goal"
      assert annotation.task_count == 2

      if original do
        Application.put_env(:operator, :rationalization_module, original)
      end
    end

    test "delegates to configured module" do
      original = Application.get_env(:operator, :rationalization_module)
      Application.put_env(:operator, :rationalization_module, MockRationalization)

      plan = Plan.new(:delegated_goal, [{:task, []}])
      annotation = Rationalization.annotate_plan(plan)

      assert annotation.custom == true
      assert annotation.goal == :delegated_goal

      if original do
        Application.put_env(:operator, :rationalization_module, original)
      else
        Application.delete_env(:operator, :rationalization_module)
      end
    end
  end

  describe "apply/1" do
    test "uses default rationalization when no module configured" do
      original = Application.get_env(:operator, :rationalization_module)
      Application.delete_env(:operator, :rationalization_module)

      event = %{type: :test_event, data: "test"}
      rationalized = Rationalization.apply(event)

      assert rationalized.explanation == "An event occurred."
      assert rationalized.effects == []
      assert rationalized.type == :test_event
      assert rationalized.data == "test"

      if original do
        Application.put_env(:operator, :rationalization_module, original)
      end
    end

    test "preserves existing explanation in default mode" do
      original = Application.get_env(:operator, :rationalization_module)
      Application.delete_env(:operator, :rationalization_module)

      event = %{type: :test, explanation: "Custom explanation"}
      rationalized = Rationalization.apply(event)

      assert rationalized.explanation == "Custom explanation"

      if original do
        Application.put_env(:operator, :rationalization_module, original)
      end
    end

    test "delegates to configured module" do
      original = Application.get_env(:operator, :rationalization_module)
      Application.put_env(:operator, :rationalization_module, MockRationalization)

      event = %{type: :delegate_test}
      rationalized = Rationalization.apply(event)

      assert rationalized.rationalized_by == :mock
      assert rationalized.type == :delegate_test

      if original do
        Application.put_env(:operator, :rationalization_module, original)
      else
        Application.delete_env(:operator, :rationalization_module)
      end
    end
  end
end
