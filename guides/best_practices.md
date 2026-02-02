# Best Practices

This is the aggressive, practical guidance for using Operator in real systems.

## Core HTN Practices

- Keep goals small and specific. Large, vague goals lead to unstable plans.
- Prefer shallow decompositions. Deep trees are harder to debug and tune.
- Keep `precond` functions pure and fast. Do not hit IO or external state.
- Use `Facts` as a snapshot, not a database. Keep it compact.
- Use `cost` to shape behavior. If two paths are valid, costs decide the plan.
- Keep primitives deterministic. If you need randomness, isolate it upstream.

## Facts Discipline

- Build facts in one place. Do not scatter facts creation across codepaths.
- Use consistent keys. Changing keys breaks preconditions silently.
- Treat facts as immutable. Always use the returned struct after updates.

## Planning Discipline

- Use `Planner.needs_replan?/2` before throwing away a plan.
- Avoid planning every tick unless the world is highly volatile.
- Cache plans for multi-tick actions; replan only when facts change.

## Task And Goal Design

- Put preconditions on the highest level that makes sense.
- Keep goal preconditions strict enough to avoid garbage plans.
- Prefer small primitives that do one thing well.
- Use metadata for analytics and tuning (`priority`, `domain`, etc.).

## Effects

- Use effects to allow multi-step reasoning.
- Use `:plan_only` for optimistic assumptions you do not want executed.
- Use `:permanent` only for irreversible world changes.

## Director + Storyteller

- Keep storytellers deterministic. You want reproducible event streams in tests.
- Use Director events as facts, not direct commands. Let HTN decide response.
- Control global pacing in the Director; keep per-agent intent in HTN.

## Debugging Strategy

- Turn on tracing early during behavior tuning.
- Inspect plans directly. The plan is just data.
- Add metadata to plans to track why they were selected.

## Testing Strategy

- Always `async: false` for tests that touch the Registry.
- Reset the Registry per test.
- Use `with_registry/2` for isolation.
- Write at least one integration test that runs planning + execution end-to-end.

## Scaling Strategy

- Precompute expensive facts outside the planner.
- Keep planning on a budget (limit ticks/agents per frame).
- Use per-entity plan storage to avoid recomputation.

## Common Failure Modes

- Preconditions referencing keys that never exist in facts.
- Aliases inside `precond` or `decompose` (will fail at runtime).
- Planning every tick with no caching.
- Effects missing for prerequisites (planner cannot reason about state changes).

## Anti-Patterns Guide

See `guides/anti_patterns.md` for real examples and fixes.
