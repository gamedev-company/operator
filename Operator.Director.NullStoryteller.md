# `Operator.Director.NullStoryteller`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/director/null_storyteller.ex#L1)

A storyteller that never generates events.

The NullStoryteller is a no-op implementation of the `Operator.Storyteller`
behaviour. It's the narrative equivalent of `/dev/null` - events go in,
nothing comes out.

## Use Cases

**Testing:** When you want to test Director integration without event noise:

    {:ok, _pid} = Director.start_link(
      storyteller: Operator.Director.NullStoryteller,
      on_event: fn event -> flunk("Should not fire: #{inspect(event)}") end
    )

**Baseline Performance:** Measure your game loop overhead without storyteller
processing:

    # Compare tick times with NullStoryteller vs your real storyteller
    {:ok, _} = Director.start_link(storyteller: NullStoryteller)

**Gradual Integration:** Start with NullStoryteller while building your game,
then swap in a real storyteller when you're ready for narrative events:

    storyteller = if Mix.env() == :dev do
      Operator.Director.NullStoryteller
    else
      MyGame.DramaticStoryteller
    end

    Director.start_link(storyteller: storyteller, on_event: &handle/1)

**Disabling Events:** Temporarily disable event generation without stopping
the Director:

    # In your config/runtime.exs
    config :my_game, :storyteller,
      if System.get_env("DISABLE_EVENTS"),
        do: Operator.Director.NullStoryteller,
        else: MyGame.Storyteller

## Behaviour

* `init/1` - Returns empty state `%{}`
* `pick_event/3` - Always returns `{nil, state}` (no event)

## See Also

* `Operator.Storyteller` - The behaviour this implements
* `Operator.Director` - The GenServer that calls this

# `init`

```elixir
@spec init(map()) :: map()
```

Initialize with empty state.

Ignores all options since NullStoryteller has no configuration.

## Parameters

* `_opts` - Ignored

## Returns

Empty map `%{}`

# `pick_event`

```elixir
@spec pick_event(integer(), map(), map()) :: {nil, map()}
```

Never generate an event.

Always returns `{nil, state}` regardless of tick or world state.

## Parameters

* `_tick` - Current game tick (ignored)
* `_world_state` - Current world state (ignored)
* `state` - Storyteller state (passed through unchanged)

## Returns

`{nil, state}` - No event, state unchanged

---

*Consult [api-reference.md](api-reference.md) for complete listing*
