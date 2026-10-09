# Agent Script — Reference (Winter '27 / API v68.0)

The complete Agent Script language: execution model, every block, variables, expressions, statements, tools and utilities.

Patterns built from these pieces: `references/agent-script-patterns.md`. Constructs that compile but misbehave:
`references/agent-control-flow-pitfalls.md`. Action definitions and targets in depth: `references/agent-actions.md`.

## 1. Execution model

Agent Script compiles. Saving a version, validating, or publishing turns the `.agent` file into the metadata the reasoning
engine runs, so syntax errors surface at save or validate time, never mid-conversation.

Every request to a subagent runs in two phases.

**Phase 1, deterministic resolution.** The runtime walks the subagent top to bottom with no LLM involved:

1. `before_reasoning` runs, if present.
2. `reasoning.instructions` resolves line by line: `if` / `else` conditions evaluate, `run` executes actions, `set` assigns
   variables, and each `|` fragment reached is appended to the prompt with its `{!...}` merge fields replaced by values.
3. A `transition to` reached anywhere in this phase stops the current subagent immediately, **discards the prompt built
   so far**, and starts the target subagent from its first line.

**Phase 2, reasoning.** The LLM receives the resolved prompt, the effective system instructions (the subagent's own
`system.instructions` if it has one, otherwise the global one), the conversation history, and the tools in
`reasoning.actions` whose `available when` evaluates true. It answers, calls tools, or both. A tool call runs its
bindings (`with`, `set`, chained `run`, `transition to`), and the LLM can keep calling tools until it stops; that is the
reasoning loop.

**After the loop.** `after_reasoning` runs once the reasoning loop exits, unless a transition already left the subagent.
Then the agent waits for the next utterance.

| Construct | Runs when | Who decides |
|---|---|---|
| `before_reasoning` | Start of every subagent execution, before instructions | Runtime |
| Logic in `reasoning.instructions` (`if`, `run`, `set`, `transition to`) | During resolution, before the LLM sees anything | Runtime |
| `\|` prompt text | Assembled during resolution, read in Phase 2 | LLM interprets |
| Tool in `reasoning.actions` | Only if the LLM calls it during Phase 2 | LLM, within `available when` |
| Chained `run` / `transition to` under a tool | Immediately after that tool runs | Runtime |
| `after_reasoning` | After the reasoning loop exits, every request | Runtime |

Transition semantics:

- `transition to` / `@utils.transition to` is **one-way**. Control never returns to the caller, and a later transition
  back re-enters that subagent from its first line, not where it left off.
- A subagent referenced directly as a tool (`@subagent.<name>`) is **delegation**: it runs, then control returns to the
  calling subagent, which can synthesise the result and call more tools.
- Variables are global to the agent and survive every transition; prompt text never does.

Entry point: the flow-of-control guide states every utterance begins at `start_agent`, while the `config.runtime`
reference documents `reset_to_initial_node` (default `False`) as resuming where the previous turn left off and `True`
as restarting at `start_agent` each turn. Write `start_agent` so re-entry is safe (guard every deterministic transition
on state), set `reset_to_initial_node` explicitly when the behaviour matters, and confirm it in a preview trace.

## 2. File layout

The file lives at `<package-dir>/main/default/aiAuthoringBundles/<Bundle>/<Bundle>.agent`. Top-level properties are
**blocks**. Write new files in this order:

```agentscript
system:
config:
access:
variables:
knowledge:
language:
connection messaging:
modality voice:
model_config:
connected_subagent <Name>:
start_agent <name>:
subagent <name>:
```

| Block | Required | Purpose |
|---|---|---|
| `system` | Yes | Global LLM instructions plus `welcome` and `error` messages |
| `config` | Yes | Identity (`developer_name`), type, runtime switches |
| `access` | Service agents | `default_agent_user`, the run-as identity |
| `variables` | No | Agent-wide state |
| `knowledge` | No | Data library binding for grounded answers |
| `language` | No | Default and additional locales |
| `connection messaging` | For `@utils.escalate` | Omni-Channel escalation route |
| `modality voice` | Voice agents | Voice, speed, pronunciation, turn-taking |
| `model_config` | No | Agent-level model override |
| `connected_subagent` | No | Another Agentforce agent used as a subagent |
| `start_agent` | Yes, exactly one | Entry subagent, normally the router |
| `subagent` | Yes, at least one | A bounded job: instructions, tools, actions |

`topic` is the deprecated spelling of `subagent`; write `subagent` and `@subagent.`.

## 3. Lexical rules

- Everything is `key: value`; the key precedes the colon. Nested properties sit on the following lines, indented.
- Indentation is structural. Indent with spaces, 4 per level in new files; the parser accepts 2+ spaces or 1 tab, but
  every line at one level must match and **mixing tabs and spaces is a parse error**.
- `#` starts a comment that runs to end of line.
- Strings use double quotes. A multiline string starts with `|` after the colon and continues on indented lines.
- Booleans are `True` and `False`, capitalised. `None` is the absence of a value.
- Every developer name (agent, subagent, variable, action): starts with a letter, letters, digits and underscores only,
  no trailing underscore, no `__`, at most 80 characters. Use `snake_case`.
- `escalate` is reserved and cannot name a subagent or action.
- End the file with a blank line; Agentforce Builder can raise an unexpected error on the last line otherwise.

## 4. `system`

```agentscript
system:
    instructions: |
        Help members of the Northwind Library find, reserve and renew books.
        Never reveal another member's loans.
    messages:
        welcome: "Hi, I'm the Northwind Library assistant. What are you looking for?"
        error: "Something went wrong on my side. Please try again."
```

- `instructions` is prompt text sent on every reasoning call: persona, tone, safety and scope that hold everywhere.
  It is declarative; `->`, `run`, `set`, `if` and `transition to` are not allowed in a `system` block.
- `messages.welcome` and `messages.error` are listed as required; define both. Use `|` for multiline copy and
  `{!@variables.x}` to personalise (linked variables are the documented source for this).
- A subagent can carry its own `system.instructions`, which **replaces** the global text for that subagent only.

## 5. `config`

| Parameter | Notes |
|---|---|
| `developer_name` | API name; naming rules of section 3; unique in the org; must equal the `aiAuthoringBundles/<Bundle>` folder name |
| `agent_label` | Optional UI label, generated from `developer_name` when omitted |
| `description` | The agent's goal and purpose |
| `role`, `company` | Optional framing for the LLM |
| `agent_type` | `AgentforceServiceAgent` (default) or `AgentforceEmployeeAgent`; set by the template |
| `agent_version` | Set automatically when a version is created |
| `enable_enhanced_event_logs` | `True` / `False`, default `False`; conversation logging for debugging, see `references/observability.md` |
| `user_locale` | Optional user locale |
| `runtime` | Sub-block, below |
| `file_upload` | Sub-block, below |
| `default_agent_user` | **Deprecated here**; put it in `access` |

`runtime` sub-block:

| Key | Effect | Turn off when |
|---|---|---|
| `streaming` | Streams the reply incrementally; `False` returns one chunk | The client consumes only a completed message |
| `thought_chunks` | Streams the agent's step-by-step reasoning | Always off on customer-facing surfaces |
| `citation` | Post-processes grounded answers with source citations | The channel cannot render citations |
| `groundedness` | Checks responses against source content to reduce hallucination | Latency matters more and the check adds no value |
| `reset_to_initial_node` | `True` restarts every turn at `start_agent` | Leave `False` for multi-turn flows that resume mid-conversation |

`file_upload` sub-block: `mode` (required) is `auto` (standard handling), `managed` (route specific files to specific
subagents with slices of `@system_variables.uploaded_files`), `disabled` (silently rejected) or `error` (rejected, shows
`message` or a generated one); `message` is optional.

`agent_type` constrains the rest of the file:

| `agent_type` | Rules |
|---|---|
| `AgentforceServiceAgent` | Requires `access.default_agent_user`, an active user with the Einstein Agent licence; publish fails if the user does not exist |
| `AgentforceEmployeeAgent` | Omit `access.default_agent_user`, `connection messaging`, `@utils.escalate` and `@MessagingSession` linked variables; publish and preview fail with an uninformative internal error otherwise |

Agent user provisioning and permissions: `references/org-setup-and-agent-user.md` and `dya-sf-permissions`.

## 6. `access`

```agentscript
access:
    default_agent_user: "library.agent@northwind.example"
```

The value is the User's `Username`. The agent runs as this user, so its permissions decide every record and action the
agent reaches; it is the security boundary.

## 7. Variables

Variables hold state deterministically across turns and subagents instead of relying on the LLM's memory. All are
declared in one `variables` block and visible to every subagent.

### Custom variables

```agentscript
variables:
    member_id: mutable string = ""
        description: "Library member number once the member is identified."
    is_verified: mutable boolean = False
        description: "True after the member passes the PIN check."
        label: "Verified"
    renewals_left: mutable number = 3
    branch: string = "Central"
    due_dates: mutable list[date]
    hold: mutable object = {"isbn": "", "branch": "Central"}
    channel_hint: mutable string = "chat"
        visibility: "External"
```

- `mutable` lets the agent change the value; without it the value never changes after declaration.
- A default (`= value`) is optional; an undeclared default leaves the variable `None`. Give a default to everything a
  condition reads (`""`, `False`, `0`); leave unset only values that must be supplied.
- `description` is what the LLM reads when it slot-fills the variable; write one for every variable the LLM sets.
- `label` sets the UI name (default derived from the name, `my_var` becomes `My Var`).
- `visibility` is `Internal` (default) or `External`; `External` lets an API caller set the value and lets simulate-mode
  testing change it.

| Type | Values | Notes |
|---|---|---|
| `string` | `"text"` | Also the type for Salesforce record IDs |
| `number` | `42`, `99.5` | Integers and decimals; IEEE 754 double |
| `boolean` | `True`, `False` | Case-sensitive |
| `date` | Any valid date | |
| `object` | `{"key": "value"}` | JSON object |
| `list[<type>]` | `[1, 2]`, `["a"]`, `None` | Any primitive or `object` |
| `id` | n/a | Deprecated; use `string` |

`integer`, `long`, `datetime`, `time` and `currency` exist only as **action parameter** types, never as variable
types; store those values in `number`, `date` or `string`.

`None` versus `""`: `is None` means never assigned; `== ""` means assigned an empty string. For a string that may be in
either state, test both: `if @variables.member_id is None or @variables.member_id == "":`.

### Linked variables

A linked variable takes its value from the session context. It cannot have a default, cannot be set by the agent, and
cannot be `object` or `list`.

```agentscript
variables:
    session_id: linked string
        source: @MessagingSession.Id
        description: "Current messaging session."
    end_user_contact: linked string
        source: @MessagingEndUser.ContactId
    call_id: linked string
        source: @VoiceCall.Id
```

| `source` namespace | Properties |
|---|---|
| `@MessagingSession` | `Id`, `MessagingEndUserId`, `EndUserLanguage` |
| `@MessagingEndUser` | `ContactId` |
| `@VoiceCall` | `Id` |

Linked types: `string`, `number`, `boolean`, `date` (`id` deprecated).

### System variables

Read-only, predefined, referenced as `@system_variables.<name>`, never declared.

| Variable | Value |
|---|---|
| `user_input` | The customer's most recent utterance only, not the history; pass it to an action that needs the raw text |
| `current_modality` | `"voice"` on telephony, `"text"` on Messaging / Enhanced Chat v2, `None` when bound to neither |
| `current_connection` | The connected client for this turn; can be `None` until the connection finishes configuring |
| `uploaded_files` | List of the 10 most recent uploads, each with `id`, `file_url`, `name`, `mime_type`; empty when none; needs `config.file_upload` |

### Lists

- Index from zero: `@variables.questions[0]`. Read an object field with `.data.<field>`:
  `@variables.accounts[2].data.Name` returns the raw value.
- `json_path(@variables.accounts, "$[2].data.Name")` returns the match wrapped as `["value"]`; use bracket access when
  storing or displaying a scalar.
- Slice with `[start:end]`: `@system_variables.uploaded_files[0:3]`.
- Check `len(...)` before indexing so the agent never reads past the end.

## 8. `knowledge`

```agentscript
knowledge:
    rag_feature_config_id: "ARFPC_<libraryId>"
    citations_enabled: True
    citations_url: ""
```

Binds the agent to an Agentforce Data Library. `rag_feature_config_id` is `ARFPC_` plus the library ID, not the bare
library ID. Action inputs can default to these values with `@knowledge.<key>`. Library setup, grounding actions and
citations: `references/knowledge-and-data-libraries.md` and `dya-sf-data360`.

## 9. `language`

```agentscript
language:
    default_locale: "en_US"
    additional_locales: "es_ES,fr_FR"
    all_additional_locales: False
```

Voice requires a deterministic locale: `adaptive: True` is ignored on voice channels with a warning, so set a specific
`default_locale` on any agent that has `modality voice`.

## 10. `connection messaging`

```agentscript
connection messaging:
    outbound_route_type: "OmniChannelFlow"
    outbound_route_name: "flow://Library_Escalation_Route"
    escalation_message: "Connecting you with a librarian now."
    adaptive_response_allowed: True
```

- Required by `@utils.escalate`; the route is an Omni-Channel flow, named with the `flow://` prefix.
- The block is singular (`connection messaging:`), standalone, service agents only.
- Routing configuration on the Omni-Channel side: `dya-sf-omni-channel`.

## 11. `modality voice`

Configures how a voice agent sounds (voice ID, speed, style, pronunciation dictionary, filler sentences, speak-up and
endpointing timers). A voice agent defaults to the ElevenLabs v3 Conversational model. Branch on channel at runtime with
`@system_variables.current_modality`, not here. Full parameter set and catalog: `references/voice.md`.

## 12. `model_config`

By default every agent uses the org-level model chosen in Setup. Override at agent level (top-level block) or subagent
level (inside `start_agent` / `subagent`); subagent beats agent, agent beats org.

```agentscript
model_config:
    model: "model://sfdc_ai__DefaultGPT41"
    params:
        temperature: 0.2
        max_tokens: 1500
        top_p: 0.9
```

| Parameter | Effect |
|---|---|
| `model` | `model://<api_name>` of a supported model |
| `temperature` | 0 to 1; lower is more repeatable |
| `max_tokens` | Caps reply length in tokens |
| `top_p` | 0 to 1 nucleus sampling; lower is less random |

- The models tested most with agents are `sfdc_ai__DefaultGPT41`, `sfdc_ai__DefaultBedrockAnthropicClaude45Haiku` and
  `sfdc_ai__DefaultVertexAIGemini35Flash`; test any other model per agent version before relying on it.
- Some templates route with `model://sfdc_ai__DefaultEinsteinHyperClassifier` in `start_agent`: faster and more accurate
  classification, but a subagent on it **cannot use `before_reasoning` or `after_reasoning` and can only call
  `@utils.transition to`**.

## 13. `start_agent`, `subagent`, `connected_subagent`

`start_agent` is a subagent with a different keyword: the entry point (the "Agent Router" in Canvas view). Both share
one internal order:

| Order | Key | Required | Content |
|---|---|---|---|
| 1 | `label` | No | Display name |
| 2 | `description` | Yes | When to use this subagent; routing reads it |
| 3 | `system` | No | `instructions:` override for this subagent only |
| 4 | `model_config` | No | Subagent model override; documented examples place it right after `description` |
| 5 | `before_reasoning` | No | Deterministic statements before instructions resolve |
| 6 | `reasoning` | Yes | `instructions` and `actions` (tools) |
| 7 | `after_reasoning` | No | Deterministic statements after the reasoning loop |
| 8 | `actions` | No | Action definitions with `target` |

- Name a subagent in `snake_case` for its job, not its mechanism; routing matches the user's words against the name and
  `description`.
- Any subagent can become the start subagent; the router is a convention, not a requirement.

### `before_reasoning` and `after_reasoning`

```agentscript
after_reasoning:
    if @variables.hold_placed == True:
        transition to @subagent.hold_confirmation
```

- Both take logic only: `if`, `run`, `set`, `transition to`. A `|` line is not allowed.
- Write `transition to` here, never `@utils.transition to`, which is a tool form.
- `before_reasoning` is equivalent to logic at the top of the instructions; it runs at the start of **every execution**
  of the subagent, including re-entry by transition within the same turn.
- `after_reasoning` runs after the reasoning loop exits on every request; it does **not** run if the subagent
  transitioned away part-way through.

### `connected_subagent`

Delegates to another, independent Agentforce agent in the org.

```agentscript
connected_subagent Billing_Agent:
    label: "Billing Agent"
    target: "agentforce://<target id filled in by Agentforce Builder>"
    description: "Answers questions about fines, fees and payments."
    loading_text: "Checking your account..."
    inputs:
        member_number: string = @variables.member_id
```

- `target` is set when the agent is connected in Agentforce Builder; `description` is required.
- `inputs` bind the connected agent's mutable variable (left) to a variable of this agent (right). Values flow **one way**,
  into the connected agent; nothing comes back.
- Handoff mode: `@utils.transition to @connected_subagent.Billing_Agent`. Supervisor mode: list
  `@connected_subagent.Billing_Agent` as a tool so control returns.
- `after_response` (optional) runs after the connected agent replies and accepts `if`, `set` and `transition to`;
  statements after a transition are skipped.
- `delegate_escalation: True` lets the connected agent escalate to a human, in handoff mode only.

Multi-agent design: `references/agent-design.md`.

## 14. Reasoning instructions

| Form | Meaning |
|---|---|
| `instructions: \|` then indented text | Static prompt, no logic |
| `instructions: ->` then statements | Logic block; prompt lines inside start with `\|` |
| `\| text` inside `->` | Appends text to the prompt when execution reaches it |
| Line without `\|` after a `\|` line | Continues the same prompt fragment |

```agentscript
reasoning:
    instructions: ->
        if @variables.member_id == "":
            | Ask for the library card number before anything else.
        else:
            | Greet {!@variables.member_name} and help with loans or reservations.
              Use {!@actions.renew_loan} only for books already on loan.
```

- Only the `|` fragments on the path taken reach the LLM; unreached branches cost nothing.
- Shorter instructions are more reliable; add lines only when testing shows a gap.
- Put persona and global rules in `system.instructions`, task steps in `reasoning.instructions`.

### Merge fields

Inside prompt text, wrap every reference in `{!...}`; a bare `@variables.x` there is sent as literal characters.

| Inside `\|` text | Resolves to |
|---|---|
| `{!@variables.x}` | The variable's current value |
| `{!@system_variables.user_input}` | System variable value |
| `{!@actions.tool_name}` | A named pointer to that tool, raising the odds the LLM calls it |
| `{!@variables.idx + 1}`, `{!len(@variables.items)}` | The expression's result |
| `{!@variables.items[@variables.idx]}` | Indexed element |

Outside prompt text (conditions, `with`, `set`, `available when`) write references bare.

### Resource references

| Reference | Points at |
|---|---|
| `@variables.<name>` | Custom or linked variable |
| `@system_variables.<name>` | System variable |
| `@actions.<name>` | Action defined in this subagent's `actions`, or a tool name in prompt text |
| `@outputs.<name>` | Output of the action just run; read it only in the `set` / `if` lines under that `run` or tool |
| `@subagent.<name>` | A subagent, as transition target or delegated tool |
| `@connected_subagent.<name>` | A connected agent |
| `@utils.<name>` | A built-in utility |
| `@knowledge.<key>` | A `knowledge` block value |

`@inputs.<name>` exists only inside the `with` lines of an invocation; to keep an input value, copy it into a variable
before the call.

## 15. Expressions and operators

| Category | Operators |
|---|---|
| Comparison | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| Identity | `is`, `is not` (with `None`) |
| Logical | `and`, `or`, `not` |
| Arithmetic | `+`, `-` (`+` also concatenates strings) |
| Grouping | `( )` |
| Access | `.field`, `[index]`, `[start:end]` |

| Function | Returns |
|---|---|
| `len(list)` | Element count |
| `max(list)`, `min(list)` | Largest or smallest number |
| `to_json(value)` | JSON string of the value |
| `json_path(value, "$...")` | JSONPath match, wrapped in `[...]` |

- `*`, `/` and `%` are not supported; compute products and ratios in an action.
- Group mixed `and` / `or` with parentheses: `available when @variables.is_verified == True and (@variables.tier ==
  "gold" or @variables.staff == True)`.
- A bare boolean is a valid condition: `if @variables.is_verified:`.
- Concatenate: `set @variables.full_name = @variables.first + " " + @variables.last`.

## 16. Statements

### `if` / `else if` / `else`

```agentscript
if @variables.fines_due > 20:
    | Explain that borrowing is blocked until fines are under 20.
else if @variables.fines_due > 0:
    | Mention the outstanding fines, then continue.
else:
    | Continue without mentioning fines.
```

- The clause is spelled `else if`; `elif` is not valid.
- Do not nest an `if` inside an `if`, `else if` or `else` body; combine predicates with `and` / `or`, chain with
  `else if`, or write sequential top-level `if` statements.
- Sequential `if` statements are independent and several can run; an `else if` chain runs only its first match.
- Give every branch at least one executable line (`|`, `run`, `set`, `transition to`); a comment-only body compiles to an
  empty branch.

### `run`, `with`, `set`

```agentscript
run @actions.find_member
    with card_number = @variables.card_number
    with branch = "Central"
    set @variables.member_id = @outputs.member_id
    set @variables.member_name = @outputs.display_name
```

- `run` executes an action from the subagent's `actions` block during resolution, every time that line is reached.
- `with <input> = <value>` binds an input to a variable, a literal or an expression. A deterministic `run` cannot
  slot-fill: bind every required input.
- `set` under a `run` copies `@outputs.<name>` into a variable; it is the only way to keep an output for conditions and
  later actions.
- `set @variables.x = <expression>` on its own line assigns deterministically: `set @variables.attempts =
  @variables.attempts + 1`.

### `transition to`

`transition to @subagent.<name>` inside logic (instructions, `before_reasoning`, `after_reasoning`, under a tool or a
`run`). It executes at once, abandons the rest of the current subagent and its prompt, and is one-way.

### `ask for` (Beta)

```agentscript
reasoning:
    instructions: ->
        ask for @variables.card_number
            instructions: | Ask for the 10-digit number printed on the library card.
        ask for @variables.pickup_branch
            instructions: | Ask which branch they will collect from.
        if @variables.pickup_branch is not None:
            transition to @subagent.place_hold
```

- Each `ask for` prompts for one value, stores the reply in the variable, and re-enters the same subagent until every
  `ask for` variable is populated.
- Replies are validated against the variable's type and asked again until valid.
- Use it for intake-form style collection that must complete before a downstream step. It is Beta: validate behaviour in
  the target org before relying on it.

## 17. Tools: `reasoning.actions`

A subagent has two `actions` lists. `subagent.actions` **defines** actions (target, inputs, outputs) for deterministic
`run`. `subagent.reasoning.actions` **exposes tools** to the LLM, each wrapping a defined action, a utility, a subagent
or a connected subagent. Only tools are visible to the LLM.

```agentscript
reasoning:
    actions:
        renew_loan: @actions.renew_loan
            description: "Renew one book the member already has on loan."
            with loan_id = ...
            with member_id = @variables.member_id
            set @variables.last_due_date = @outputs.new_due_date
            available when @variables.is_verified == True and @variables.renewals_left > 0
        go_to_reservations: @utils.transition to @subagent.reservations
            description: "The member wants to reserve a title that is not on the shelf."
        consult_catalogue: @subagent.catalogue_search
            description: "Find titles by author, subject or ISBN, then come back."
```

| Line under a tool | Effect |
|---|---|
| `description: "..."` | What the LLM reads to choose the tool; defaults from the name when omitted |
| `with x = @variables.y` / literal | Fixed input; the LLM cannot change it |
| `with x = ...` | Slot-fill: the LLM supplies the value from the conversation |
| (input omitted) | Required unbound inputs are slot-filled; optional ones are left empty |
| `set @variables.v = @outputs.o` | Captures an output after the LLM-chosen call |
| `run @actions.next` + its own `with` / `set` | Chained action, runs right after this tool; cannot slot-fill |
| `transition to @subagent.x` | Hands off right after this tool completes |
| `available when <condition>` | Tool exists for the LLM only while the condition is true |

- The LLM chooses by tool **name and description**; make both specific and distinct across the agent.
- The LLM can call any available tool even when no instruction mentions it; gate by `available when`, not by prose.
- Binding many inputs to variables makes a tool selectable only when all are known; bind only what testing shows must
  be fixed and slot-fill the rest.
- In the UI, an action and its tool share a name; in script they can differ (`lookup_member: @actions.find_member`).
- Name transition tools `go_to_<destination>`.

## 18. Utilities

| Utility | Form | Behaviour |
|---|---|---|
| `@utils.transition to @subagent.x` | Tool | One-way handoff chosen by the LLM; logic uses bare `transition to` |
| `@utils.setVariables` | Tool with `with v = ...` lines | The LLM writes values from the conversation into variables (slot filling); the `description` says how |
| `@utils.escalate` | Tool | Hands the conversation to a human through the `connection messaging` route; service agents only |
| `@utils.end_session` | Tool | Ends the conversation immediately |

```agentscript
reasoning:
    actions:
        capture_contact: @utils.setVariables
            description: "Store the member's email and phone when they give them."
            with email = ...
            with phone = ...
            available when @variables.contact_saved == False
        talk_to_librarian: @utils.escalate
            description: "The member asks for a person, or the request is outside lending."
            available when @variables.branch_open == True
        finish: @utils.end_session
            description: "The member says they are done."
```

- Utilities produce no `@outputs`; do not hang `set ... = @outputs.x` under them.
- `@utils.escalate` replaces the need for a dedicated escalation subagent.
- Setting a variable deterministically is a `set` statement, not a utility.

## 19. Action definitions

```agentscript
actions:
    find_member:
        description: "Look up a member by library card number."
        target: "flow://Find_Library_Member"
        include_in_progress_indicator: True
        inputs:
            card_number: string
                description: "The 10-digit card number."
                is_required: True
        outputs:
            member_id: string
                filter_from_agent: True
            display_name: string
```

- `target` is `{type}://{DeveloperName}` with `apex://` (an `@InvocableMethod`), `flow://` (autolaunched Flow) or
  `prompt://` (Prompt Template).
- Actions are not shared: each subagent owns its definitions, and an imported action is a copy.
- Outputs stay in the agent's context for the whole session; `filter_from_agent: True` keeps one out of the LLM's sight
  while scripts can still `set` it.
- `require_user_confirmation`, `label`, `is_displayable`, `complex_data_type_name`, input `is_user_input`, quoted
  prompt-template input names, and every target type's contract: `references/agent-actions.md`.

## 20. Authoring and validation

- Agentforce Builder Canvas view summarises the script as blocks (`/` inserts expressions, `@` inserts resources);
  Script view edits the text with highlighting and validation; the agent chat converts plain-language requests into
  script.
- In a DX project, the Agent Script Language Server extension for VS Code gives highlighting, error squiggles and an
  Outline tree.
- Validate that the file compiles before every publish; the command lists the bundles when `--api-name` is omitted:

```bash
sf agent validate authoring-bundle --api-name Library_Agent --target-org my-org
```

Bundle lifecycle, publish and activation: `references/agent-lifecycle-metadata.md`. CLI surface: `dya-sf-cli`.

## 21. Anti-Patterns

| Anti-pattern | Replacement |
|---|---|
| A business rule written as prose after `\|` | An `if` or `available when` on a variable |
| `@variables.x` inside prompt text | `{!@variables.x}` |
| `elif`, or an `if` nested in another branch | `else if`, compound predicates, or sequential top-level `if` |
| `true` / `false` | `True` / `False` |
| Mixing tabs and spaces | One style; 4 spaces in new files |
| `default_agent_user` under `config` | `access.default_agent_user` |
| `@utils.transition to` in `before_reasoning` / `after_reasoning` / instructions logic | Bare `transition to` |
| Bare `transition to` as a tool | `@utils.transition to @subagent.x` |
| `integer` / `datetime` / `currency` variable | `number`, `date` or `string` |
| Linked variable with a default, or set by the agent | Declare it `mutable` instead, or read it only |
| Reading `@outputs.x` in a later line or another subagent | `set` it into a variable under the `run` or tool |
| `with x = ...` on a chained `run` or a deterministic `run` | Bind it to a variable or literal |
| A tool with a side effect and no `available when` | Gate it on the state that makes it legal |
| Relying on the LLM to remember state | A variable |
| A subagent name describing the mechanism | A name and description in the user's words |
| `escalate` as a subagent or action name | Any other name; it is reserved |
| `before_reasoning` / `after_reasoning` on an EinsteinHyperClassifier subagent | Move the logic to another subagent or change the model |
