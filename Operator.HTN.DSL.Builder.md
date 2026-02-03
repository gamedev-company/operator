# `Operator.HTN.DSL.Builder`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/dsl/builder.ex#L1)

Builds runtime structures from DSL AST.

This module transforms the compile-time AST captured by `Operator.HTN.DSL`
macros into data structures that can be stored in the compiled module. It's
the bridge between Elixir's macro system and Operator's runtime planning.

## Why This Module Exists

When you write DSL code like:

    goal :attack do
      precond fn facts -> Facts.get(facts, {:self, :armed}) end
      decompose do
        task :aim
        task :fire
      end
    end

The `goal` macro captures this as AST (Abstract Syntax Tree). But we can't
just store raw AST - we need structured data that the planner can work with
efficiently at runtime.

This module handles that transformation:

1. **Parses** the captured AST blocks
2. **Extracts** preconditions, decompose functions, costs, metadata
3. **Builds** `%Task{}` structs and goal maps
4. **Preserves** function AST for runtime compilation

## AST Preservation

Anonymous functions cannot be escaped with `Macro.escape/1` and stored
directly in module attributes. Instead, we store them as quoted AST and
compile them at runtime when needed (see `Operator.HTN.Executor`).

This is why you'll see patterns like:

    %Task{
      preconditions: [{:fn, _, _clauses}],  # Stored as AST
      decompose: {:fn, _, _clauses}          # Stored as AST
    }

## Internal Module

This module is considered internal to the DSL implementation. Users should
interact with `Operator.HTN.DSL` macros rather than calling these functions
directly.

## See Also

* `Operator.HTN.DSL` - The public macro interface
* `Operator.HTN.Task` - The runtime task structure
* `Operator.HTN.Registry` - Where built structures are stored

# `build_axiom`

```elixir
@spec build_axiom({atom(), any()}) :: map()
```

Build an axiom map from captured DSL AST.

Transforms the AST captured by the `axiom` macro into a map structure.
Axioms are reusable query patterns that can be referenced in preconditions.

## Parameters

* `{name, query_fn_ast}` - Tuple of axiom name and the query function AST

## Returns

A map with:

* `:name` - Axiom identifier atom
* `:query_fn` - The query function AST

## Axiom Functions

Axiom functions have the signature:

    fn facts, args -> boolean end

Where `args` is a keyword list of arguments passed when the axiom is
invoked in a precondition.

## Example

Given this DSL input:

    axiom :enemy_in_range do
      fn facts, args ->
        max_range = Keyword.get(args, :range, 10)
        enemy_dist = Facts.get(facts, {:world, :enemy_distance}, 999)
        enemy_dist <= max_range
      end
    end

Used in preconditions as:

    precond {:axiom, :enemy_in_range, range: 5}

# `build_goal`

```elixir
@spec build_goal({atom(), any()}) :: map()
```

Build a goal map from captured DSL AST.

Transforms the AST captured by the `goal` macro into a map structure
suitable for storage in the Registry.

## Parameters

* `{name, block}` - Tuple of goal name atom and the captured block AST

## Returns

A map with the following keys:

* `:name` - Goal identifier atom
* `:precond` - Precondition function AST, or `nil` if none specified
* `:decompose` - List of `{task_name, args}` tuples from the decompose block
* `:metadata` - Map of user-defined metadata

## Example Transformation

Given this DSL input:

    goal :infiltrate do
      precond fn facts -> Facts.get(facts, {:self, :stealthy}) end
      decompose do
        task :sneak_to, :entrance
        task :pick_lock
      end
      metadata domain: :stealth, priority: 5
    end

This function produces:

    %{
      name: :infiltrate,
      precond: {:fn, _, _},  # AST for the precondition
      decompose: [{:sneak_to, [:entrance]}, {:pick_lock, []}],
      metadata: %{domain: :stealth, priority: 5}
    }

# `build_primitive`

```elixir
@spec build_primitive({atom(), any(), any()}) :: Operator.HTN.Task.t()
```

Build a primitive Task struct from captured DSL AST.

Transforms the AST captured by the `primitive` macro into a `%Task{}`
struct. Primitives are the executable leaf nodes of the HTN tree - they
don't decompose further but instead have a `run` function.

## Parameters

* `{name, args, block}` - Tuple containing:
  * `name` - Primitive identifier atom
  * `args` - List of argument variable names
  * `block` - The captured block AST

## Returns

A `%Task{}` struct with:

* `:name` - Primitive identifier
* `:type` - Always `:primitive`
* `:preconditions` - Empty list (primitives use runtime checks)
* `:decompose` - `nil` (primitives don't decompose)
* `:cost` - Fixed at 1.0
* `:metadata` - Map containing:
  * `:args` - Argument names from definition
  * `:run` - The execution function AST
  * Any user-defined metadata

## Run Function

The `run` function AST is stored in metadata and compiled at execution
time by `Operator.HTN.Executor`. The function signature is:

    fn actor, facts -> {:ok, updated_actor} | {:error, reason} end

## Example

Given this DSL input:

    primitive :fire_weapon, target do
      run fn actor, facts ->
        {:ok, %{actor | ammo: actor.ammo - 1}}
      end
      metadata animation: "shoot", sound: "gunfire.wav"
    end

This function produces a Task with metadata containing both the run
function AST and the user metadata.

# `build_task`

```elixir
@spec build_task({atom(), any(), any()}) :: Operator.HTN.Task.t()
```

Build a Task struct from captured DSL AST.

Transforms the AST captured by the `task` macro into a `%Task{}` struct.
Tasks defined via DSL are always `:abstract` type (they decompose into
other tasks or primitives).

## Parameters

* `{name, args, block}` - Tuple containing:
  * `name` - Task identifier atom
  * `args` - List of argument variable names from the task definition
  * `block` - The captured block AST

## Returns

A `%Task{}` struct with:

* `:name` - Task identifier
* `:type` - Always `:abstract` for DSL tasks
* `:preconditions` - List of precondition function ASTs
* `:decompose` - Either `{:static_tasks, list}` or function AST
* `:cost` - Numeric cost value (default: 1.0)
* `:metadata` - Map including `:args` and user metadata

## Decomposition Modes

Tasks can decompose in two ways:

**Static decomposition** (compile-time known sequence):

    task :prepare_attack do
      decompose do
        task :draw_weapon
        task :aim
      end
    end

Stored as: `{:static_tasks, [{:draw_weapon, []}, {:aim, []}]}`

**Dynamic decomposition** (runtime decision):

    task :move_to, destination do
      decompose fn facts ->
        current = Facts.get(facts, {:self, :position})
        [{:pathfind, [current, destination]}]
      end
    end

Stored as: `{:fn, _, _}` (raw AST for runtime compilation)

---

*Consult [api-reference.md](api-reference.md) for complete listing*
