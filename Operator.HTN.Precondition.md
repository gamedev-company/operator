# `Operator.HTN.Precondition`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/precondition.ex#L1)

Logical operators for HTN preconditions.

Inspired by the Decima engine's HTN implementation, this module provides
logical combinators for preconditions beyond simple conjunction (AND).

## Supported Operators

- `:all` (AND) - All conditions must be true (default behavior)
- `:any` (OR) - At least one condition must be true
- `:first` (ALT) - Use first matching condition with preference order
- `:not` - Negate a condition
- `:none` - No conditions match (equivalent to not-any)
- `:axiom` - Reference a registered axiom

## Usage

Preconditions can be:
- A simple function: `fn facts -> boolean end`
- A tuple with operator: `{:any, [fn1, fn2, fn3]}`
- Nested operators: `{:all, [fn1, {:any, [fn2, fn3]}]}`
- An axiom reference: `{:axiom, :axiom_name}` or `{:axiom, :axiom_name, args}`

## Examples

    iex> alias Operator.HTN.{Facts, Precondition}
    iex> facts = Facts.from_perception(%{self: %{has_weapon: true}})
    iex> cond = {:any, [
    ...>   fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
    ...>   fn facts -> Facts.has?(facts, {:world, :weapon_nearby}) end
    ...> ]}
    iex> Precondition.satisfied?(cond, facts, %{})
    true

    iex> facts = Facts.from_perception(%{self: %{has_melee_weapon: true}})
    iex> cond = {:first, [
    ...>   fn facts -> Facts.has?(facts, {:self, :has_ranged_weapon}) end,
    ...>   fn facts -> Facts.has?(facts, {:self, :has_melee_weapon}) end
    ...> ]}
    iex> Precondition.satisfied?(cond, facts, %{})
    true

    iex> facts = Facts.from_perception(%{self: %{in_combat: false}})
    iex> cond = {:not, fn facts -> Facts.get(facts, {:self, :in_combat}, false) end}
    iex> Precondition.satisfied?(cond, facts, %{})
    true

    iex> facts = Facts.from_perception(%{self: %{has_cover: true, has_grenade: true}})
    iex> cond = {:all, [
    ...>   fn facts -> Facts.has?(facts, {:self, :has_cover}) end,
    ...>   {:any, [
    ...>     fn facts -> Facts.has?(facts, {:self, :has_weapon}) end,
    ...>     fn facts -> Facts.has?(facts, {:self, :has_grenade}) end
    ...>   ]}
    ...> ]}
    iex> Precondition.satisfied?(cond, facts, %{})
    true

# `condition`

```elixir
@type condition() ::
  function() | {operator(), [condition()]} | {operator(), condition()}
```

# `operator`

```elixir
@type operator() :: :all | :any | :first | :not | :none
```

# `all_satisfied?`

```elixir
@spec all_satisfied?([condition()], Operator.HTN.Facts.t(), map()) :: boolean()
```

Evaluate a list of preconditions with AND semantics.

This is the default behavior matching Task.preconditions_satisfied?/3.

# `evaluate`

```elixir
@spec evaluate(condition(), Operator.HTN.Facts.t(), map()) :: {boolean(), map() | nil}
```

Evaluate a precondition against facts and traits.

Returns `{true, bindings}` on success or `{false, nil}` on failure.
Bindings are currently unused but reserved for future unification support.

# `find_all_matches`

```elixir
@spec find_all_matches([condition()], Operator.HTN.Facts.t(), map()) :: [
  non_neg_integer()
]
```

Find all matching alternatives.

Returns a list of indices for all conditions that match.
Useful for OR semantics where you want to know all valid options.

# `find_first_match`

```elixir
@spec find_first_match([condition()], Operator.HTN.Facts.t(), map()) ::
  {:ok, non_neg_integer()} | :none
```

Find the first matching alternative in an ALT list.

Unlike `:first` which just returns true/false, this returns
`{:ok, index}` with the index of the first matching condition,
or `:none` if nothing matches.

Useful for branch selection in decomposition.

# `satisfied?`

```elixir
@spec satisfied?(condition(), Operator.HTN.Facts.t(), map()) :: boolean()
```

Simple boolean evaluation of a precondition.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
