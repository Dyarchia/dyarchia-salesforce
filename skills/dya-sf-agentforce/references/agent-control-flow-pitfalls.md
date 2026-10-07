# Agent Script Control Flow — Where It Goes Wrong

The syntax is in `references/agent-script.md`. This file lists constructs that compile, deploy, then
behave differently from how they read.

Every entry fails *quietly*, with no error at authoring time.

## A bare `@variables.X` inside a `|` block passes its name, not its value

Use `{!@variables.x}`, the merge syntax for a value, inside every `|` block.

```agentscript
reasoning:|
    Summarise this case for the customer: @variables.case_summary        ❌
    Summarise this case for the customer: {!@variables.case_summary}     ✅
```

The model receives the literal characters `@variables.case_summary` and usually invents a plausible
summary around them, so the output looks like a quality problem rather than a wiring one.

The action equivalent, `{!@actions.X}`, names an action to the model inside prompt text.

## Indentation inside a `|` block is prose, not scope

Keep deterministic statements outside `|` blocks.

```agentscript
if @variables.escalate == True
    |
        Tell the customer we are escalating.
        run @actions.create_case                ❌ not inside the `if`
```

Everything after `|` is text. Indenting a statement under it does not put it inside the enclosing
`if`, so the action runs unconditionally.

Related: a line **without** a `|` continues the current prompt fragment. Use **one `|` per contiguous
block**; repeated adjacent `|` markers do not create steps, stages, or any notion of priority.

## `available when` gates action definitions too

Gate every action that has a side effect. Beyond transitions, `available when` also gates whether
an action exists for the model to choose:

```agentscript
actions:
    create_ticket: @actions.create_ticket
        available when @variables.lookup_failed == True
```

Without the guard the model can call the action and was merely not told to; with it, the action is
not on the menu.

## `before_reasoning` runs once per subagent *execution*, not per turn

Guard every assignment in `before_reasoning` so it initialises once. A transition — **including a self-transition** — starts another execution inside the same user turn,
so an unconditional assignment in `before_reasoning` re-runs and silently erases state gathered
earlier in that turn.

```agentscript
before_reasoning:
    set @variables.attempts = 0          ❌ resets on every self-transition
    if @variables.attempts == null
        set @variables.attempts = 0      ✅ initialises once
```

## Deterministic statements do not pause for the model

Use a **guarded self-transition** as the phase boundary; it is the supported one. A `|` block between a `run` and a following `set` does **not** create a turn boundary. The whole
sequence executes before the model sees anything, so code expecting the user to have answered in
between runs against stale state.

## A `system` block is declarative

Put logic in `before_reasoning` or the subagent's own body, never in a `system` block.
`system.instructions` is prompt text, not a procedure. `instructions: ->`, `run`, `set`, `if` and
`transition` are all illegal inside a `system` block.

## Model output is not evidence a side effect happened

When an action reaches an external system, verify the whole chain rather than trusting the
transcript:

```text
configured → available → invoked → executed → effected
```

- **configured** — the action exists and is wired to the subagent.
- **available** — no `available when` guard excluded it for this turn.
- **invoked** — the agent chose it.
- **executed** — it ran without throwing.
- **effected** — the external system changed.

An agent saying "I've created that ticket for you" establishes none of these: it is generated text,
and a confidently wrong claim is the normal failure mode. Check the target system or the trace.

## `elif` does not exist

Write `else if`, the supported spelling. `elif` is a syntax error.

## Nested `if` is unsupported

Flatten every nested `if` with `else if`, with compound predicates (`and` / `or`), or with
sequential top-level `if` statements. Agentforce lint rejects a user-written nested `if` with
**`unsupported-nested-if`**.
