# `Operator`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator.ex#L1)

Operator - A pluggable AI planning and narrative orchestration library.

Operator provides two main subsystems for building intelligent agents and
dynamic narrative systems:

* **HTN Planning** - Goal-based hierarchical task decomposition
* **Director** - Event-driven narrative orchestration

## Quick Start

### 1. Define Agent Behaviors

Use the DSL to define goals, tasks, and primitives:

    defmodule MyGame.NPCBehavior do
      use Operator.HTN.DSL

      goal :patrol do
        precond fn facts ->
          Operator.HTN.Facts.has?(facts, {:self, :on_duty})
        end

        decompose do
          task :walk_to_waypoint, :next
          task :scan_area
          task :patrol  # Recursive!
        end

        metadata priority: 3, domain: :security
      end

      primitive :scan_area do
        run fn actor, _facts ->
          # Your game logic here
          {:ok, %{actor | scanning: true}}
        end
      end
    end

### 2. Generate Plans

    facts = Operator.HTN.Facts.from_perception(%{
      self: %{on_duty: true, location: :lobby},
      world: %{threat_level: :low}
    })

    case Operator.HTN.Planner.run(:patrol, facts, agent_traits) do
      {:ok, plan} ->
        # plan.tasks contains executable primitives
        execute_plan(plan)

      {:error, reason} ->
        handle_planning_failure(reason)
    end

### 3. Orchestrate Narrative Events

    defmodule MyGame.DramaticStoryteller do
      @behaviour Operator.Storyteller

      @impl true
      def init(_opts), do: %{tension: 0.0}

      @impl true
      def pick_event(tick, world_state, state) do
        if world_state.tension > 0.8 do
          event = %{type: :confrontation, severity: :high}
          {event, %{state | tension: 0.0}}
        else
          {nil, state}
        end
      end
    end

    {:ok, _pid} = Operator.Director.start_link(
      storyteller: MyGame.DramaticStoryteller,
      on_event: &MyGame.EventHandler.process/1
    )

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Operator Library                        │
├─────────────────────────────────────────────────────────────┤
│  HTN Planning                   │  Director                  │
│  ├─ Facts (world state)         │  ├─ Storyteller behaviour  │
│  ├─ Goals (high-level)          │  ├─ Tick-based events      │
│  ├─ Tasks (decomposable)        │  └─ World state queries    │
│  ├─ Primitives (executable)     │                            │
│  ├─ Effects (state changes)     │                            │
│  └─ Axioms (reusable queries)   │                            │
├─────────────────────────────────────────────────────────────┤
│  Integration Behaviours                                      │
│  ├─ Telemetry  - Metrics and observability                  │
│  ├─ Traits     - Agent personality/capabilities             │
│  ├─ Storage    - Plan persistence                           │
│  └─ Rationalization - Plan annotation/explanation           │
└─────────────────────────────────────────────────────────────┘
```

## Module Index

### HTN Planning

* `Operator.HTN.DSL` - Macro-based goal/task definition
* `Operator.HTN.Facts` - World state representation
* `Operator.HTN.Plan` - Generated plan structure
* `Operator.HTN.Task` - Task definition struct
* `Operator.HTN.Effect` - World state modifications
* `Operator.HTN.Axiom` - Reusable query patterns
* `Operator.HTN.Precondition` - Logical operators (AND/OR/NOT)
* `Operator.HTN.Engine` - Plan generation algorithm
* `Operator.HTN.Planner` - High-level planning API
* `Operator.HTN.GoalSelector` - Automatic goal selection
* `Operator.HTN.Registry` - Goal/task lookup
* `Operator.HTN.Trace` - Debug tracing

### Director

* `Operator.Director` - Event orchestration GenServer
* `Operator.Storyteller` - Event generation behaviour

### Integration Behaviours

* `Operator.Telemetry` - Metrics callbacks
* `Operator.Traits` - Agent trait integration
* `Operator.Storage` - Plan persistence
* `Operator.Rationalization` - Plan annotation

## Configuration

All configuration is optional. Operator works out of the box with sensible
defaults:

    # config/config.exs
    config :operator,
      # Emit telemetry events for monitoring
      telemetry_module: MyApp.OperatorTelemetry,

      # Custom agent trait system integration
      traits_module: MyApp.OperatorTraits,

      # Plan storage backend (default: ETS)
      storage_module: Operator.HTN.Storage,

      # Plan explanation/annotation
      rationalization_module: MyApp.OperatorRationalization,

      # Enable detailed planning traces
      trace_handler: Operator.HTN.Trace.ConsoleHandler

## Use Cases

Operator is designed for:

* **Game AI** - NPC behaviors, enemy tactics, companion AI
* **Simulation** - Agent-based modeling, emergent behavior
* **Robotics** - Task planning, goal-directed behavior
* **Workflow Automation** - Complex multi-step processes
* **Chatbots** - Conversation flow management

## Resources

* [GameAIPro HTN Chapter](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf) - Theory background
* [Hex Documentation](https://hexdocs.pm/operator) - API reference
* [Examples](https://github.com/yourorg/operator/tree/main/examples) - Sample applications

# `version`

```elixir
@spec version() :: String.t()
```

Returns the Operator library version.

## Examples

    iex> Operator.version()
    "0.1.0"

---

*Consult [api-reference.md](api-reference.md) for complete listing*
