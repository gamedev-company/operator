defmodule Operator.Integration.HTNReplanningTest do
  use ExUnit.Case, async: false

  import Operator.HTN.TestHelpers

  alias Operator.HTN.{Executor, Facts, Planner}

  defmodule PatrolBehavior do
    use Operator.HTN.DSL, auto_register: false

    goal :patrol do
      precond fn facts ->
        Operator.HTN.Facts.get(facts, {:self, :energy}, 0) > 10
      end

      decompose do
        task :move_to_waypoint_1
        task :look_around
      end

      metadata priority: 3, domain: :routine
    end

    goal :rest do
      precond fn facts ->
        Operator.HTN.Facts.get(facts, {:self, :energy}, 0) <= 10
      end

      decompose do
        task :sit_down
      end

      metadata priority: 9, domain: :recovery
    end

    primitive :move_to_waypoint_1 do
      run fn actor, _facts ->
        {:ok, %{actor | position: :waypoint_1}}
      end
    end

    primitive :look_around do
      run fn actor, _facts -> {:ok, actor} end
    end

    primitive :sit_down do
      run fn actor, _facts -> {:ok, %{actor | resting: true}} end
    end
  end

  setup :reset_registry

  setup do
    register_modules([PatrolBehavior])
    :ok
  end

  test "plan invalidation triggers replanning" do
    traits = %{}
    actor = %{id: 1, position: :start, resting: false}

    high_energy_facts = Facts.from_perception(%{self: %{energy: 50}})
    {:ok, patrol_plan} = Planner.run(:patrol, high_energy_facts, traits)

    # Execute one step to show the plan is valid
    {:ok, :continue, actor, facts_after_step, remaining} =
      Executor.step(patrol_plan, actor, high_energy_facts)

    assert length(remaining.tasks) == 1

    # World state changes: energy drops, patrol should become invalid
    low_energy_facts = Facts.put(facts_after_step, {:self, :energy}, 0)
    invalid_plan = Operator.HTN.Plan.invalidate(remaining)

    assert Planner.needs_replan?(invalid_plan, low_energy_facts)

    {:ok, rest_plan} = Planner.run(:rest, low_energy_facts, traits)
    {:ok, actor, _facts} = Executor.run_plan(rest_plan, actor, low_energy_facts)

    assert actor.resting == true
  end
end
