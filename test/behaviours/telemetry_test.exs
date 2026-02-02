defmodule Operator.TelemetryTest do
  use ExUnit.Case, async: false

  alias Operator.Telemetry

  # Mock telemetry module for testing
  defmodule MockTelemetry do
    @behaviour Operator.Telemetry

    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def stop do
      try do
        Agent.stop(__MODULE__)
      catch
        :exit, _ -> :ok
      end
    end

    def get_events do
      Agent.get(__MODULE__, & &1)
    end

    @impl true
    def emit_goal_selected(goal_name, measurements, metadata) do
      Agent.update(__MODULE__, fn events ->
        events ++ [{:goal_selected, goal_name, measurements, metadata}]
      end)

      :ok
    end

    @impl true
    def emit_htn_plan_generated(goal, task_count, duration_ms) do
      Agent.update(__MODULE__, fn events ->
        events ++ [{:plan_generated, goal, task_count, duration_ms}]
      end)

      :ok
    end

    @impl true
    def emit_director_event(event_type, tick) do
      Agent.update(__MODULE__, fn events ->
        events ++ [{:director_event, event_type, tick}]
      end)

      :ok
    end
  end

  describe "get_module/0" do
    test "returns nil when not configured" do
      original = Application.get_env(:operator, :telemetry_module)
      Application.delete_env(:operator, :telemetry_module)

      assert Telemetry.get_module() == nil

      if original do
        Application.put_env(:operator, :telemetry_module, original)
      end
    end

    test "returns configured module" do
      original = Application.get_env(:operator, :telemetry_module)
      Application.put_env(:operator, :telemetry_module, MockTelemetry)

      assert Telemetry.get_module() == MockTelemetry

      if original do
        Application.put_env(:operator, :telemetry_module, original)
      else
        Application.delete_env(:operator, :telemetry_module)
      end
    end
  end

  describe "emit_goal_selected/3" do
    setup do
      MockTelemetry.start_link()
      original = Application.get_env(:operator, :telemetry_module)
      Application.put_env(:operator, :telemetry_module, MockTelemetry)

      on_exit(fn ->
        if original do
          Application.put_env(:operator, :telemetry_module, original)
        else
          Application.delete_env(:operator, :telemetry_module)
        end

        MockTelemetry.stop()
      end)

      :ok
    end

    test "delegates to configured module" do
      assert Telemetry.emit_goal_selected(:attack, %{score: 10}, %{domain: :combat}) == :ok

      events = MockTelemetry.get_events()
      assert {:goal_selected, :attack, %{score: 10}, %{domain: :combat}} in events
    end

    test "accepts default arguments" do
      assert Telemetry.emit_goal_selected(:patrol) == :ok

      events = MockTelemetry.get_events()
      assert {:goal_selected, :patrol, %{}, %{}} in events
    end
  end

  describe "emit_htn_plan_generated/3" do
    setup do
      MockTelemetry.start_link()
      original = Application.get_env(:operator, :telemetry_module)
      Application.put_env(:operator, :telemetry_module, MockTelemetry)

      on_exit(fn ->
        if original do
          Application.put_env(:operator, :telemetry_module, original)
        else
          Application.delete_env(:operator, :telemetry_module)
        end

        MockTelemetry.stop()
      end)

      :ok
    end

    test "delegates to configured module" do
      assert Telemetry.emit_htn_plan_generated(:infiltrate, 5, 100) == :ok

      events = MockTelemetry.get_events()
      assert {:plan_generated, :infiltrate, 5, 100} in events
    end
  end

  describe "emit_director_event/2" do
    setup do
      MockTelemetry.start_link()
      original = Application.get_env(:operator, :telemetry_module)
      Application.put_env(:operator, :telemetry_module, MockTelemetry)

      on_exit(fn ->
        if original do
          Application.put_env(:operator, :telemetry_module, original)
        else
          Application.delete_env(:operator, :telemetry_module)
        end

        MockTelemetry.stop()
      end)

      :ok
    end

    test "delegates to configured module" do
      assert Telemetry.emit_director_event(:story_beat, 42) == :ok

      events = MockTelemetry.get_events()
      assert {:director_event, :story_beat, 42} in events
    end
  end

  describe "no-op behavior when not configured" do
    setup do
      original = Application.get_env(:operator, :telemetry_module)
      Application.delete_env(:operator, :telemetry_module)

      on_exit(fn ->
        if original do
          Application.put_env(:operator, :telemetry_module, original)
        end
      end)

      :ok
    end

    test "emit_goal_selected returns :ok without error" do
      assert Telemetry.emit_goal_selected(:test, %{}, %{}) == :ok
    end

    test "emit_htn_plan_generated returns :ok without error" do
      assert Telemetry.emit_htn_plan_generated(:test, 0, 0) == :ok
    end

    test "emit_director_event returns :ok without error" do
      assert Telemetry.emit_director_event(:test, 0) == :ok
    end
  end
end
