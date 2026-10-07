# Agent Script Control Flow — Where It Goes Wrong

The Agent Script syntax reference is `references/agent-script.md`. This file is the shorter, more
useful list: constructs that compile, deploy, then behave differently from how they read.

Every entry fails *quietly*, with no error at authoring time.

## A bare `@variables.X` inside a `|` block passes its name, not its value

```agentscript
reasoning:|
    Summarise this case for the customer: @variables.case_summary        ❌
    Summarise this case for the customer: {!@variables.case_summary}     ✅
```

The model receives the literal characters `@variables.case_summary` and usually invents a plausible
summary around them, so the output looks like a quality problem rather than a wiring one.

`{!@variables.x}` is the merge syntax for a value. The action equivalent, `{!@actions.X}`, names an
action to the model inside prompt text.

## Indentation inside a `|` block is prose, not scope

```agentscript
if @variables.escalate == True
    |
        Tell the customer we are escalating.
        run @actions.create_case                ❌ not inside the `if`
```

Everything after `|` is text. Indenting a statement under it does not put it inside the enclosing
`if`, so the action runs unconditionally. Deterministic statements live outside `|` blocks.

Related: a line **without** a `|` continues the current prompt fragment. Use **one `|` per contiguous
block**; repeated adjacent `|` markers do not create steps, stages, or any notion of priority.

## `available when` gates action definitions too

Most examples show it on a transition, so it looks routing-only. It also gates whether an action
exists for the model to choose at all:

```agentscript
actions:
    create_ticket: @actions.create_ticket
        available when @variables.lookup_failed == True
```

That is the difference between an agent that *can* call an action and merely was not told to, and an
agent for which the action is not on the menu. For anything with a side effect, you want the second.

## `before_reasoning` runs once per subagent *execution*, not per turn

A transition — **including a self-transition** — starts another execution inside the same user turn,
so an unconditional assignment in `before_reasoning` re-runs and silently erases state gathered
earlier in that turn.

```agentscript
before_reasoning:
    set @variables.attempts = 0          ❌ resets on every self-transition
    if @variables.attempts == null
        set @variables.attempts = 0      ✅ initialises once
```

## Deterministic statements do not pause for the model

A `|` block between a `run` and a following `set` does **not** create a turn boundary. The whole
sequence executes before the model sees anything, so code expecting the user to have answered in
between runs against stale state.

The supported phase boundary is a **guarded self-transition**.

## A `system` block is declarative

`system.instructions` is prompt text, not a procedure. `instructions: ->`, `run`, `set`, `if` and
`transition` are all illegal inside a `system` block. Logic that wants them belongs in
`before_reasoning` or the subagent's own body.

## Model output is not evidence a side effect happened

When an action reaches an external system, verify the whole chain rather than trusting the
transcript:

```text
configured → available → invoked → executed → effected
```

- **configured** — the action exists and is wired to the subagent.
- **available** — no `available when` guard excluded it for this turn.
- **invoked** — the agent actually chose it.
- **executed** — it ran without throwing.
- **effected** — the external system changed.

An agent saying "I've created that ticket for you" establishes none of these. It is generated text,
and a confidently wrong claim is the normal failure mode. Check the target system or the trace.

## `elif` does not exist

`else if` is the supported spelling. `elif` is a syntax error.

## Nested `if` is unsupported

Agentforce lint rejects a user-written nested `if` with **`unsupported-nested-if`**. Flatten it with
`else if`, with compound predicates (`and` / `or`), or with sequential top-level `if` statements.
