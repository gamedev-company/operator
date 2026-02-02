defmodule Operator.HTN.DSL.Builder do
  @moduledoc """
  Builds runtime structures from DSL AST.

  This module transforms the compile-time AST captured by `Operator.HTN.DSL`
  macros into data structures that can be stored in the compiled module. It's
  the bridge between Elixir's macro system and Operator's runtime planning.

  ## Why This Module Exists

  When you write DSL code like:

      goal :attack do
        precond fn facts -> Facts.get(facts, {:self, :armed}) end
        decompose do
          task :aim
          task :fire
        end
      end

  The `goal` macro captures this as AST (Abstract Syntax Tree). But we can't
  just store raw AST - we need structured data that the planner can work with
  efficiently at runtime.

  This module handles that transformation:

  1. **Parses** the captured AST blocks
  2. **Extracts** preconditions, decompose functions, costs, metadata
  3. **Builds** `%Task{}` structs and goal maps
  4. **Preserves** function AST for runtime compilation

  ## AST Preservation

  Anonymous functions cannot be escaped with `Macro.escape/1` and stored
  directly in module attributes. Instead, we store them as quoted AST and
  compile them at runtime when needed (see `Operator.HTN.Executor`).

  This is why you'll see patterns like:

      %Task{
        preconditions: [{:fn, _, _clauses}],  # Stored as AST
        decompose: {:fn, _, _clauses}          # Stored as AST
      }

  ## Internal Module

  This module is considered internal to the DSL implementation. Users should
  interact with `Operator.HTN.DSL` macros rather than calling these functions
  directly.

  ## See Also

  * `Operator.HTN.DSL` - The public macro interface
  * `Operator.HTN.Task` - The runtime task structure
  * `Operator.HTN.Registry` - Where built structures are stored

  """

  alias Operator.HTN.Task

  @doc """
  Build a goal map from captured DSL AST.

  Transforms the AST captured by the `goal` macro into a map structure
  suitable for storage in the Registry.

  ## Parameters

  * `{name, block}` - Tuple of goal name atom and the captured block AST

  ## Returns

  A map with the following keys:

  * `:name` - Goal identifier atom
  * `:precond` - Precondition function AST, or `nil` if none specified
  * `:decompose` - List of `{task_name, args}` tuples from the decompose block
  * `:metadata` - Map of user-defined metadata

  ## Example Transformation

  Given this DSL input:

      goal :infiltrate do
        precond fn facts -> Facts.get(facts, {:self, :stealthy}) end
        decompose do
          task :sneak_to, :entrance
          task :pick_lock
        end
        metadata domain: :stealth, priority: 5
      end

  This function produces:

      %{
        name: :infiltrate,
        precond: {:fn, _, _},  # AST for the precondition
        decompose: [{:sneak_to, [:entrance]}, {:pick_lock, []}],
        metadata: %{domain: :stealth, priority: 5}
      }

  """
  @spec build_goal({atom(), any()}) :: map()
  def build_goal({name, block}) do
    {precond, decompose_tasks, metadata} = extract_goal_parts(block)

    %{
      name: name,
      precond: precond,
      decompose: decompose_tasks,
      metadata: metadata
    }
  end

  @doc """
  Build a Task struct from captured DSL AST.

  Transforms the AST captured by the `task` macro into a `%Task{}` struct.
  Tasks defined via DSL are always `:abstract` type (they decompose into
  other tasks or primitives).

  ## Parameters

  * `{name, args, block}` - Tuple containing:
    * `name` - Task identifier atom
    * `args` - List of argument variable names from the task definition
    * `block` - The captured block AST

  ## Returns

  A `%Task{}` struct with:

  * `:name` - Task identifier
  * `:type` - Always `:abstract` for DSL tasks
  * `:preconditions` - List of precondition function ASTs
  * `:decompose` - Either `{:static_tasks, list}` or function AST
  * `:cost` - Numeric cost value (default: 1.0)
  * `:metadata` - Map including `:args` and user metadata

  ## Decomposition Modes

  Tasks can decompose in two ways:

  **Static decomposition** (compile-time known sequence):

      task :prepare_attack do
        decompose do
          task :draw_weapon
          task :aim
        end
      end

  Stored as: `{:static_tasks, [{:draw_weapon, []}, {:aim, []}]}`

  **Dynamic decomposition** (runtime decision):

      task :move_to, destination do
        decompose fn facts ->
          current = Facts.get(facts, {:self, :position})
          [{:pathfind, [current, destination]}]
        end
      end

  Stored as: `{:fn, _, _}` (raw AST for runtime compilation)

  """
  @spec build_task({atom(), any(), any()}) :: Task.t()
  def build_task({name, args, block}) do
    {precond, decompose, cost, metadata} = extract_task_parts(block)

    %Task{
      name: name,
      type: :abstract,
      preconditions: precond,
      decompose: decompose,
      cost: cost,
      metadata: Map.merge(metadata, %{args: args})
    }
  end

  @doc """
  Build a primitive Task struct from captured DSL AST.

  Transforms the AST captured by the `primitive` macro into a `%Task{}`
  struct. Primitives are the executable leaf nodes of the HTN tree - they
  don't decompose further but instead have a `run` function.

  ## Parameters

  * `{name, args, block}` - Tuple containing:
    * `name` - Primitive identifier atom
    * `args` - List of argument variable names
    * `block` - The captured block AST

  ## Returns

  A `%Task{}` struct with:

  * `:name` - Primitive identifier
  * `:type` - Always `:primitive`
  * `:preconditions` - Empty list (primitives use runtime checks)
  * `:decompose` - `nil` (primitives don't decompose)
  * `:cost` - Fixed at 1.0
  * `:metadata` - Map containing:
    * `:args` - Argument names from definition
    * `:run` - The execution function AST
    * Any user-defined metadata

  ## Run Function

  The `run` function AST is stored in metadata and compiled at execution
  time by `Operator.HTN.Executor`. The function signature is:

      fn actor, facts -> {:ok, updated_actor} | {:error, reason} end

  ## Example

  Given this DSL input:

      primitive :fire_weapon, target do
        run fn actor, facts ->
          {:ok, %{actor | ammo: actor.ammo - 1}}
        end
        metadata animation: "shoot", sound: "gunfire.wav"
      end

  This function produces a Task with metadata containing both the run
  function AST and the user metadata.

  """
  @spec build_primitive({atom(), any(), any()}) :: Task.t()
  def build_primitive({name, args, block}) do
    {run_fun, metadata} = extract_primitive_parts(block)

    %Task{
      name: name,
      type: :primitive,
      preconditions: [],
      decompose: nil,
      cost: 1.0,
      metadata: Map.merge(metadata, %{args: args, run: run_fun})
    }
  end

  @doc """
  Build an axiom map from captured DSL AST.

  Transforms the AST captured by the `axiom` macro into a map structure.
  Axioms are reusable query patterns that can be referenced in preconditions.

  ## Parameters

  * `{name, query_fn_ast}` - Tuple of axiom name and the query function AST

  ## Returns

  A map with:

  * `:name` - Axiom identifier atom
  * `:query_fn` - The query function AST

  ## Axiom Functions

  Axiom functions have the signature:

      fn facts, args -> boolean end

  Where `args` is a keyword list of arguments passed when the axiom is
  invoked in a precondition.

  ## Example

  Given this DSL input:

      axiom :enemy_in_range do
        fn facts, args ->
          max_range = Keyword.get(args, :range, 10)
          enemy_dist = Facts.get(facts, {:world, :enemy_distance}, 999)
          enemy_dist <= max_range
        end
      end

  Used in preconditions as:

      precond {:axiom, :enemy_in_range, range: 5}

  """
  @spec build_axiom({atom(), any()}) :: map()
  def build_axiom({name, query_fn_ast}) do
    %{
      name: name,
      query_fn: query_fn_ast
    }
  end

  # Private helpers

  defp extract_goal_parts(block) do
    statements =
      case block do
        {:__block__, _, stmts} -> stmts
        single -> [single]
      end

    {precond_list, decompose, _cost, metadata} = extract_from_statements(statements)
    {combine_preconds(precond_list), decompose, metadata}
  end

  defp extract_task_parts(block) do
    case block do
      {:__block__, _, statements} ->
        extract_from_statements(statements)

      single ->
        extract_from_statements([single])
    end
  end

  defp extract_primitive_parts(block) do
    case block do
      {:__block__, _, statements} ->
        extract_run_from_statements(statements)

      single ->
        extract_run_from_statements([single])
    end
  end

  defp extract_from_statements(statements) do
    Enum.reduce(statements, {[], nil, 1.0, %{}}, fn statement,
                                                    {precond_acc, decompose_acc, cost_acc,
                                                     metadata_acc} ->
      case statement do
        {:precond, _, [fun]} ->
          {[fun | precond_acc], decompose_acc, cost_acc, metadata_acc}

        # Order matters: check for do block patterns first (more specific)
        {:decompose, _, [[{:do, block}]]} ->
          # Format with keyword list: {:decompose, _, [[{:do, block}]]}
          tasks = extract_tasks_from_block(block)
          {precond_acc, {:static_tasks, tasks}, cost_acc, metadata_acc}

        {:decompose, _, [{:do, block}]} ->
          # Format: {:decompose, _, [{:do, block}]}
          tasks = extract_tasks_from_block(block)
          {precond_acc, {:static_tasks, tasks}, cost_acc, metadata_acc}

        {:decompose, _, [{:fn, _, _} = fun]} ->
          # Store function AST for later evaluation
          {precond_acc, fun, cost_acc, metadata_acc}

        {:cost, _, [value]} ->
          {precond_acc, decompose_acc, value, metadata_acc}

        {:metadata, _, [metadata_value]} ->
          metadata_map = metadata_to_map(metadata_value)
          {precond_acc, decompose_acc, cost_acc, Map.merge(metadata_acc, metadata_map)}

        _other ->
          {precond_acc, decompose_acc, cost_acc, metadata_acc}
      end
    end)
    |> then(fn {precond, decompose, cost, metadata} ->
      {Enum.reverse(precond), decompose, cost, metadata}
    end)
  end

  defp extract_tasks_from_block(block) do
    statements =
      case block do
        {:__block__, _, stmts} -> stmts
        single -> [single]
      end

    Enum.flat_map(statements, fn
      {:task, _, [name | args]} ->
        [{name, args}]

      _ ->
        []
    end)
  end

  defp combine_preconds([]), do: nil
  defp combine_preconds(funs), do: funs

  defp extract_run_from_statements(statements) do
    Enum.reduce(statements, {nil, %{}}, fn statement, {run_acc, metadata_acc} ->
      case statement do
        {:run, _, [fun]} ->
          {fun, metadata_acc}

        {:metadata, _, [metadata_value]} ->
          metadata_map = metadata_to_map(metadata_value)
          {run_acc, Map.merge(metadata_acc, metadata_map)}

        _ ->
          {run_acc, metadata_acc}
      end
    end)
  end

  defp metadata_to_map(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, val} ->
      {key, normalize_metadata_value(val)}
    end)
  end

  defp metadata_to_map(value) when is_list(value) do
    Enum.into(value, %{}, fn {key, val} ->
      {key, normalize_metadata_value(val)}
    end)
  rescue
    _ ->
      %{}
  end

  defp metadata_to_map(value) do
    case normalize_metadata_value(value) do
      %{} = map -> map
      _ -> %{}
    end
  end

  defp normalize_metadata_value({:%{}, _, _} = quoted), do: safe_eval_literal(quoted)

  defp normalize_metadata_value(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, val} ->
      {key, normalize_metadata_value(val)}
    end)
  end

  defp normalize_metadata_value(value) when is_list(value) do
    Enum.map(value, &normalize_metadata_value/1)
  end

  defp normalize_metadata_value(value), do: value

  defp safe_eval_literal(quoted) do
    {result, _bindings} = Code.eval_quoted(quoted)
    result
  rescue
    _ -> quoted
  end
end
