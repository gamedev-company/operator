# `Operator.Director`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/director/director.ex#L1)

Narrative orchestration system for dynamic event generation.

The Director is a GenServer that acts as your game's "AI Director" (inspired
by Left 4 Dead's famous system). It monitors world state and decides when
interesting events should occur, controlling narrative pacing and dramatic
tension.

## The Director Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                        Game Loop                                 │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│   │ Update NPCs │ --> │ Physics/AI  │ --> │ Render      │       │
│   └─────────────┘     └─────────────┘     └─────────────┘       │
│         │                                                        │
│         │ world_state                                            │
│         ▼                                                        │
│   ┌─────────────────────────────────────┐                       │
│   │           Director                  │                       │
│   │  ┌─────────────────────────────┐    │                       │
│   │  │      Storyteller            │    │     ┌──────────────┐  │
│   │  │  - monitors tension         │----│---> │ Game Events  │  │
│   │  │  - picks event timing       │    │     │ (spawn enemy,│  │
│   │  │  - controls pacing          │    │     │  trigger     │  │
│   │  └─────────────────────────────┘    │     │  dialogue)   │  │
│   └─────────────────────────────────────┘     └──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

    # 1. Define your storyteller
    defmodule MyGame.TensionStoryteller do
      @behaviour Operator.Storyteller

      @impl true
      def init(_opts), do: %{last_event_tick: 0}

      @impl true
      def pick_event(tick, world_state, state) do
        tension = Map.get(world_state, :tension, 0.0)

        if tension > 0.7 and tick - state.last_event_tick > 100 do
          event = %{type: :ambush, location: pick_location(world_state)}
          {event, %{state | last_event_tick: tick}}
        else
          {nil, state}
        end
      end
    end

    # 2. Start the Director
    {:ok, _pid} = Operator.Director.start_link(
      storyteller: MyGame.TensionStoryteller,
      on_event: &MyGame.EventHandler.process/1
    )

    # 3. Feed it world state each tick
    def game_tick(world_state) do
      Operator.Director.tick(world_state)
      # ... rest of game loop
    end

## Startup Options

* `:storyteller` - Module implementing `Operator.Storyteller`
  (default: `NullStoryteller`)
* `:name` - GenServer name (default: `Operator.Director`)
* `:on_event` - Callback `fn event -> :ok end` for generated events

## Event Flow

1. Your game calls `Director.tick(world_state)` each simulation tick
2. Director invokes `storyteller.pick_event(tick, world_state, state)`
3. If the storyteller returns an event, Director:
   - Rationalizes it via `Operator.Rationalization`
   - Emits telemetry via `Operator.Telemetry`
   - Calls your `:on_event` callback
4. Your game reacts to the event (spawn enemies, trigger dialogue, etc.)

## Runtime Control

    # Change storytellers based on game phase
    Operator.Director.change_storyteller(MyGame.BossFightStoryteller)

    # Get current tick for synchronization
    current_tick = Operator.Director.current_tick()

    # Debug storyteller state
    state = Operator.Director.get_state()

## Integration Philosophy

The Director is intentionally lightweight. It does NOT:

* Subscribe to PubSub topics
* Persist events to timelines
* Handle clustering

These concerns belong to your host application. The Director's job is
purely to decide **when** and **what** events to generate.

## Synchronous Testing

For tests, use `tick_sync/2` to get immediate results:

    event = Operator.Director.tick_sync(world_state)
    assert event.type == :ambush

## See Also

* `Operator.Storyteller` - Behaviour for storyteller modules
* `Operator.Director.NullStoryteller` - No-op storyteller for testing
* `Operator.Rationalization` - Event annotation

# `storyteller_state`

```elixir
@type storyteller_state() :: {module(), map()}
```

# `t`

```elixir
@type t() :: %Operator.Director{
  last_event_tick: non_neg_integer(),
  on_event: (map() -&gt; :ok) | nil,
  storyteller: storyteller_state(),
  tick: non_neg_integer()
}
```

# `change_storyteller`

```elixir
@spec change_storyteller(module(), GenServer.server()) :: :ok
```

Change the active storyteller at runtime.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `current_tick`

```elixir
@spec current_tick(GenServer.server()) :: non_neg_integer()
```

Get the current tick.

# `get_state`

```elixir
@spec get_state(GenServer.server()) :: t()
```

Get the current state (for debugging).

# `start_link`

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

Start the Director.

## Options

- `:storyteller` - Storyteller module (default: NullStoryteller)
- `:name` - GenServer name (default: Operator.Director)
- `:on_event` - Callback for generated events

# `tick`

```elixir
@spec tick(map(), GenServer.server()) :: :ok
```

Trigger a tick with the given world state.

Call this from your simulation's tick handler.

# `tick_sync`

```elixir
@spec tick_sync(map(), GenServer.server()) :: map() | nil
```

Synchronous tick that returns any generated event.

Useful for testing.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
