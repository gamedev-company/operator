defmodule Simulation.CityStoryteller do
  @moduledoc """
  Example storyteller for city simulation.

  Monitors city metrics and generates narrative events to
  create emergent stories:
  - Crime waves trigger police responses
  - Economic problems can lead to riots
  - Random ambient events add flavor
  - Tension builds over time without events

  """

  @behaviour Operator.Storyteller

  @impl true
  def init(opts) do
    %{
      tension: 0.0,
      last_event_tick: 0,
      event_cooldown: Map.get(opts, :cooldown, 100),
      tension_decay: Map.get(opts, :tension_decay, 0.01),
      tension_buildup: Map.get(opts, :tension_buildup, 0.05)
    }
  end

  @impl true
  def pick_event(tick, world_state, state) do
    crime_rate = Map.get(world_state, :crime_rate, 0.0)
    unemployment = Map.get(world_state, :unemployment, 0.0)
    ticks_since_event = tick - state.last_event_tick

    cond do
      # High crime -> police response
      crime_rate > 0.7 ->
        district = highest_crime_district(world_state)
        event = %{
          type: :police_raid,
          district: district,
          severity: ceil(crime_rate * 5),
          tick: tick
        }
        {event, %{state | last_event_tick: tick, tension: state.tension * 0.5}}

      # Economic collapse + high tension -> riots
      unemployment > 0.5 and state.tension > 0.8 ->
        event = %{
          type: :riot,
          severity: :major,
          cause: :economic,
          tick: tick
        }
        {event, %{state | last_event_tick: tick, tension: 0.2}}

      # Gradual tension buildup with ambient events
      ticks_since_event > state.event_cooldown ->
        {ambient_event, new_tension} = maybe_ambient_event(world_state, state)
        new_state = %{state |
          last_event_tick: if(ambient_event, do: tick, else: state.last_event_tick),
          tension: new_tension
        }
        {ambient_event, new_state}

      # No event, just update tension
      true ->
        new_tension = min(1.0, state.tension + state.tension_buildup * tension_factor(world_state))
        {nil, %{state | tension: new_tension}}
    end
  end

  # Private helpers

  defp highest_crime_district(world_state) do
    districts = Map.get(world_state, :district_crime, %{})

    if map_size(districts) > 0 do
      {district, _crime} = Enum.max_by(districts, fn {_d, c} -> c end)
      district
    else
      :downtown
    end
  end

  defp maybe_ambient_event(world_state, state) do
    roll = :rand.uniform()

    cond do
      # High tension -> dramatic event
      state.tension > 0.6 and roll < 0.3 ->
        event = %{
          type: :street_incident,
          severity: :minor,
          cause: :tension
        }
        {event, state.tension * 0.7}

      # Random ambient events
      roll < 0.1 ->
        event = random_ambient_event(world_state)
        {event, state.tension - state.tension_decay}

      # No event, decay tension
      true ->
        {nil, max(0.0, state.tension - state.tension_decay)}
    end
  end

  defp random_ambient_event(_world_state) do
    events = [
      %{type: :street_performer, severity: 1},
      %{type: :minor_accident, severity: 2},
      %{type: :celebrity_sighting, severity: 1},
      %{type: :protest_gathering, severity: 3},
      %{type: :power_fluctuation, severity: 2}
    ]

    Enum.random(events)
  end

  defp tension_factor(world_state) do
    crime = Map.get(world_state, :crime_rate, 0.0)
    unemployment = Map.get(world_state, :unemployment, 0.0)
    # Tension builds faster with worse conditions
    0.5 + crime * 0.3 + unemployment * 0.2
  end
end
