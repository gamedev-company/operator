defmodule GameNPC.Example do
  @moduledoc """
  Runnable examples demonstrating the Game NPC AI system.

  ## Running

      iex> GameNPC.Example.run()

  Or run individual scenarios:

      iex> GameNPC.Example.patrol_scenario()
      iex> GameNPC.Example.combat_scenario()
      iex> GameNPC.Example.survival_scenario()

  """

  alias Operator.HTN.{Facts, Planner, GoalSelector, Registry, Trace}
  alias GameNPC.{Domain, Executor}

  @doc """
  Run a complete demonstration of the NPC AI system.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         GAME NPC AI DEMONSTRATION")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Ensure domain is registered
    Registry.register(Domain)

    # Run each scenario
    patrol_scenario()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    combat_scenario()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    survival_scenario()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    goal_selection_demo()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         DEMONSTRATION COMPLETE")
    IO.puts(String.duplicate("=", 60) <> "\n")

    :ok
  end

  @doc """
  Demonstrate patrol behavior.

  The guard NPC patrols between waypoints when on duty with no threats.
  """
  def patrol_scenario do
    IO.puts("📍 SCENARIO: Patrol Duty")
    IO.puts("   Guard is on duty, no threats detected\n")

    # Set up world state for patrol
    state = %{
      health: 100,
      ammo: 30,
      position: {0, 0},
      on_duty: true,
      current_waypoint: 0,
      world: %{
        patrol_waypoints: [{10, 0}, {10, 10}, {0, 10}, {0, 0}],
        visible_enemies: [],
        cover_points: [{5, 5}]
      }
    }

    facts = build_facts(state)
    traits = %{archetype: :guard, traits: [:vigilant]}

    IO.puts("   Initial state:")
    IO.puts("   - Position: #{inspect(state.position)}")
    IO.puts("   - Health: #{state.health}")
    IO.puts("   - On duty: #{state.on_duty}")
    IO.puts("   - Waypoints: #{length(state.world.patrol_waypoints)}\n")

    # Generate and execute plan
    case Planner.run(:patrol, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Tasks: #{inspect(Enum.map(plan.tasks, &elem(&1, 0)))}\n")

        case Executor.execute_plan(plan, state) do
          {:ok, new_state} ->
            IO.puts("\n   ✓ Patrol step completed")
            IO.puts("   New position: #{inspect(new_state.position)}")
            IO.puts("   Current waypoint: #{new_state.current_waypoint}")

          {:error, reason, _state} ->
            IO.puts("   ✗ Patrol failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("   Could not plan patrol: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate combat behavior.

  The guard detects an enemy and engages in combat.
  """
  def combat_scenario do
    IO.puts("⚔️  SCENARIO: Combat Engagement")
    IO.puts("   Guard detects hostile at close range\n")

    # Set up world state for combat
    state = %{
      health: 80,
      ammo: 15,
      position: {5, 5},
      weapon_ready: false,
      world: %{
        {:distance, :hostile_1} => 12,
        {:position, :hostile_1} => {15, 5},
        visible_enemies: [:hostile_1],
        current_target: :hostile_1,
        cover_points: [{3, 3}, {7, 7}]
      }
    }

    facts = build_facts(state)
    traits = %{archetype: :guard, traits: [:aggressive]}

    IO.puts("   Initial state:")
    IO.puts("   - Health: #{state.health}")
    IO.puts("   - Ammo: #{state.ammo}")
    IO.puts("   - Enemy distance: #{state.world[{:distance, :hostile_1}]}\n")

    case Planner.run(:combat, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Tasks: #{inspect(Enum.map(plan.tasks, &elem(&1, 0)))}\n")

        case Executor.execute_plan(plan, state) do
          {:ok, new_state} ->
            IO.puts("\n   ✓ Combat action completed")
            IO.puts("   Ammo remaining: #{Map.get(new_state, :ammo, "unknown")}")
            IO.puts("   Position: #{inspect(new_state.position)}")

          {:error, reason, _state} ->
            IO.puts("   ✗ Combat failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("   Could not plan combat: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate survival behavior.

  The guard is critically wounded and attempts to flee.
  """
  def survival_scenario do
    IO.puts("🏃 SCENARIO: Survival - Flee")
    IO.puts("   Guard is critically wounded, must escape\n")

    # Set up world state for fleeing
    state = %{
      health: 15,  # Critical!
      ammo: 0,
      position: {10, 10},
      world: %{
        {:distance, :hostile_1} => 8,
        {:distance, :hostile_2} => 12,
        {:distance_between, {0, 0}, :hostile_1} => 15,
        {:distance_between, {20, 20}, :hostile_1} => 5,
        visible_enemies: [:hostile_1, :hostile_2],
        exit_points: [{0, 0}, {20, 20}]
      }
    }

    facts = build_facts(state)
    traits = %{archetype: :guard, traits: [:cautious]}

    IO.puts("   Initial state:")
    IO.puts("   - Health: #{state.health} (CRITICAL)")
    IO.puts("   - Ammo: #{state.ammo}")
    IO.puts("   - Enemies nearby: #{length(state.world.visible_enemies)}\n")

    case Planner.run(:flee, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Tasks: #{inspect(Enum.map(plan.tasks, &elem(&1, 0)))}\n")

        case Executor.execute_plan(plan, state) do
          {:ok, new_state} ->
            IO.puts("\n   ✓ Escape initiated")
            IO.puts("   Called backup: #{Map.get(new_state, :called_backup, false)}")

          {:error, reason, _state} ->
            IO.puts("   ✗ Escape failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("   Could not plan escape: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate automatic goal selection.

  The GoalSelector picks the most appropriate goal based on world state.
  """
  def goal_selection_demo do
    IO.puts("🎯 DEMO: Automatic Goal Selection")
    IO.puts("   Showing how goals are prioritized based on state\n")

    scenarios = [
      {"Routine patrol (no threats)", %{
        health: 100,
        ammo: 30,
        on_duty: true,
        world: %{visible_enemies: [], patrol_waypoints: [{1,1}]}
      }},
      {"Enemy detected", %{
        health: 80,
        ammo: 20,
        world: %{{:distance, :enemy} => 15, visible_enemies: [:enemy]}
      }},
      {"Critical health", %{
        health: 10,
        world: %{visible_enemies: [:enemy], exit_points: [{0,0}]}
      }},
      {"Wounded, safe area", %{
        health: 50,
        world: %{visible_enemies: [], healing_station_distance: 20}
      }}
    ]

    for {description, state} <- scenarios do
      facts = build_facts(state)
      traits = %{archetype: :guard}

      case GoalSelector.pick_goal(facts, traits) do
        {:ok, goal} ->
          IO.puts("   #{description}")
          IO.puts("   → Selected: :#{goal}\n")

        :none ->
          IO.puts("   #{description}")
          IO.puts("   → No applicable goal\n")
      end
    end
  end

  @doc """
  Run with tracing enabled to see detailed planning output.
  """
  def run_with_tracing do
    # Enable console tracing
    Trace.set_handler(Operator.HTN.Trace.ConsoleHandler)

    IO.puts("\n🔍 Running with detailed tracing...\n")

    patrol_scenario()

    # Disable tracing
    Trace.reset()
  end

  # Helper to build Facts from state map
  defp build_facts(state) do
    Facts.from_perception(%{
      self: Map.drop(state, [:world, :social]),
      world: Map.get(state, :world, %{}),
      social: Map.get(state, :social, %{})
    })
  end
end
