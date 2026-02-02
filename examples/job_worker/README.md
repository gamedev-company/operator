# Job Worker Example

Using Operator for background job orchestration with complex workflows,
dependencies, and error recovery.

## Use Case

A background job system that:
- Processes multi-step data pipelines
- Handles job dependencies
- Implements retry and recovery strategies
- Tracks job state and progress

## Key Concepts

### Goals as Job Types

```elixir
goal :process_data_pipeline do
  precond fn facts ->
    Facts.has?(facts, {:self, :input_data})
  end

  decompose do
    task :validate_input
    task :transform_data
    task :enrich_data
    task :store_results
    task :notify_completion
  end
end
```

### Tasks as Pipeline Stages

```elixir
task :enrich_data do
  decompose fn facts ->
    enrichment_sources = Facts.get(facts, {:self, :enrichment_sources}, [])

    # Build task list based on required enrichments
    Enum.map(enrichment_sources, fn source ->
      {:enrich_from, [source]}
    end)
  end
end
```

### Primitives as Job Operations

```elixir
primitive :store_results do
  run fn actor, _facts ->
    data = actor.processed_data

    case Database.insert(data) do
      {:ok, id} -> {:ok, Map.put(actor, :result_id, id)}
      {:error, reason} -> {:error, {:db_error, reason}}
    end
  end
end
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 Job Queue                            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐             │
│  │  Job 1  │  │  Job 2  │  │  Job 3  │  ...        │
│  └────┬────┘  └────┬────┘  └────┬────┘             │
│       │            │            │                   │
└───────┼────────────┼────────────┼───────────────────┘
        │            │            │
        ▼            ▼            ▼
┌───────────────────────────────────────────────────┐
│              Worker Pool                           │
│  ┌─────────────────────────────────────────────┐  │
│  │  Worker 1           Worker 2        Worker N │  │
│  │  ┌─────────────┐   ┌─────────────┐          │  │
│  │  │ Goal:       │   │ Goal:       │          │  │
│  │  │ process_    │   │ enrich_     │          │  │
│  │  │ pipeline    │   │ and_store   │          │  │
│  │  └─────────────┘   └─────────────┘          │  │
│  └─────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

## Running

```bash
cd examples/job_worker
mix deps.get
iex -S mix

JobWorker.Example.run()
```
