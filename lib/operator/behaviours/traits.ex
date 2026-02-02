defmodule Operator.Traits do
  @moduledoc """
  Behaviour for agent traits/genome integration.

  Implement this behaviour to integrate NPC personality traits, genetic
  attributes, or other agent-specific data with HTN goal selection.

  ## Configuration

      config :operator,
        traits_module: MyApp.OperatorTraits

  ## Example Implementation

      defmodule MyApp.OperatorTraits do
        @behaviour Operator.Traits

        @impl true
        def traits(genome) do
          # Return list of trait atoms from genome data
          Map.get(genome, :traits, [])
        end

        @impl true
        def trait_affinity_score(genome, metadata) do
          # Score how well agent's traits match goal metadata
          weights = Map.get(metadata, :trait_weights, %{})

          genome
          |> traits()
          |> Enum.reduce(0, fn trait, acc ->
            acc + Map.get(weights, trait, 0)
          end)
        end

        @impl true
        def archetype_affinity_score(genome, metadata) do
          # Score archetype-specific affinity
          archetype = Map.get(genome, :archetype)
          weights = Map.get(metadata, :archetype_weights, %{})
          Map.get(weights, archetype, 0)
        end
      end

  ## Default Implementation

  If no traits module is configured, Operator provides sensible defaults
  that return empty traits and zero scores.
  """

  @type genome :: map() | nil
  @type metadata :: map() | nil

  @doc """
  Return the list of trait atoms for a genome.

  Traits are used in goal selection to weight certain goals higher
  for agents with matching traits.
  """
  @callback traits(genome()) :: [atom()]

  @doc """
  Score how well an agent's traits match goal metadata.

  Returns a numeric bonus to add to goal priority scoring.
  """
  @callback trait_affinity_score(genome(), metadata()) :: number()

  @doc """
  Score archetype-specific affinity.

  Archetypes are higher-level categorizations (e.g., "warrior", "thief")
  that can influence goal selection.
  """
  @callback archetype_affinity_score(genome(), metadata()) :: number()

  @doc """
  Get the configured traits module.
  """
  @spec get_module() :: module() | nil
  def get_module do
    Application.get_env(:operator, :traits_module)
  end

  @doc """
  Get traits for a genome, using configured module or defaults.
  """
  @spec traits(genome()) :: [atom()]
  def traits(genome) do
    case get_module() do
      nil -> default_traits(genome)
      module -> module.traits(genome)
    end
  end

  @doc """
  Calculate trait affinity score, using configured module or defaults.
  """
  @spec trait_affinity_score(genome(), metadata()) :: number()
  def trait_affinity_score(genome, metadata) do
    case get_module() do
      nil -> default_trait_affinity_score(genome, metadata)
      module -> module.trait_affinity_score(genome, metadata)
    end
  end

  @doc """
  Calculate archetype affinity score, using configured module or defaults.
  """
  @spec archetype_affinity_score(genome(), metadata()) :: number()
  def archetype_affinity_score(genome, metadata) do
    case get_module() do
      nil -> default_archetype_affinity_score(genome, metadata)
      module -> module.archetype_affinity_score(genome, metadata)
    end
  end

  # Default implementations

  defp default_traits(nil), do: []
  defp default_traits(genome), do: Map.get(genome, :traits, [])

  defp default_trait_affinity_score(genome, metadata) do
    weights = metadata_trait_weights(metadata)

    genome
    |> default_traits()
    |> Enum.reduce(0, fn trait, acc ->
      acc + Map.get(weights, trait, 0)
    end)
  end

  defp default_archetype_affinity_score(genome, metadata) do
    archetype = genome |> ensure_map() |> Map.get(:archetype)
    weights = metadata_archetype_weights(metadata)
    Map.get(weights, archetype, 0)
  end

  defp metadata_trait_weights(nil), do: %{}

  defp metadata_trait_weights(metadata) do
    metadata
    |> Map.get(:trait_weights, %{})
    |> to_map()
  end

  defp metadata_archetype_weights(nil), do: %{}

  defp metadata_archetype_weights(metadata) do
    metadata
    |> Map.get(:archetype_weights, %{})
    |> to_map()
  end

  defp to_map(value) when is_map(value), do: value
  defp to_map(value) when is_list(value), do: Map.new(value)
  defp to_map(_), do: %{}

  defp ensure_map(nil), do: %{}
  defp ensure_map(map), do: map
end
