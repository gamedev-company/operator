defmodule Operator.HTN.EffectTest do
  use ExUnit.Case, async: true

  alias Operator.HTN.{Effect, Facts}

  describe "new/3" do
    test "creates plan_only effect" do
      effect = Effect.new(:plan_only, {:self, :temp_flag}, true)

      assert effect.type == :plan_only
      assert effect.key == {:self, :temp_flag}
      assert effect.value == true
    end

    test "creates plan_and_execute effect" do
      effect = Effect.new(:plan_and_execute, {:world, :door_open}, true)

      assert effect.type == :plan_and_execute
      assert effect.key == {:world, :door_open}
      assert effect.value == true
    end

    test "creates permanent effect" do
      effect = Effect.new(:permanent, {:self, :learned_skill}, :hacking)

      assert effect.type == :permanent
      assert effect.key == {:self, :learned_skill}
      assert effect.value == :hacking
    end
  end

  describe "apply/2" do
    test "applies effect to facts" do
      facts = Facts.from_perception(%{self: %{health: 100}})
      effect = Effect.new(:plan_and_execute, {:self, :has_weapon}, true)

      updated = Effect.apply_effect(effect, facts)

      assert Facts.get(updated, {:self, :has_weapon}) == true
      assert Facts.get(updated, {:self, :health}) == 100
    end
  end

  describe "apply_all/2" do
    test "applies multiple effects in order" do
      facts = Facts.from_perception(%{})

      effects = [
        Effect.new(:plan_and_execute, {:self, :a}, 1),
        Effect.new(:plan_and_execute, {:self, :b}, 2),
        Effect.new(:plan_and_execute, {:world, :c}, 3)
      ]

      updated = Effect.apply_all(effects, facts)

      assert Facts.get(updated, {:self, :a}) == 1
      assert Facts.get(updated, {:self, :b}) == 2
      assert Facts.get(updated, {:world, :c}) == 3
    end
  end

  describe "filter_by_type/2" do
    test "filters effects by type" do
      effects = [
        Effect.new(:plan_only, {:self, :a}, 1),
        Effect.new(:plan_and_execute, {:self, :b}, 2),
        Effect.new(:permanent, {:self, :c}, 3),
        Effect.new(:plan_only, {:self, :d}, 4)
      ]

      plan_only = Effect.filter_by_type(effects, :plan_only)
      assert length(plan_only) == 2
      assert Enum.all?(plan_only, &(&1.type == :plan_only))

      permanent = Effect.filter_by_type(effects, :permanent)
      assert length(permanent) == 1
    end
  end

  describe "execution_effects/1" do
    test "excludes plan_only effects" do
      effects = [
        Effect.new(:plan_only, {:self, :a}, 1),
        Effect.new(:plan_and_execute, {:self, :b}, 2),
        Effect.new(:permanent, {:self, :c}, 3)
      ]

      exec_effects = Effect.execution_effects(effects)

      assert length(exec_effects) == 2
      refute Enum.any?(exec_effects, &(&1.type == :plan_only))
    end
  end

  describe "planning_effects/1" do
    test "includes all effects" do
      effects = [
        Effect.new(:plan_only, {:self, :a}, 1),
        Effect.new(:plan_and_execute, {:self, :b}, 2),
        Effect.new(:permanent, {:self, :c}, 3)
      ]

      plan_effects = Effect.planning_effects(effects)

      assert length(plan_effects) == 3
    end
  end
end
