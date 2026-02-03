defmodule Operator.Rationalization do
  @moduledoc """
  Behaviour for narrative annotation of plans and events.

  The Rationalization system transforms cold, mechanical HTN outputs into
  rich narrative content. Instead of "NPC executed :attack", you get
  "The guard spotted the intruder and drew his weapon."

  ## Two Responsibilities

  1. **Plan Annotation** - Add narrative context to generated plans
  2. **Event Rationalization** - Transform raw Director events into full narratives

  ## Configuration

      config :ex_operator,
        rationalization_module: MyApp.OperatorRationalization

  ## Example Implementation

      defmodule MyApp.OperatorRationalization do
        @behaviour Operator.Rationalization

        @impl true
        def annotate_plan(plan) do
          %{
            plan_id: plan.goal,
            explanation: explain_goal(plan.goal),
            narrative_tags: infer_tags(plan),
            mood: infer_mood(plan)
          }
        end

        @impl true
        def apply(event) do
          Map.merge(event, %{
            explanation: generate_explanation(event),
            effects: generate_effects(event),
            dialogue: generate_dialogue(event)
          })
        end

        defp explain_goal(:patrol), do: "The guard begins their routine patrol."
        defp explain_goal(:attack), do: "Aggression surges as combat instincts take over."
        defp explain_goal(:flee), do: "Self-preservation kicks in. Time to run."
        defp explain_goal(goal), do: "Pursuing objective: \#{goal}"

        defp infer_tags(%{goal: :attack}), do: [:combat, :action]
        defp infer_tags(%{goal: :patrol}), do: [:routine, :ambient]
        defp infer_tags(_), do: [:general]

        defp infer_mood(%{goal: :flee}), do: :fearful
        defp infer_mood(%{goal: :attack}), do: :aggressive
        defp infer_mood(_), do: :neutral

        defp generate_explanation(%{type: :ambush, severity: s}) when s >= 4 do
          "A devastating ambush springs from the shadows!"
        end
        defp generate_explanation(%{type: :ambush}) do
          "Enemies emerge from hiding."
        end
        defp generate_explanation(%{type: type}) do
          "An event of type \#{type} occurs."
        end
      end

  ## Use Cases

  ### Debug Logging

  Add explanations for development debugging:

      Logger.debug("Plan: \#{plan.metadata.explanation}")
      # => "Plan: The guard spotted movement and is investigating."

  ### UI/UX Integration

  Feed rationalized events to your UI:

      def handle_event(event) do
        Toast.show(event.explanation)
        play_sound(event.mood)
      end

  ### Narrative Generation

  Build emergent storytelling from plan sequences:

      def chronicle_day(entity, plans) do
        plans
        |> Enum.map(& &1.metadata.explanation)
        |> Enum.join(" ")
      end
      # => "The merchant opened shop. A customer arrived. They haggled fiercely."

  ## Default Implementation

  If no rationalization module is configured, Operator provides minimal
  defaults that pass through data with basic annotations like
  "Agent pursuing goal: :patrol".

  ## See Also

  * `Operator.HTN.Plan` - Plans that get annotated
  * `Operator.Director` - Generates events that get rationalized

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
    Application.get_env(:ex_operator, :rationalization_module)
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
