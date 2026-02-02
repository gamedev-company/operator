defmodule Operator.HTN.DSL do
  @moduledoc """
  Domain-specific language for defining HTN goals, tasks, and primitives.

  The DSL provides a declarative way to define agent behaviors that compile
  into efficient runtime structures. This is the primary way to define HTN
  domains in Operator.

  ## Important: Alias Scope in Functions

  **Functions inside `precond` and `decompose` are evaluated at runtime, not
  compile time.** This means module aliases from your module's header are NOT
  available inside these functions.

  ### This will FAIL at runtime:

      defmodule MyBehavior do
        use Operator.HTN.DSL

        alias Operator.HTN.Facts  # This alias is NOT available in precond!

        goal :my_goal do
          precond fn facts ->
            Facts.get(facts, {:self, :ready})  # FAILS - Facts not in scope
          end
        end
      end

  ### Use full module paths instead:

      defmodule MyBehavior do
        use Operator.HTN.DSL

        goal :my_goal do
          precond fn facts ->
            Operator.HTN.Facts.get(facts, {:self, :ready})  # Works!
          end
        end
      end

  This limitation exists because the anonymous functions are stored as AST
  and compiled at runtime when the module is registered. The runtime
  compilation context doesn't have access to your module's compile-time
  aliases.

  ## Quick Start

      defmodule MyGame.NPCBehavior do
        use Operator.HTN.DSL

        # High-level objective
        goal :find_food do
          precond fn facts ->
            Operator.HTN.Facts.get(facts, {:self, :hunger}, 0) > 50
          end

          decompose do
            task :locate_food
            task :move_to_food
            task :eat_food
          end

          metadata priority: 5, domain: :survival
        end

        # Intermediate task with dynamic decomposition
        task :locate_food do
          precond fn facts ->
            not Operator.HTN.Facts.has?(facts, {:self, :food_location})
          end

          decompose fn facts ->
            nearby = Operator.HTN.Facts.get(facts, {:world, :food_sources}, [])
            [{:search_for_food, [List.first(nearby)]}]
          end

          cost 2.0
        end

        # Directly executable action
        primitive :eat_food do
          run fn actor, _facts ->
            # Your execution logic here
            {:ok, %{actor | hunger: 0}}
          end

          metadata action_type: :consume, duration: 1000
        end
      end

  ## DSL Elements

  ### Goals

  Goals are high-level objectives that an agent can pursue:

      goal :goal_name do
        # Optional precondition (must be true to pursue goal)
        precond fn facts -> boolean end

        # Static task sequence
        decompose do
          task :first_task
          task :second_task, "arg1", :arg2
        end

        # Optional metadata
        metadata priority: 5, category: :combat
      end

  ### Tasks

  Tasks are intermediate steps that can decompose into subtasks:

      task :task_name, arg1, arg2 do
        # Optional precondition
        precond fn facts -> boolean end

        # Dynamic decomposition based on world state
        decompose fn facts ->
          [{:subtask_a, []}, {:subtask_b, [some_value]}]
        end

        # Optional cost for planning heuristics
        cost 1.5

        # Optional metadata
        metadata category: :movement
      end

  ### Primitives

  Primitives are directly executable actions:

      primitive :action_name, target do
        # Execution function
        run fn actor, facts ->
          # Perform the action
          {:ok, updated_actor}
        end

        # Optional metadata
        metadata action_type: :attack, animation: "strike"
      end

  ### Axioms

  Axioms are reusable query patterns (inspired by Decima's HTN):

      axiom :enemy_nearby do
        fn facts, args ->
          max_dist = Keyword.get(args, :max_distance, 10)
          enemy_dist = Operator.HTN.Facts.get(facts, {:world, :enemy_distance}, 999)
          enemy_dist <= max_dist
        end
      end

      # Use in preconditions:
      precond {:axiom, :enemy_nearby, max_distance: 5}

  ## Precondition Operators

  Preconditions support logical operators:

      # AND (all must be true)
      precond {:all, [fn1, fn2, fn3]}

      # OR (any must be true)
      precond {:any, [fn1, fn2]}

      # ALT (first matching, with preference order)
      precond {:first, [preferred_fn, fallback_fn]}

      # NOT (negation)
      precond {:not, fn facts -> ... end}

      # Axiom reference
      precond {:axiom, :axiom_name, args}

  ## Auto-Registration

  Modules using this DSL are automatically registered with `Operator.HTN.Registry`
  after compilation. To disable:

      use Operator.HTN.DSL, auto_register: false

  ## Compilation

  The DSL uses Elixir macros to transform your definitions into optimized
  runtime structures at compile time. Anonymous functions in preconditions
  and decompose blocks are preserved for runtime evaluation.

  ## See Also

  * `Operator.HTN.Registry` - Where goals/tasks are stored
  * `Operator.HTN.Engine` - How goals are expanded into plans
  * `Operator.HTN.Precondition` - Logical operators
  * `Operator.HTN.Axiom` - Reusable queries

  """

  alias Operator.HTN.DSL.Builder

  @doc """
  Sets up the module to use the HTN DSL.

  ## Options

  * `:auto_register` - Whether to register with `Operator.HTN.Registry` after
    compilation. Defaults to `true`.

  ## Examples

      defmodule MyDomain do
        use Operator.HTN.DSL
        # ...
      end

      # Disable auto-registration (useful for testing)
      defmodule TestDomain do
        use Operator.HTN.DSL, auto_register: false
        # ...
      end

  """
  defmacro __using__(opts) do
    auto_register = Keyword.get(opts, :auto_register, true)

    quote do
      import Operator.HTN.DSL
      Module.register_attribute(__MODULE__, :htn_goals, accumulate: true)
      Module.register_attribute(__MODULE__, :htn_tasks, accumulate: true)
      Module.register_attribute(__MODULE__, :htn_primitives, accumulate: true)
      Module.register_attribute(__MODULE__, :htn_axioms, accumulate: true)
      @before_compile Operator.HTN.DSL

      if unquote(auto_register) do
        @after_compile {Operator.HTN.DSL, :__register_module__}
      end
    end
  end

  @doc """
  Define a goal.

  Goals are high-level objectives that decompose into sequences of tasks.
  They are the entry points for HTN planning.

  ## Parameters

  * `name` - Atom identifier for the goal

  ## Block Contents

  * `precond fn facts -> boolean end` - Optional precondition
  * `decompose do ... end` - Task sequence
  * `metadata key: value` - Optional metadata

  ## Examples

      goal :patrol do
        precond fn facts ->
          Operator.HTN.Facts.get(facts, {:self, :on_duty}, false)
        end

        decompose do
          task :walk_to_waypoint, :next
          task :scan_area
        end

        metadata priority: 3, domain: :security
      end

  """
  defmacro goal(name, do: block) do
    quote do
      @htn_goals {unquote(name), unquote(Macro.escape(block))}
    end
  end

  @doc """
  Define a task with arguments.

  Tasks are intermediate steps that may decompose into subtasks or primitives.

  ## Parameters

  * `name` - Atom identifier for the task
  * `args` - Variable names for task arguments (captured at definition time)

  ## Block Contents

  * `precond fn facts -> boolean end` - Optional precondition
  * `decompose fn facts -> [{task, args}] end` - Dynamic subtask list
  * `cost number` - Optional planning cost
  * `metadata key: value` - Optional metadata

  ## Examples

      task :move_to, destination do
        precond fn facts ->
          Operator.HTN.Facts.has?(facts, {:self, :can_move})
        end

        decompose fn facts ->
          current = Operator.HTN.Facts.get(facts, {:self, :position})
          [{:navigate, [current, destination]}]
        end

        cost 5.0
        metadata category: :locomotion
      end

  """
  defmacro task(name, args, do: block) do
    quote do
      @htn_tasks {unquote(name), unquote(args), unquote(Macro.escape(block))}
    end
  end

  @doc """
  Define a task without arguments.

  See `task/3` for full documentation.

  ## Examples

      task :scan_area do
        precond fn facts ->
          Operator.HTN.Facts.has?(facts, {:self, :sensors})
        end

        decompose do
          task :rotate_sensors
          task :process_data
        end

        cost 1.0
      end

  """
  defmacro task(name, do: block) do
    quote do
      @htn_tasks {unquote(name), [], unquote(Macro.escape(block))}
    end
  end

  @doc """
  Define a primitive action with arguments.

  Primitives are directly executable actions that don't decompose further.
  They are the "leaves" of the HTN tree.

  ## Parameters

  * `name` - Atom identifier for the primitive
  * `args` - Variable names for action arguments

  ## Block Contents

  * `run fn actor, facts -> {:ok, actor} | {:error, reason} end` - Execution function
  * `metadata key: value` - Optional metadata

  ## Examples

      primitive :fire_weapon, target do
        run fn actor, facts ->
          ammo = Operator.HTN.Facts.get(facts, {:self, :ammo}, 0)

          if ammo > 0 do
            # Your game logic here
            {:ok, %{actor | ammo: ammo - 1}}
          else
            {:error, :no_ammo}
          end
        end

        metadata action_type: :attack, sound: "gunshot.wav"
      end

  """
  defmacro primitive(name, args, do: block) do
    quote do
      @htn_primitives {unquote(name), unquote(args), unquote(Macro.escape(block))}
    end
  end

  @doc """
  Define a primitive action without arguments.

  See `primitive/3` for full documentation.

  ## Examples

      primitive :wait do
        run fn actor, _facts ->
          {:ok, actor}
        end

        metadata action_type: :idle
      end

  """
  defmacro primitive(name, do: block) do
    quote do
      @htn_primitives {unquote(name), [], unquote(Macro.escape(block))}
    end
  end

  @doc """
  Define a reusable query axiom.

  Axioms are named query patterns that can be reused in preconditions.
  Inspired by Decima's HTN implementation.

  ## Parameters

  * `name` - Atom identifier for the axiom

  ## Block Contents

  The block should contain a function with signature:

      fn facts, args -> boolean end

  Where:
  * `facts` - Current world state (`Operator.HTN.Facts.t()`)
  * `args` - Keyword list of arguments passed when invoked

  ## Examples

      axiom :has_clear_shot do
        fn facts, args ->
          target = Keyword.get(args, :target)
          distance = Operator.HTN.Facts.get(facts, {:world, {:distance, target}}, 999)
          cover = Operator.HTN.Facts.get(facts, {:world, {:cover_between, target}}, false)

          distance < 50 and not cover
        end
      end

      # Use in preconditions:
      goal :snipe do
        precond {:axiom, :has_clear_shot, target: :enemy}
        # ...
      end

  """
  defmacro axiom(name, do: query_fn) do
    quote do
      @htn_axioms {unquote(name), unquote(Macro.escape(query_fn))}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    goals =
      Module.get_attribute(env.module, :htn_goals)
      |> Enum.map(&Builder.build_goal/1)

    tasks =
      Module.get_attribute(env.module, :htn_tasks)
      |> Enum.map(&Builder.build_task/1)

    primitives =
      Module.get_attribute(env.module, :htn_primitives)
      |> Enum.map(&Builder.build_primitive/1)

    axioms =
      Module.get_attribute(env.module, :htn_axioms)
      |> Enum.map(&Builder.build_axiom/1)

    quote do
      @doc """
      Returns this module's HTN definitions.

      This function is called by `Operator.HTN.Registry` to collect
      goals, tasks, primitives, and axioms defined in this module.
      """
      @spec __htn__() :: map()
      def __htn__ do
        %{
          goals: unquote(Macro.escape(goals)),
          tasks: unquote(Macro.escape(tasks)),
          primitives: unquote(Macro.escape(primitives)),
          axioms: unquote(Macro.escape(axioms))
        }
      end
    end
  end

  @doc false
  def __register_module__(env, _bytecode) do
    Operator.HTN.Registry.register(env.module)
  rescue
    _ -> :ok
  end
end
