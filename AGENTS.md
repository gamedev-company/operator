# AGENTS

## Project Overview
Operator is an Elixir library for HTN planning and a narrative Director system.

## Repo Layout
- `lib/operator/htn/` HTN core (planner, executor, facts, registry, DSL).
- `lib/operator/director/` Director orchestration.
- `lib/operator/behaviours/` shared behaviours and protocols.
- `guides/` ExDoc guides (Getting Started, How-To, Cheatsheet).
- `examples/` sample implementations.
- `test/htn/` HTN unit tests.
- `test/director/` Director unit tests.
- `doc/` generated ExDoc output (do not edit by hand).

## Build, Test, Docs
- `mix test` runs the full test suite.
- `mix test test/htn/facts_test.exs` runs a focused test file.
- `mix format` formats the codebase.
- `mix docs` regenerates ExDoc output into `doc/`.

## Doc + Doctest Guidance
- Prefer `iex>` examples in module docs and add `doctest ModuleName` in tests.
- Keep the version string in `mix.exs` and `lib/operator.ex` in sync.

## HTN DSL Gotchas
- `precond` and `decompose` functions execute at runtime; use fully qualified
  module names inside them (no module-level aliases).
- The HTN registry is global state; tests that touch it should be `async: false`
  and use `Operator.HTN.TestHelpers` to reset or isolate the registry.
