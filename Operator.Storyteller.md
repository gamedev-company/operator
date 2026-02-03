# `Operator.Storyteller`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/director/storyteller.ex#L1)

Behaviour for narrative event generators.

Storytellers are the brains behind the Director's event generation. Each
storyteller encapsulates a different dramatic philosophy - one might favor
constant action, another might build tension slowly before explosive releases.

## The Storyteller's Job

A storyteller answers one question each tick: "Should something interesting
happen right now?" Based on world state (tension, player health, time since
last event, etc.), it either returns `nil` (nothing happens) or an event
map that the Director will process.

## Implementing a Storyteller

    defmodule MyGame.DramaticStoryteller do
      @behaviour Operator.Storyteller

      @impl true
      def init(opts) do
        %{
          last_event_tick: 0,
          min_interval: Map.get(opts, :min_interval, 100),
          tension_threshold: Map.get(opts, :tension_threshold, 0.6),
          escalation_factor: 1.0
        }
      end

      @impl true
      def pick_event(tick, world_state, state) do
        tension = Map.get(world_state, :tension, 0.0)
        ticks_since = tick - state.last_event_tick

        cond do
          # Cooldown period - no events too close together
          ticks_since < state.min_interval ->
            {nil, state}

          # High tension - trigger dramatic event
          tension > state.tension_threshold ->
            event = %{
              type: :dramatic_encounter,
              severity: min(5, round(tension * 5)),
              location: pick_hotspot(world_state)
            }
            {event, %{state | last_event_tick: tick, escalation_factor: 1.0}}

          # Low tension for too long - inject ambient event
          ticks_since > 500 and :rand.uniform() < 0.1 ->
            event = %{
              type: :ambient_event,
              severity: 1,
              location: pick_quiet_area(world_state)
            }
            {event, %{state | last_event_tick: tick}}

          # Nothing this tick
          true ->
            {nil, state}
        end
      end

      defp pick_hotspot(world_state), do: # ...
      defp pick_quiet_area(world_state), do: # ...
    end

## Storyteller Philosophies

Different games need different pacing. Here are some patterns:

### Tension-Release (Left 4 Dead style)

Build tension through enemy density and environmental cues, then release
with a dramatic event (horde attack, special infected spawn).

### Reactive (Nemesis system style)

Track player actions and generate events that respond to them. Kill a
captain? His blood brother shows up for revenge.

### Procedural Drama (Dwarf Fortress style)

Generate events based on faction relationships, resource scarcity, and
historical grudges. Let chaos emerge from simulation.

### Cinematic (Scripted game style)

Use storyteller state to track narrative beats. First act builds world,
second act introduces conflict, third act resolves it.

## Event Structure

Events should be maps with at least a `:type` key:

    %{
      type: :event_type,           # Required: atom identifier
      location: %{...},            # Where the event occurs
      actors: [entity_id, ...],    # Entities involved
      severity: 1..5,              # Event intensity
      raw_data: %{...}             # Game-specific data
    }

The Director passes events through `Operator.Rationalization` before
delivering them to your game.

## World State

The Director passes a `world_state` map to `pick_event/3`. Structure this
to give storytellers the information they need:

    %{
      tick: 12345,
      tension: 0.7,                    # 0.0 - 1.0
      player_health_percent: 0.4,
      summary: %{
        total_entities: 150,
        enemies_alive: 23,
        by_district: %{"downtown" => 45, "suburbs" => 30}
      },
      recent_events: [...],            # What's happened lately
      # ... your game's specific data
    }

## Built-in Storytellers

* `Operator.Director.NullStoryteller` - Never generates events (for testing)

## See Also

* `Operator.Director` - The GenServer that calls storytellers
* `Operator.Rationalization` - Event annotation

# `init`

```elixir
@callback init(opts :: map()) :: map()
```

Initialize storyteller state.

Called once when the Director starts or when switching storytellers.
Returns the initial state map that will be passed to `pick_event/3`.

## Arguments

- `opts` - Configuration options passed from Director startup

# `pick_event`

```elixir
@callback pick_event(
  tick :: non_neg_integer(),
  world_state :: map(),
  storyteller_state :: map()
) :: {map() | nil, map()}
```

Decide whether to generate an event this tick.

Called every tick by the Director. Should return:
- `{nil, new_state}` - No event this tick
- `{event_map, new_state}` - Generate an event

## Arguments

- `tick` - Current simulation tick
- `world_state` - Map containing world information
- `storyteller_state` - Current storyteller state from init/previous tick

## World State

The `world_state` map typically includes:

    %{
      tick: non_neg_integer(),
      summary: %{
        total_entities: non_neg_integer(),
        by_type: %{atom() => non_neg_integer()},
        by_district: %{String.t() => non_neg_integer()}
      },
      reports: [...],
      # Additional fields depend on host application
    }

---

*Consult [api-reference.md](api-reference.md) for complete listing*
