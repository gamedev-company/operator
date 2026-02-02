# Architecture

This guide explains the data flow so you can reason about performance and
integration points.

## High-Level Flow

1. Behavior modules define goals, tasks, primitives, axioms.
1. The Registry collects those definitions.
1. Facts capture the world state for an agent.
1. The Planner expands a goal into a plan.
1. The Executor steps through the plan.
1. Effects mutate facts during planning and execution.

## Data Model

Facts are a plain struct with three maps:

- `:self` for agent state.
- `:world` for environment state.
- `:social` for relationships and factions.

Plans are immutable structs:

- `:goal` the selected objective.
- `:tasks` the remaining primitive tasks.
- `:validity` active, invalid, completed.
- `:metadata` for trace and instrumentation.

## Registry Model

The Registry stores definitions in `persistent_term` for fast reads.

- Reads are O(1).
- Writes are expensive and should be rare.

## Runtime vs Compile Time

The DSL is compiled into structs, but `precond` and `decompose` run at runtime.
This is why aliases do not work inside them.

## Replanning Strategy

Use this approach for predictable behavior:

1. Keep the current plan if it still applies.
1. Call `Planner.needs_replan?/2` before discarding it.
1. Replan only when facts change materially.

## Scaling Tips

- Keep facts small and focused.
- Avoid heavy work inside `precond` and `decompose`.
- Use tracing only when needed.
- Cache expensive facts outside the planner.
