# `Operator.HTN.Trace.ConsoleHandler`
[🔗](https://github.com/gamedev-company/operator/blob/v0.1.0/lib/operator/htn/trace/console_handler.ex#L1)

Console-based trace handler for debugging HTN planning.

Prints colored, formatted trace output to the console.

## Usage

    # Enable console tracing
    Operator.HTN.Trace.set_handler(Operator.HTN.Trace.ConsoleHandler)

    # Run your planner
    Operator.HTN.Planner.run(:some_goal, facts, traits)

    # Disable tracing
    Operator.HTN.Trace.reset()

## Output Format

    [HTN] ▶ GOAL acquire_data
    [HTN]   ✓ Precondition passed (goal: acquire_data)
    [HTN]   → TASK ensure_access []
    [HTN]     ✓ Precondition passed (task: ensure_access)
    [HTN]     ⚡ Effect applied: {:self, :has_access} = true
    [HTN]   ← TASK ensure_access → 2 subtasks
    [HTN] ◀ GOAL acquire_data SUCCESS

---

*Consult [api-reference.md](api-reference.md) for complete listing*
