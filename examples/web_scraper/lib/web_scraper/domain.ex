defmodule WebScraper.Domain do
  @moduledoc """
  HTN domain for intelligent web scraping.

  Demonstrates using Operator for workflow orchestration with:
  - Retry strategies
  - Fallback sources
  - Rate limit handling
  - Data validation

  """

  use Operator.HTN.DSL

  alias Operator.HTN.Facts

  # ============================================================================
  # AXIOMS - Reusable query patterns
  # ============================================================================

  axiom :can_retry do
    fn facts, args ->
      max_retries = Keyword.get(args, :max, 3)
      current = Facts.get(facts, {:self, :retry_count}, 0)
      current < max_retries
    end
  end

  axiom :is_rate_limited do
    fn facts, _args ->
      Facts.get(facts, {:self, :rate_limited}, false)
    end
  end

  axiom :has_valid_response do
    fn facts, _args ->
      status = Facts.get(facts, {:self, :last_status}, 0)
      status >= 200 and status < 300
    end
  end

  axiom :has_proxy_available do
    fn facts, _args ->
      proxies = Facts.get(facts, {:world, :available_proxies}, [])
      length(proxies) > 0
    end
  end

  axiom :has_alternative_source do
    fn facts, _args ->
      sources = Facts.get(facts, {:world, :alternative_sources}, [])
      length(sources) > 0
    end
  end

  # ============================================================================
  # GOALS
  # ============================================================================

  @doc "Main goal: scrape product data from target URL"
  goal :scrape_product_data do
    precond fn facts ->
      Facts.has?(facts, {:self, :target_url})
    end

    decompose do
      task :prepare_session
      task :fetch_page
      task :extract_data
      task :validate_data
      task :store_results
    end

    metadata domain: :scraping, priority: 5
  end

  @doc "Handle rate limiting by waiting and retrying"
  goal :handle_rate_limit do
    precond {:all, [
      {:axiom, :is_rate_limited},
      {:axiom, :can_retry, max: 3}
    ]}

    decompose do
      task :calculate_backoff
      task :wait_for_cooldown
      task :clear_rate_limit_flag
      task :retry_with_proxy
    end

    metadata domain: :recovery, priority: 8
  end

  @doc "Try an alternative data source when primary fails"
  goal :try_alternative_source do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :primary_failed}, false) end,
      {:axiom, :has_alternative_source}
    ]}

    decompose do
      task :select_alternative_source
      task :fetch_from_alternative
      task :normalize_data
    end

    metadata domain: :recovery, priority: 7
  end

  @doc "Retry failed fetch with exponential backoff"
  goal :retry_with_backoff do
    precond {:all, [
      fn facts -> Facts.get(facts, {:self, :last_error}) != nil end,
      {:axiom, :can_retry, max: 5}
    ]}

    decompose do
      task :calculate_backoff
      task :wait_for_cooldown
      task :increment_retry_count
      task :fetch_page
    end

    metadata domain: :recovery, priority: 6
  end

  # ============================================================================
  # TASKS
  # ============================================================================

  task :prepare_session do
    decompose do
      task :set_user_agent
      task :set_cookies
      task :set_headers
    end

    cost 1.0
  end

  task :fetch_page do
    decompose fn facts ->
      if Facts.get(facts, {:self, :rate_limited}, false) do
        [{:fetch_with_proxy, []}]
      else
        [{:direct_fetch, []}]
      end
    end

    cost 3.0
  end

  task :extract_data do
    decompose fn facts ->
      content_type = Facts.get(facts, {:self, :content_type}, "text/html")

      case content_type do
        "application/json" -> [{:parse_json, []}]
        "text/html" -> [{:parse_html, []}, {:extract_selectors, []}]
        _ -> [{:extract_raw, []}]
      end
    end

    cost 2.0
  end

  task :validate_data do
    decompose do
      task :check_required_fields
      task :validate_formats
      task :sanitize_values
    end

    cost 1.0
  end

  task :retry_with_proxy do
    precond {:axiom, :has_proxy_available}

    decompose do
      task :select_proxy
      task :fetch_with_proxy
    end

    cost 4.0
  end

  task :calculate_backoff do
    decompose fn facts ->
      retry_count = Facts.get(facts, {:self, :retry_count}, 0)
      # Exponential backoff: 1s, 2s, 4s, 8s...
      delay = :math.pow(2, retry_count) |> round()
      [{:set_backoff_delay, [delay]}]
    end

    cost 0.5
  end

  task :select_alternative_source do
    decompose fn facts ->
      sources = Facts.get(facts, {:world, :alternative_sources}, [])
      tried = Facts.get(facts, {:self, :tried_sources}, [])
      available = sources -- tried

      case available do
        [next | _] -> [{:set_target_source, [next]}]
        [] -> [{:fail_no_sources, []}]
      end
    end

    cost 1.0
  end

  task :normalize_data do
    decompose fn facts ->
      source_type = Facts.get(facts, {:self, :current_source_type}, :api)

      case source_type do
        :api -> [{:normalize_api_response, []}]
        :html -> [{:normalize_html_data, []}]
        :feed -> [{:normalize_feed_data, []}]
      end
    end

    cost 2.0
  end

  # ============================================================================
  # PRIMITIVES
  # ============================================================================

  primitive :set_user_agent do
    run fn actor, _facts ->
      user_agent = "Mozilla/5.0 (compatible; DataBot/1.0)"
      headers = Map.get(actor, :headers, %{})
      {:ok, %{actor | headers: Map.put(headers, "User-Agent", user_agent)}}
    end
  end

  primitive :set_cookies do
    run fn actor, facts ->
      cookies = Facts.get(facts, {:self, :session_cookies}, %{})
      {:ok, Map.put(actor, :cookies, cookies)}
    end
  end

  primitive :set_headers do
    run fn actor, _facts ->
      headers = Map.get(actor, :headers, %{})
      new_headers = Map.merge(headers, %{
        "Accept" => "text/html,application/json",
        "Accept-Language" => "en-US,en;q=0.9"
      })
      {:ok, %{actor | headers: new_headers}}
    end
  end

  primitive :direct_fetch do
    run fn actor, facts ->
      url = Facts.get(facts, {:self, :target_url})
      IO.puts("[Scraper] Fetching: #{url}")

      # Simulated fetch
      case simulate_fetch(url) do
        {:ok, body, status} ->
          {:ok, Map.merge(actor, %{
            last_response: body,
            last_status: status,
            content_type: "text/html"
          })}

        {:error, :rate_limited} ->
          {:ok, Map.put(actor, :rate_limited, true)}

        {:error, reason} ->
          {:ok, Map.put(actor, :last_error, reason)}
      end
    end
  end

  primitive :fetch_with_proxy do
    run fn actor, facts ->
      url = Facts.get(facts, {:self, :target_url})
      proxy = Facts.get(facts, {:self, :selected_proxy})
      IO.puts("[Scraper] Fetching via proxy #{proxy}: #{url}")

      # Simulated proxied fetch
      {:ok, Map.merge(actor, %{
        last_response: "<html>proxied content</html>",
        last_status: 200,
        used_proxy: proxy
      })}
    end
  end

  primitive :select_proxy do
    run fn actor, facts ->
      proxies = Facts.get(facts, {:world, :available_proxies}, [])
      proxy = List.first(proxies)
      {:ok, Map.put(actor, :selected_proxy, proxy)}
    end
  end

  primitive :parse_html do
    run fn actor, _facts ->
      body = Map.get(actor, :last_response, "")
      IO.puts("[Scraper] Parsing HTML (#{byte_size(body)} bytes)")
      {:ok, Map.put(actor, :parsed_doc, {:html_doc, body})}
    end
  end

  primitive :parse_json do
    run fn actor, _facts ->
      body = Map.get(actor, :last_response, "{}")
      IO.puts("[Scraper] Parsing JSON")
      {:ok, Map.put(actor, :parsed_doc, {:json_doc, body})}
    end
  end

  primitive :extract_selectors do
    run fn actor, facts ->
      selectors = Facts.get(facts, {:self, :css_selectors}, [])
      IO.puts("[Scraper] Extracting with #{length(selectors)} selectors")

      # Simulated extraction
      data = %{title: "Product Name", price: "$99.99", sku: "ABC123"}
      {:ok, Map.put(actor, :extracted_data, data)}
    end
  end

  primitive :extract_raw do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :extracted_data, %{raw: actor.last_response})}
    end
  end

  primitive :check_required_fields do
    run fn actor, facts ->
      required = Facts.get(facts, {:self, :required_fields}, [:title])
      data = Map.get(actor, :extracted_data, %{})

      missing = Enum.reject(required, &Map.has_key?(data, &1))

      if Enum.empty?(missing) do
        {:ok, actor}
      else
        {:error, {:missing_fields, missing}}
      end
    end
  end

  primitive :validate_formats do
    run fn actor, _facts ->
      # Simulated format validation
      {:ok, Map.put(actor, :formats_valid, true)}
    end
  end

  primitive :sanitize_values do
    run fn actor, _facts ->
      data = Map.get(actor, :extracted_data, %{})
      sanitized = Enum.into(data, %{}, fn {k, v} ->
        {k, String.trim(to_string(v))}
      end)
      {:ok, Map.put(actor, :extracted_data, sanitized)}
    end
  end

  primitive :store_results do
    run fn actor, _facts ->
      data = Map.get(actor, :extracted_data, %{})
      IO.puts("[Scraper] Storing result: #{inspect(data)}")
      {:ok, Map.put(actor, :stored, true)}
    end
  end

  primitive :set_backoff_delay do
    run fn actor, _facts ->
      delay = Map.get(actor, :pending_args, [1]) |> List.first()
      IO.puts("[Scraper] Setting backoff delay: #{delay}s")
      {:ok, Map.put(actor, :backoff_delay, delay)}
    end
  end

  primitive :wait_for_cooldown do
    run fn actor, _facts ->
      delay = Map.get(actor, :backoff_delay, 1)
      IO.puts("[Scraper] Waiting #{delay}s...")
      Process.sleep(delay * 100)  # Shortened for demo
      {:ok, actor}
    end
  end

  primitive :clear_rate_limit_flag do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :rate_limited, false)}
    end
  end

  primitive :increment_retry_count do
    run fn actor, _facts ->
      count = Map.get(actor, :retry_count, 0)
      {:ok, Map.put(actor, :retry_count, count + 1)}
    end
  end

  primitive :set_target_source do
    run fn actor, _facts ->
      source = Map.get(actor, :pending_args, []) |> List.first()
      tried = Map.get(actor, :tried_sources, [])
      {:ok, Map.merge(actor, %{
        current_source: source,
        tried_sources: [source | tried]
      })}
    end
  end

  primitive :fetch_from_alternative do
    run fn actor, _facts ->
      source = Map.get(actor, :current_source)
      IO.puts("[Scraper] Fetching from alternative: #{source}")
      {:ok, Map.put(actor, :last_response, "alternative data")}
    end
  end

  primitive :normalize_api_response do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :normalized, true)}
    end
  end

  primitive :normalize_html_data do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :normalized, true)}
    end
  end

  primitive :normalize_feed_data do
    run fn actor, _facts ->
      {:ok, Map.put(actor, :normalized, true)}
    end
  end

  primitive :fail_no_sources do
    run fn _actor, _facts ->
      {:error, :no_sources_available}
    end
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp simulate_fetch(url) do
    # Simulate various responses for demo
    cond do
      String.contains?(url, "rate-limit") ->
        {:error, :rate_limited}

      String.contains?(url, "error") ->
        {:error, :connection_failed}

      true ->
        {:ok, "<html><title>Product Page</title></html>", 200}
    end
  end
end
