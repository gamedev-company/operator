# Anti-Patterns

This guide shows the most common ways HTN systems fail in practice, with fixes.

## 1) Planning Every Tick With No Caching

Bad:

```elixir
# Replans every tick regardless of change
{:ok, plan} = Operator.HTN.Planner.run(:patrol, facts, traits)
```

Better:

```elixir
if Operator.HTN.Planner.needs_replan?(plan, facts) do
  {:ok, plan} = Operator.HTN.Planner.run(:patrol, facts, traits)
end
```

## 2) Facts As A Dumping Ground

Bad:

```elixir
facts = Operator.HTN.Facts.from_perception(%{
  world: %{raw_game_state: huge_struct}
})
```

Better:

```elixir
facts = Operator.HTN.Facts.from_perception(%{
  world: %{threat_level: :high, target_visible: true}
})
```

## 2a) No Facts Validation

Bad:

```elixir
metadata priority: 5
```

Better:

```elixir
metadata priority: 5, requires_facts: [{:self, :energy}, {:world, :threat_level}]
```

## 3) Preconditions With Side Effects

Bad:

```elixir
precond fn facts ->
  MyApp.SideEffectingCache.refresh()
  Operator.HTN.Facts.has?(facts, {:self, :ready})
end
```

Better:

```elixir
precond fn facts ->
  Operator.HTN.Facts.has?(facts, {:self, :ready})
end
```

## 4) Missing Effects For Multi-Step Plans

Bad:

```elixir
primitive :unlock do
  run fn actor, _facts -> {:ok, actor} end
end

primitive :open_door do
  precond fn facts -> Operator.HTN.Facts.get(facts, {:world, :door_unlocked}, false) end
  run fn actor, _facts -> {:ok, actor} end
end
```

Better:

```elixir
primitive :unlock do
  effects [Operator.HTN.Effect.new(:plan_and_execute, {:world, :door_unlocked}, true)]
  run fn actor, _facts -> {:ok, actor} end
end
```

## 5) Aliases Inside `precond` and `decompose`

Bad:

```elixir
alias Operator.HTN.Facts

precond fn facts -> Facts.has?(facts, {:self, :ready}) end
```

Better:

```elixir
precond fn facts -> Operator.HTN.Facts.has?(facts, {:self, :ready}) end
```

## 6) Deep, Monolithic Goals

Bad:

```elixir
goal :do_everything do
  # 20 tasks, 5 branches, 3 levels deep
end
```

Better:

```elixir
goal :patrol do
  # Small, clear, testable
end
```

## 7) Hidden Randomness In Primitives

Bad:

```elixir
primitive :shoot do
  run fn actor, _facts ->
    if :rand.uniform() < 0.1, do: {:error, :jammed}, else: {:ok, actor}
  end
end
```

Better:

```elixir
# Roll randomness outside, pass into facts or actor
primitive :shoot do
  run fn actor, _facts ->
    if actor.weapon_jammed, do: {:error, :jammed}, else: {:ok, actor}
  end
end
```
