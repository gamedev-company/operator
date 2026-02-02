defmodule Operator.HTN.PreconditionTest do
  use ExUnit.Case, async: true

  alias Operator.HTN.{Facts, Precondition}

  doctest Operator.HTN.Precondition

  describe "simple function evaluation" do
    test "arity-1 function with facts" do
      facts = Facts.from_perception(%{self: %{ready: true}})

      condition = fn facts -> Facts.has?(facts, {:self, :ready}) end

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "arity-2 function with facts and traits" do
      facts = Facts.from_perception(%{self: %{aggression: 5}})
      traits = %{threshold: 3}

      condition = fn facts, traits ->
        Facts.get(facts, {:self, :aggression}, 0) > traits.threshold
      end

      assert Precondition.satisfied?(condition, facts, traits)
    end

    test "failing condition" do
      facts = Facts.from_perception(%{self: %{ready: false}})

      condition = fn facts -> Facts.get(facts, {:self, :ready}, false) end

      refute Precondition.satisfied?(condition, facts, %{})
    end
  end

  describe ":all operator (AND)" do
    test "all conditions pass" do
      facts = Facts.from_perception(%{self: %{ready: true, armed: true}})

      condition =
        {:all,
         [
           fn facts -> Facts.has?(facts, {:self, :ready}) end,
           fn facts -> Facts.has?(facts, {:self, :armed}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "one condition fails" do
      facts = Facts.from_perception(%{self: %{ready: true, armed: false}})

      condition =
        {:all,
         [
           fn facts -> Facts.has?(facts, {:self, :ready}) end,
           fn facts -> Facts.get(facts, {:self, :armed}, false) end
         ]}

      refute Precondition.satisfied?(condition, facts, %{})
    end

    test "empty list passes" do
      facts = Facts.from_perception(%{})
      assert Precondition.satisfied?({:all, []}, facts, %{})
    end
  end

  describe ":any operator (OR)" do
    test "first condition passes" do
      facts = Facts.from_perception(%{self: %{has_weapon: true}})

      condition =
        {:any,
         [
           fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
           fn facts -> Facts.has?(facts, {:self, :has_grenade}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "second condition passes" do
      facts = Facts.from_perception(%{self: %{has_grenade: true}})

      condition =
        {:any,
         [
           fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
           fn facts -> Facts.has?(facts, {:self, :has_grenade}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "no conditions pass" do
      facts = Facts.from_perception(%{self: %{}})

      condition =
        {:any,
         [
           fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
           fn facts -> Facts.has?(facts, {:self, :has_grenade}) end
         ]}

      refute Precondition.satisfied?(condition, facts, %{})
    end
  end

  describe ":first operator (ALT)" do
    test "first matching alternative wins" do
      facts = Facts.from_perception(%{self: %{has_ranged: true, has_melee: true}})

      condition =
        {:first,
         [
           fn facts -> Facts.has?(facts, {:self, :has_ranged}) end,
           fn facts -> Facts.has?(facts, {:self, :has_melee}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "fallback to second alternative" do
      facts = Facts.from_perception(%{self: %{has_melee: true}})

      condition =
        {:first,
         [
           fn facts -> Facts.has?(facts, {:self, :has_ranged}) end,
           fn facts -> Facts.has?(facts, {:self, :has_melee}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end
  end

  describe ":not operator" do
    test "negates true to false" do
      facts = Facts.from_perception(%{self: %{in_combat: true}})

      condition = {:not, fn facts -> Facts.get(facts, {:self, :in_combat}, false) end}

      refute Precondition.satisfied?(condition, facts, %{})
    end

    test "negates false to true" do
      facts = Facts.from_perception(%{self: %{in_combat: false}})

      condition = {:not, fn facts -> Facts.get(facts, {:self, :in_combat}, false) end}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "negates missing key to true" do
      facts = Facts.from_perception(%{self: %{}})

      condition = {:not, fn facts -> Facts.has?(facts, {:self, :in_combat}) end}

      assert Precondition.satisfied?(condition, facts, %{})
    end
  end

  describe ":none operator" do
    test "all conditions fail passes" do
      facts = Facts.from_perception(%{self: %{}})

      condition =
        {:none,
         [
           fn facts -> Facts.has?(facts, {:self, :dead}) end,
           fn facts -> Facts.has?(facts, {:self, :stunned}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "any condition passes fails" do
      facts = Facts.from_perception(%{self: %{stunned: true}})

      condition =
        {:none,
         [
           fn facts -> Facts.has?(facts, {:self, :dead}) end,
           fn facts -> Facts.has?(facts, {:self, :stunned}) end
         ]}

      refute Precondition.satisfied?(condition, facts, %{})
    end
  end

  describe "nested operators" do
    test "AND containing OR" do
      facts = Facts.from_perception(%{self: %{has_cover: true, has_weapon: true}})

      condition =
        {:all,
         [
           fn facts -> Facts.has?(facts, {:self, :has_cover}) end,
           {:any,
            [
              fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
              fn facts -> Facts.has?(facts, {:self, :has_grenade}) end
            ]}
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "OR containing AND" do
      facts = Facts.from_perception(%{self: %{has_cover: true, has_weapon: true}})

      condition =
        {:any,
         [
           {:all,
            [
              fn facts -> Facts.has?(facts, {:self, :has_cover}) end,
              fn facts -> Facts.has?(facts, {:self, :has_weapon}) end
            ]},
           fn facts -> Facts.has?(facts, {:self, :invincible}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end

    test "deeply nested operators" do
      facts = Facts.from_perception(%{self: %{a: true, b: true, c: true}})

      condition =
        {:all,
         [
           {:any, [fn facts -> Facts.has?(facts, {:self, :a}) end]},
           {:not, {:none, [fn facts -> Facts.has?(facts, {:self, :b}) end]}},
           fn facts -> Facts.has?(facts, {:self, :c}) end
         ]}

      assert Precondition.satisfied?(condition, facts, %{})
    end
  end

  describe "find_first_match/3" do
    test "returns index of first match" do
      facts = Facts.from_perception(%{self: %{option_b: true, option_c: true}})

      conditions = [
        fn facts -> Facts.has?(facts, {:self, :option_a}) end,
        fn facts -> Facts.has?(facts, {:self, :option_b}) end,
        fn facts -> Facts.has?(facts, {:self, :option_c}) end
      ]

      assert {:ok, 1} = Precondition.find_first_match(conditions, facts, %{})
    end

    test "returns :none when nothing matches" do
      facts = Facts.from_perception(%{self: %{}})

      conditions = [
        fn facts -> Facts.has?(facts, {:self, :option_a}) end,
        fn facts -> Facts.has?(facts, {:self, :option_b}) end
      ]

      assert :none = Precondition.find_first_match(conditions, facts, %{})
    end
  end

  describe "find_all_matches/3" do
    test "returns all matching indices" do
      facts = Facts.from_perception(%{self: %{option_a: true, option_c: true}})

      conditions = [
        fn facts -> Facts.has?(facts, {:self, :option_a}) end,
        fn facts -> Facts.has?(facts, {:self, :option_b}) end,
        fn facts -> Facts.has?(facts, {:self, :option_c}) end
      ]

      assert [0, 2] = Precondition.find_all_matches(conditions, facts, %{})
    end

    test "returns empty list when nothing matches" do
      facts = Facts.from_perception(%{self: %{}})

      conditions = [
        fn facts -> Facts.has?(facts, {:self, :option_a}) end,
        fn facts -> Facts.has?(facts, {:self, :option_b}) end
      ]

      assert [] = Precondition.find_all_matches(conditions, facts, %{})
    end
  end

  describe "all_satisfied?/3" do
    test "empty list returns true" do
      facts = Facts.from_perception(%{})
      assert Precondition.all_satisfied?([], facts, %{})
    end

    test "all simple conditions pass" do
      facts = Facts.from_perception(%{self: %{a: true, b: true}})

      conditions = [
        fn facts -> Facts.has?(facts, {:self, :a}) end,
        fn facts -> Facts.has?(facts, {:self, :b}) end
      ]

      assert Precondition.all_satisfied?(conditions, facts, %{})
    end

    test "mixed conditions with operators" do
      facts = Facts.from_perception(%{self: %{a: true, c: true}})

      conditions = [
        fn facts -> Facts.has?(facts, {:self, :a}) end,
        {:any,
         [
           fn facts -> Facts.has?(facts, {:self, :b}) end,
           fn facts -> Facts.has?(facts, {:self, :c}) end
         ]}
      ]

      assert Precondition.all_satisfied?(conditions, facts, %{})
    end
  end

  describe "evaluate/3" do
    test "returns {true, %{}} when condition satisfied" do
      facts = Facts.from_perception(%{self: %{ready: true}})
      condition = fn facts -> Facts.has?(facts, {:self, :ready}) end

      assert {true, %{}} = Precondition.evaluate(condition, facts, %{})
    end

    test "returns {false, nil} when condition not satisfied" do
      facts = Facts.from_perception(%{self: %{}})
      condition = fn facts -> Facts.has?(facts, {:self, :ready}) end

      assert {false, nil} = Precondition.evaluate(condition, facts, %{})
    end
  end

  describe "unknown condition types" do
    test "returns false for unknown condition format" do
      facts = Facts.from_perception(%{})

      # A condition that's not a function or recognized tuple
      refute Precondition.satisfied?(:unknown_atom, facts, %{})
      refute Precondition.satisfied?("string", facts, %{})
      refute Precondition.satisfied?(123, facts, %{})
      refute Precondition.satisfied?({:unknown_op, []}, facts, %{})
    end
  end

  describe ":axiom operator" do
    test "returns false for non-existent axiom" do
      facts = Facts.from_perception(%{})

      # Axiom that doesn't exist
      condition = {:axiom, :nonexistent_axiom}
      refute Precondition.satisfied?(condition, facts, %{})
    end

    test "returns false for non-existent axiom with args" do
      facts = Facts.from_perception(%{})

      # Axiom with args that doesn't exist
      condition = {:axiom, :nonexistent_axiom, [range: 10]}
      refute Precondition.satisfied?(condition, facts, %{})
    end
  end
end
