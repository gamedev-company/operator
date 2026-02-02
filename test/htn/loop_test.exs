defmodule Operator.HTN.LoopTest do
  use ExUnit.Case, async: false

  import Operator.HTN.TestHelpers

  alias Operator.HTN.{Facts, Loop}

  defmodule TestBehavior do
    use Operator.HTN.DSL, auto_register: false

    goal :patrol do
      precond fn facts ->
        Operator.HTN.Facts.get(facts, {:self, :energy}, 0) > 0
      end

      decompose do
        task :move
        task :wait
      end

      metadata priority: 5, domain: :routine
    end

    primitive :move do
      run fn actor, _facts -> {:ok, %{actor | moved: true}} end
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

  test "tick returns idle when no goal available" do
    facts = Facts.from_perception(%{self: %{energy: 0}})
    actor = %{id: 1}

    result = Loop.tick(nil, actor, facts, %{}, goal: :patrol)

    assert result.status == :idle
    assert result.plan == nil
  end

  test "tick plans and executes one step" do
    facts = Facts.from_perception(%{self: %{energy: 10}})
    actor = %{id: 1, moved: false}

    result = Loop.tick(nil, actor, facts, %{}, goal: :patrol)

    assert result.status == :continue
    assert result.plan != nil
    assert result.actor.moved == true
  end

  test "tick completes when final task finishes" do
    facts = Facts.from_perception(%{self: %{energy: 10}})
    actor = %{id: 1, moved: false}

    first = Loop.tick(nil, actor, facts, %{}, goal: :patrol)
    assert first.status == :continue

    second = Loop.tick(first.plan, first.actor, first.facts, %{}, goal: :patrol)
    assert second.status == :completed
    assert second.plan == nil
  end

  test "tick returns failed when task errors" do
    defmodule ErrorBehavior do
      use Operator.HTN.DSL, auto_register: false

      goal :explode do
        precond fn _facts -> true end

        decompose do
          task :boom
        end
      end

      primitive :boom do
        run fn actor, _facts -> {:error, :boom} end
      end
    end

    register_modules([ErrorBehavior])

    facts = Facts.from_perception(%{self: %{}})
    actor = %{id: 2}

    result = Loop.tick(nil, actor, facts, %{}, goal: :explode)

    assert result.status == :failed
    assert result.reason == :boom
  end
end
