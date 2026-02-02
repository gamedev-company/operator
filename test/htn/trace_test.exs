defmodule Operator.HTN.TraceTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Effect, Facts, Registry, Trace}

  # Test trace handler that records events
  defmodule RecordingHandler do
    use Agent

    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def stop do
      if Process.whereis(__MODULE__) do
        Agent.stop(__MODULE__)
      end
    end

    def get_events do
      Agent.get(__MODULE__, & &1)
    end

    def clear do
      Agent.update(__MODULE__, fn _ -> [] end)
    end

    defp record(event) do
      Agent.update(__MODULE__, fn events -> events ++ [event] end)
      :ok
    end

    # Handler callbacks
    def on_goal_start(goal_name, _facts, _opts) do
      record({:goal_start, goal_name})
    end

    def on_goal_end(goal_name, result, _opts) do
      record({:goal_end, goal_name, result})
    end

    def on_precondition_eval(context, result, _opts) do
      record({:precondition_eval, context, result})
    end

    def on_task_expand(task_name, args, _facts, _opts) do
      record({:task_expand, task_name, args})
    end

    def on_task_complete(task_name, result_tasks, status, _opts) do
      record({:task_complete, task_name, length(result_tasks), status})
    end

    def on_effect_apply(effect, _facts, _opts) do
      record({:effect_apply, effect.key, effect.value})
    end

    def on_branch_select(task_name, branch_id, _opts) do
      record({:branch_select, task_name, branch_id})
    end
  end

  setup do
    Trace.reset()
    RecordingHandler.start_link()
    Registry.reset()

    on_exit(fn ->
      Trace.reset()
      RecordingHandler.stop()
    end)

    :ok
  end

  describe "Trace configuration" do
    test "enabled? returns false when no handler" do
      refute Trace.enabled?()
    end

    test "enabled? returns true when handler set" do
      Trace.set_handler(RecordingHandler)
      assert Trace.enabled?()
    end

    test "get_handler returns nil when not set" do
      assert Trace.get_handler() == nil
    end

    test "get_handler returns handler when set" do
      Trace.set_handler(RecordingHandler)
      assert Trace.get_handler() == RecordingHandler
    end

    test "reset clears handler" do
      Trace.set_handler(RecordingHandler)
      assert Trace.enabled?()
      Trace.reset()
      refute Trace.enabled?()
    end
  end

  describe "Trace events" do
    setup do
      Trace.set_handler(RecordingHandler)
      :ok
    end

    test "goal_start records event" do
      facts = Facts.from_perception(%{})
      Trace.goal_start(:test_goal, facts)

      events = RecordingHandler.get_events()
      assert {:goal_start, :test_goal} in events
    end

    test "goal_end records event" do
      Trace.goal_end(:test_goal, :success)

      events = RecordingHandler.get_events()
      assert {:goal_end, :test_goal, :success} in events
    end

    test "precondition_eval records event" do
      Trace.precondition_eval(%{goal: :test_goal}, true)

      events = RecordingHandler.get_events()
      assert {:precondition_eval, %{goal: :test_goal}, true} in events
    end

    test "task_expand records event" do
      facts = Facts.from_perception(%{})
      Trace.task_expand(:test_task, [:arg1], facts)

      events = RecordingHandler.get_events()
      assert {:task_expand, :test_task, [:arg1]} in events
    end

    test "task_complete records event" do
      Trace.task_complete(:test_task, [{:subtask, []}], :success)

      events = RecordingHandler.get_events()
      assert {:task_complete, :test_task, 1, :success} in events
    end

    test "effect_apply records event" do
      facts = Facts.from_perception(%{})
      effect = Effect.new(:plan_and_execute, {:self, :armed}, true)
      Trace.effect_apply(effect, facts)

      events = RecordingHandler.get_events()
      assert {:effect_apply, {:self, :armed}, true} in events
    end

    test "branch_select records event" do
      Trace.branch_select(:test_task, :combat_branch)

      events = RecordingHandler.get_events()
      assert {:branch_select, :test_task, :combat_branch} in events
    end
  end

  describe "Trace with disabled handler" do
    test "events are no-ops when handler not set" do
      facts = Facts.from_perception(%{})

      # These should all return :ok without errors
      assert Trace.goal_start(:test, facts) == :ok
      assert Trace.goal_end(:test, :success) == :ok
      assert Trace.precondition_eval(%{}, true) == :ok
      assert Trace.task_expand(:test, [], facts) == :ok
      assert Trace.task_complete(:test, [], :success) == :ok
      assert Trace.branch_select(:test, :branch) == :ok
    end
  end

  describe "Engine integration" do
    defmodule TracedDomain do
      use Operator.HTN.DSL, auto_register: false

      goal :traced_goal do
        precond(fn facts -> Operator.HTN.Facts.has?(facts, {:self, :ready}) end)

        decompose do
          task(:traced_action)
        end
      end

      primitive :traced_action do
        run(fn actor, _facts -> {:ok, actor} end)
      end
    end

    setup do
      Trace.set_handler(RecordingHandler)
      Registry.register(TracedDomain)
      :ok
    end

    test "engine emits trace events during planning" do
      facts = Facts.from_perception(%{self: %{ready: true}})

      {:ok, _plan} = Operator.HTN.Engine.expand(:traced_goal, facts, %{})

      events = RecordingHandler.get_events()

      # Check for key events in order
      assert {:goal_start, :traced_goal} in events
      assert {:precondition_eval, %{goal: :traced_goal}, true} in events
      assert {:goal_end, :traced_goal, :success} in events
    end

    test "engine traces precondition failures" do
      # Empty facts - :ready key doesn't exist
      facts = Facts.from_perception(%{self: %{}})

      {:error, :preconditions_not_met} = Operator.HTN.Engine.expand(:traced_goal, facts, %{})

      events = RecordingHandler.get_events()

      assert {:goal_start, :traced_goal} in events
      assert {:precondition_eval, %{goal: :traced_goal}, false} in events
      assert {:goal_end, :traced_goal, :failure} in events
    end
  end
end
