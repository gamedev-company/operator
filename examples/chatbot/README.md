# Chatbot Example

Using Operator for conversation flow management in chatbots
and virtual assistants.

## Use Case

A customer support chatbot that:
- Manages conversation state
- Handles multiple intents
- Follows complex dialog flows
- Escalates when appropriate

## Key Concepts

### Goals as Conversation Intents

```elixir
goal :handle_order_inquiry do
  precond fn facts ->
    Facts.get(facts, {:self, :detected_intent}) == :order_status
  end

  decompose do
    task :confirm_order_number
    task :fetch_order_details
    task :present_order_status
    task :offer_additional_help
  end
end

goal :escalate_to_human do
  precond {:any, [
    fn facts -> Facts.get(facts, {:self, :sentiment}) == :frustrated end,
    fn facts -> Facts.get(facts, {:self, :escalation_requested}, false) end,
    fn facts -> Facts.get(facts, {:self, :failed_attempts}, 0) > 2 end
  ]}

  decompose do
    task :apologize
    task :collect_context
    task :transfer_to_agent
  end

  metadata priority: 10  # Highest priority
end
```

### Tasks as Dialog Steps

```elixir
task :confirm_order_number do
  decompose fn facts ->
    if Facts.has?(facts, {:self, :order_number}) do
      [{:validate_order_number, []}]
    else
      [{:ask_for_order_number, []}, {:wait_for_response, []}]
    end
  end
end
```

### Primitives as Bot Actions

```elixir
primitive :ask_for_order_number do
  run fn actor, _facts ->
    response = "I'd be happy to help you check your order status. " <>
               "Could you please provide your order number?"

    {:ok, Map.put(actor, :pending_response, response)}
  end
end
```

## Conversation State

```elixir
facts = Facts.from_perception(%{
  self: %{
    detected_intent: :order_status,
    sentiment: :neutral,
    order_number: nil,
    conversation_turns: 3
  },
  world: %{
    available_agents: 5,
    queue_length: 12
  },
  social: %{
    customer_tier: :premium,
    previous_interactions: 7
  }
})
```

## Running

```bash
cd examples/chatbot
mix deps.get
iex -S mix

Chatbot.Example.run()
```

## Dialog Flow Visualization

```
┌─────────────────────────────────────────────────────────┐
│                    User Message                          │
│              "Where is my order?"                        │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Intent Detection                            │
│         detected_intent: :order_status                   │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│          Goal Selection: handle_order_inquiry            │
│                                                          │
│  Precond: intent == :order_status? ✓                    │
│  Priority: 5                                             │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Task: confirm_order_number                  │
│  ┌─────────────────────────────────────────────────┐    │
│  │ order_number present? NO                        │    │
│  │ → ask_for_order_number                          │    │
│  │ → wait_for_response                             │    │
│  └─────────────────────────────────────────────────┘    │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│                   Bot Response                           │
│  "Could you please provide your order number?"          │
└─────────────────────────────────────────────────────────┘
```
