defmodule Operator.HTN.Storage do
  @moduledoc """
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

  """

  @behaviour Operator.Storage

  @table_name :operator_htn_plans

  @doc """
  Initialize the storage table.

  Called automatically by the Operator application, but can also be
  called manually in tests.
  """
  @spec init() :: :ok
  def init do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _ref ->
        :ok
    end
  end

  @impl Operator.Storage
  def persist_plan(entity_id, plan) do
    ensure_table()
    :ets.insert(@table_name, {entity_id, plan})
    :ok
  end

  @impl Operator.Storage
  def fetch_plan(entity_id) do
    ensure_table()

    case :ets.lookup(@table_name, entity_id) do
      [{^entity_id, plan}] -> plan
      [] -> nil
    end
  end

  @impl Operator.Storage
  def clear_plan(entity_id) do
    ensure_table()
    :ets.delete(@table_name, entity_id)
    :ok
  end

  @impl Operator.Storage
  def list_plans do
    ensure_table()
    :ets.tab2list(@table_name)
  end

  @doc """
  Clear all stored plans.

  Useful for testing.
  """
  @spec clear_all() :: :ok
  def clear_all do
    ensure_table()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Get storage statistics.
  """
  @spec stats() :: %{total_plans: non_neg_integer(), validity: map()}
  def stats do
    ensure_table()
    plans = list_plans()

    validity_counts =
      plans
      |> Enum.map(fn {_id, plan} -> plan.validity end)
      |> Enum.frequencies()

    %{
      total_plans: length(plans),
      validity: validity_counts
    }
  end

  defp ensure_table do
    case :ets.whereis(@table_name) do
      :undefined -> init()
      _ref -> :ok
    end
  end
end
