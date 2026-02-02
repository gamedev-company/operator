defmodule Simulation.Example do
  @moduledoc """
  Runnable examples demonstrating the city simulation system.

  ## Running

      iex> Simulation.Example.run_city(ticks: 100)

  Or run individual demonstrations:

      iex> Simulation.Example.citizen_behavior()
      iex> Simulation.Example.police_response()
      iex> Simulation.Example.director_events()

  """

  alias Operator.HTN.{Facts, Planner, GoalSelector, Registry}
  alias Operator.Director
  alias Simulation.{CitizenDomain, CityStoryteller}

  @doc """
  Run a complete city simulation demonstration.
  """
  def run_city(opts \\ []) do
    ticks = Keyword.get(opts, :ticks, 50)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         CITY SIMULATION DEMONSTRATION")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Ensure domain is registered
    Registry.register(CitizenDomain)

    # Run demonstrations
    citizen_behavior()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    police_response()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    director_events(ticks)
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    emergent_story_demo()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         SIMULATION COMPLETE")
    IO.puts(String.duplicate("=", 60) <> "\n")

    :ok
  end

  @doc """
  Demonstrate citizen daily behavior.

  Shows how citizens select goals based on their needs
  and the time of day.
  """
  def citizen_behavior do
    IO.puts("👤 DEMO: Citizen Daily Behavior")
    IO.puts("   Simulating a citizen's day\n")

    scenarios = [
      {"Morning commute (9 AM)", %{
        self: %{employed: true, at_work: false, home_location: :suburbs, work_location: :downtown},
        world: %{hour: 9, threat_level: 0.0}
      }},
      {"Low on supplies", %{
        self: %{supplies: 20, energy: 70, at_work: false},
        world: %{hour: 14, threat_level: 0.0}
      }},
      {"Evening leisure", %{
        self: %{at_work: false, energy: 80, supplies: 60},
        world: %{hour: 19, threat_level: 0.1}
      }},
      {"Danger nearby!", %{
        self: %{at_work: false},
        world: %{hour: 15, threat_level: 0.8, active_event: :riot}
      }}
    ]

    for {description, state} <- scenarios do
      facts = Facts.from_perception(state)
      traits = %{archetype: :citizen}

      IO.puts("   #{description}")
      case GoalSelector.pick_goal(facts, traits) do
        {:ok, goal} ->
          IO.puts("   → Goal: :#{goal}")
          case Planner.run(goal, facts, traits) do
            {:ok, plan} ->
              tasks = Enum.map(plan.tasks, &elem(&1, 0)) |> Enum.join(" → ")
              IO.puts("   → Plan: #{tasks}\n")
            {:error, _} ->
              IO.puts("   → Could not plan\n")
          end

        :none ->
          IO.puts("   → No applicable goal\n")
      end
    end
  end

  @doc """
  Demonstrate police response to incidents.

  Shows how police agents prioritize and respond to calls.
  """
  def police_response do
    IO.puts("👮 DEMO: Police Response")
    IO.puts("   Simulating police behavior\n")

    scenarios = [
      {"On patrol (no incidents)", %{
        self: %{role: :police, on_shift: true, responding_to_call: false},
        world: %{hour: 14}
      }},
      {"Incident assigned", %{
        self: %{role: :police, on_shift: true, assigned_incident: :burglary,
                incident_location: {:downtown, 5}, incident_type: :theft},
        world: %{hour: 15, incident_severity: 2}
      }},
      {"Spotted suspect", %{
        self: %{role: :police, on_shift: true, spotted_suspect: :suspect_1},
        world: %{hour: 16}
      }}
    ]

    for {description, state} <- scenarios do
      facts = Facts.from_perception(state)
      traits = %{archetype: :police}

      IO.puts("   #{description}")
      case GoalSelector.pick_goal(facts, traits) do
        {:ok, goal} ->
          IO.puts("   → Goal: :#{goal}")
          case Planner.run(goal, facts, traits) do
            {:ok, plan} ->
              IO.puts("   → Steps:")
              Enum.each(plan.tasks, fn {name, _} ->
                IO.puts("        • #{name}")
              end)
              IO.puts("")
            {:error, _} ->
              IO.puts("   → Could not plan\n")
          end

        :none ->
          IO.puts("   → No applicable goal\n")
      end
    end
  end

  @doc """
  Demonstrate the Director generating narrative events.

  Shows how the CityStoryteller responds to city conditions.
  """
  def director_events(ticks \\ 20) do
    IO.puts("🎬 DEMO: Director Event Generation")
    IO.puts("   Running #{ticks} ticks with CityStoryteller\n")

    # Start Director with our storyteller
    events_received = :ets.new(:events, [:set, :public])

    {:ok, director} = Director.start_link(
      storyteller: CityStoryteller,
      name: :demo_director,
      on_event: fn event ->
        :ets.insert(events_received, {event.type, event})
        IO.puts("   📢 Event: #{event.type} (severity: #{Map.get(event, :severity, "?")})")
      end
    )

    # Simulate ticks with varying conditions
    world_states = [
      # Normal conditions
      Enum.map(1..5, fn t -> %{tick: t, crime_rate: 0.2, unemployment: 0.1} end),
      # Rising crime
      Enum.map(6..10, fn t -> %{tick: t, crime_rate: 0.5 + t * 0.03, unemployment: 0.2} end),
      # Crime wave
      Enum.map(11..15, fn t -> %{tick: t, crime_rate: 0.75, unemployment: 0.3,
                                  district_crime: %{harbor: 0.9, downtown: 0.7}} end),
      # Economic crisis
      Enum.map(16..ticks, fn t -> %{tick: t, crime_rate: 0.5, unemployment: 0.55} end)
    ] |> List.flatten()

    for world_state <- world_states do
      Director.tick(world_state, :demo_director)
      Process.sleep(50)  # Small delay for readability
    end

    # Summary
    events = :ets.tab2list(events_received) |> Enum.map(fn {type, _} -> type end)
    IO.puts("\n   Events generated: #{length(events)}")
    IO.puts("   Event types: #{events |> Enum.uniq() |> inspect()}")

    # Cleanup
    GenServer.stop(director)
    :ets.delete(events_received)
  end

  @doc """
  Demonstrate emergent narrative from interacting systems.

  Shows how HTN agents + Director events create stories.
  """
  def emergent_story_demo do
    IO.puts("📖 DEMO: Emergent Narrative")
    IO.puts("   Combining agent behavior with Director events\n")

    IO.puts("   Scenario: Crime wave in Harbor District")
    IO.puts("   " <> String.duplicate("-", 40) <> "\n")

    # Initial situation
    IO.puts("   [Tick 1] Crime rate rises in Harbor district...")

    # Criminal sees opportunity
    criminal_facts = Facts.from_perception(%{
      self: %{desperate: true},
      world: %{vulnerable_targets: [:store_1], nearest_police_distance: 150}
    })

    case GoalSelector.pick_goal(criminal_facts, %{archetype: :criminal}) do
      {:ok, :commit_crime} ->
        IO.puts("   [Tick 2] Criminal spots opportunity, police far away")
        {:ok, plan} = Planner.run(:commit_crime, criminal_facts, %{})
        IO.puts("            Plan: #{plan.tasks |> Enum.map(&elem(&1, 0)) |> Enum.join(" → ")}")
      _ -> :ok
    end

    # Director generates event
    IO.puts("\n   [Tick 3] 🎬 Director: :police_raid in Harbor!")

    # Police respond
    police_facts = Facts.from_perception(%{
      self: %{role: :police, on_shift: true, assigned_incident: :robbery,
              incident_location: :harbor, incident_type: :theft},
      world: %{incident_severity: 3}
    })

    case GoalSelector.pick_goal(police_facts, %{archetype: :police}) do
      {:ok, :respond_to_incident} ->
        IO.puts("   [Tick 4] Police respond to incident")
        {:ok, plan} = Planner.run(:respond_to_incident, police_facts, %{})
        IO.puts("            Plan: #{plan.tasks |> Enum.map(&elem(&1, 0)) |> Enum.join(" → ")}")
      _ -> :ok
    end

    # Citizen flees
    citizen_facts = Facts.from_perception(%{
      self: %{at_work: false, home_location: :suburbs},
      world: %{threat_level: 0.7, hour: 15}
    })

    case GoalSelector.pick_goal(citizen_facts, %{archetype: :citizen}) do
      {:ok, :flee_danger} ->
        IO.puts("   [Tick 5] Citizen flees the area")
        {:ok, plan} = Planner.run(:flee_danger, citizen_facts, %{})
        IO.puts("            Plan: #{plan.tasks |> Enum.map(&elem(&1, 0)) |> Enum.join(" → ")}")
      _ -> :ok
    end

    IO.puts("\n   " <> String.duplicate("-", 40))
    IO.puts("   Story emerged from autonomous agents + Director!")
  end
end
