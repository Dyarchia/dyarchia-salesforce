# Agent Script — Reference (Winter '27 / API v68.0)

This file is the syntax of Agent Script, the language behind Agentforce Builder.

## Logic versus prompt instructions

- **`->` logic instructions** run **deterministically**, every time: business rules, running actions,
  setting variables, branching.
- **`|` prompt instructions** are natural language **sent to the LLM**, which interprets them and
  decides how to respond.

```agentscript
reasoning:
    instructions: ->
        if @variables.isPremiumUser:
            | ask the user if they want to redeem their Premium points
        else:
            | ask the user if they want to upgrade to Premium service
```

## Language shape

**Compiled.** Saving an agent version compiles the script into the lower-level metadata the reasoning
engine runs. Syntax errors surface at save time, not conversation time.

**Property-based.** Everything is `key: value`. Top-level properties are called **blocks**.

**Whitespace-sensitive**, like Python or YAML. Indent at least 2 spaces or 1 tab to nest, and **pick
one and never mix** — mixing spaces and tabs is a parse error.

**Comments** start with `#` and run to end of line.

## Referencing things

The `@` symbol reaches every resource:

| Reference | What it points at |
|---|---|
| `@actions.<name>` | An action |
| `@subagent.<name>` | A subagent |
| `@variables.<name>` | A variable |
| `@outputs.<name>` | An action's output |
| `@utils.<name>` | A built-in utility |

Bare `@variables.x` works in logic instructions; inside **prompt text** it must be `{!@variables.x}`:

```agentscript
| Ask the user this question: {!@variables.my_question}
```

## Running an action

`run` executes, `with` passes inputs, `set` captures outputs:

```agentscript
run @actions.get_account_info
    with account_id=@variables.account_id
    set @variables.hotel_code=@outputs.hotel_code
```

## The blocks

### `system` — agent-wide instructions and messages

The `messages` block is **optional**. Define `welcome` or `error` when a target or use case needs
custom copy, and validate them against that target; otherwise omit the block rather than padding it
with placeholder text.

Keep a `system` block **declarative**; put logic in `before_reasoning` or the subagent body.
`instructions` is prompt text, and `->` logic, `run`, `set`, `if` and `transition` are all illegal
inside it.

```agentscript
system:
    instructions:|
        You are an AI agent. Have a friendly conversation with the user.
    messages:
        welcome:|
            Welcome {!@variables.userPreferredName}! I'm your personal shopping assistant.
        error: "Whoops!"
```

### `config` — identity and runtime behaviour

| Parameter | Notes |
|---|---|
| `developer_name` | The API name. Max 80 chars, starts with a letter, alphanumeric and underscores only, no trailing or consecutive underscores, unique in the org. **Must match the `aiAuthoringBundles/<dir>` name exactly** or the deploy fails |
| `agent_label` | Optional display label; generated from `developer_name` if omitted |
| `description` | The agent's goals and purpose |
| `role`, `company` | Optional framing for the LLM |
| `agent_type` | `AgentforceServiceAgent` (default) or `AgentforceEmployeeAgent` |
| `enable_enhanced_event_logs` | `True` / `False`, default `False`. Conversation logging for debugging |
| `runtime`, `file_upload` | Sub-blocks for streaming, citations, groundedness checks, and uploaded-file handling |

Put `default_agent_user` in the `access` block; it is **deprecated here**.

`agent_type` is not cosmetic; each value forbids or requires things elsewhere in the file:

| `agent_type` | Rules |
|---|---|
| `AgentforceEmployeeAgent` | **Must NOT** carry `access.default_agent_user`, an escalation subagent using `@utils.escalate`, or a `connection messaging:` block |
| `AgentforceServiceAgent` | **Requires** `access.default_agent_user`, on a user with an Einstein Agent licence |

`label:` is also an optional block on both `start_agent` and `subagent`, giving a human-readable
display name, distinct from the top-level `config.agent_label`.

Write new `.agent` files with **4 spaces** per indent level.

### `access` — who the agent runs as

```agentscript
access:
    default_agent_user: "service@example.com"
```

**This is the security boundary**: the agent runs in that user's context, and their permissions
decide what it can reach. See `dya-sf-permissions`.

### `variables` — state that does not depend on LLM memory

```agentscript
variables:
    string_var: mutable string = "hello world"
    isPremiumUser: mutable boolean = False
        description: "Indicates whether the user is a premium user."
```

### `subagent` — a bounded job, with its own reasoning and actions

Blocks go in a fixed order: `label` (optional) → `description` (required) → `system` (optional) →
**`before_reasoning`** (optional) → `reasoning` (required) → **`after_reasoning`** (optional) →
`actions` (optional). The two reasoning hooks run either side of the reasoning phase;
`before_reasoning` runs once per *execution*, which a self-transition restarts within the same turn.
See `references/agent-control-flow-pitfalls.md`.

Branch with **`else if`**; `elif` is a syntax error. Flatten every user-written **nested `if`**
with `else if`, with `and` / `or` predicates, or with sequential top-level `if` statements; it is
unsupported and lint rejects it as `unsupported-nested-if`.

```agentscript
subagent Order_Management:
    description: "Handles order lookup, order updates, and summaries."

    reasoning:
        instructions: ->
            if @variables.order_summary == "":
                run @actions.lookup_current_order
                with member_email=@variables.member_email
                set @variables.order_summary=@outputs.order_summary

            | Refer to the user by name {!@variables.member_name}.
              Show their current order summary: {!@variables.order_summary}.

        actions:
            lookup_order: @actions.lookup_order
                with query = ...
                set @variables.order_summary=@outputs.order_summary

    actions:
        lookup_order:
            description: "Retrieve order details."
            inputs:
                query: string
            outputs:
                order_summary: string
                order_id: string
            target: "flow://SvcCopilotTmpl__GetOrdersByContact"
```

Name a subagent in `snake_case`, describing the scope; the name cannot contain spaces, and routing
reads the name and `description`.

**`target`** uses `{TARGET_TYPE}://{DEVELOPER_NAME}` and accepts three types:

- `apex://` — an Apex `@InvocableMethod`
- `flow://` — an autolaunched Flow
- `prompt://` — a Prompt Template

Set `filter_from_agent: True` on an output parameter the script needs but the model should never
see or repeat; it hides the parameter from the agent.

### `start_agent` — the router

Every customer utterance begins here. It is a subagent with the `start_agent` prefix (the "Agent
Router" in Canvas view), and it decides which subagent takes over.

```agentscript
start_agent agent_router:
    description: "Welcome the user and determine the appropriate subagent based on user input"
    reasoning:
        instructions: |
            You are an agent router for this assistant. Welcome the guest
            and analyze their input to determine the most appropriate subagent.
        actions:
            go_to_identity: @utils.transition to @subagent.Identity_Verification
                description: "Verifies user identity"
                available when @variables.verified == False
            go_to_order: @utils.transition to @subagent.Order_Management
                description: "Handles order lookup, refunds, and order updates."
                available when @variables.verified == True
```

**`available when`** gates a route on a deterministic condition, so the LLM cannot route to order
management before identity is verified, however persuasively the customer asks.

## Expressions and operators

Flow control: `if` / `else`, arithmetic (`+`, `-`), comparison (`==`, `!=`, `>`, `<`), and
emptiness with `is None` / `is not None`.

```agentscript
if @variables.count >= 10:
    run @actions.count_achieved_announcement
else:
    run @actions.count_missed_announcement
```

## Built-in utilities

| Util | Use |
|---|---|
| `@utils.transition` | Move to another subagent — the routing primitive |
| `@utils.setVariables` | Let the model fill variables from the conversation (slot filling) |
| `@utils.escalate` | Hand off to a human |

Assign a variable deterministically with the `set` statement, not a utility.

## Where to write it

- **Agentforce Builder, Canvas view** — script summarised into blocks. `/` inserts common expressions, `@` inserts resources.
- **Agentforce Builder, Script view** — direct editing with highlighting, autocompletion and validation.
- **Chat with Agentforce** — describe the behaviour ("if the order total is over $100, offer free shipping") and it generates the subagents, actions and expressions.
- **Agentforce DX + VS Code** — retrieve the script into a DX project and edit it there. See `references/lifecycle-and-api.md`.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| A business rule written as prose after `\|` | Put it after `->` as a condition — prose is a suggestion, logic is a rule |
| Mixing spaces and tabs to indent | Pick one; mixing is a parse error |
| `@variables.x` inside prompt text | `{!@variables.x}` — bare form only works in logic instructions |
| Relying on the LLM to remember state across turns | Declare a variable |
| Routing to a subagent with no `available when` guard | Gate the transition on a deterministic condition |
| A subagent name that describes the mechanism, not the job | Routing reads the name and description; write them for the router |
| `default_agent_user` in the `config` block | It is deprecated there — use the `access` block |
| Returning a sensitive output the agent may repeat | `filter_from_agent: True` |
