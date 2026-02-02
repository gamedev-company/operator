defmodule Operator.HTN.DSL.Builder do
  @moduledoc """
  Builds runtime structures from DSL AST.

  This module transforms the compile-time AST captured by `Operator.HTN.DSL`
  macros into data structures that can be stored in the compiled module.

  Note: Anonymous functions cannot be escaped with Macro.escape/1, so we store
  decompose blocks as static task lists rather than as functions. The functions
  are created at runtime when needed.
  """

  alias Operator.HTN.Task

  @doc """
  Build a goal from AST.

  Goals have:
  - `name` - Goal identifier
  - `precond` - Optional precondition (stored as AST)
  - `decompose` - Task list for decomposition (stored as data)
  - `metadata` - Optional metadata map
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
  Build a task from AST.

  Tasks have:
  - `name` - Task identifier
  - `type` - Always `:abstract` for DSL-defined tasks
  - `preconditions` - List of preconditions (stored as AST)
  - `decompose` - Task list or function AST for decomposition
  - `cost` - Static or dynamic cost
  - `metadata` - Includes args and other metadata
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
  Build a primitive from AST.

  Primitives have:
  - `name` - Primitive identifier
  - `type` - Always `:primitive`
  - `run` - Execution function AST in metadata
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
  Build an axiom from AST.

  Axioms have:
  - `name` - Axiom identifier
  - `query_fn` - The query function AST
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
    try do
      {result, _bindings} = Code.eval_quoted(quoted)
      result
    rescue
      _ -> quoted
    end
  end
end
