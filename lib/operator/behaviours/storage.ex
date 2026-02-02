defmodule Operator.Storage do
  @moduledoc """
  Behaviour for plan persistence.

  Implement this behaviour to customize how HTN plans are stored and
  retrieved. The default implementation uses ETS.

  ## Configuration

      config :operator,
        storage_module: MyApp.PlanStorage

  ## Example Implementation

      defmodule MyApp.PlanStorage do
        @behaviour Operator.Storage

        @impl true
        def persist_plan(entity_id, plan) do
          MyApp.Cache.put({:plan, entity_id}, plan)
          :ok
        end

        @impl true
        def fetch_plan(entity_id) do
          MyApp.Cache.get({:plan, entity_id})
        end

        @impl true
        def clear_plan(entity_id) do
          MyApp.Cache.delete({:plan, entity_id})
          :ok
        end

        @impl true
        def list_plans do
          MyApp.Cache.list_by_prefix(:plan)
        end
      end

  ## Default ETS Implementation

  If no storage module is configured, Operator uses `Operator.HTN.Storage`
  which provides ETS-based storage.
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
