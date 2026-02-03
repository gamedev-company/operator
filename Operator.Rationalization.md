# `Operator.Rationalization`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/behaviours/rationalization.ex#L1)

Behaviour for narrative annotation of plans and events.

The Rationalization system transforms cold, mechanical HTN outputs into
rich narrative content. Instead of "NPC executed :attack", you get
"The guard spotted the intruder and drew his weapon."

## Two Responsibilities

1. **Plan Annotation** - Add narrative context to generated plans
2. **Event Rationalization** - Transform raw Director events into full narratives

## Configuration

    config :operator,
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
      defp explain_goal(goal), do: "Pursuing objective: #{goal}"

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
        "An event of type #{type} occurs."
      end
    end

## Use Cases

### Debug Logging

Add explanations for development debugging:

    Logger.debug("Plan: #{plan.metadata.explanation}")
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

# `annotate_plan`

```elixir
@callback annotate_plan(plan :: Operator.HTN.Plan.t()) :: map()
```

Annotate an HTN plan with narrative justification.

Called after plan generation to add context about why the plan
was chosen and what it represents narratively.

Returns a map of annotations to merge into plan metadata.

# `apply`

```elixir
@callback apply(event :: map()) :: map()
```

Rationalize a raw event into a full event with explanation.

Takes a raw event map and returns a fully rationalized event
with explanation text, effects, and other narrative context.

# `annotate_plan`

```elixir
@spec annotate_plan(Operator.HTN.Plan.t()) :: map()
```

Annotate a plan using the configured module or defaults.

# `apply`

```elixir
@spec apply(map()) :: map()
```

Rationalize an event using the configured module or defaults.

# `get_module`

```elixir
@spec get_module() :: module() | nil
```

Get the configured rationalization module, if any.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
