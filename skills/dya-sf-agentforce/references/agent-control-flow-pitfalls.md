# Agent Script Control Flow Pitfalls — Reference (Winter '27 / API v68.0)

Constructs that compile and deploy, then behave differently from how they read; check here before debugging an agent that "ignores" its script.

The syntax is in `references/agent-script.md`; the patterns that avoid these traps are in
`references/agent-script-patterns.md`. Most entries fail **quietly**, with no error at authoring time.

## Prompt text versus logic

### A bare `@variables.x` inside a `|` block passes its name, not its value

Use `{!@variables.x}` inside every `|` block.

```agentscript
reasoning:
    instructions: ->
        | Summarise the member's loans: @variables.loan_summary          ❌
        | Summarise the member's loans: {!@variables.loan_summary}       ✅
```

The model receives the literal characters `@variables.loan_summary` and usually invents a plausible answer around them,
so the defect looks like a quality problem rather than a wiring one. The same applies to tools: `{!@actions.renew_loan}`.

### `|` after `instructions:` makes everything prose

`instructions: |` is a static prompt. An `if` written under it is sent to the model as text and never evaluated. Use
`instructions: ->` whenever the block holds any logic.

```agentscript
instructions: |
    if @variables.is_verified == True:            ❌ text, not a condition
instructions: ->
    if @variables.is_verified == True:            ✅
        | Offer account changes.
```

### Indentation inside a `|` block is prose, not scope

Keep deterministic statements outside `|` blocks.

```agentscript
if @variables.needs_case == True:
    | Tell the member a case will be opened.
      run @actions.create_case                    ❌ text inside the prompt, never executed
    run @actions.create_case                      ✅ statement inside the if
```

A line without `|` after a prompt line continues that prompt fragment. Repeating `|` on adjacent lines is valid but
creates no steps, stages or priority. Words such as "call", "set" or "stop" in prompt text are requests to the model,
not statements.

### Prompt wording cannot enforce a rule

"NEVER", "ALWAYS" and capitals raise the odds, not the guarantee. Put every rule whose violation matters in an `if`,
an `available when`, or a transition.

## Tools and availability

### A tool is callable whenever it is available, mentioned or not

Mentioning a tool only under one `|` branch does not hide it on the other branch. Tool availability is decided by
`available when` alone.

```agentscript
if @variables.is_verified == True:
    | Offer {!@actions.cancel_hold}.               ❌ tool still callable when unverified
actions:
    cancel_hold: @actions.cancel_hold
        available when @variables.is_verified == True   ✅
```

### A tool stays available after it succeeds

Without a gate the model can call a create or send tool again on a later turn or loop iteration. Gate one-shot tools
on the state their success writes (`available when @variables.hold_id == ""`) and tell the model what to do with the
result.

### Bound inputs can hide a tool

A tool with inputs bound to variables is offered only once those values are known. When a tool "never gets called",
check whether a bound variable is still empty; slot-fill the input instead (`with x = ...`) if the model should
supply it.

### Slot filling does not reach chained or deterministic actions

`with x = ...` works on a tool input the model calls. On a `run` (in instructions, in `after_reasoning`, or chained
under a tool) the runtime has no one to ask: bind every required input explicitly.

### Utilities return nothing

`@utils.transition to`, `@utils.escalate` and `@utils.end_session` have no `@outputs`. A `set ... = @outputs.x`
under them is meaningless. Record state with a `set` before the transition instead.

## Variables and data

### `@outputs` and `@inputs` are short-lived

Read `@outputs.x` only in the `set` / `if` lines directly under the `run` or tool that produced it, and `@inputs.x`
only in `with` lines. Copy anything needed later into a variable.

### `is None` and `== ""` are different tests

A string defaulted to `""` is never `None`; an undeclared default is never `""`. Match the test to the default, or test
both: `if @variables.member_id is None or @variables.member_id == "":`.

### `json_path` returns a wrapped value

`json_path(@variables.accounts, "$[0].data.Name")` yields `["Acme"]`, not `Acme`. Comparing or displaying it as a
scalar fails silently. Use `@variables.accounts[0].data.Name`.

### Lowercase booleans

`true` / `false` are not booleans. Write `True` / `False` in defaults and comparisons.

### Linked variables are read-only

A linked variable cannot have a default and cannot be set by a `set`, a tool, or slot filling. Declare a separate
`mutable` variable for anything the agent writes.

### Connected subagent inputs go one way

Values bound in a `connected_subagent` `inputs` block reach the connected agent; nothing it sets comes back. Design the
orchestrator so it never waits on a value from the connected agent.

## Conditionals

### `elif` does not exist

Write `else if`. `elif` fails validation.

### Nested `if` is unsupported

Do not place an `if` inside the body of another `if`, `else if` or `else`. Flatten with compound predicates
(`and` / `or`), an `else if` chain, or sequential top-level `if` statements.

```agentscript
if @variables.is_verified == True:
    if @variables.fines_due > 0:                                    ❌
if @variables.is_verified == True and @variables.fines_due > 0:     ✅
```

### Sequential `if` statements can both fire

Independent `if` statements each evaluate; overlapping predicates append both prompts or run both actions. Use an
`else if` chain when exactly one branch must win, and check that no two conditions in a chain repeat.

### A comment-only branch is an empty branch

Comments are stripped, so an `if` whose body is only `# TODO` compiles to a no-op and swallows the path. Put at least one
`|`, `run`, `set` or `transition to` in every branch.

## Transitions and lifecycle

### A transition discards everything resolved before it

Prompt text assembled before a `transition to` is dropped, and actions already run still cost time and money.
Put guarding transitions first. The abandoned subagent's `after_reasoning` does not run.

### `transition to` versus `@utils.transition to`

`@utils.transition to` is a **tool** and belongs only in `reasoning.actions`. Logic (instructions, `before_reasoning`,
`after_reasoning`, under a `run` or tool) uses bare `transition to`. Swapping them fails validation.

### Re-entry starts at the top

A transition back to a subagent resumes nowhere: it runs from `before_reasoning` and the first instruction again.
Guard one-time work on state so re-entry does not repeat it.

### `before_reasoning` runs on every execution, not once per turn

A transition, including one back into the same subagent, starts another execution inside the same user turn. Guard
every assignment so it initialises once instead of erasing state gathered earlier.

```agentscript
before_reasoning:
    set @variables.attempts = 0                ❌ resets on every re-entry
    if @variables.attempts is None:
        set @variables.attempts = 0            ✅ initialises once
```

### A transition can replay the same utterance

When one subagent finishes a gate and transitions (often from `after_reasoning`) into another, the target runs in the
same turn against the message that completed the gate, not a fresh request. A router reached this way can re-route the
old message. Make the target handle that arrival (greet and ask how to help) or transition only when the target has
the state it needs.

### Deterministic statements do not pause for the model

The whole resolution phase runs before the model sees anything. A `|` line between a `run` and a following `set` does
not let the model act in between, so logic expecting the model's answer there reads stale state. Split the work at a
real boundary: a tool the model calls, `after_reasoning`, or a guarded transition into the next step.

### `after_reasoning` is per request, not per tool call

It runs once the reasoning loop exits, after any number of tool calls, and only if the subagent was not left by a
transition. Logic that must follow one specific tool belongs under that tool (chained `run` or `transition to`).

### Transition loops

Two subagents whose logic sends each to the other can loop indefinitely. Make at least one of the two transitions depend
on state the other changes.

### Entry point assumptions

The guide states every utterance starts at `start_agent`; `config.runtime.reset_to_initial_node` (default `False`) is
documented as resuming the previous subagent instead. Make the router's deterministic transitions state-guarded so either
behaviour is safe, and read a preview trace to see which one the agent follows.

## Blocks and configuration

### A `system` block is declarative

`system.instructions` is prompt text. `instructions: ->`, `run`, `set`, `if` and `transition to` are illegal anywhere in
a `system` block; put logic in `before_reasoning` or the subagent body.

### A subagent system override replaces, it does not merge

A subagent's `system.instructions` stands in for the global text entirely. Any safety or scope rule omitted from the
override is gone for that subagent.

### EinsteinHyperClassifier limits the subagent using it

A subagent on `model://sfdc_ai__DefaultEinsteinHyperClassifier` cannot use `before_reasoning` or `after_reasoning` and
can call only `@utils.transition to`. Move other logic to the subagents it routes to.

### Employee agents reject service-only constructs

On `AgentforceEmployeeAgent`, an `access.default_agent_user`, a `connection messaging` block, `@utils.escalate`, or a
`@MessagingSession` linked variable makes publish and preview fail with an uninformative internal error. Remove them.

### `@utils.escalate` needs a route

Without a `connection messaging` block naming an Omni-Channel flow (`flow://` prefix), escalation has nowhere to go.
`escalate` is also reserved and cannot name a subagent or action.

### The last line of the file

Agentforce Builder can report an unexpected error on the final line; end the file with a blank line.

## Model output is not evidence a side effect happened

When an action reaches an external system, verify the whole chain rather than trusting the transcript:

```text
configured -> available -> invoked -> executed -> effected
```

- **configured**: the action is defined in the subagent and exposed or run.
- **available**: no `available when` excluded it at that moment.
- **invoked**: the model chose it, or the runtime ran it.
- **executed**: it ran without error.
- **effected**: the target system changed.

"I've reserved that for you" establishes none of these: it is generated text, and a confidently wrong claim is the
normal failure mode. Advance workflow state only from an action output (pattern "collect then commit" in
`references/agent-script-patterns.md`), and check the record or the trace (`references/observability.md`).
