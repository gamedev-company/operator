defmodule Operator.HTN.Trace.ConsoleHandler do
  @moduledoc """
  Console-based trace handler for debugging HTN planning.

  Prints colored, formatted trace output to the console.

  ## Usage

      # Enable console tracing
      Operator.HTN.Trace.set_handler(Operator.HTN.Trace.ConsoleHandler)

      # Run your planner
      Operator.HTN.Planner.run(:some_goal, facts, traits)

      # Disable tracing
      Operator.HTN.Trace.reset()

  ## Output Format

      [HTN] ▶ GOAL acquire_data
      [HTN]   ✓ Precondition passed (goal: acquire_data)
      [HTN]   → TASK ensure_access []
      [HTN]     ✓ Precondition passed (task: ensure_access)
      [HTN]     ⚡ Effect applied: {:self, :has_access} = true
      [HTN]   ← TASK ensure_access → 2 subtasks
      [HTN] ◀ GOAL acquire_data SUCCESS

  """

  @behaviour Operator.HTN.Trace.Handler

  @impl true
  def on_goal_start(goal_name, _facts, _opts) do
    log("▶ GOAL #{goal_name}", :cyan)
  end

  @impl true
  def on_goal_end(goal_name, result, _opts) do
    color = if result == :success, do: :green, else: :red
    result_str = String.upcase(to_string(result))
    log("◀ GOAL #{goal_name} #{result_str}", color)
  end

  @impl true
  def on_precondition_eval(context, result, _opts) do
    {symbol, color} = if result, do: {"✓", :green}, else: {"✗", :red}
    context_str = format_context(context)

    log(
      "  #{symbol} Precondition #{if result, do: "passed", else: "failed"} (#{context_str})",
      color,
      indent: 1
    )
  end

  @impl true
  def on_task_expand(task_name, args, _facts, _opts) do
    args_str = if args == [], do: "", else: " #{inspect(args)}"
    log("  → TASK #{task_name}#{args_str}", :blue, indent: 1)
  end

  @impl true
  def on_task_complete(task_name, result_tasks, status, _opts) do
    count = length(result_tasks)

    {color, status_str} =
      if status == :success do
        {:blue, "#{count} subtask#{if count != 1, do: "s", else: ""}"}
      else
        {:red, "FAILED"}
      end

    log("  ← TASK #{task_name} → #{status_str}", color, indent: 1)
  end

  @impl true
  def on_effect_apply(effect, _facts, _opts) do
    log("  ⚡ Effect applied: #{inspect(effect.key)} = #{inspect(effect.value)}", :yellow,
      indent: 2
    )
  end

  @impl true
  def on_branch_select(task_name, branch_id, _opts) do
    log("  ⎇ Branch selected: #{task_name} → #{branch_id}", :magenta, indent: 1)
  end

  # Private helpers

  defp log(message, color, opts \\ []) do
    indent = Keyword.get(opts, :indent, 0)
    prefix = "[HTN]" <> String.duplicate("  ", indent)
    IO.puts(colorize("#{prefix} #{message}", color))
    :ok
  end

  defp format_context(context) do
    cond do
      Map.has_key?(context, :goal) -> "goal: #{context.goal}"
      Map.has_key?(context, :task) -> "task: #{context.task}"
      true -> inspect(context)
    end
  end

  @spec colorize(String.t(), atom()) :: String.t()
  defp colorize(text, :red), do: "\e[31m#{text}\e[0m"
  defp colorize(text, :green), do: "\e[32m#{text}\e[0m"
  defp colorize(text, :yellow), do: "\e[33m#{text}\e[0m"
  defp colorize(text, :blue), do: "\e[34m#{text}\e[0m"
  defp colorize(text, :magenta), do: "\e[35m#{text}\e[0m"
  defp colorize(text, :cyan), do: "\e[36m#{text}\e[0m"
end
