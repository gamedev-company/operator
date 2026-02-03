# `Operator.HTN.Storage`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/storage.ex#L1)

Default ETS-based plan storage implementation.

This module provides the default storage backend for HTN plans.
Plans are stored in an ETS table and persist for the lifetime of
the application.

## Usage

This module is used automatically when no custom storage module
is configured:

    # Automatic via Planner
    {:ok, plan} = Operator.HTN.Planner.run(:goal, facts, traits)

    # Direct access
    Operator.HTN.Storage.persist_plan(entity_id, plan)
    plan = Operator.HTN.Storage.fetch_plan(entity_id)

## Configuration

To use a different storage backend:

    config :operator,
      storage_module: MyApp.CustomStorage

# `clear_all`

```elixir
@spec clear_all() :: :ok
```

Clear all stored plans.

Useful for testing.

# `init`

```elixir
@spec init() :: :ok
```

Initialize the storage table.

Called automatically by the Operator application, but can also be
called manually in tests.

# `stats`

```elixir
@spec stats() :: %{total_plans: non_neg_integer(), validity: map()}
```

Get storage statistics.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
