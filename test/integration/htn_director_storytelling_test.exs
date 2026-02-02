defmodule Operator.Integration.HTNDirectorStorytellingTest do
  use ExUnit.Case, async: false

  import Operator.HTN.TestHelpers

  alias Operator.Director
  alias Operator.HTN.{Executor, Facts, GoalSelector, Planner}

  defmodule TestStoryteller do
    @behaviour Operator.Storyteller

    @impl true
    def init(_opts), do: %{last_event_tick: 0}

    @impl true
    def pick_event(tick, world_state, state) do
      tension = Map.get(world_state, :tension, 0.0)

      if tension > 0.7 do
        event = %{type: :ambush, severity: round(tension * 5), tick: tick}
        {event, %{state | last_event_tick: tick}}
      else
        {nil, state}
      end
    end
  end

  defmodule TestBehavior do
    use Operator.HTN.DSL, auto_register: false

    goal :respond_to_event do
      precond fn facts ->
        Operator.HTN.Facts.get(facts, {:world, :event_type}) == :ambush
      end

      decompose do
        task :raise_alarm
        task :seek_cover
      end

      metadata priority: 10, domain: :combat
    end

    goal :idle do
      precond fn _facts -> true end

      decompose do
        task :wait
      end

      metadata priority: 1, domain: :idle
    end

    primitive :raise_alarm do
      run fn actor, _facts ->
        {:ok, Map.put(actor, :alarmed, true)}
      end
    end

    primitive :seek_cover do
      run fn actor, _facts ->
        {:ok, Map.put(actor, :in_cover, true)}
      end
    end

    primitive :wait do
      run fn actor, _facts -> {:ok, actor} end
    end
  end

  setup :reset_registry

  setup do
    register_modules([TestBehavior])
    :ok
  end

  test "director event drives goal selection and execution" do
    {:ok, pid} =
      Director.start_link(
        storyteller: TestStoryteller,
        name: :integration_director_1
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    event = Director.tick_sync(%{tick: 10, tension: 0.9}, :integration_director_1)
    assert event.type == :ambush

    facts = Facts.from_perception(%{world: %{event_type: event.type}})
    traits = %{traits: [:brave]}

    assert {:ok, :respond_to_event} = GoalSelector.pick_goal(facts, traits)

    {:ok, plan} = Planner.run(:respond_to_event, facts, traits)

    actor = %{id: 1, alarmed: false, in_cover: false}
    {:ok, actor, _facts} = Executor.run_plan(plan, actor, facts)

    assert actor.alarmed == true
    assert actor.in_cover == true
  end

  test "no event falls back to idle goal" do
    {:ok, pid} =
      Director.start_link(
        storyteller: TestStoryteller,
        name: :integration_director_2
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    event = Director.tick_sync(%{tick: 1, tension: 0.1}, :integration_director_2)
    assert event == nil

    facts = Facts.from_perception(%{world: %{event_type: nil}})
    traits = %{}

    assert {:ok, :idle} = GoalSelector.pick_goal(facts, traits)
    {:ok, plan} = Planner.run(:idle, facts, traits)
    assert length(plan.tasks) == 1
  end
end
