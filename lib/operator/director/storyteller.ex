defmodule Operator.Storyteller do
  @moduledoc """
  Behaviour for storyteller strategies.

  Storytellers decide what events to inject into the simulation based on
  world state. Each storyteller encapsulates a different narrative style
  or dramatic tension model.

  ## Implementing a Storyteller

      defmodule MyStoryteller do
        @behaviour Operator.Storyteller

        @impl true
        def init(opts) do
          %{
            last_event_tick: 0,
            min_event_interval: Map.get(opts, :interval, 100),
            tension_threshold: Map.get(opts, :tension_threshold, 0.5)
          }
        end

        @impl true
        def pick_event(tick, world_state, state) do
          tension = world_state[:tension] || 0.0
          ticks_since_event = tick - state.last_event_tick

          cond do
            ticks_since_event < state.min_event_interval ->
              {nil, state}

            tension > state.tension_threshold ->
              event = generate_high_tension_event(world_state)
              {event, %{state | last_event_tick: tick}}

            :rand.uniform() < 0.1 ->
              event = generate_ambient_event(world_state)
              {event, %{state | last_event_tick: tick}}

            true ->
              {nil, state}
          end
        end
      end

  ## Event Structure

  Events returned by `pick_event/3` should be maps with at least:

      %{
        type: :event_type,           # Required: atom identifying event type
        location: %{...},            # Optional: where the event occurs
        actors: [...],               # Optional: entities involved
        severity: 1..5,              # Optional: event severity
        raw_data: %{...}             # Optional: additional data
      }

  The Director will rationalize these events into full narrative events.

  ## Built-in Storytellers

  Operator provides a default storyteller for testing:

  - `Operator.Director.NullStoryteller` - Never generates events

  """

  @doc """
  Initialize storyteller state.

  Called once when the Director starts or when switching storytellers.
  Returns the initial state map that will be passed to `pick_event/3`.

  ## Arguments

  - `opts` - Configuration options passed from Director startup

  """
  @callback init(opts :: map()) :: map()

  @doc """
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

  """
  @callback pick_event(
              tick :: non_neg_integer(),
              world_state :: map(),
              storyteller_state :: map()
            ) :: {map() | nil, map()}
end
