defmodule Operator.DirectorTest do
  use ExUnit.Case, async: false

  alias Operator.Director
  alias Operator.Director.NullStoryteller

  describe "start_link/1" do
    test "starts with default storyteller" do
      {:ok, pid} = Director.start_link(name: :test_director_1)

      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "starts with custom storyteller" do
      defmodule TestStoryteller do
        @behaviour Operator.Storyteller

        @impl true
        def init(_opts), do: %{initialized: true}

        @impl true
        def pick_event(_tick, _world_state, state), do: {nil, state}
      end

      {:ok, pid} =
        Director.start_link(
          storyteller: TestStoryteller,
          name: :test_director_2
        )

      state = Director.get_state(:test_director_2)
      {module, st_state} = state.storyteller

      assert module == TestStoryteller
      assert st_state.initialized == true

      GenServer.stop(pid)
    end
  end

  describe "current_tick/1" do
    test "returns current tick" do
      {:ok, pid} = Director.start_link(name: :test_director_3)

      assert Director.current_tick(:test_director_3) == 0

      GenServer.stop(pid)
    end
  end

  describe "tick/2" do
    test "updates tick counter" do
      {:ok, pid} = Director.start_link(name: :test_director_4)

      Director.tick(%{tick: 42}, :test_director_4)

      # Give the cast time to process
      Process.sleep(10)

      assert Director.current_tick(:test_director_4) == 42

      GenServer.stop(pid)
    end

    test "calls storyteller pick_event" do
      test_pid = self()

      defmodule EventStoryteller do
        @behaviour Operator.Storyteller

        def init(_opts), do: %{test_pid: nil}

        def pick_event(tick, _world_state, state) do
          if state.test_pid do
            send(state.test_pid, {:pick_event_called, tick})
          end

          {nil, state}
        end
      end

      {:ok, pid} =
        Director.start_link(
          storyteller: EventStoryteller,
          name: :test_director_5
        )

      # Update storyteller state to include test pid
      state = Director.get_state(:test_director_5)
      {mod, st_state} = state.storyteller
      new_st_state = Map.put(st_state, :test_pid, test_pid)
      :sys.replace_state(pid, fn s -> %{s | storyteller: {mod, new_st_state}} end)

      Director.tick(%{tick: 1}, :test_director_5)

      assert_receive {:pick_event_called, 1}, 100

      GenServer.stop(pid)
    end
  end

  describe "tick_sync/2" do
    test "returns generated event" do
      defmodule EventGeneratingStoryteller do
        @behaviour Operator.Storyteller

        def init(_opts), do: %{event_count: 0}

        def pick_event(tick, _world_state, state) do
          event = %{
            type: :test_event,
            tick: tick,
            data: "generated"
          }

          {event, %{state | event_count: state.event_count + 1}}
        end
      end

      {:ok, pid} =
        Director.start_link(
          storyteller: EventGeneratingStoryteller,
          name: :test_director_6
        )

      event = Director.tick_sync(%{tick: 10}, :test_director_6)

      assert event.type == :test_event
      assert event.tick == 10

      GenServer.stop(pid)
    end

    test "returns nil when no event generated" do
      {:ok, pid} =
        Director.start_link(
          storyteller: NullStoryteller,
          name: :test_director_7
        )

      event = Director.tick_sync(%{tick: 1}, :test_director_7)

      assert event == nil

      GenServer.stop(pid)
    end
  end

  describe "change_storyteller/2" do
    test "changes active storyteller" do
      defmodule StorytelllerA do
        @behaviour Operator.Storyteller
        def init(_), do: %{name: :a}
        def pick_event(_, _, state), do: {nil, state}
      end

      defmodule StorytelllerB do
        @behaviour Operator.Storyteller
        def init(_), do: %{name: :b}
        def pick_event(_, _, state), do: {nil, state}
      end

      {:ok, pid} =
        Director.start_link(
          storyteller: StorytelllerA,
          name: :test_director_8
        )

      state_before = Director.get_state(:test_director_8)
      {mod_before, st_state_before} = state_before.storyteller
      assert mod_before == StorytelllerA
      assert st_state_before.name == :a

      Director.change_storyteller(StorytelllerB, :test_director_8)

      state_after = Director.get_state(:test_director_8)
      {mod_after, st_state_after} = state_after.storyteller
      assert mod_after == StorytelllerB
      assert st_state_after.name == :b

      GenServer.stop(pid)
    end
  end

  describe "on_event callback" do
    test "calls callback when event generated" do
      test_pid = self()

      defmodule CallbackStoryteller do
        @behaviour Operator.Storyteller
        def init(_), do: %{}

        def pick_event(tick, _, state) do
          {%{type: :callback_test, tick: tick}, state}
        end
      end

      {:ok, pid} =
        Director.start_link(
          storyteller: CallbackStoryteller,
          on_event: fn event -> send(test_pid, {:event_received, event}) end,
          name: :test_director_9
        )

      Director.tick(%{tick: 5}, :test_director_9)

      assert_receive {:event_received, event}, 100
      assert event.type == :callback_test
      assert event.tick == 5

      GenServer.stop(pid)
    end
  end
end
