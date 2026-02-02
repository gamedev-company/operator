defmodule Operator.Rationalization do
  @moduledoc """
  Behaviour for plan annotation and event rationalization.

  Implement this behaviour to add narrative explanations to HTN plans
  and transform raw events into rationalized events with context.

  ## Configuration

      config :operator,
        rationalization_module: MyApp.OperatorRationalization

  ## Example Implementation

      defmodule MyApp.OperatorRationalization do
        @behaviour Operator.Rationalization

        @impl true
        def annotate_plan(p) do
          %{
            plan_id: p.goal,
            explanation: "NPC decided to pursue goal based on current situation",
            task_count: length(p.tasks),
            narrative_tags: infer_narrative_tags(p)
          }
        end

        @impl true
        def apply(event) do
          # Transform raw event into rationalized event with explanation
          %{
            event
            | explanation: generate_explanation(event),
              effects: generate_effects(event)
          }
        end

        defp infer_narrative_tags(plan) do
          case plan.goal do
            :acquire_data -> [:intrigue, :technology]
            :patrol_area -> [:routine, :security]
            _ -> [:general]
          end
        end
      end

  ## Default Implementation

  If no rationalization module is configured, Operator provides minimal
  default implementations that pass through data with basic annotations.
  """

  alias Operator.HTN.Plan

  @doc """
  Annotate an HTN plan with narrative justification.

  Called after plan generation to add context about why the plan
  was chosen and what it represents narratively.

  Returns a map of annotations to merge into plan metadata.
  """
  @callback annotate_plan(plan :: Plan.t()) :: map()

  @doc """
  Rationalize a raw event into a full event with explanation.

  Takes a raw event map and returns a fully rationalized event
  with explanation text, effects, and other narrative context.
  """
  @callback apply(event :: map()) :: map()

  @doc """
  Get the configured rationalization module, if any.
  """
  @spec get_module() :: module() | nil
  def get_module do
    Application.get_env(:operator, :rationalization_module)
  end

  @doc """
  Annotate a plan using the configured module or defaults.
  """
  @spec annotate_plan(Plan.t()) :: map()
  def annotate_plan(plan) do
    case get_module() do
      nil -> default_annotate_plan(plan)
      module -> module.annotate_plan(plan)
    end
  end

  @doc """
  Rationalize an event using the configured module or defaults.
  """
  @spec apply(map()) :: map()
  def apply(event) do
    case get_module() do
      nil -> default_apply(event)
      module -> module.apply(event)
    end
  end

  # Default implementations

  defp default_annotate_plan(plan) do
    %{
      plan_id: plan.goal,
      explanation: "Agent pursuing goal: #{plan.goal}",
      task_count: length(plan.tasks),
      created_at: plan.created_at
    }
  end

  defp default_apply(event) do
    Map.merge(
      %{
        explanation: Map.get(event, :explanation, "An event occurred."),
        effects: Map.get(event, :effects, [])
      },
      event
    )
  end
end
