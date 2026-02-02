defmodule Chatbot.Domain do
  @moduledoc """
  HTN domain for conversational AI dialog management.

  Demonstrates using Operator for:
  - Managing conversation state and flow
  - Handling multiple user intents
  - Complex multi-step dialogs
  - Graceful escalation to human agents

  """

  use Operator.HTN.DSL

  alias Operator.HTN.Facts

  # ============================================================================
  # AXIOMS - Reusable query patterns
  # ============================================================================

  axiom :user_frustrated do
    fn facts, _args ->
      sentiment = Facts.get(facts, {:self, :sentiment}, :neutral)
      sentiment in [:frustrated, :angry, :upset]
    end
  end

  axiom :exceeded_attempts do
    fn facts, args ->
      max = Keyword.get(args, :max, 2)
      attempts = Facts.get(facts, {:self, :failed_attempts}, 0)
      attempts > max
    end
  end

  axiom :agent_available do
    fn facts, _args ->
      available = Facts.get(facts, {:world, :available_agents}, 0)
      available > 0
    end
  end

  axiom :has_order_context do
    fn facts, _args ->
      Facts.has?(facts, {:self, :order_number}) and
        Facts.has?(facts, {:self, :order_details})
    end
  end

  # ============================================================================
  # GOALS
  # ============================================================================

  @doc "Handle order status inquiry"
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

    metadata priority: 5, domain: :support
  end

  @doc "Handle product question"
  goal :handle_product_question do
    precond fn facts ->
      Facts.get(facts, {:self, :detected_intent}) == :product_info
    end

    decompose do
      task :identify_product
      task :fetch_product_info
      task :present_product_info
      task :suggest_related_products
    end

    metadata priority: 5, domain: :sales
  end

  @doc "Handle return/refund request"
  goal :handle_return_request do
    precond fn facts ->
      Facts.get(facts, {:self, :detected_intent}) == :return_request
    end

    decompose do
      task :confirm_order_number
      task :check_return_eligibility
      task :explain_return_process
      task :initiate_return_if_confirmed
    end

    metadata priority: 6, domain: :support
  end

  @doc "Escalate to human agent"
  goal :escalate_to_human do
    precond {:any, [
      {:axiom, :user_frustrated},
      fn facts -> Facts.get(facts, {:self, :escalation_requested}, false) end,
      {:axiom, :exceeded_attempts, max: 2}
    ]}

    decompose do
      task :apologize
      task :collect_context
      task :transfer_to_agent
    end

    metadata priority: 10, domain: :escalation
  end

  @doc "Welcome new conversation"
  goal :greet_user do
    precond fn facts ->
      Facts.get(facts, {:self, :conversation_state}) == :new
    end

    decompose do
      task :send_greeting
      task :identify_user
      task :ask_how_to_help
    end

    metadata priority: 1, domain: :greeting
  end

  @doc "Handle unclear intent"
  goal :clarify_intent do
    precond fn facts ->
      Facts.get(facts, {:self, :detected_intent}) == :unclear and
        not Facts.get(facts, {:self, :escalation_requested}, false)
    end

    decompose do
      task :acknowledge_message
      task :ask_clarifying_question
      task :suggest_options
    end

    metadata priority: 3, domain: :clarification
  end

  # ============================================================================
  # TASKS
  # ============================================================================

  task :confirm_order_number do
    decompose fn facts ->
      if Facts.has?(facts, {:self, :order_number}) do
        [{:validate_order_number, []}]
      else
        [{:ask_for_order_number, []}, {:wait_for_response, [:order_number]}]
      end
    end

    cost 1.0
  end

  task :identify_product do
    decompose fn facts ->
      if Facts.has?(facts, {:self, :product_id}) do
        [{:validate_product_id, []}]
      else
        [{:extract_product_from_message, []}, {:confirm_product, []}]
      end
    end

    cost 1.0
  end

  task :check_return_eligibility do
    decompose fn facts ->
      order_date = Facts.get(facts, {:self, :order_date})
      product_type = Facts.get(facts, {:self, :product_type})

      cond do
        product_type == :digital ->
          [{:explain_digital_return_policy, []}]
        order_date != nil ->
          [{:check_return_window, []}, {:check_item_condition, []}]
        true ->
          [{:ask_for_order_date, []}]
      end
    end

    cost 2.0
  end

  task :transfer_to_agent do
    precond {:axiom, :agent_available}

    decompose do
      task :summarize_conversation
      task :create_support_ticket
      task :connect_to_agent
      task :send_transfer_confirmation
    end

    cost 3.0
  end

  task :identify_user do
    decompose fn facts ->
      if Facts.has?(facts, {:self, :user_id}) do
        [{:load_user_profile, []}]
      else
        [{:ask_for_identification, []}, {:wait_for_response, [:user_info]}]
      end
    end

    cost 1.0
  end

  # ============================================================================
  # PRIMITIVES
  # ============================================================================

  primitive :ask_for_order_number do
    run fn actor, _facts ->
      response = "I'd be happy to help you check your order status. " <>
                 "Could you please provide your order number? " <>
                 "It usually starts with 'ORD-' followed by numbers."

      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :validate_order_number do
    run fn actor, facts ->
      order_number = Facts.get(facts, {:self, :order_number})
      IO.puts("[Bot] Validating order: #{order_number}")

      # Simulated validation
      if String.starts_with?(to_string(order_number), "ORD-") do
        {:ok, Map.put(actor, :order_validated, true)}
      else
        {:error, :invalid_order_format}
      end
    end
  end

  primitive :fetch_order_details do
    run fn actor, facts ->
      order_number = Facts.get(facts, {:self, :order_number})
      IO.puts("[Bot] Fetching details for #{order_number}")

      # Simulated lookup
      details = %{
        status: :shipped,
        tracking: "TRK123456",
        estimated_delivery: "Feb 5, 2026"
      }
      {:ok, Map.put(actor, :order_details, details)}
    end
  end

  primitive :present_order_status do
    run fn actor, _facts ->
      details = Map.get(actor, :order_details, %{})

      response = """
      Here's what I found for your order:
      📦 Status: #{details[:status]}
      🚚 Tracking: #{details[:tracking]}
      📅 Estimated delivery: #{details[:estimated_delivery]}
      """

      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :offer_additional_help do
    run fn actor, _facts ->
      response = "Is there anything else I can help you with today?"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :wait_for_response do
    run fn actor, _facts ->
      expected_field = Map.get(actor, :pending_args, [:input]) |> List.first()
      IO.puts("[Bot] Waiting for user to provide: #{expected_field}")
      {:ok, Map.put(actor, :awaiting, expected_field)}
    end
  end

  primitive :apologize do
    run fn actor, _facts ->
      response = "I apologize that I haven't been able to help you better. " <>
                 "Let me connect you with a human agent who can assist you."
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :collect_context do
    run fn actor, facts ->
      context = %{
        intent: Facts.get(facts, {:self, :detected_intent}),
        sentiment: Facts.get(facts, {:self, :sentiment}),
        order_number: Facts.get(facts, {:self, :order_number}),
        conversation_turns: Facts.get(facts, {:self, :conversation_turns}, 0)
      }
      {:ok, Map.put(actor, :escalation_context, context)}
    end
  end

  primitive :summarize_conversation do
    run fn actor, _facts ->
      IO.puts("[Bot] Summarizing conversation for handoff...")
      {:ok, Map.put(actor, :summary_generated, true)}
    end
  end

  primitive :create_support_ticket do
    run fn actor, _facts ->
      ticket_id = "TKT-#{System.unique_integer([:positive])}"
      IO.puts("[Bot] Created support ticket: #{ticket_id}")
      {:ok, Map.put(actor, :ticket_id, ticket_id)}
    end
  end

  primitive :connect_to_agent do
    run fn actor, _facts ->
      IO.puts("[Bot] Connecting to available agent...")
      {:ok, Map.put(actor, :transfer_initiated, true)}
    end
  end

  primitive :send_transfer_confirmation do
    run fn actor, _facts ->
      response = "You're now being connected to an agent. " <>
                 "Your reference number is #{Map.get(actor, :ticket_id)}."
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :send_greeting do
    run fn actor, _facts ->
      response = "Hello! Welcome to Customer Support. I'm here to help you today."
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :ask_how_to_help do
    run fn actor, _facts ->
      response = "How can I assist you today? I can help with:\n" <>
                 "• Order status and tracking\n" <>
                 "• Product information\n" <>
                 "• Returns and refunds\n" <>
                 "• General questions"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :acknowledge_message do
    run fn actor, _facts ->
      response = "I'm not quite sure I understood that."
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :ask_clarifying_question do
    run fn actor, _facts ->
      response = "Could you please tell me more about what you need help with?"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :suggest_options do
    run fn actor, _facts ->
      response = "Here are some things I can help with:\n" <>
                 "1. Check order status\n" <>
                 "2. Product questions\n" <>
                 "3. Returns and refunds\n" <>
                 "4. Talk to a human agent"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :load_user_profile do
    run fn actor, facts ->
      user_id = Facts.get(facts, {:self, :user_id})
      IO.puts("[Bot] Loading profile for user: #{user_id}")
      {:ok, Map.put(actor, :profile_loaded, true)}
    end
  end

  primitive :ask_for_identification do
    run fn actor, _facts ->
      response = "To better assist you, could you provide your email address " <>
                 "or phone number associated with your account?"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :fetch_product_info do
    run fn actor, facts ->
      product_id = Facts.get(facts, {:self, :product_id})
      IO.puts("[Bot] Fetching product info: #{product_id}")
      {:ok, Map.put(actor, :product_info, %{name: "Sample Product", price: "$99.99"})}
    end
  end

  primitive :present_product_info do
    run fn actor, _facts ->
      info = Map.get(actor, :product_info, %{})
      response = "Here's what I found:\n#{info[:name]} - #{info[:price]}"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :suggest_related_products do
    run fn actor, _facts ->
      response = "Customers who viewed this also liked: [Product A], [Product B]"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :extract_product_from_message do
    run fn actor, _facts ->
      IO.puts("[Bot] Extracting product from message...")
      {:ok, actor}
    end
  end

  primitive :confirm_product do
    run fn actor, _facts ->
      response = "Just to confirm, you're asking about [Product Name]?"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :validate_product_id do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :product_validated, true)}
    end
  end

  primitive :explain_return_process do
    run fn actor, _facts ->
      response = "To return your item, you can:\n" <>
                 "1. Print a prepaid shipping label\n" <>
                 "2. Pack the item securely\n" <>
                 "3. Drop it off at any shipping location"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :explain_digital_return_policy do
    run fn actor, _facts ->
      response = "Digital products can be refunded within 14 days of purchase " <>
                 "if you haven't downloaded or accessed the content."
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :check_return_window do
    run fn actor, _facts ->
      IO.puts("[Bot] Checking return window...")
      {:ok, Map.put(actor, :within_return_window, true)}
    end
  end

  primitive :check_item_condition do
    run fn actor, _facts ->
      response = "Is the item in its original condition with all tags attached?"
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :ask_for_order_date do
    run fn actor, _facts ->
      response = "When did you place this order? This helps me check eligibility."
      {:ok, Map.put(actor, :pending_response, response)}
    end
  end

  primitive :initiate_return_if_confirmed do
    run fn actor, _facts ->
      IO.puts("[Bot] Initiating return process...")
      {:ok, Map.put(actor, :return_initiated, true)}
    end
  end
end
