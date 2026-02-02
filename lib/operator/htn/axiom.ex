defmodule Operator.HTN.Axiom do
  @moduledoc """
  Reusable query patterns for HTN preconditions.

  Inspired by Decima's HTN implementation, axioms allow you to define
  named, parameterized query patterns that can be reused across multiple
  goals and tasks.

  ## Usage

  Define axioms in your HTN module:

      defmodule MyGame.Behavior do
        use Operator.HTN.DSL

        # Define a reusable query pattern
        axiom :nearby_enemy do
          fn facts, args ->
            max_distance = Keyword.get(args, :max_distance, 10.0)
            enemies = Facts.get(facts, {:world, :visible_enemies}, [])

            Enum.any?(enemies, fn enemy ->
              Facts.get(facts, {:world, {:distance, enemy}}, 999) <= max_distance
            end)
          end
        end

        # Use the axiom in a precondition
        goal :attack_nearby do
          precond {:axiom, :nearby_enemy, max_distance: 5.0}

          decompose do
            task :engage_enemy
          end
        end
      end

  ## Arguments

  Axioms receive two arguments:
  - `facts` - The current world state
  - `args` - Keyword list of arguments passed when the axiom is invoked

  ## Examples

      # Axiom with no arguments
      axiom :has_weapon do
        fn facts, _args -> Facts.has?(facts, {:self, :weapon}) end
      end

      # Axiom with arguments
      axiom :health_above do
        fn facts, args ->
          threshold = Keyword.get(args, :threshold, 50)
          Facts.get(facts, {:self, :health}, 0) > threshold
        end
      end

      # Usage in preconditions
      precond {:axiom, :has_weapon}
      precond {:axiom, :health_above, threshold: 75}

  ## Registration

  Axioms defined in DSL modules are automatically registered with the
  `Operator.HTN.Registry` alongside goals, tasks, and primitives.

  """

  defstruct [:name, :query_fn, :metadata]

  @type t :: %__MODULE__{
          name: atom(),
          query_fn: (Operator.HTN.Facts.t(), keyword() -> boolean()),
          metadata: map()
        }

  @doc """
  Create a new axiom.

  ## Arguments

  - `name` - The axiom identifier
  - `query_fn` - A function of arity 2: `fn facts, args -> boolean end`
  - `opts` - Options:
    - `:metadata` - Arbitrary metadata map

  ## Examples

      iex> alias Operator.HTN.Axiom
      iex> axiom = Axiom.new(:has_energy, fn _facts, _args -> true end)
      iex> axiom.name
      :has_energy

  """
  @spec new(atom(), function(), keyword()) :: t()
  def new(name, query_fn, opts \\ []) when is_atom(name) and is_function(query_fn, 2) do
    %__MODULE__{
      name: name,
      query_fn: query_fn,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Evaluate an axiom against facts with the given arguments.

  ## Examples

      iex> alias Operator.HTN.{Axiom, Facts}
      iex> axiom = Axiom.new(:energized?, fn facts, _args -> Facts.get(facts, {:self, :energy}, 0) > 0 end)
      iex> facts = Facts.from_perception(%{self: %{energy: 10}})
      iex> Axiom.evaluate(axiom, facts, [])
      true

  """
  @spec evaluate(t(), Operator.HTN.Facts.t(), keyword()) :: boolean()
  def evaluate(%__MODULE__{query_fn: query_fn}, facts, args) do
    query_fn.(facts, args)
  end
end
