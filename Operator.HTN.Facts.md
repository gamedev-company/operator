# `Operator.HTN.Facts`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/facts.ex#L1)

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

# `category`

```elixir
@type category() :: :self | :world | :social
```

The category of a fact.

# `fact_key`

```elixir
@type fact_key() :: {category(), atom()}
```

A fact key specifying category and path.

Categories:
* `:self` - Agent's internal state
* `:world` - Environmental knowledge
* `:social` - Relationship data

## Examples

    {:self, :health}
    {:world, :door_locked}
    {:social, :faction_standing}

# `t`

```elixir
@type t() :: %Operator.HTN.Facts{self: map(), social: map(), world: map()}
```

The Facts struct containing agent world knowledge.

## Fields

* `:self` - Map of agent's internal state
* `:world` - Map of environmental knowledge
* `:social` - Map of relationship/social knowledge

# `delete`

```elixir
@spec delete(t(), fact_key()) :: t()
```

Delete a fact key, returning a new Facts struct.

## Parameters

* `facts` - The Facts struct
* `key` - Tuple of `{category, path}` to delete

## Examples

    iex> facts = Facts.from_perception(%{self: %{health: 100, mana: 50}})
    iex> updated = Facts.delete(facts, {:self, :mana})
    iex> Facts.has?(updated, {:self, :mana})
    false
    iex> Facts.get(updated, {:self, :health})
    100

# `from_perception`

```elixir
@spec from_perception(map()) :: t()
```

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

# `get`

```elixir
@spec get(t(), fact_key(), any()) :: any()
```

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

# `has?`

```elixir
@spec has?(t(), fact_key()) :: boolean()
```

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

    # Key exists, even though value is nil
    iex> facts = Facts.from_perception(%{self: %{weapon: nil}})
    iex> Facts.has?(facts, {:self, :weapon})
    true

    iex> facts = Facts.from_perception(%{self: %{}})
    iex> Facts.has?(facts, {:self, :weapon})
    false

# `merge`

```elixir
@spec merge(t(), map()) :: t()
```

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

# `missing_keys`

```elixir
@spec missing_keys(t(), [fact_key()]) :: [fact_key()]
```

Return the list of missing fact keys from a required set.

## Examples

    iex> facts = Facts.from_perception(%{self: %{ready: true}})
    iex> Facts.missing_keys(facts, [{:self, :ready}, {:world, :time}])
    [{:world, :time}]

# `new`

```elixir
@spec new() :: t()
```

Create an empty Facts struct.

This is a convenience alias for `from_perception(%{})`.

## Examples

    iex> facts = Facts.new()
    iex> Facts.has?(facts, {:self, :anything})
    false

# `put`

```elixir
@spec put(t(), fact_key(), any()) :: t()
```

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
    iex> Facts.get(facts, {:self, :health})
    100

# `to_map`

```elixir
@spec to_map(t()) :: map()
```

Convert facts to a flat map representation.

Useful for debugging and logging.

## Examples

    iex> facts = Facts.from_perception(%{self: %{hp: 100}, world: %{zone: :a}})
    iex> Facts.to_map(facts)
    %{self: %{hp: 100}, world: %{zone: :a}, social: %{}}

# `validate_required`

```elixir
@spec validate_required(t(), [fact_key()]) :: :ok | {:error, [fact_key()]}
```

Validate that all required fact keys exist.

Returns `:ok` when all keys exist, otherwise returns `{:error, missing_keys}`.

## Examples

    iex> facts = Facts.from_perception(%{self: %{ready: true}})
    iex> Facts.validate_required(facts, [{:self, :ready}])
    :ok

    iex> facts = Facts.from_perception(%{self: %{ready: true}})
    iex> Facts.validate_required(facts, [{:self, :ready}, {:world, :time}])
    {:error, [{:world, :time}]}

---

*Consult [api-reference.md](api-reference.md) for complete listing*
