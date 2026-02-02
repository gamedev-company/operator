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
end
