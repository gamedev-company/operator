defmodule Simulation.CitizenDomain do
  @moduledoc """
  HTN domain for citizen agents in city simulation.

  Demonstrates multiple agent archetypes with different goals:
  - Citizens pursue daily life (work, shopping, leisure)
  - Police respond to crimes and patrol
  - Criminals opportunistically commit crimes

  """

  use Operator.HTN.DSL

  alias Operator.HTN.Facts

  # ============================================================================
  # AXIOMS
  # ============================================================================

  axiom :is_working_hours do
    fn facts, _args ->
      hour = Facts.get(facts, {:world, :hour}, 12)
      hour >= 9 and hour < 17
    end
  end

  axiom :is_nighttime do
    fn facts, _args ->
      hour = Facts.get(facts, {:world, :hour}, 12)
      hour >= 21 or hour < 6
    end
  end

  axiom :police_nearby do
    fn facts, args ->
      range = Keyword.get(args, :range, 50)
      police_distance = Facts.get(facts, {:world, :nearest_police_distance}, 999)
      police_distance <= range
    end
  end

  axiom :danger_nearby do
    fn facts, _args ->
      threat = Facts.get(facts, {:world, :threat_level}, 0.0)
      threat > 0.5
    end
  end

  # ============================================================================
  # CITIZEN GOALS
  # ============================================================================

  goal :go_to_work do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :employed}, false) end,
      {:axiom, :is_working_hours},
      fn facts -> Facts.get(facts, {:self, :at_work}, false) == false end
    ]}

    decompose do
      task :plan_commute
      task :travel_to_work
      task :check_in_at_work
    end

    metadata priority: 5, archetype: :citizen
  end

  goal :shop_for_supplies do
    precond fn facts ->
      supplies = Facts.get(facts, {:self, :supplies}, 100)
      supplies < 30
    end

    decompose do
      task :find_nearby_store
      task :travel_to_store
      task :purchase_supplies
      task :return_home
    end

    metadata priority: 6, archetype: :citizen
  end

  goal :seek_leisure do
    precond {:all, [
      fn facts -> not Facts.get(facts, {:self, :at_work}, false) end,
      {:not, {:axiom, :danger_nearby}},
      fn facts -> Facts.get(facts, {:self, :energy}, 0) > 50 end
    ]}

    decompose do
      task :choose_activity
      task :travel_to_venue
      task :enjoy_activity
    end

    metadata priority: 2, archetype: :citizen
  end

  goal :flee_danger do
    precond {:axiom, :danger_nearby}

    decompose do
      task :assess_threat
      task :find_safe_route
      task :evacuate
      task :notify_authorities
    end

    metadata priority: 10, archetype: :citizen
  end

  # ============================================================================
  # POLICE GOALS
  # ============================================================================

  goal :patrol_district do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :role}) == :police end,
      fn facts -> Facts.get(facts, {:self, :on_shift}, false) end,
      fn facts -> Facts.get(facts, {:self, :responding_to_call}, false) == false end
    ]}

    decompose do
      task :get_patrol_route
      task :walk_patrol_route
      task :observe_surroundings
    end

    metadata priority: 4, archetype: :police
  end

  goal :respond_to_incident do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :role}) == :police end,
      fn facts -> Facts.get(facts, {:self, :assigned_incident}) != nil end
    ]}

    decompose do
      task :acknowledge_dispatch
      task :travel_to_incident
      task :assess_situation
      task :take_appropriate_action
      task :file_report
    end

    metadata priority: 9, archetype: :police
  end

  goal :pursue_suspect do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :role}) == :police end,
      fn facts -> Facts.get(facts, {:self, :spotted_suspect}) != nil end
    ]}

    decompose do
      task :call_for_backup
      task :chase_suspect
      task :apprehend_if_possible
    end

    metadata priority: 8, archetype: :police
  end

  # ============================================================================
  # CRIMINAL GOALS
  # ============================================================================

  goal :commit_crime do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :desperate}, false) end,
      fn facts -> opportunity_present?(facts) end,
      {:not, {:axiom, :police_nearby, range: 100}}
    ]}

    decompose do
      task :case_target
      task :execute_crime
      task :flee_scene
    end

    metadata priority: 7, archetype: :criminal
  end

  goal :lay_low do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :heat_level}, 0) > 0.5 end,
      fn facts -> Facts.get(facts, {:self, :has_hideout}, false) end
    ]}

    decompose do
      task :travel_to_hideout
      task :wait_for_heat_to_drop
    end

    metadata priority: 8, archetype: :criminal
  end

  # ============================================================================
  # TASKS
  # ============================================================================

  task :plan_commute do
    decompose fn facts ->
      home = Facts.get(facts, {:self, :home_location})
      work = Facts.get(facts, {:self, :work_location})
      [{:calculate_route, [home, work]}]
    end
    cost 0.5
  end

  task :travel_to_work do
    decompose fn facts ->
      transport = Facts.get(facts, {:self, :preferred_transport}, :walk)
      case transport do
        :car -> [{:drive_to, [:work_location]}]
        :transit -> [{:take_transit_to, [:work_location]}]
        _ -> [{:walk_to, [:work_location]}]
      end
    end
    cost 2.0
  end

  task :assess_situation do
    decompose fn facts ->
      severity = Facts.get(facts, {:world, :incident_severity}, 1)
      if severity > 3 do
        [{:call_for_backup, []}, {:secure_perimeter, []}]
      else
        [{:interview_witnesses, []}, {:gather_evidence, []}]
      end
    end
    cost 2.0
  end

  task :take_appropriate_action do
    decompose fn facts ->
      incident_type = Facts.get(facts, {:self, :incident_type}, :disturbance)
      case incident_type do
        :violent_crime -> [{:use_force_if_necessary, []}, {:arrest_perpetrator, []}]
        :theft -> [{:detain_suspect, []}, {:recover_property, []}]
        _ -> [{:mediate_situation, []}, {:issue_warning, []}]
      end
    end
    cost 3.0
  end

  # ============================================================================
  # PRIMITIVES
  # ============================================================================

  primitive :walk_to do
    run fn actor, _facts ->
      destination = Map.get(actor, :pending_args, [:unknown]) |> List.first()
      IO.puts("[Citizen] Walking to #{inspect(destination)}")
      {:ok, Map.put(actor, :moving_to, destination)}
    end
  end

  primitive :drive_to do
    run fn actor, _facts ->
      destination = Map.get(actor, :pending_args, [:unknown]) |> List.first()
      IO.puts("[Citizen] Driving to #{inspect(destination)}")
      {:ok, Map.put(actor, :moving_to, destination)}
    end
  end

  primitive :take_transit_to do
    run fn actor, _facts ->
      destination = Map.get(actor, :pending_args, [:unknown]) |> List.first()
      IO.puts("[Citizen] Taking transit to #{inspect(destination)}")
      {:ok, Map.put(actor, :moving_to, destination)}
    end
  end

  primitive :check_in_at_work do
    run fn actor, _facts ->
      IO.puts("[Citizen] Checking in at work")
      {:ok, Map.put(actor, :at_work, true)}
    end
  end

  primitive :calculate_route do
    run fn actor, _facts ->
      args = Map.get(actor, :pending_args, [nil, nil])
      from = Enum.at(args, 0)
      to = Enum.at(args, 1)
      IO.puts("[Citizen] Planning route from #{inspect(from)} to #{inspect(to)}")
      {:ok, Map.put(actor, :planned_route, {from, to})}
    end
  end

  primitive :call_for_backup do
    run fn actor, _facts ->
      IO.puts("[Police] Calling for backup!")
      {:ok, Map.put(actor, :backup_requested, true)}
    end
  end

  primitive :secure_perimeter do
    run fn actor, _facts ->
      IO.puts("[Police] Securing perimeter")
      {:ok, actor}
    end
  end

  primitive :interview_witnesses do
    run fn actor, _facts ->
      IO.puts("[Police] Interviewing witnesses")
      {:ok, actor}
    end
  end

  primitive :gather_evidence do
    run fn actor, _facts ->
      IO.puts("[Police] Gathering evidence")
      {:ok, actor}
    end
  end

  primitive :arrest_perpetrator do
    run fn actor, _facts ->
      IO.puts("[Police] Arresting perpetrator")
      {:ok, Map.put(actor, :made_arrest, true)}
    end
  end

  primitive :file_report do
    run fn actor, _facts ->
      IO.puts("[Police] Filing incident report")
      {:ok, Map.put(actor, :report_filed, true)}
    end
  end

  primitive :acknowledge_dispatch do
    run fn actor, _facts ->
      IO.puts("[Police] Acknowledging dispatch")
      {:ok, Map.put(actor, :responding_to_call, true)}
    end
  end

  primitive :travel_to_incident do
    run fn actor, facts ->
      location = Facts.get(facts, {:self, :incident_location})
      IO.puts("[Police] Responding to incident at #{inspect(location)}")
      {:ok, Map.put(actor, :moving_to, location)}
    end
  end

  # Additional primitives...

  primitive :case_target do
    run fn actor, _facts ->
      IO.puts("[Criminal] Casing the target...")
      {:ok, Map.put(actor, :target_cased, true)}
    end
  end

  primitive :execute_crime do
    run fn actor, _facts ->
      IO.puts("[Criminal] Executing crime...")
      {:ok, Map.merge(actor, %{crime_committed: true, heat_level: 0.8})}
    end
  end

  primitive :flee_scene do
    run fn actor, _facts ->
      IO.puts("[Criminal] Fleeing the scene!")
      {:ok, Map.put(actor, :fleeing, true)}
    end
  end

  # Helper function used in precondition
  defp opportunity_present?(facts) do
    targets = Facts.get(facts, {:world, :vulnerable_targets}, [])
    length(targets) > 0
  end
end
