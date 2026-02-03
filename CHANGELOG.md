# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-02-03

### Added

#### HTN Planning System
- `Operator.HTN.DSL` - Declarative macro-based DSL for defining goals, tasks, and primitives
- `Operator.HTN.Planner` - High-level planning API with `plan/3`, `plan_and_execute/3`, and `execute/2`
- `Operator.HTN.Engine` - Core plan generation algorithm with backtracking support
- `Operator.HTN.Facts` - World state representation with nested path access
- `Operator.HTN.Plan` - Generated plan structure with step tracking and execution state
- `Operator.HTN.Task` - Task definition struct with preconditions and effects
- `Operator.HTN.Effect` - World state modifications (set, delete, increment, decrement, append, remove)
- `Operator.HTN.Precondition` - Logical operators (AND, OR, NOT) for complex conditions
- `Operator.HTN.Axiom` - Reusable query patterns for common precondition logic
- `Operator.HTN.GoalSelector` - Automatic goal selection with trait-based weighting
- `Operator.HTN.Registry` - ETS-based goal and task registration
- `Operator.HTN.Storage` - Default ETS-based plan persistence
- `Operator.HTN.Trace` - Debug tracing infrastructure with pluggable handlers

#### Director System
- `Operator.Director` - GenServer for tick-based event orchestration
- `Operator.Director.Storyteller` - Behaviour for implementing narrative event generators
- `Operator.Director.NullStoryteller` - Default no-op storyteller implementation

#### Integration Behaviours
- `Operator.Telemetry` - Callbacks for metrics and observability integration
- `Operator.Traits` - Agent personality/genome integration for goal weighting
- `Operator.Storage` - Pluggable plan persistence backend behaviour
- `Operator.Rationalization` - Plan annotation and event rationalization callbacks

#### Documentation & Examples
- Comprehensive README with quick start guide
- Detailed moduledocs for all public modules
- Five complete example applications:
  - `game_npc` - NPC AI with patrol, combat, and survival behaviors
  - `web_scraper` - Intelligent web scraping with retry/fallback
  - `job_worker` - Background job orchestration with dependencies
  - `chatbot` - Conversation flow management
  - `simulation` - Agent-based simulation with Director events

[Unreleased]: https://github.com/gamedev-company/operator/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gamedev-company/operator/releases/tag/v0.1.0
