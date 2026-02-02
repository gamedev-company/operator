defmodule JobWorker.Example do
  @moduledoc """
  Runnable examples demonstrating the job worker system.

  ## Running

      iex> JobWorker.Example.run()

  Or run individual scenarios:

      iex> JobWorker.Example.pipeline_scenario()
      iex> JobWorker.Example.retry_scenario()
      iex> JobWorker.Example.batch_scenario()

  """

  alias Operator.HTN.{Facts, Planner, Registry}
  alias JobWorker.Domain

  @doc """
  Run a complete demonstration of the job worker system.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         JOB WORKER HTN DEMONSTRATION")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Ensure domain is registered
    Registry.register(Domain)

    # Run each scenario
    pipeline_scenario()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    retry_scenario()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    batch_scenario()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    compensation_scenario()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         DEMONSTRATION COMPLETE")
    IO.puts(String.duplicate("=", 60) <> "\n")

    :ok
  end

  @doc """
  Demonstrate a basic data pipeline.

  The worker processes input data through validation,
  transformation, enrichment, storage, and notification steps.
  """
  def pipeline_scenario do
    IO.puts("📊 SCENARIO: Data Pipeline Processing")
    IO.puts("   Processing customer data through ETL pipeline\n")

    facts = Facts.from_perception(%{
      self: %{
        job_id: "job_12345",
        input_data: %{customer_id: 1001, name: "Acme Corp", region: "NA"},
        transformations: [:normalize, :dedupe, :format],
        enrichment_sources: [:crm_api, :analytics_db],
        storage_type: :both
      },
      world: %{
        completed_jobs: ["job_12340", "job_12341"]
      }
    })

    traits = %{archetype: :worker}

    IO.puts("   Job ID: #{Facts.get(facts, {:self, :job_id})}")
    IO.puts("   Transformations: #{Facts.get(facts, {:self, :transformations}) |> inspect()}")
    IO.puts("   Enrichment sources: #{Facts.get(facts, {:self, :enrichment_sources}) |> length()}")
    IO.puts("   Storage: #{Facts.get(facts, {:self, :storage_type})}\n")

    case Planner.run(:process_data_pipeline, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Pipeline steps (#{length(plan.tasks)}):")
        Enum.each(plan.tasks, fn {name, args} ->
          case args do
            [] -> IO.puts("     • #{name}")
            _ -> IO.puts("     • #{name}(#{inspect(args)})")
          end
        end)
        IO.puts("\n   ✓ Pipeline ready for execution")

      {:error, reason} ->
        IO.puts("   ✗ Pipeline planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate retry behavior after failure.

  The worker handles a failed job with exponential backoff
  and automatic retry.
  """
  def retry_scenario do
    IO.puts("🔁 SCENARIO: Job Retry with Backoff")
    IO.puts("   Job failed, initiating retry sequence\n")

    facts = Facts.from_perception(%{
      self: %{
        job_id: "job_12346",
        last_error: :connection_timeout,
        retry_count: 2
      },
      world: %{}
    })

    traits = %{archetype: :worker, traits: [:resilient]}

    backoff = :math.pow(2, 2) |> round()
    IO.puts("   Job ID: #{Facts.get(facts, {:self, :job_id})}")
    IO.puts("   Last error: #{Facts.get(facts, {:self, :last_error})}")
    IO.puts("   Retry count: #{Facts.get(facts, {:self, :retry_count})}")
    IO.puts("   Expected backoff: #{backoff}s\n")

    case Planner.run(:retry_failed_job, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Recovery steps:")
        Enum.each(plan.tasks, fn {name, args} ->
          case args do
            [] -> IO.puts("     • #{name}")
            [delay] when is_integer(delay) -> IO.puts("     • #{name}(#{delay}s)")
            _ -> IO.puts("     • #{name}")
          end
        end)
        IO.puts("\n   ✓ Retry plan ready")

      {:error, reason} ->
        IO.puts("   ✗ Retry planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate batch job processing.

  The worker processes multiple jobs in a batch.
  """
  def batch_scenario do
    IO.puts("📦 SCENARIO: Batch Job Processing")
    IO.puts("   Processing batch of 3 jobs\n")

    facts = Facts.from_perception(%{
      self: %{
        batch_id: "batch_001",
        job_batch: ["job_a", "job_b", "job_c"]
      },
      world: %{}
    })

    traits = %{}

    batch = Facts.get(facts, {:self, :job_batch})
    IO.puts("   Batch ID: #{Facts.get(facts, {:self, :batch_id})}")
    IO.puts("   Jobs in batch: #{length(batch)}")
    IO.puts("   Job IDs: #{inspect(batch)}\n")

    case Planner.run(:process_job_batch, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Batch execution order:")
        Enum.each(plan.tasks, fn {name, args} ->
          [job_id] = args
          IO.puts("     • #{name}(#{job_id})")
        end)
        IO.puts("\n   ✓ Batch plan ready")

      {:error, reason} ->
        IO.puts("   ✗ Batch planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate compensation for partial completion.

  When a job fails partway through, the worker compensates
  for completed steps by rolling them back.
  """
  def compensation_scenario do
    IO.puts("⏪ SCENARIO: Partial Completion Compensation")
    IO.puts("   Job failed partway, rolling back\n")

    facts = Facts.from_perception(%{
      self: %{
        job_id: "job_12347",
        partial_completion: true,
        completed_steps: [:validate, :transform, :enrich],
        last_error: :storage_failure
      },
      world: %{}
    })

    traits = %{}

    completed = Facts.get(facts, {:self, :completed_steps})
    IO.puts("   Job ID: #{Facts.get(facts, {:self, :job_id})}")
    IO.puts("   Completed steps: #{inspect(completed)}")
    IO.puts("   Failed at: storage")
    IO.puts("   Steps to compensate: #{length(completed)}\n")

    case Planner.run(:compensate_partial_run, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Compensation steps:")
        Enum.each(plan.tasks, fn {name, args} ->
          case args do
            [] -> IO.puts("     • #{name}")
            [step] -> IO.puts("     • #{name}(#{step})")
            _ -> IO.puts("     • #{name}")
          end
        end)
        IO.puts("\n   ✓ Compensation plan ready")

      {:error, reason} ->
        IO.puts("   ✗ Compensation planning failed: #{inspect(reason)}")
    end
  end
end
