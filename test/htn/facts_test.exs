defmodule Operator.HTN.FactsTest do
  use ExUnit.Case, async: true

  alias Operator.HTN.Facts

  doctest Operator.HTN.Facts

  describe "from_perception/1" do
    test "creates facts from perception map" do
      perception = %{
        self: %{health: 100, has_weapon: true},
        world: %{location: :downtown},
        social: %{faction: :runners}
      }

      facts = Facts.from_perception(perception)

      assert facts.self == %{health: 100, has_weapon: true}
      assert facts.world == %{location: :downtown}
      assert facts.social == %{faction: :runners}
    end

    test "handles missing categories" do
      facts = Facts.from_perception(%{self: %{health: 50}})

      assert facts.self == %{health: 50}
      assert facts.world == %{}
      assert facts.social == %{}
    end

    test "handles empty map" do
      facts = Facts.from_perception(%{})

      assert facts.self == %{}
      assert facts.world == %{}
      assert facts.social == %{}
    end
  end

  describe "has?/2" do
    test "returns true for existing facts" do
      facts = Facts.from_perception(%{self: %{has_weapon: true}})

      assert Facts.has?(facts, {:self, :has_weapon})
    end

    test "returns false for missing facts" do
      facts = Facts.from_perception(%{self: %{health: 100}})

      refute Facts.has?(facts, {:self, :has_weapon})
    end

    test "returns true even if value is nil" do
      facts = Facts.from_perception(%{self: %{weapon: nil}})

      assert Facts.has?(facts, {:self, :weapon})
    end

    test "returns false for missing key in existing category" do
      facts = Facts.from_perception(%{world: %{location: :city}})

      refute Facts.has?(facts, {:world, :weather})
    end
  end

  describe "get/3" do
    test "returns fact value" do
      facts = Facts.from_perception(%{world: %{threat_level: :high}})

      assert Facts.get(facts, {:world, :threat_level}) == :high
    end

    test "returns default for missing fact" do
      facts = Facts.from_perception(%{})

      assert Facts.get(facts, {:world, :threat_level}, :unknown) == :unknown
    end

    test "returns nil by default for missing fact" do
      facts = Facts.from_perception(%{})

      assert Facts.get(facts, {:world, :threat_level}) == nil
    end

    test "returns nil value when explicitly set to nil" do
      facts = Facts.from_perception(%{self: %{target: nil}})

      assert Facts.get(facts, {:self, :target}, :default) == nil
    end

    test "works with all three categories" do
      facts =
        Facts.from_perception(%{
          self: %{hp: 100},
          world: %{zone: :forest},
          social: %{ally: :fixer}
        })

      assert Facts.get(facts, {:self, :hp}) == 100
      assert Facts.get(facts, {:world, :zone}) == :forest
      assert Facts.get(facts, {:social, :ally}) == :fixer
    end
  end

  describe "put/3" do
    test "sets fact value" do
      facts = Facts.from_perception(%{self: %{health: 100}})

      updated = Facts.put(facts, {:self, :health}, 80)

      assert Facts.get(updated, {:self, :health}) == 80
    end

    test "adds new fact" do
      facts = Facts.from_perception(%{})

      updated = Facts.put(facts, {:world, :alert_level}, :red)

      assert Facts.get(updated, {:world, :alert_level}) == :red
    end

    test "does not mutate original" do
      facts = Facts.from_perception(%{self: %{health: 100}})

      _updated = Facts.put(facts, {:self, :health}, 50)

      assert Facts.get(facts, {:self, :health}) == 100
    end

    test "works with all three categories" do
      facts = Facts.from_perception(%{})

      facts = Facts.put(facts, {:self, :hp}, 100)
      facts = Facts.put(facts, {:world, :zone}, :city)
      facts = Facts.put(facts, {:social, :faction}, :runners)

      assert Facts.get(facts, {:self, :hp}) == 100
      assert Facts.get(facts, {:world, :zone}) == :city
      assert Facts.get(facts, {:social, :faction}) == :runners
    end
  end

  describe "merge/2" do
    test "merges new data into existing facts" do
      facts =
        Facts.from_perception(%{
          self: %{health: 100},
          world: %{location: :downtown}
        })

      new_data = %{
        self: %{has_weapon: true},
        social: %{ally: :fixer}
      }

      merged = Facts.merge(facts, new_data)

      assert Facts.get(merged, {:self, :health}) == 100
      assert Facts.get(merged, {:self, :has_weapon}) == true
      assert Facts.get(merged, {:world, :location}) == :downtown
      assert Facts.get(merged, {:social, :ally}) == :fixer
    end

    test "overwrites existing values" do
      facts = Facts.from_perception(%{self: %{health: 100}})
      new_data = %{self: %{health: 50}}

      merged = Facts.merge(facts, new_data)

      assert Facts.get(merged, {:self, :health}) == 50
    end

    test "handles empty merge data" do
      facts = Facts.from_perception(%{self: %{health: 100}})

      merged = Facts.merge(facts, %{})

      assert Facts.get(merged, {:self, :health}) == 100
    end
  end

  describe "to_map/1" do
    test "converts facts to plain map" do
      facts =
        Facts.from_perception(%{
          self: %{hp: 100},
          world: %{zone: :city}
        })

      map = Facts.to_map(facts)

      assert map == %{
               self: %{hp: 100},
               world: %{zone: :city},
               social: %{}
             }
    end

    test "includes all three categories" do
      facts = Facts.from_perception(%{})

      map = Facts.to_map(facts)

      assert Map.has_key?(map, :self)
      assert Map.has_key?(map, :world)
      assert Map.has_key?(map, :social)
    end
  end

  describe "new/0" do
    test "creates empty facts" do
      facts = Facts.new()

      assert facts.self == %{}
      assert facts.world == %{}
      assert facts.social == %{}
    end

    test "has? returns false for any key" do
      facts = Facts.new()

      refute Facts.has?(facts, {:self, :anything})
      refute Facts.has?(facts, {:world, :anything})
      refute Facts.has?(facts, {:social, :anything})
    end
  end

  describe "delete/2" do
    test "removes fact from self category" do
      facts = Facts.from_perception(%{self: %{health: 100, mana: 50}})

      updated = Facts.delete(facts, {:self, :mana})

      assert Facts.has?(updated, {:self, :health})
      refute Facts.has?(updated, {:self, :mana})
    end

    test "removes fact from world category" do
      facts = Facts.from_perception(%{world: %{time: :day, weather: :sunny}})

      updated = Facts.delete(facts, {:world, :weather})

      assert Facts.has?(updated, {:world, :time})
      refute Facts.has?(updated, {:world, :weather})
    end

    test "removes fact from social category" do
      facts = Facts.from_perception(%{social: %{ally: :fixer, enemy: :corp}})

      updated = Facts.delete(facts, {:social, :enemy})

      assert Facts.has?(updated, {:social, :ally})
      refute Facts.has?(updated, {:social, :enemy})
    end

    test "does not mutate original" do
      facts = Facts.from_perception(%{self: %{health: 100}})

      _updated = Facts.delete(facts, {:self, :health})

      assert Facts.has?(facts, {:self, :health})
    end

    test "safely handles non-existent key" do
      facts = Facts.from_perception(%{self: %{health: 100}})

      updated = Facts.delete(facts, {:self, :nonexistent})

      assert Facts.has?(updated, {:self, :health})
    end
  end
end
