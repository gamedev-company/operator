defmodule JobWorker.Domain do
  @moduledoc """
  HTN domain for background job orchestration.

  Demonstrates using Operator for complex job workflows with:
  - Multi-step data pipelines
  - Dependency handling
  - Retry strategies with exponential backoff
  - Error recovery and compensation

  """

  use Operator.HTN.DSL

  alias Operator.HTN.Facts

  # ============================================================================
  # AXIOMS - Reusable query patterns
  # ============================================================================

  axiom :can_retry do
    fn facts, args ->
      max_retries = Keyword.get(args, :max, 3)
      current = Facts.get(facts, {:self, :retry_count}, 0)
      current < max_retries
    end
  end

  axiom :has_valid_input do
    fn facts, _args ->
      Facts.has?(facts, {:self, :input_data}) and
        Facts.get(facts, {:self, :input_valid}, false)
    end
  end

  axiom :dependencies_complete do
    fn facts, _args ->
      deps = Facts.get(facts, {:self, :dependencies}, [])
      completed = Facts.get(facts, {:world, :completed_jobs}, [])
      Enum.all?(deps, &(&1 in completed))
    end
  end

  # ============================================================================
  # GOALS
  # ============================================================================

  @doc "Main goal: process a data pipeline job"
  goal :process_data_pipeline do
    precond {:all, [
      fn facts -> Facts.has?(facts, {:self, :input_data}) end,
      {:axiom, :dependencies_complete}
    ]}

    decompose do
      task :validate_input
      task :transform_data
      task :enrich_data
      task :store_results
      task :notify_completion
    end

    metadata domain: :pipeline, priority: 5
  end

  @doc "Handle job failure with retry"
  goal :retry_failed_job do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :last_error}) != nil end,
      {:axiom, :can_retry, max: 5}
    ]}

    decompose do
      task :calculate_backoff
      task :wait_for_cooldown
      task :increment_retry_count
      task :clear_error_state
      task :retry_job
    end

    metadata domain: :recovery, priority: 8
  end

  @doc "Compensate for partial pipeline completion"
  goal :compensate_partial_run do
    precond fn facts ->
      Facts.get(facts, {:self, :partial_completion}, false) and
      Facts.has?(facts, {:self, :completed_steps})
    end

    decompose do
      task :identify_compensation_steps
      task :rollback_completed_steps
      task :cleanup_temp_data
      task :mark_job_failed
    end

    metadata domain: :recovery, priority: 9
  end

  @doc "Process batch of jobs"
  goal :process_job_batch do
    precond fn facts ->
      batch = Facts.get(facts, {:self, :job_batch}, [])
      length(batch) > 0
    end

    decompose fn facts ->
      batch = Facts.get(facts, {:self, :job_batch}, [])
      # Process jobs sequentially (in real system, might parallelize)
      Enum.flat_map(batch, fn job_id ->
        [{:process_single_job, [job_id]}]
      end)
    end

    metadata domain: :batch, priority: 4
  end

  # ============================================================================
  # TASKS
  # ============================================================================

  task :validate_input do
    decompose do
      task :check_schema
      task :sanitize_data
      task :validate_references
    end

    cost 1.0
  end

  task :transform_data do
    decompose fn facts ->
      transformations = Facts.get(facts, {:self, :transformations}, [:normalize])
      Enum.map(transformations, fn t -> {:apply_transform, [t]} end)
    end

    cost 2.0
  end

  task :enrich_data do
    decompose fn facts ->
      enrichment_sources = Facts.get(facts, {:self, :enrichment_sources}, [])
      Enum.map(enrichment_sources, fn source ->
        {:enrich_from, [source]}
      end)
    end

    cost 3.0
  end

  task :store_results do
    decompose fn facts ->
      storage_type = Facts.get(facts, {:self, :storage_type}, :database)

      case storage_type do
        :database -> [{:store_to_database, []}]
        :s3 -> [{:upload_to_s3, []}]
        :both -> [{:store_to_database, []}, {:upload_to_s3, []}]
      end
    end

    cost 2.0
  end

  task :calculate_backoff do
    decompose fn facts ->
      retry_count = Facts.get(facts, {:self, :retry_count}, 0)
      # Exponential backoff: 1s, 2s, 4s, 8s, 16s
      delay = :math.pow(2, retry_count) |> round()
      [{:set_backoff_delay, [delay]}]
    end

    cost 0.5
  end

  task :identify_compensation_steps do
    decompose fn facts ->
      completed_steps = Facts.get(facts, {:self, :completed_steps}, [])
      # Build compensation in reverse order
      completed_steps
      |> Enum.reverse()
      |> Enum.map(fn step -> {:mark_for_compensation, [step]} end)
    end

    cost 1.0
  end

  task :rollback_completed_steps do
    decompose fn facts ->
      to_compensate = Facts.get(facts, {:self, :compensation_queue}, [])
      Enum.map(to_compensate, fn step ->
        {:rollback_step, [step]}
      end)
    end

    cost 5.0
  end

  # ============================================================================
  # PRIMITIVES
  # ============================================================================

  primitive :check_schema do
    run fn actor, facts ->
      input = Facts.get(facts, {:self, :input_data})
      schema = Facts.get(facts, {:self, :expected_schema}, %{})
      IO.puts("[JobWorker] Checking schema...")

      # Simulated schema check
      if input != nil do
        {:ok, Map.put(actor, :schema_valid, true)}
      else
        {:error, :invalid_schema}
      end
    end
  end

  primitive :sanitize_data do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Sanitizing data...")
      {:ok, Map.put(actor, :data_sanitized, true)}
    end
  end

  primitive :validate_references do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Validating references...")
      {:ok, Map.put(actor, :refs_valid, true)}
    end
  end

  primitive :apply_transform do
    run fn actor, _facts ->
      transformation = Map.get(actor, :pending_args, [:unknown]) |> List.first()
      IO.puts("[JobWorker] Applying transformation: #{transformation}")
      {:ok, actor}
    end
  end

  primitive :enrich_from do
    run fn actor, _facts ->
      source = Map.get(actor, :pending_args, [:unknown]) |> List.first()
      IO.puts("[JobWorker] Enriching from: #{source}")
      {:ok, actor}
    end
  end

  primitive :store_to_database do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Storing to database...")
      result_id = System.unique_integer([:positive])
      {:ok, Map.put(actor, :db_result_id, result_id)}
    end
  end

  primitive :upload_to_s3 do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Uploading to S3...")
      s3_key = "results/#{System.unique_integer([:positive])}.json"
      {:ok, Map.put(actor, :s3_key, s3_key)}
    end
  end

  primitive :notify_completion do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Notifying completion...")
      {:ok, Map.put(actor, :notified, true)}
    end
  end

  primitive :set_backoff_delay do
    run fn actor, _facts ->
      delay = Map.get(actor, :pending_args, [1]) |> List.first()
      IO.puts("[JobWorker] Setting backoff delay: #{delay}s")
      {:ok, Map.put(actor, :backoff_delay, delay)}
    end
  end

  primitive :wait_for_cooldown do
    run fn actor, _facts ->
      delay = Map.get(actor, :backoff_delay, 1)
      IO.puts("[JobWorker] Waiting #{delay}s...")
      Process.sleep(delay * 100)  # Shortened for demo
      {:ok, actor}
    end
  end

  primitive :increment_retry_count do
    run fn actor, _facts ->
      count = Map.get(actor, :retry_count, 0)
      {:ok, Map.put(actor, :retry_count, count + 1)}
    end
  end

  primitive :clear_error_state do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Clearing error state...")
      {:ok, Map.delete(actor, :last_error)}
    end
  end

  primitive :retry_job do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Retrying job...")
      {:ok, Map.put(actor, :retrying, true)}
    end
  end

  primitive :process_single_job do
    run fn actor, _facts ->
      job_id = Map.get(actor, :pending_args, [:unknown]) |> List.first()
      IO.puts("[JobWorker] Processing job: #{job_id}")
      {:ok, actor}
    end
  end

  primitive :mark_for_compensation do
    run fn actor, _facts ->
      step = Map.get(actor, :pending_args, []) |> List.first()
      queue = Map.get(actor, :compensation_queue, [])
      {:ok, Map.put(actor, :compensation_queue, queue ++ [step])}
    end
  end

  primitive :rollback_step do
    run fn actor, _facts ->
      step = Map.get(actor, :pending_args, [:unknown]) |> List.first()
      IO.puts("[JobWorker] Rolling back step: #{step}")
      {:ok, actor}
    end
  end

  primitive :cleanup_temp_data do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Cleaning up temporary data...")
      {:ok, Map.put(actor, :cleaned_up, true)}
    end
  end

  primitive :mark_job_failed do
    run fn actor, _facts ->
      IO.puts("[JobWorker] Marking job as failed...")
      {:ok, Map.put(actor, :status, :failed)}
    end
  end
end
