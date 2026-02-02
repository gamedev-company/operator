defmodule Operator.Storage do
  @moduledoc """
  Behaviour for plan persistence across ticks.

  The Storage behaviour lets you customize how HTN plans are cached between
  game ticks. This is essential for games where plan execution spans multiple
  frames - you need somewhere to store the "current plan" for each NPC.

  ## Why Plan Storage?

  HTN plans often take multiple ticks to execute:

  1. Tick 1: Generate plan `[{:move_to, [:door]}, {:open_door, []}, {:enter, []}]`
  2. Tick 1: Execute `:move_to` - NPC starts walking
  3. Tick 2-10: NPC still walking (plan stored, waiting)
  4. Tick 11: NPC arrives, execute `:open_door`
  5. Tick 12: Execute `:enter`
  6. Tick 12: Plan complete, clear storage

  Without storage, you'd need to track plans yourself or regenerate them
  every tick (expensive and inconsistent).

  ## Configuration

      config :operator,
        storage_module: MyApp.PlanStorage

  ## Example Implementations

  ### Redis (for distributed games)

      defmodule MyApp.RedisPlanStorage do
        @behaviour Operator.Storage

        @impl true
        def persist_plan(entity_id, plan) do
          Redix.command!(:redix, ["SET", "plan:\#{entity_id}", :erlang.term_to_binary(plan)])
          :ok
        end

        @impl true
        def fetch_plan(entity_id) do
          case Redix.command!(:redix, ["GET", "plan:\#{entity_id}"]) do
            nil -> nil
            binary -> :erlang.binary_to_term(binary)
          end
        end

        @impl true
        def clear_plan(entity_id) do
          Redix.command!(:redix, ["DEL", "plan:\#{entity_id}"])
          :ok
        end

        @impl true
        def list_plans do
          keys = Redix.command!(:redix, ["KEYS", "plan:*"])
          Enum.map(keys, fn key ->
            entity_id = String.replace_prefix(key, "plan:", "")
            plan = fetch_plan(entity_id)
            {entity_id, plan}
          end)
        end
      end

  ### In-Memory with TTL (for single-node games)

      defmodule MyApp.CachexPlanStorage do
        @behaviour Operator.Storage

        @impl true
        def persist_plan(entity_id, plan) do
          Cachex.put(:plans, entity_id, plan, ttl: :timer.minutes(5))
          :ok
        end

        @impl true
        def fetch_plan(entity_id) do
          case Cachex.get(:plans, entity_id) do
            {:ok, plan} -> plan
            _ -> nil
          end
        end

        # ... etc
      end

  ## Default Implementation

  If no storage module is configured, Operator uses `Operator.HTN.Storage`,
  which provides simple ETS-based storage suitable for single-node games.

  ## See Also

  * `Operator.HTN.Storage` - Default ETS implementation
  * `Operator.HTN.Plan` - The plan structure being stored
  * `Operator.HTN.Executor` - Uses storage during plan execution

  """

  alias Operator.HTN.Plan

  @doc """
  Persist a plan for an entity.

  Called after successful plan generation to cache the plan for later
  retrieval during execution.
  """
  @callback persist_plan(entity_id :: term(), plan :: Plan.t()) :: :ok

  @doc """
  Fetch a plan for an entity.

  Returns the cached plan or `nil` if no plan exists.
  """
  @callback fetch_plan(entity_id :: term()) :: Plan.t() | nil

  @doc """
  Clear a plan for an entity.

  Called when a plan is completed, invalidated, or needs to be replaced.
  """
  @callback clear_plan(entity_id :: term()) :: :ok

  @doc """
  List all stored plans.

  Returns a list of `{entity_id, plan}` tuples.
  """
  @callback list_plans() :: [{term(), Plan.t()}]

  @doc """
  Get the configured storage module or the default ETS storage.
  """
  @spec get_module() :: module()
  def get_module do
    Application.get_env(:operator, :storage_module, Operator.HTN.Storage)
  end

  @doc """
  Persist a plan using the configured storage module.
  """
  @spec persist_plan(term(), Plan.t()) :: :ok
  def persist_plan(entity_id, plan) do
    get_module().persist_plan(entity_id, plan)
  end

  @doc """
  Fetch a plan using the configured storage module.
  """
  @spec fetch_plan(term()) :: Plan.t() | nil
  def fetch_plan(entity_id) do
    get_module().fetch_plan(entity_id)
  end

  @doc """
  Clear a plan using the configured storage module.
  """
  @spec clear_plan(term()) :: :ok
  def clear_plan(entity_id) do
    get_module().clear_plan(entity_id)
  end

  @doc """
  List all plans using the configured storage module.
  """
  @spec list_plans() :: [{term(), Plan.t()}]
  def list_plans do
    get_module().list_plans()
  end
end
