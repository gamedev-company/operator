# Web Scraper Example

Using Operator for intelligent web scraping with retry strategies,
fallback sources, and adaptive behavior.

## Use Case

This example demonstrates how HTN planning can be applied to non-game
scenarios. A web scraper that:

1. Handles multiple data sources with fallbacks
2. Implements intelligent retry strategies
3. Adapts to rate limiting
4. Maintains session state
5. Validates and transforms data

## Key Concepts

### Goals as Data Acquisition Objectives

```elixir
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
end
```

### Tasks as Workflow Steps

```elixir
task :fetch_page do
  # Dynamically choose fetch strategy based on state
  decompose fn facts ->
    if Facts.get(facts, {:self, :rate_limited}, false) do
      [{:wait_for_cooldown, []}, {:fetch_with_proxy, []}]
    else
      [{:direct_fetch, []}]
    end
  end
end
```

### Primitives as HTTP Operations

```elixir
primitive :direct_fetch do
  run fn actor, facts ->
    url = Facts.get(facts, {:self, :target_url})

    case HTTPClient.get(url, headers: actor.headers) do
      {:ok, response} ->
        {:ok, Map.put(actor, :last_response, response)}

      {:error, :rate_limited} ->
        {:error, :rate_limited}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Axioms for Reusable Checks

```elixir
axiom :can_retry do
  fn facts, args ->
    max_retries = Keyword.get(args, :max, 3)
    current = Facts.get(facts, {:self, :retry_count}, 0)
    current < max_retries
  end
end

axiom :response_valid do
  fn facts, _args ->
    status = Facts.get(facts, {:self, :last_status}, 0)
    status >= 200 and status < 300
  end
end
```

## Running

```bash
cd examples/web_scraper
mix deps.get
iex -S mix

WebScraper.Example.run()
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Scraping Job                        │
│  ┌─────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │ Target  │  │   Session   │  │   Results   │  │
│  │  URLs   │  │    State    │  │   Storage   │  │
│  └─────────┘  └─────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│            Goal: scrape_product_data             │
├─────────────────────────────────────────────────┤
│  1. prepare_session                              │
│  2. fetch_page                                   │
│     ├─ direct_fetch OR                          │
│     └─ fetch_with_proxy (if rate limited)       │
│  3. extract_data                                 │
│  4. validate_data                                │
│  5. store_results                                │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│           Retry/Fallback on Failure             │
│  ┌─────────────────────────────────────────┐    │
│  │ If rate_limited:                        │    │
│  │   → Goal: handle_rate_limit             │    │
│  │   → Wait, then retry with proxy         │    │
│  ├─────────────────────────────────────────┤    │
│  │ If source_unavailable:                  │    │
│  │   → Goal: try_alternative_source        │    │
│  │   → Switch to backup API                │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

## Why HTN for Web Scraping?

1. **Declarative Error Handling**: Define recovery strategies as goals
2. **Adaptive Behavior**: Decomposition can change based on state
3. **Clear Workflow**: Goals make the scraping logic explicit
4. **Testable**: Each primitive is independently testable
5. **Observable**: Tracing shows exactly what decisions were made
