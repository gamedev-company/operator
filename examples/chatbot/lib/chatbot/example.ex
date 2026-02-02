defmodule Chatbot.Example do
  @moduledoc """
  Runnable examples demonstrating the chatbot dialog system.

  ## Running

      iex> Chatbot.Example.run()

  Or run individual scenarios:

      iex> Chatbot.Example.order_inquiry()
      iex> Chatbot.Example.escalation()
      iex> Chatbot.Example.greeting()

  """

  alias Operator.HTN.{Facts, Planner, GoalSelector, Registry}
  alias Chatbot.Domain

  @doc """
  Run a complete demonstration of the chatbot system.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         CHATBOT DIALOG HTN DEMONSTRATION")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Ensure domain is registered
    Registry.register(Domain)

    # Run each scenario
    greeting()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    order_inquiry()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    product_question()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    escalation()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    intent_selection_demo()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         DEMONSTRATION COMPLETE")
    IO.puts(String.duplicate("=", 60) <> "\n")

    :ok
  end

  @doc """
  Demonstrate greeting a new user.
  """
  def greeting do
    IO.puts("👋 SCENARIO: New User Greeting")
    IO.puts("   User just started a new conversation\n")

    facts = Facts.from_perception(%{
      self: %{
        conversation_state: :new,
        user_id: nil,
        detected_intent: nil
      },
      world: %{
        available_agents: 3
      }
    })

    traits = %{archetype: :support_bot}

    IO.puts("   Conversation state: #{Facts.get(facts, {:self, :conversation_state})}")
    IO.puts("   User identified: #{Facts.has?(facts, {:self, :user_id})}\n")

    case Planner.run(:greet_user, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Dialog steps:")
        Enum.each(plan.tasks, fn {name, _args} ->
          IO.puts("     • #{name}")
        end)
        IO.puts("\n   ✓ Greeting flow ready")

      {:error, reason} ->
        IO.puts("   ✗ Planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate order status inquiry flow.

  User asks "Where is my order?" and the bot guides them through
  providing order number and displays status.
  """
  def order_inquiry do
    IO.puts("📦 SCENARIO: Order Status Inquiry")
    IO.puts("   User: \"Where is my order?\"\n")

    facts = Facts.from_perception(%{
      self: %{
        detected_intent: :order_status,
        sentiment: :neutral,
        order_number: "ORD-12345",
        conversation_turns: 2
      },
      world: %{
        available_agents: 3,
        queue_length: 5
      },
      social: %{
        customer_tier: :premium
      }
    })

    traits = %{archetype: :support_bot}

    IO.puts("   Intent: #{Facts.get(facts, {:self, :detected_intent})}")
    IO.puts("   Sentiment: #{Facts.get(facts, {:self, :sentiment})}")
    IO.puts("   Order #: #{Facts.get(facts, {:self, :order_number})}")
    IO.puts("   Customer tier: #{Facts.get(facts, {:social, :customer_tier})}\n")

    case Planner.run(:handle_order_inquiry, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Dialog flow (#{length(plan.tasks)} steps):")
        Enum.each(plan.tasks, fn {name, _args} ->
          IO.puts("     • #{name}")
        end)
        IO.puts("\n   ✓ Order inquiry flow ready")

      {:error, reason} ->
        IO.puts("   ✗ Planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate product question flow.
  """
  def product_question do
    IO.puts("🛍️  SCENARIO: Product Information")
    IO.puts("   User: \"Tell me about the wireless headphones\"\n")

    facts = Facts.from_perception(%{
      self: %{
        detected_intent: :product_info,
        sentiment: :neutral,
        product_id: "PROD-WH100",
        conversation_turns: 1
      },
      world: %{}
    })

    traits = %{archetype: :sales_bot}

    IO.puts("   Intent: #{Facts.get(facts, {:self, :detected_intent})}")
    IO.puts("   Product ID: #{Facts.get(facts, {:self, :product_id})}\n")

    case Planner.run(:handle_product_question, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Dialog flow:")
        Enum.each(plan.tasks, fn {name, _args} ->
          IO.puts("     • #{name}")
        end)
        IO.puts("\n   ✓ Product info flow ready")

      {:error, reason} ->
        IO.puts("   ✗ Planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate escalation to human agent.

  User is frustrated after multiple failed attempts, triggering
  automatic escalation to a human agent.
  """
  def escalation do
    IO.puts("🚨 SCENARIO: Escalation to Human")
    IO.puts("   User is frustrated, requesting human help\n")

    facts = Facts.from_perception(%{
      self: %{
        detected_intent: :order_status,
        sentiment: :frustrated,
        failed_attempts: 3,
        escalation_requested: true,
        order_number: "ORD-99999",
        conversation_turns: 8
      },
      world: %{
        available_agents: 2,
        queue_length: 3
      }
    })

    traits = %{archetype: :support_bot}

    IO.puts("   Sentiment: #{Facts.get(facts, {:self, :sentiment})} ⚠️")
    IO.puts("   Failed attempts: #{Facts.get(facts, {:self, :failed_attempts})}")
    IO.puts("   Escalation requested: #{Facts.get(facts, {:self, :escalation_requested})}")
    IO.puts("   Available agents: #{Facts.get(facts, {:world, :available_agents})}\n")

    case Planner.run(:escalate_to_human, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Escalation steps:")
        Enum.each(plan.tasks, fn {name, _args} ->
          IO.puts("     • #{name}")
        end)
        IO.puts("\n   ✓ Escalation flow ready")

      {:error, reason} ->
        IO.puts("   ✗ Planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate automatic intent/goal selection.

  Shows how the system selects the appropriate dialog goal based
  on detected intent and conversation state.
  """
  def intent_selection_demo do
    IO.puts("🎯 DEMO: Automatic Intent Selection")
    IO.puts("   Showing how goals are selected by intent\n")

    scenarios = [
      {"New conversation", %{
        self: %{conversation_state: :new}
      }},
      {"Order status question", %{
        self: %{detected_intent: :order_status, sentiment: :neutral}
      }},
      {"Product inquiry", %{
        self: %{detected_intent: :product_info}
      }},
      {"Frustrated user", %{
        self: %{detected_intent: :order_status, sentiment: :frustrated}
      }},
      {"Unclear message", %{
        self: %{detected_intent: :unclear, sentiment: :neutral}
      }}
    ]

    for {description, state} <- scenarios do
      facts = Facts.from_perception(state)
      traits = %{}

      case GoalSelector.pick_goal(facts, traits) do
        {:ok, goal} ->
          IO.puts("   #{description}")
          IO.puts("   → Selected: :#{goal}\n")

        :none ->
          IO.puts("   #{description}")
          IO.puts("   → No applicable goal\n")
      end
    end
  end
end
