defmodule Operator.HTN.Facts do
  @moduledoc """
  World state representation for HTN planning.

  Facts represent an agent's knowledge about the world, organized into three
  categories:

  * **self** - Agent's internal state (health, inventory, abilities)
  * **world** - Environmental knowledge (locations, objects, conditions)
  * **social** - Relationships and knowledge about other agents

  ## Creating Facts

  The primary way to create facts is from a perception map:

      facts = Facts.from_perception(%{
        self: %{
          health: 100,
          position: {10, 20},
          inventory: [:keycard, :pistol]
        },
        world: %{
          time_of_day: :night,
          alarm_active: false,
          guards_nearby: 2
        },
        social: %{
          faction_standing: %{corp: -50, runners: 80}
        }
      })

  ## Querying Facts

  Use `has?/2` to check for existence and `get/3` to retrieve values:

      Facts.has?(facts, {:self, :keycard})
      #=> true (checks if key exists in self map)

      Facts.get(facts, {:self, :health}, 0)
      #=> 100

      Facts.get(facts, {:world, :alarm_active}, true)
      #=> false

  ## Modifying Facts (During Planning)

  Facts are immutable. Modifications return new fact structs:

      updated = Facts.put(facts, {:self, :health}, 80)
      updated = Facts.merge(facts, %{self: %{ammo: 30}})

  This immutability is crucial for HTN planning - the planner can explore
  different branches without corrupting shared state.

  ## Fact Keys

  Keys are always tuples of `{category, path}` where:

  * `category` is `:self`, `:world`, or `:social`
  * `path` is an atom or nested key path

  ## Integration with Preconditions

  Facts are passed to precondition functions during planning:

      goal :attack do
        precond fn facts ->
          Facts.has?(facts, {:self, :weapon}) and
          Facts.get(facts, {:self, :ammo}, 0) > 0
        end
        # ...
      end

  ## See Also

  * `Operator.HTN.Effect` - Modifying facts during planning
  * `Operator.HTN.Plan` - Plans generated from facts
  * `Operator.HTN.Precondition` - Logical operators on facts

  """

  defstruct self: %{}, world: %{}, social: %{}

  @typedoc """
  A fact key specifying category and path.

  Categories:
  * `:self` - Agent's internal state
  * `:world` - Environmental knowledge
  * `:social` - Relationship data

  ## Examples

      {:self, :health}
      {:world, :door_locked}
      {:social, :faction_standing}

  """
  @type fact_key :: {category(), atom()}

  @typedoc "The category of a fact."
  @type category :: :self | :world | :social

  @typedoc """
  The Facts struct containing agent world knowledge.

  ## Fields

  * `:self` - Map of agent's internal state
  * `:world` - Map of environmental knowledge
  * `:social` - Map of relationship/social knowledge

  """
  @type t :: %__MODULE__{
          self: map(),
          world: map(),
          social: map()
        }

  @doc """
  Create facts from a perception map.

  This is the primary constructor for Facts. The perception map should contain
  keys for `:self`, `:world`, and/or `:social`.

  ## Parameters

  * `perception` - Map with optional `:self`, `:world`, `:social` keys

  ## Examples

      iex> facts = Facts.from_perception(%{self: %{ready: true}})
      iex> Facts.get(facts, {:self, :ready})
      true

      iex> facts = Facts.from_perception(%{
      ...>   self: %{hp: 100, mp: 50},
      ...>   world: %{location: :town}
      ...> })
      iex> Facts.get(facts, {:world, :location})
      :town

  ## Empty Facts

      iex> facts = Facts.from_perception(%{})
      iex> Facts.has?(facts, {:self, :anything})
      false

  """
  @spec from_perception(map()) :: t()
  def from_perception(perception) when is_map(perception) do
    %__MODULE__{
      self: Map.get(perception, :self, %{}),
      world: Map.get(perception, :world, %{}),
      social: Map.get(perception, :social, %{})
    }
  end

  @doc """
  Check if a fact key exists (has a value, even if nil).

  Returns `true` if the key exists in the appropriate category map,
  regardless of the value.

  ## Parameters

  * `facts` - The Facts struct
  * `key` - Tuple of `{category, path}`

  ## Examples

      iex> facts = Facts.from_perception(%{self: %{weapon: :sword}})
      iex> Facts.has?(facts, {:self, :weapon})
      true

      iex> facts = Facts.from_perception(%{self: %{weapon: nil}})
      iex> Facts.has?(facts, {:self, :weapon})
      true  # Key exists, even though value is nil

      iex> facts = Facts.from_perception(%{self: %{}})
      iex> Facts.has?(facts, {:self, :weapon})
      false

  """
  @spec has?(t(), fact_key()) :: boolean()
  def has?(%__MODULE__{} = facts, {category, key}) do
    category_map = get_category(facts, category)
    Map.has_key?(category_map, key)
  end

  @doc """
  Get a fact value with an optional default.

  Returns the value at the given key, or the default if the key doesn't exist.

  ## Parameters

  * `facts` - The Facts struct
  * `key` - Tuple of `{category, path}`
  * `default` - Value to return if key doesn't exist (default: `nil`)

  ## Examples

      iex> facts = Facts.from_perception(%{self: %{health: 100}})
      iex> Facts.get(facts, {:self, :health})
      100

      iex> facts = Facts.from_perception(%{self: %{}})
      iex> Facts.get(facts, {:self, :health}, 0)
      0

      iex> facts = Facts.from_perception(%{world: %{enemies: [:goblin, :orc]}})
      iex> Facts.get(facts, {:world, :enemies}, [])
      [:goblin, :orc]

  """
  @spec get(t(), fact_key(), any()) :: any()
  def get(%__MODULE__{} = facts, {category, key}, default \\ nil) do
    category_map = get_category(facts, category)
    Map.get(category_map, key, default)
  end

  @doc """
  Set a fact value, returning a new Facts struct.

  This is used during planning to simulate effects of actions.

  ## Parameters

  * `facts` - The Facts struct
  * `key` - Tuple of `{category, path}`
  * `value` - The new value to set

  ## Examples

      iex> facts = Facts.from_perception(%{self: %{health: 100}})
      iex> updated = Facts.put(facts, {:self, :health}, 80)
      iex> Facts.get(updated, {:self, :health})
      80

      # Original is unchanged (immutable)
      iex> Facts.get(facts, {:self, :health})
      100

  """
  @spec put(t(), fact_key(), any()) :: t()
  def put(%__MODULE__{} = facts, {category, key}, value) do
    category_map = get_category(facts, category)
    updated_map = Map.put(category_map, key, value)
    set_category(facts, category, updated_map)
  end

  @doc """
  Merge additional facts into the existing struct.

  Performs a shallow merge of each category.

  ## Parameters

  * `facts` - The Facts struct
  * `additional` - Map with `:self`, `:world`, and/or `:social` keys

  ## Examples

      iex> facts = Facts.from_perception(%{self: %{health: 100}})
      iex> updated = Facts.merge(facts, %{self: %{mana: 50}, world: %{zone: :forest}})
      iex> Facts.get(updated, {:self, :mana})
      50
      iex> Facts.get(updated, {:world, :zone})
      :forest

  """
  @spec merge(t(), map()) :: t()
  def merge(%__MODULE__{} = facts, additional) when is_map(additional) do
    %__MODULE__{
      self: Map.merge(facts.self, Map.get(additional, :self, %{})),
      world: Map.merge(facts.world, Map.get(additional, :world, %{})),
      social: Map.merge(facts.social, Map.get(additional, :social, %{}))
    }
  end

  @doc """
  Convert facts to a flat map representation.

  Useful for debugging and logging.

  ## Examples

      iex> facts = Facts.from_perception(%{self: %{hp: 100}, world: %{zone: :a}})
      iex> Facts.to_map(facts)
      %{self: %{hp: 100}, world: %{zone: :a}, social: %{}}

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{self: self, world: world, social: social}) do
    %{self: self, world: world, social: social}
  end

  # Private helpers

  @doc false
  @spec get_category(t(), category()) :: map()
  defp get_category(%__MODULE__{self: self}, :self), do: self
  defp get_category(%__MODULE__{world: world}, :world), do: world
  defp get_category(%__MODULE__{social: social}, :social), do: social

  @doc false
  @spec set_category(t(), category(), map()) :: t()
  defp set_category(facts, :self, map), do: %{facts | self: map}
  defp set_category(facts, :world, map), do: %{facts | world: map}
  defp set_category(facts, :social, map), do: %{facts | social: map}
end
