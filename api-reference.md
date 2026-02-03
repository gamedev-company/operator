# Operator v0.1.0 - API Reference

## Modules

- [Operator](Operator.md): Operator - A pluggable AI planning and narrative orchestration library.
- [Operator.Director](Operator.Director.md): Narrative orchestration system for dynamic event generation.
- [Operator.Director.NullStoryteller](Operator.Director.NullStoryteller.md): A storyteller that never generates events.
- [Operator.HTN.Axiom](Operator.HTN.Axiom.md): Reusable query patterns for HTN preconditions.
- [Operator.HTN.DSL](Operator.HTN.DSL.md): Domain-specific language for defining HTN goals, tasks, and primitives.
- [Operator.HTN.DSL.Builder](Operator.HTN.DSL.Builder.md): Builds runtime structures from DSL AST.
- [Operator.HTN.Effect](Operator.HTN.Effect.md): Effects represent world state changes that result from task execution.
- [Operator.HTN.Engine](Operator.HTN.Engine.md): HTN engine for goal expansion, precondition evaluation, and plan generation.
- [Operator.HTN.Executor](Operator.HTN.Executor.md): Executes HTN plans and primitive tasks.
- [Operator.HTN.Facts](Operator.HTN.Facts.md): World state representation for HTN planning.
- [Operator.HTN.GoalSelector](Operator.HTN.GoalSelector.md): Automatic goal selection for agents based on world state and personality.
- [Operator.HTN.Loop](Operator.HTN.Loop.md): Convenience helpers for integrating HTN planning into tick-based loops.
- [Operator.HTN.Plan](Operator.HTN.Plan.md): Represents a generated plan from HTN expansion.
- [Operator.HTN.Planner](Operator.HTN.Planner.md): High-level API for HTN plan generation.
- [Operator.HTN.Precondition](Operator.HTN.Precondition.md): Logical operators for HTN preconditions.
- [Operator.HTN.Registry](Operator.HTN.Registry.md): Central storage for HTN goals, tasks, primitives, and axioms.
- [Operator.HTN.Storage](Operator.HTN.Storage.md): Default ETS-based plan storage implementation.
- [Operator.HTN.Task](Operator.HTN.Task.md): A task in the HTN hierarchy.
- [Operator.HTN.TestHelpers](Operator.HTN.TestHelpers.md): Test utilities for working with Operator's HTN system.
- [Operator.HTN.Trace](Operator.HTN.Trace.md): Detailed tracing for HTN planning operations.
- [Operator.HTN.Trace.ConsoleHandler](Operator.HTN.Trace.ConsoleHandler.md): Console-based trace handler for debugging HTN planning.
- [Operator.HTN.Trace.Handler](Operator.HTN.Trace.Handler.md): Behaviour for HTN trace handlers.
- [Operator.Rationalization](Operator.Rationalization.md): Behaviour for narrative annotation of plans and events.
- [Operator.Storage](Operator.Storage.md): Behaviour for plan persistence across ticks.
- [Operator.Storyteller](Operator.Storyteller.md): Behaviour for narrative event generators.
- [Operator.Telemetry](Operator.Telemetry.md): Behaviour for telemetry and metrics integration.
- [Operator.Traits](Operator.Traits.md): Behaviour for agent personality and genome integration.

