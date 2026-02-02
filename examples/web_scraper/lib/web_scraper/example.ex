defmodule WebScraper.Example do
  @moduledoc """
  Runnable examples demonstrating the web scraping workflow system.

  ## Running

      iex> WebScraper.Example.run()

  Or run individual scenarios:

      iex> WebScraper.Example.basic_scrape()
      iex> WebScraper.Example.rate_limit_recovery()
      iex> WebScraper.Example.alternative_source_fallback()

  """

  alias Operator.HTN.{Facts, Planner, Registry}
  alias WebScraper.Domain

  @doc """
  Run a complete demonstration of the web scraping system.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         WEB SCRAPER HTN DEMONSTRATION")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Ensure domain is registered
    Registry.register(Domain)

    # Run each scenario
    basic_scrape()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    rate_limit_recovery()
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

    alternative_source_fallback()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("         DEMONSTRATION COMPLETE")
    IO.puts(String.duplicate("=", 60) <> "\n")

    :ok
  end

  @doc """
  Demonstrate basic product data scraping.

  The scraper fetches a product page, parses HTML, extracts data,
  validates it, and stores the results.
  """
  def basic_scrape do
    IO.puts("🌐 SCENARIO: Basic Product Scrape")
    IO.puts("   Scraping product data from e-commerce site\n")

    facts = Facts.from_perception(%{
      self: %{
        target_url: "https://shop.example.com/product/12345",
        css_selectors: [".product-title", ".price", ".sku"],
        required_fields: [:title, :price]
      },
      world: %{
        available_proxies: ["proxy1:8080", "proxy2:8080"],
        alternative_sources: ["api.example.com", "backup.example.com"]
      }
    })

    traits = %{archetype: :scraper}

    IO.puts("   Target: #{Facts.get(facts, {:self, :target_url})}")
    IO.puts("   Selectors: #{Facts.get(facts, {:self, :css_selectors}) |> length()} defined\n")

    case Planner.run(:scrape_product_data, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Tasks (#{length(plan.tasks)}):")
        Enum.each(plan.tasks, fn {name, _args} ->
          IO.puts("     • #{name}")
        end)
        IO.puts("\n   ✓ Plan ready for execution")

      {:error, reason} ->
        IO.puts("   ✗ Planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate rate limit handling with exponential backoff.

  When the scraper hits a rate limit, it waits with exponential
  backoff and retries using a proxy.
  """
  def rate_limit_recovery do
    IO.puts("⏳ SCENARIO: Rate Limit Recovery")
    IO.puts("   Scraper hit rate limit, initiating backoff\n")

    facts = Facts.from_perception(%{
      self: %{
        target_url: "https://rate-limit.example.com/data",
        rate_limited: true,
        retry_count: 1
      },
      world: %{
        available_proxies: ["proxy1:8080", "proxy2:8080", "proxy3:8080"]
      }
    })

    traits = %{archetype: :scraper, traits: [:patient]}

    IO.puts("   Status: Rate limited")
    IO.puts("   Retry count: #{Facts.get(facts, {:self, :retry_count})}")
    IO.puts("   Available proxies: #{Facts.get(facts, {:world, :available_proxies}) |> length()}\n")

    case Planner.run(:handle_rate_limit, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Recovery steps:")
        Enum.each(plan.tasks, fn {name, _args} ->
          IO.puts("     • #{name}")
        end)
        IO.puts("\n   ✓ Recovery plan ready")

      {:error, reason} ->
        IO.puts("   ✗ Recovery planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate fallback to alternative data sources.

  When the primary source fails, the scraper automatically tries
  alternative sources and normalizes the different data formats.
  """
  def alternative_source_fallback do
    IO.puts("🔄 SCENARIO: Alternative Source Fallback")
    IO.puts("   Primary source failed, trying alternatives\n")

    facts = Facts.from_perception(%{
      self: %{
        target_url: "https://error.example.com/product",
        primary_failed: true,
        tried_sources: ["error.example.com"],
        current_source_type: :api
      },
      world: %{
        alternative_sources: [
          "api.backup.com",
          "data.partner.com",
          "feed.supplier.com"
        ]
      }
    })

    traits = %{archetype: :scraper, traits: [:resilient]}

    IO.puts("   Primary failed: #{Facts.get(facts, {:self, :primary_failed})}")
    IO.puts("   Already tried: #{Facts.get(facts, {:self, :tried_sources}) |> inspect()}")
    alternatives = Facts.get(facts, {:world, :alternative_sources})
    IO.puts("   Alternatives available: #{length(alternatives)}\n")

    case Planner.run(:try_alternative_source, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Fallback steps:")
        Enum.each(plan.tasks, fn {name, _args} ->
          IO.puts("     • #{name}")
        end)
        IO.puts("\n   ✓ Fallback plan ready")

      {:error, reason} ->
        IO.puts("   ✗ Fallback planning failed: #{inspect(reason)}")
    end
  end

  @doc """
  Demonstrate retry with exponential backoff.

  When a fetch fails (but not from rate limiting), the scraper
  uses exponential backoff before retrying.
  """
  def retry_with_backoff do
    IO.puts("🔁 SCENARIO: Retry with Exponential Backoff")
    IO.puts("   Connection failed, calculating backoff\n")

    facts = Facts.from_perception(%{
      self: %{
        target_url: "https://flaky.example.com/data",
        last_error: :connection_timeout,
        retry_count: 2
      },
      world: %{}
    })

    traits = %{}

    IO.puts("   Last error: #{Facts.get(facts, {:self, :last_error})}")
    IO.puts("   Retry count: #{Facts.get(facts, {:self, :retry_count})}")
    backoff = :math.pow(2, 2) |> round()
    IO.puts("   Expected backoff: #{backoff}s\n")

    case Planner.run(:retry_with_backoff, facts, traits) do
      {:ok, plan} ->
        IO.puts("   Generated plan: #{plan.goal}")
        IO.puts("   Retry steps:")
        Enum.each(plan.tasks, fn {name, args} ->
          case args do
            [] -> IO.puts("     • #{name}")
            _ -> IO.puts("     • #{name} #{inspect(args)}")
          end
        end)
        IO.puts("\n   ✓ Retry plan ready")

      {:error, reason} ->
        IO.puts("   ✗ Retry planning failed: #{inspect(reason)}")
    end
  end
end
