defmodule Operator.HTN.AxiomTest do
  use ExUnit.Case, async: true

  alias Operator.HTN.{Axiom, Facts, Precondition, Registry}

  doctest Operator.HTN.Axiom

  describe "Axiom.new/3" do
    test "creates an axiom with query function" do
      query_fn = fn facts, args ->
        threshold = Keyword.get(args, :threshold, 50)
        Facts.get(facts, {:self, :health}, 0) > threshold
      end

      axiom = Axiom.new(:health_check, query_fn)

      assert axiom.name == :health_check
      assert is_function(axiom.query_fn, 2)
    end

    test "accepts metadata option" do
      query_fn = fn _facts, _args -> true end
      axiom = Axiom.new(:test, query_fn, metadata: %{domain: :combat})

      assert axiom.metadata == %{domain: :combat}
    end
  end

  describe "Axiom.evaluate/3" do
    test "evaluates axiom with facts and args" do
      query_fn = fn facts, args ->
        threshold = Keyword.get(args, :threshold, 50)
        Facts.get(facts, {:self, :health}, 0) > threshold
      end

      axiom = Axiom.new(:health_check, query_fn)
      facts = Facts.from_perception(%{self: %{health: 75}})

      assert Axiom.evaluate(axiom, facts, threshold: 50)
      refute Axiom.evaluate(axiom, facts, threshold: 80)
    end

    test "uses default args when none provided" do
      query_fn = fn facts, args ->
        threshold = Keyword.get(args, :threshold, 50)
        Facts.get(facts, {:self, :health}, 0) > threshold
      end

      axiom = Axiom.new(:health_check, query_fn)
      facts = Facts.from_perception(%{self: %{health: 75}})

      assert Axiom.evaluate(axiom, facts, [])
    end
  end

  describe "DSL axiom definition" do
    defmodule TestAxiomDomain do
      use Operator.HTN.DSL, auto_register: false

      axiom :has_weapon do
        fn facts, _args ->
          Operator.HTN.Facts.has?(facts, {:self, :weapon})
        end
      end

      axiom :health_above do
        fn facts, args ->
          threshold = Keyword.get(args, :threshold, 50)
          Operator.HTN.Facts.get(facts, {:self, :health}, 0) > threshold
        end
      end

      axiom :enemy_nearby do
        fn facts, args ->
          max_distance = Keyword.get(args, :max_distance, 10.0)
          distance = Operator.HTN.Facts.get(facts, {:world, :enemy_distance}, 999)
          distance <= max_distance
        end
      end

      goal :attack do
        precond(fn facts -> Operator.HTN.Facts.has?(facts, {:self, :ready}) end)

        decompose do
          task(:engage)
        end
      end

      primitive :engage do
        run(fn actor, _facts -> {:ok, actor} end)
      end
    end

    setup do
      Registry.reset()
      Registry.register(TestAxiomDomain)
      :ok
    end

    test "axioms are registered" do
      assert Registry.get_axiom(:has_weapon) != nil
      assert Registry.get_axiom(:health_above) != nil
      assert Registry.get_axiom(:enemy_nearby) != nil
    end

    test "axiom query functions are evaluated" do
      axiom = Registry.get_axiom(:has_weapon)
      facts = Facts.from_perception(%{self: %{weapon: :sword}})

      assert Axiom.evaluate(axiom, facts, [])
    end

    test "axiom with args works" do
      axiom = Registry.get_axiom(:health_above)
      facts = Facts.from_perception(%{self: %{health: 75}})

      assert Axiom.evaluate(axiom, facts, threshold: 50)
      refute Axiom.evaluate(axiom, facts, threshold: 80)
    end

    test "list_axiom_names returns registered axiom names" do
      names = Registry.list_axiom_names()

      assert :has_weapon in names
      assert :health_above in names
      assert :enemy_nearby in names
    end

    test "stats includes axiom count" do
      stats = Registry.stats()

      assert stats.axioms == 3
    end
  end

  describe "Precondition axiom evaluation" do
    defmodule PrecondAxiomDomain do
      use Operator.HTN.DSL, auto_register: false

      axiom :is_armed do
        fn facts, _args ->
          Operator.HTN.Facts.has?(facts, {:self, :weapon})
        end
      end

      axiom :distance_check do
        fn facts, args ->
          max_dist = Keyword.get(args, :max_distance, 10)
          dist = Operator.HTN.Facts.get(facts, {:world, :target_distance}, 999)
          dist <= max_dist
        end
      end
    end

    setup do
      Registry.reset()
      Registry.register(PrecondAxiomDomain)
      :ok
    end

    test "evaluates axiom with no args" do
      facts = Facts.from_perception(%{self: %{weapon: :rifle}})

      assert Precondition.satisfied?({:axiom, :is_armed}, facts, %{})
    end

    test "evaluates axiom with args" do
      facts = Facts.from_perception(%{world: %{target_distance: 5}})

      assert Precondition.satisfied?({:axiom, :distance_check, max_distance: 10}, facts, %{})
      refute Precondition.satisfied?({:axiom, :distance_check, max_distance: 3}, facts, %{})
    end

    test "unknown axiom returns false" do
      facts = Facts.from_perception(%{})

      refute Precondition.satisfied?({:axiom, :nonexistent}, facts, %{})
    end

    test "axiom in nested operators" do
      facts =
        Facts.from_perception(%{
          self: %{weapon: :pistol},
          world: %{target_distance: 5}
        })

      condition =
        {:all,
         [
           {:axiom, :is_armed},
           {:axiom, :distance_check, max_distance: 10}
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "axiom with OR operator" do
      facts = Facts.from_perception(%{self: %{}})

      condition =
        {:any,
         [
           {:axiom, :is_armed},
           fn facts -> Operator.HTN.Facts.has?(facts, {:self, :cover}) end
         ]}

      refute Precondition.satisfied?(condition, facts, %{})

      facts_with_cover = Facts.from_perception(%{self: %{cover: true}})
      assert Precondition.satisfied?(condition, facts_with_cover, %{})
    end
  end
end
