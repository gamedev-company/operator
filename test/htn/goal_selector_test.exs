defmodule Operator.HTN.GoalSelectorTest do
  use ExUnit.Case, async: false

  alias Operator.HTN.{Facts, GoalSelector, Registry}

  setup do
    Registry.reset()
    :ok
  end

  describe "pick_goal/3" do
    test "selects goal with highest priority" do
      registry = %{
        goals: %{
          low_priority: %{
            name: :low_priority,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1}
          },
          high_priority: %{
            name: :high_priority,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 10}
          },
          medium_priority: %{
            name: :medium_priority,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 5}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      {:ok, goal} = GoalSelector.pick_goal(facts, traits)

      assert goal == :high_priority
    end

    test "filters out goals with failed preconditions" do
      registry = %{
        goals: %{
          blocked: %{
            name: :blocked,
            precond: fn _facts -> false end,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 100}
          },
          available: %{
            name: :available,
            precond: fn _facts -> true end,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      {:ok, goal} = GoalSelector.pick_goal(facts, traits)

      # Should pick available even though blocked has higher priority
      assert goal == :available
    end

    test "returns :none when no goals available" do
      Registry.reset()
      facts = Facts.new()
      traits = %{}

      result = GoalSelector.pick_goal(facts, traits)

      assert result == :none
    end

    test "returns :none when all goals have failed preconditions" do
      registry = %{
        goals: %{
          blocked1: %{
            name: :blocked1,
            precond: fn _facts -> false end,
            decompose: fn _facts -> [] end,
            metadata: %{}
          },
          blocked2: %{
            name: :blocked2,
            precond: fn _facts -> false end,
            decompose: fn _facts -> [] end,
            metadata: %{}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      result = GoalSelector.pick_goal(facts, traits)

      assert result == :none
    end

    test "applies trait weights from options" do
      registry = %{
        goals: %{
          attack: %{
            name: :attack,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1}
          },
          defend: %{
            name: :defend,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{traits: [:aggressive]}

      # Without weights, either could win
      # With weights favoring aggressive -> attack, attack should win
      {:ok, goal} =
        GoalSelector.pick_goal(facts, traits,
          trait_weights: %{{:aggressive, :attack} => 10}
        )

      assert goal == :attack
    end

    test "uses goal_order for tie-breaking" do
      registry = %{
        goals: %{
          goal_a: %{
            name: :goal_a,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 5}
          },
          goal_b: %{
            name: :goal_b,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 5}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      # With goal_order preferring goal_b
      {:ok, goal} = GoalSelector.pick_goal(facts, traits, goal_order: [:goal_b, :goal_a])

      assert goal == :goal_b
    end

    test "applies priority_bonus to all goals" do
      registry = %{
        goals: %{
          single_goal: %{
            name: :single_goal,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      # Just verify it doesn't crash with priority_bonus
      {:ok, goal} = GoalSelector.pick_goal(facts, traits, priority_bonus: 5)

      assert goal == :single_goal
    end

    test "respects required_traits in metadata" do
      registry = %{
        goals: %{
          requires_stealth: %{
            name: :requires_stealth,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 10, required_traits: [:stealthy]}
          },
          no_requirements: %{
            name: :no_requirements,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()

      # Without stealthy trait
      traits_no_stealth = %{traits: [:loud]}
      {:ok, goal} = GoalSelector.pick_goal(facts, traits_no_stealth)
      assert goal == :no_requirements

      # With stealthy trait
      traits_stealthy = %{traits: [:stealthy]}
      {:ok, goal} = GoalSelector.pick_goal(facts, traits_stealthy)
      assert goal == :requires_stealth
    end

    test "applies world context bonus based on tension and domain" do
      registry = %{
        goals: %{
          security_goal: %{
            name: :security_goal,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1, domain: :security}
          },
          street_goal: %{
            name: :street_goal,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1, domain: :street}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      traits = %{}

      # In corporate land use with high tension, security should score higher
      corporate_facts =
        Facts.from_perception(%{
          world: %{tension: 0.9, land_use: :corporate}
        })

      {:ok, goal} = GoalSelector.pick_goal(corporate_facts, traits)
      # Security domain gets 0.5 * tension bonus in corporate
      # Street domain gets default 0.1 * tension
      assert goal == :security_goal

      # In barrens, street goals should score higher
      barrens_facts =
        Facts.from_perception(%{
          world: %{tension: 0.9, land_use: :barrens}
        })

      {:ok, goal} = GoalSelector.pick_goal(barrens_facts, traits)
      # Street domain gets 0.6 * tension bonus in barrens
      assert goal == :street_goal
    end
  end

  describe "explain/3" do
    test "returns selected, eligible, and ineligible goals" do
      registry = %{
        goals: %{
          patrol: %{
            name: :patrol,
            precond: fn facts -> Facts.get(facts, {:self, :ready}, false) end,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 5}
          },
          rest: %{
            name: :rest,
            precond: fn _facts -> false end,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 10}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.from_perception(%{self: %{ready: true}})
      result = GoalSelector.explain(facts, %{})

      assert result.selected == :patrol
      assert Enum.any?(result.eligible, &(&1.goal == :patrol))
      assert Enum.any?(result.ineligible, &(&1.goal == :rest and &1.reason == :preconditions_not_met))
    end
  end

  describe "score_goal/4" do
    test "returns score for existing goal" do
      registry = %{
        goals: %{
          scored_goal: %{
            name: :scored_goal,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 5}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{}

      score = GoalSelector.score_goal(:scored_goal, facts, traits)

      assert is_number(score)
      # Base priority is 5, plus minimal world context bonus
      assert score >= 5
    end

    test "returns nil for non-existent goal" do
      Registry.reset()
      facts = Facts.new()
      traits = %{}

      score = GoalSelector.score_goal(:nonexistent, facts, traits)

      assert score == nil
    end

    test "includes trait weights in score" do
      registry = %{
        goals: %{
          attack: %{
            name: :attack,
            precond: nil,
            decompose: fn _facts -> [] end,
            metadata: %{priority: 1}
          }
        },
        tasks: %{},
        primitives: %{},
        axioms: %{}
      }

      :persistent_term.put({Registry, :registry}, registry)
      :persistent_term.put({Registry, :modules}, MapSet.new())

      facts = Facts.new()
      traits = %{traits: [:aggressive]}

      score_without_weight = GoalSelector.score_goal(:attack, facts, traits)

      score_with_weight =
        GoalSelector.score_goal(:attack, facts, traits,
          trait_weights: %{{:aggressive, :attack} => 10}
        )

      assert score_with_weight > score_without_weight
      assert score_with_weight - score_without_weight == 10
    end
  end
end
