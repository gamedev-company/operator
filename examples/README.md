# Operator Examples

This directory contains example applications demonstrating various use cases
for the Operator library.

## Examples Overview

| Example | Description | Key Concepts |
|---------|-------------|--------------|
| [game_npc](./game_npc/) | Game NPC AI with patrol, combat, and survival behaviors | Goals, Tasks, Primitives, Effects |
| [web_scraper](./web_scraper/) | Intelligent web scraping with retry and fallback strategies | Dynamic Decomposition, Error Recovery |
| [job_worker](./job_worker/) | Background job orchestration with dependencies | Goal Selection, Plan Persistence |
| [chatbot](./chatbot/) | Conversation flow management for chatbots | Axioms, Preconditions, State Tracking |
| [simulation](./simulation/) | Agent-based simulation with Director events | Director, Storytellers, Multi-agent |

## Running Examples

Each example is a self-contained Elixir module that can be run in IEx:

```bash
cd examples/game_npc
iex -S mix

# Run the example
GameNPC.Example.run()
```

## Example Structure

Each example includes:

- `mix.exs` - Project configuration
- `lib/` - Source code
  - `domain.ex` - HTN goal/task definitions
  - `executor.ex` - Plan execution logic
  - `example.ex` - Runnable demonstration
- `README.md` - Detailed explanation

## Key Patterns

### 1. Defining Behaviors (All Examples)

```elixir
defmodule MyApp.Behaviors do
  use Operator.HTN.DSL

  goal :accomplish_task do
    precond fn facts -> can_attempt?(facts) end

    decompose do
      task :prepare
      task :execute
      task :cleanup
    end
  end
end
```

### 2. Generating Plans

```elixir
facts = Operator.HTN.Facts.from_perception(current_state)
traits = %{archetype: :worker}

case Operator.HTN.Planner.run(:accomplish_task, facts, traits) do
  {:ok, plan} -> execute(plan)
  {:error, reason} -> handle_error(reason)
end
```

### 3. Using the Director

```elixir
{:ok, _pid} = Operator.Director.start_link(
  storyteller: MyApp.MyStoryteller,
  on_event: fn event -> handle_event(event) end
)

# On each tick
Operator.Director.tick(world_state)
```

## Adding New Examples

1. Create a new directory under `examples/`
2. Add a `mix.exs` with `:ex_operator` as a dependency
3. Define your domain in `lib/domain.ex`
4. Create an executable example in `lib/example.ex`
5. Add a `README.md` explaining the example
6. Update this file's overview table
