# Director

The Director is a global pacing system. It decides when world events should
happen based on evolving state. It is not tied to a single NPC.

## Core Idea

- HTN handles per-agent intent.
- The Director handles global narrative pressure.

## Minimal Storyteller

```elixir
defmodule MyGame.SimpleStoryteller do
  @behaviour Operator.Storyteller

  @impl true
  def init(_opts), do: %{last_event_tick: 0}

  @impl true
  def pick_event(tick, world_state, state) do
    tension = Map.get(world_state, :tension, 0.0)

    if tension > 0.7 do
      event = %{type: :ambush, severity: round(tension * 5)}
      {event, %{state | last_event_tick: tick}}
    else
      {nil, state}
    end
  end
end
```

## Start The Director

```elixir
{:ok, _pid} = Operator.Director.start_link(
  storyteller: MyGame.SimpleStoryteller,
  on_event: &MyGame.EventHandler.process/1
)
```

## Drive It Every Tick

```elixir
Operator.Director.tick(%{tick: current_tick, tension: world_tension})
```

Use `tick_sync/1` if you want the event returned immediately.

```elixir
event = Operator.Director.tick_sync(%{tick: current_tick, tension: world_tension})
```

## Integrate With HTN

Treat Director events as facts in your agents.

```elixir
facts = Operator.HTN.Facts.from_perception(%{
  self: %{energy: 40},
  world: %{director_event: event}
})
```

## Testing Storytellers

```elixir
state = MyGame.SimpleStoryteller.init([])
{event, _state} = MyGame.SimpleStoryteller.pick_event(10, %{tension: 0.8}, state)
assert event.type == :ambush
```

## Checklist

- Storyteller is pure and deterministic.
- Events are small maps with a clear `:type`.
- Director ticks are called exactly once per frame or simulation step.
