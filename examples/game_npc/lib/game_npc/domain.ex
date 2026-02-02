defmodule GameNPC.Domain do
  @moduledoc """
  HTN domain definition for game NPC AI.

  Defines goals, tasks, and primitives for a guard NPC that can:
  - Patrol waypoints
  - Investigate disturbances
  - Engage in combat
  - Flee when wounded
  - Heal at supply points

  ## Goal Hierarchy

      ┌─────────────────────────────────────────┐
      │              flee (priority: 10)        │
      │    ↓ health critical                    │
      ├─────────────────────────────────────────┤
      │             combat (priority: 5)        │
      │    ↓ enemy detected                     │
      ├─────────────────────────────────────────┤
      │          investigate (priority: 4)      │
      │    ↓ disturbance heard                  │
      ├─────────────────────────────────────────┤
      │             heal (priority: 3)          │
      │    ↓ wounded but safe                   │
      ├─────────────────────────────────────────┤
      │            patrol (priority: 2)         │
      │    ↓ on duty, no threats                │
      ├─────────────────────────────────────────┤
      │             idle (priority: 1)          │
      │    ↓ fallback                           │
      └─────────────────────────────────────────┘

  """

  use Operator.HTN.DSL

  alias Operator.HTN.Facts

  # ============================================================================
  # AXIOMS - Reusable query patterns
  # ============================================================================

  @doc "Check if health is below a threshold"
  axiom :health_critical do
    fn facts, args ->
      threshold = Keyword.get(args, :threshold, 25)
      Facts.get(facts, {:self, :health}, 100) < threshold
    end
  end

  @doc "Check if there's a nearby threat"
  axiom :threat_nearby do
    fn facts, args ->
      max_distance = Keyword.get(args, :distance, 20)
      enemies = Facts.get(facts, {:world, :visible_enemies}, [])

      Enum.any?(enemies, fn enemy ->
        Facts.get(facts, {:world, {:distance, enemy}}, 999) <= max_distance
      end)
    end
  end

  @doc "Check if NPC has ammunition"
  axiom :has_ammo do
    fn facts, _args ->
      Facts.get(facts, {:self, :ammo}, 0) > 0
    end
  end

  @doc "Check if there's a nearby healing station"
  axiom :healing_available do
    fn facts, args ->
      max_distance = Keyword.get(args, :distance, 50)
      station_distance = Facts.get(facts, {:world, :healing_station_distance}, 999)
      station_distance <= max_distance
    end
  end

  # ============================================================================
  # GOALS - High-level objectives
  # ============================================================================

  @doc """
  Flee from danger when health is critical.

  Highest priority - survival takes precedence over all else.
  """
  goal :flee do
    precond {:axiom, :health_critical, threshold: 25}

    decompose do
      task :find_escape_route
      task :run_to_safety
      task :call_for_backup
    end

    metadata priority: 10, domain: :survival
  end

  @doc """
  Engage detected enemies in combat.

  Activates when enemies are visible and NPC has combat capability.
  """
  goal :combat do
    precond {:all, [
      {:axiom, :threat_nearby, distance: 30},
      {:not, {:axiom, :health_critical, threshold: 25}},
      {:any, [
        {:axiom, :has_ammo},
        fn facts -> Facts.has?(facts, {:self, :melee_weapon}) end
      ]}
    ]}

    decompose do
      task :take_cover
      task :engage_target
    end

    metadata priority: 5, domain: :combat
  end

  @doc """
  Investigate a disturbance.

  Triggered by sounds or suspicious activity when no direct threat.
  """
  goal :investigate do
    precond {:all, [
      fn facts -> Facts.has?(facts, {:world, :disturbance_location}) end,
      {:not, {:axiom, :threat_nearby, distance: 10}}
    ]}

    decompose do
      task :approach_cautiously
      task :search_area
      task :clear_disturbance
    end

    metadata priority: 4, domain: :security
  end

  @doc """
  Heal at a supply station when wounded but safe.
  """
  goal :heal do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :health}, 100) < 80 end,
      {:axiom, :healing_available, distance: 100},
      {:not, {:axiom, :threat_nearby, distance: 20}}
    ]}

    decompose do
      task :move_to_healing_station
      task :use_healing_station
    end

    metadata priority: 3, domain: :survival
  end

  @doc """
  Routine patrol behavior.

  Default behavior when on duty with no active threats.
  """
  goal :patrol do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :on_duty}, false) end,
      {:not, {:axiom, :threat_nearby, distance: 30}},
      {:not, fn facts -> Facts.has?(facts, {:world, :disturbance_location}) end}
    ]}

    decompose do
      task :move_to_next_waypoint
      task :scan_surroundings
    end

    metadata priority: 2, domain: :security
  end

  @doc """
  Idle fallback when nothing else to do.
  """
  goal :idle do
    precond fn _facts -> true end

    decompose do
      task :wait_idle
    end

    metadata priority: 1, domain: :default
  end

  # ============================================================================
  # TASKS - Intermediate decomposable steps
  # ============================================================================

  task :find_escape_route do
    decompose fn facts ->
      enemies = Facts.get(facts, {:world, :visible_enemies}, [])
      exit_points = Facts.get(facts, {:world, :exit_points}, [])

      # Find exit furthest from enemies
      best_exit = Enum.max_by(exit_points, fn exit ->
        Enum.min(Enum.map(enemies, fn enemy ->
          Facts.get(facts, {:world, {:distance_between, exit, enemy}}, 0)
        end))
      end, fn -> :fallback_exit end)

      [{:calculate_path, [best_exit]}]
    end

    cost 1.0
    metadata category: :navigation
  end

  task :run_to_safety do
    decompose fn facts ->
      escape_path = Facts.get(facts, {:self, :escape_path}, [])
      Enum.map(escape_path, fn waypoint -> {:sprint_to, [waypoint]} end)
    end

    cost 3.0
    metadata category: :movement
  end

  task :take_cover do
    decompose fn facts ->
      cover_points = Facts.get(facts, {:world, :cover_points}, [])
      position = Facts.get(facts, {:self, :position})

      nearest_cover = Enum.min_by(cover_points, fn cover ->
        distance(position, cover)
      end, fn -> nil end)

      if nearest_cover do
        [{:move_to, [nearest_cover]}, {:crouch, []}]
      else
        [{:crouch, []}]  # No cover, just crouch
      end
    end

    cost 2.0
    metadata category: :tactical
  end

  task :engage_target do
    decompose fn facts ->
      target = Facts.get(facts, {:world, :current_target})
      has_ammo = Facts.get(facts, {:self, :ammo}, 0) > 0
      distance = Facts.get(facts, {:world, {:distance, target}}, 999)

      cond do
        has_ammo and distance < 30 ->
          [{:aim_at, [target]}, {:fire_weapon, [target]}]

        has_ammo and distance >= 30 ->
          [{:move_closer, [target]}, {:aim_at, [target]}, {:fire_weapon, [target]}]

        distance < 5 ->
          [{:melee_attack, [target]}]

        true ->
          [{:move_closer, [target]}, {:melee_attack, [target]}]
      end
    end

    cost 5.0
    metadata category: :combat
  end

  task :approach_cautiously do
    decompose fn facts ->
      target = Facts.get(facts, {:world, :disturbance_location})
      [{:ready_weapon, []}, {:slow_move_to, [target]}]
    end

    cost 3.0
    metadata category: :tactical
  end

  task :search_area do
    decompose do
      task :look_around
      task :check_corners
    end

    cost 2.0
    metadata category: :perception
  end

  task :move_to_healing_station do
    decompose fn facts ->
      station = Facts.get(facts, {:world, :nearest_healing_station})
      [{:move_to, [station]}]
    end

    cost 2.0
    metadata category: :navigation
  end

  task :move_to_next_waypoint do
    decompose fn facts ->
      current_waypoint = Facts.get(facts, {:self, :current_waypoint}, 0)
      waypoints = Facts.get(facts, {:world, :patrol_waypoints}, [])
      next_index = rem(current_waypoint + 1, length(waypoints))
      next_waypoint = Enum.at(waypoints, next_index)

      [{:move_to, [next_waypoint]}, {:update_waypoint_index, [next_index]}]
    end

    cost 2.0
    metadata category: :patrol
  end

  task :scan_surroundings do
    decompose do
      task :look_around
      task :listen_for_sounds
    end

    cost 1.0
    metadata category: :perception
  end

  # ============================================================================
  # PRIMITIVES - Directly executable actions
  # ============================================================================

  # Note: Primitives receive args through the actor's :pending_args field
  # which is set by the executor before running the primitive

  primitive :calculate_path do
    run fn actor, facts ->
      # Get destination from pending_args (set by executor)
      destination = Map.get(actor, :pending_args, []) |> List.first()
      position = Facts.get(facts, {:self, :position}, {0, 0})
      path = if destination, do: [position, destination], else: [position]
      {:ok, Map.put(actor, :escape_path, path)}
    end

    metadata action_type: :planning
  end

  primitive :sprint_to do
    run fn actor, _facts ->
      # Get waypoint from pending_args
      waypoint = Map.get(actor, :pending_args, []) |> List.first() || actor[:position]
      {:ok, Map.put(actor, :position, waypoint)}
    end

    metadata action_type: :movement, speed: :fast
  end

  primitive :move_to do
    run fn actor, _facts ->
      # Get destination from pending_args
      destination = Map.get(actor, :pending_args, []) |> List.first() || actor[:position]
      {:ok, Map.put(actor, :position, destination)}
    end

    metadata action_type: :movement, speed: :normal
  end

  primitive :slow_move_to do
    run fn actor, _facts ->
      destination = Map.get(actor, :pending_args, []) |> List.first() || actor[:position]
      {:ok, Map.merge(actor, %{position: destination, stance: :cautious})}
    end

    metadata action_type: :movement, speed: :slow
  end

  primitive :move_closer do
    run fn actor, facts ->
      target = Map.get(actor, :pending_args, []) |> List.first()
      target_pos = Facts.get(facts, {:world, {:position, target}}, {0, 0})
      current_pos = Facts.get(facts, {:self, :position}, {0, 0})
      new_pos = midpoint(current_pos, target_pos)
      {:ok, Map.put(actor, :position, new_pos)}
    end

    metadata action_type: :movement
  end

  primitive :crouch do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :stance, :crouched)}
    end

    metadata action_type: :stance
  end

  primitive :ready_weapon do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :weapon_ready, true)}
    end

    metadata action_type: :preparation
  end

  primitive :aim_at do
    run fn actor, _facts ->
      target = Map.get(actor, :pending_args, []) |> List.first()
      {:ok, Map.put(actor, :aiming_at, target)}
    end

    metadata action_type: :combat
  end

  primitive :fire_weapon do
    run fn actor, facts ->
      ammo = Facts.get(facts, {:self, :ammo}, 0)

      if ammo > 0 do
        {:ok, Map.update(actor, :ammo, 0, &(&1 - 1))}
      else
        {:error, :no_ammo}
      end
    end

    metadata action_type: :combat, sound: "gunshot"
  end

  primitive :melee_attack do
    run fn actor, _facts ->
      target = Map.get(actor, :pending_args, []) |> List.first()
      {:ok, Map.put(actor, :attacking, target)}
    end

    metadata action_type: :combat
  end

  primitive :call_for_backup do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :called_backup, true)}
    end

    metadata action_type: :communication
  end

  primitive :look_around do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :last_scan, System.os_time(:second))}
    end

    metadata action_type: :perception
  end

  primitive :check_corners do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :corners_checked, true)}
    end

    metadata action_type: :perception
  end

  primitive :listen_for_sounds do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :listening, true)}
    end

    metadata action_type: :perception
  end

  primitive :clear_disturbance do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :disturbance_cleared, true)}
    end

    metadata action_type: :security
  end

  primitive :use_healing_station do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :health, 100)}
    end

    metadata action_type: :healing, duration: 3000
  end

  primitive :update_waypoint_index do
    run fn actor, _facts ->
      index = Map.get(actor, :pending_args, []) |> List.first() || 0
      {:ok, Map.put(actor, :current_waypoint, index)}
    end

    metadata action_type: :internal
  end

  primitive :wait_idle do
    run fn actor, _facts ->
      {:ok, actor}
    end

    metadata action_type: :idle, duration: 1000
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))
  end

  defp midpoint({x1, y1}, {x2, y2}) do
    {(x1 + x2) / 2, (y1 + y2) / 2}
  end
end
