defmodule Operator.TraitsTest do
  use ExUnit.Case, async: true

  alias Operator.Traits

  describe "traits/1" do
    test "returns traits from genome map" do
      genome = %{traits: [:aggressive, :stealthy]}

      assert Traits.traits(genome) == [:aggressive, :stealthy]
    end

    test "returns empty list when genome has no traits" do
      genome = %{other_data: "value"}

      assert Traits.traits(genome) == []
    end

    test "returns empty list for nil genome" do
      assert Traits.traits(nil) == []
    end

    test "returns empty list for empty genome" do
      assert Traits.traits(%{}) == []
    end
  end

  describe "trait_affinity_score/2" do
    test "calculates score from trait_weights in metadata" do
      genome = %{traits: [:aggressive, :brave]}

      metadata = %{
        trait_weights: %{
          aggressive: 5,
          brave: 3,
          cowardly: -2
        }
      }

      # aggressive (5) + brave (3) = 8
      assert Traits.trait_affinity_score(genome, metadata) == 8
    end

    test "returns 0 when no matching traits" do
      genome = %{traits: [:sneaky]}
      metadata = %{trait_weights: %{aggressive: 5}}

      assert Traits.trait_affinity_score(genome, metadata) == 0
    end

    test "returns 0 when no trait_weights in metadata" do
      genome = %{traits: [:aggressive]}
      metadata = %{}

      assert Traits.trait_affinity_score(genome, metadata) == 0
    end

    test "returns 0 for nil metadata" do
      genome = %{traits: [:aggressive]}

      assert Traits.trait_affinity_score(genome, nil) == 0
    end

    test "returns 0 for nil genome" do
      metadata = %{trait_weights: %{aggressive: 5}}

      assert Traits.trait_affinity_score(nil, metadata) == 0
    end

    test "handles keyword list trait_weights" do
      genome = %{traits: [:fast]}
      metadata = %{trait_weights: [fast: 3, slow: -1]}

      assert Traits.trait_affinity_score(genome, metadata) == 3
    end
  end

  describe "archetype_affinity_score/2" do
    test "returns score for matching archetype" do
      genome = %{archetype: :warrior}

      metadata = %{
        archetype_weights: %{
          warrior: 10,
          mage: 5
        }
      }

      assert Traits.archetype_affinity_score(genome, metadata) == 10
    end

    test "returns 0 for non-matching archetype" do
      genome = %{archetype: :rogue}
      metadata = %{archetype_weights: %{warrior: 10}}

      assert Traits.archetype_affinity_score(genome, metadata) == 0
    end

    test "returns 0 when no archetype_weights" do
      genome = %{archetype: :warrior}
      metadata = %{}

      assert Traits.archetype_affinity_score(genome, metadata) == 0
    end

    test "returns 0 for nil metadata" do
      genome = %{archetype: :warrior}

      assert Traits.archetype_affinity_score(genome, nil) == 0
    end

    test "returns 0 for nil genome" do
      metadata = %{archetype_weights: %{warrior: 10}}

      assert Traits.archetype_affinity_score(nil, metadata) == 0
    end

    test "returns 0 when genome has no archetype" do
      genome = %{traits: [:aggressive]}
      metadata = %{archetype_weights: %{warrior: 10}}

      assert Traits.archetype_affinity_score(genome, metadata) == 0
    end

    test "handles keyword list archetype_weights" do
      genome = %{archetype: :healer}
      metadata = %{archetype_weights: [healer: 7, tank: 3]}

      assert Traits.archetype_affinity_score(genome, metadata) == 7
    end
  end

  describe "get_module/0" do
    test "returns nil when no module configured" do
      # Default configuration has no traits module
      assert Traits.get_module() == nil
    end
  end
end
