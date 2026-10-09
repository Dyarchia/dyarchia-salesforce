# Agent Design — Reference (Winter '27 / API v68.0)

How to decide what an agent is, how it splits, and where the model is allowed to choose, before a line of Agent Script exists.

Syntax lives in `references/agent-script.md`, reusable constructs in
`references/agent-script-patterns.md`, action implementation in `references/agent-actions.md`.
This file decides; those files build.

## 1. Discovery — answer these before generating anything

Write the answers into the agent spec (§9). An unanswered row becomes a guess the LLM makes at
runtime.

| Question | Why it shapes the design |
|---|---|
| What outcome ends a successful conversation? | Becomes the subagent that owns completion and the test's expected result |
| Who talks to the agent: customers, partners, employees? | Picks the agent type and the run-as identity (§2) |
| On which channels: web chat, mobile, voice, API, Slack? | Voice changes instruction style (`references/voice.md`); the API excludes "Agentforce (Default)" agents |
| What must be proven about the person before anything is shown or changed? | Defines the verification gate (§5) |
| Which actions change data, move money, or cannot be undone? | Each gets a deterministic gate and a confirmed outcome (§5) |
| Which facts must come from records or documents, never from the model? | Becomes actions and grounding (`references/knowledge-and-data-libraries.md`) |
| When does a human take over, and in which hours? | Escalation design (§6) |
| Which languages, and is the locale fixed per channel? | The `language` block; voice needs a fixed `default_locale` |
| What must the agent refuse, and how does it say so? | Scope statements in instructions plus `available when` filters |
| Which systems already own the logic? | Reuse their Flow or Apex as actions instead of re-describing rules in prose |
| How will you know it works? | Test cases per subagent, per action and per grounding source (`references/testing-and-evaluation.md`) |

## 2. Choose the agent type

`config.agent_type` takes `AgentforceServiceAgent` (the default) or `AgentforceEmployeeAgent`. The
spec generator's `--type` maps to the same choice as `customer` or `internal`.

| Concern | Service agent (`customer`) | Employee agent (`internal`) |
|---|---|---|
| Audience | People outside the company, often unauthenticated | Logged-in Salesforce users |
| Run-as identity | `access.default_agent_user`, **required** | The user working with the agent (`references/org-setup-and-agent-user.md`) |
| Identity proof | Must be designed in: a verification subagent and a gate | Inherited from the login |
| Human handoff | `@utils.escalate` over an Omni-Channel messaging connection | Usually unnecessary; the user is already staff |
| Typical channels | Enhanced Chat v2, telephony and voice, Agent API, mobile SDK | Lightning, Slack, mobile SDK |
| Main risk | Persuasion past a rule; over-broad agent-user access | Acting with too much of the user's own access |

Size the agent user's permissions to the actions, not to the profile it copied. What the agent user
can read, the agent can say (`dya-sf-permissions`).

## 3. Shape: one router, few subagents

Every turn enters at `start_agent`, the router. Design it to classify and route, nothing more.

- **Start with the fewest subagents that cover the outcomes**; add one only when a test shows two
  jobs interfering. Fewer subagents route more reliably.
- **One job per subagent.** A subagent owns one outcome and the actions that serve it; actions are
  not shared, so a subagent gets its own copy of any imported action.
- **Write transition descriptions that do not overlap.** The model routes by reading them; two
  descriptions that both fit an utterance produce a coin toss.
- **Name transition tools `go_to_<destination>`** so the model reads them as navigation.
- **Hide internal subagents from the router.** A subagent reachable only by transition (a
  confirmation step, a verification step) has no router entry.
- **Use a fast classifier only for pure routing.** Einstein HyperClassifier on the router classifies
  faster and honours negative instructions better, but allows only `@utils.transition` and no
  `before_reasoning` / `after_reasoning`. Any router that sets variables or runs actions needs an
  LLM model.
- **Stateless Q&A agents** can set `config.runtime.reset_to_initial_node: True` to replan every turn;
  multi-turn flows leave it off.

| Situation | Split into |
|---|---|
| Two jobs share data but never share a turn | Two subagents in one agent |
| A job needs a step-by-step interview with validation per answer | One subagent per step, driven by a step variable |
| A capability belongs to another team, has its own users and release cycle | A separate agent, called as a connected subagent (§7) |
| One job needs a different tone or persona | Same subagent count; a `system` override in that subagent |
| One subagent needs a stronger or cheaper model | `model_config` on that subagent only |

## 4. Deterministic versus model-decided paths

Decide per rule, not per agent. The test: if the model choosing wrongly would break a policy, cost
money, or leak data, the path is deterministic.

| Mechanism | Who decides | Use it for |
|---|---|---|
| `if` / `run` / `set` in `instructions: ->` | Script, every time the subagent runs | Lookups the prompt needs, eligibility, computed values |
| `transition to` at the top of `->` instructions | Script, before the model sees anything | Mandatory steps: verification, collecting a key, legal notices |
| Step variable read by the router | Script, across turns | Interviews whose order must hold over many turns |
| `after_reasoning` | Script, after each reasoning loop | Commit an action once every input is captured; move on when a result exists |
| `available when` on a tool or transition | Script removes options; model picks among the rest | Hiding features the user is not entitled to right now |
| Tool in `reasoning.actions` | Model | Optional lookups and conversational choices |
| Action chained under a tool | Script, after the model's choice | A follow-up that must always accompany the chosen action |
| `{!@actions.x}` in prompt text | Model, nudged | Hinting which tool fits a described situation |

`available when` narrows; it never forces. A model denied the sensitive option can still choose an
unguarded one and skip the step you wanted. Force a step with a conditional transition; narrow
choices with `available when`; use both on anything consequential.

Put conditional transitions first in the instructions. A transition discards the prompt resolved so
far, so any action run above it costs latency and credits for nothing.

## 5. Gates before consequential actions

A consequential action changes data, spends money, sends a message, or cannot be undone. Give each
one three guards: a gate before, a single commit, and a confirmation that reads the result.

```agentscript
variables:
    identity_verified: mutable boolean = False
        description: "True once the caller passed the verification check"
    claim_id: mutable string = ""
        description: "Id of the warranty claim created in this session; empty until created"
    serial_number: mutable string = ""
        description: "Product serial number the caller gave"
    fault_summary: mutable string = ""
        description: "One-sentence description of the fault"

start_agent claims_router:
    description: "Route warranty callers after verifying who they are"
    reasoning:
        instructions: ->
            if @variables.identity_verified == False:
                transition to @subagent.verify_caller              # ✅ forced, no model choice
            | Pick the tool that matches what the caller needs.
        actions:
            go_to_new_claim: @utils.transition to @subagent.new_claim
                description: "Open a warranty claim for a faulty product"
                available when @variables.identity_verified == True   # ✅ narrows as well

subagent new_claim:
    description: "Collect serial number and fault, then open one warranty claim"
    reasoning:
        instructions: ->
            | Ask for the serial number and a short fault description.
              Ask only for what is still missing.
              Never say a claim exists unless you were told its number.
        actions:
            capture_claim: @utils.setVariables
                available when @variables.claim_id == ""            # ✅ no second claim
                with serial_number = ...
                with fault_summary = ...
    after_reasoning:
        if @variables.serial_number != "" and @variables.fault_summary != "" and @variables.claim_id == "":
            run @actions.open_claim
                with serial = @variables.serial_number
                with fault = @variables.fault_summary
                set @variables.claim_id = @outputs.claim_id
        if @variables.claim_id != "":
            transition to @subagent.claim_confirmed                # ✅ confirmation reads the result
    actions:
        open_claim:
            description: "Create a warranty claim and return its Id"
            target: "flow://Open_Warranty_Claim"
            inputs:
                serial: string
                fault: string
            outputs:
                claim_id: string
                    filter_from_agent: True
```

- Gate the router with a deterministic transition, and gate each sensitive tool with
  `available when`; never rely on an instruction like "only if verified".
- Commit from `after_reasoning` once every input is captured, not from a model-chosen tool.
- Close the create path with `available when <id> == ""` so a second commit cannot happen.
- Confirm only from a subagent reached when the returned Id is set; the router has no route to it.
- Make the backing Flow or Apex clear its output on failure, so a fault never reads as success.
- Keep a value the model must not repeat out of context with `filter_from_agent: True`.
- `require_user_confirmation: True` asks the customer before an action runs; it adds a human check
  and never replaces the gates above.

## 6. Escalation

Design the exit before the happy path; an agent that cannot hand over traps the customer.

- **Mechanism.** `@utils.escalate` hands the conversation to a human through Omni-Channel. It needs a
  `connection messaging` block with `outbound_route_type: "OmniChannelFlow"` and
  `outbound_route_name` naming the routing flow; `escalation_message` is what the customer sees
  while waiting. Routing flows and queues: `dya-sf-omni-channel`.
- **Gate it.** Put `available when` on the escalate tool for business hours, and tell the model in
  prompt text when to call it.
- **Escalate on signals, not only requests.** Repeated failure to verify, a loop counter passing a
  limit in `after_reasoning`, a refused action the caller insists on, or a safety topic.
- **Connected agents.** In handoff mode, `delegate_escalation: True` lets the connected agent
  escalate itself; otherwise escalation happens in the orchestrator only.
- **Mobile.** Through the mobile SDK, escalation works on the Enhanced Chat v2 path and not on the
  Agent API telephony path.
- **Test it on the channel.** Preview does not support escalation; publish, activate, and test it
  on a real deployment.
- **Close cleanly.** `@utils.end_session` ends the conversation when the job is done or must stop.

## 7. Multi-agent orchestration

Split into separate agents only when ownership, users or release cadence differ (§3); otherwise use
subagents. A separate agent joins as a `connected_subagent`.

| Mode | Script | Behaviour | Use when |
|---|---|---|---|
| Handoff | `go_to_x: @utils.transition to @connected_subagent.X` | The connected agent takes over and answers the user | The specialist owns the rest of the conversation |
| Supervision | `x: @connected_subagent.X` as a tool | The connected agent returns; the orchestrator composes the answer | The orchestrator must check, merge or reformat the result |

- Pass context through `inputs`; the left side is a variable of the connected agent, the right side
  a variable of the caller. **Values flow one way**, orchestrator to connected agent, never back.
- Use `after_response` to branch, set a variable, or hand to the next connected agent once the
  connected agent has answered; commands after a transition there are skipped.
- Give each connected subagent a description as precise as a subagent's; it is how the orchestrator
  routes. Set `loading_text` for the wait.
- `target` (`agentforce://...`) is filled when you connect the agent in Agentforce Builder; do not
  hand-write it.
- Serialise turns per conversation; a second message during a running task fails with
  `A2A_CONFLICT` (`references/troubleshooting.md`).

## 8. Writing instructions

- **Write imperatives with a subject and a limit.** "Ask for the serial number. Ask only for what is
  missing." beats "Gather the information".
- **Say what the agent must not claim.** Name the false statements to avoid: a record exists, a
  refund is approved, a meeting is booked.
- **Keep agent-level `system.instructions` short and universal.** Persona, tone, refusal style.
  Anything one subagent contradicts goes into that subagent's `system` override; conflicting levels
  make the agent hang or behave erratically.
- **Put values in with `{!@variables.x}` and tools with `{!@actions.x}`.** A bare reference inside
  prompt text is passed as its name (`references/agent-control-flow-pitfalls.md`).
- **Describe every action, input, output and variable.** The model reads action and input
  descriptions to choose and slot-fill; a missing description is generated from the name.
- **Bind inputs sparingly in tools.** An action becomes available once all bound inputs have values,
  so binding many inputs makes selection erratic; bind only what logic requires.
- **Fetch before you ask.** Run lookups in `->` logic, guarded by "only if empty", so the prompt
  already holds the facts and the agent never asks for what it can look up.
- **Initialise every variable with a value meaning "not yet"** (`""`, `False`) and test with `is None`
  only when unassigned differs from empty.
- **Prefer a recommended model.** GPT 4.1, Claude Haiku 4.5 and Gemini 3.5 Flash are the models
  Salesforce tested with agents; test any other choice per subagent before release.
- **Lower `temperature` where answers must be repeatable**; raise it only for generative subagents.

## 9. The agent spec as the design artefact

Generate the spec, iterate it, review it, then generate the bundle from it. The spec is YAML in
version control; review it like a design document.

```bash
sf agent generate agent-spec --type customer \
    --role "Open and track warranty claims for consumer appliances" \
    --company-name "Acme Appliances" \
    --company-description "Sells and repairs kitchen appliances in Spain and Portugal" \
    --max-topics 4 --tone neutral \
    --output-file specs/warrantyAgent.yaml --target-org dev
```

| Flag | Effect |
|---|---|
| `--type customer\|internal` | Service or employee agent |
| `--role`, `--company-name`, `--company-description`, `--company-website` | The inputs the org's LLM turns into subagents; vague text yields generic subagents |
| `--max-topics` | Ceiling on generated subagents; default 5 |
| `--tone formal\|casual\|neutral` | Conversational style |
| `--agent-user` | Username the agent runs as |
| `--enrich-logs true\|false` | Adds conversation data to event logs |
| `--prompt-template` + `--grounding-context` | A custom prompt template for generation, and the context added to it |
| `--spec <file>` | Reuses an existing spec as input, to refine it |
| `--output-file` | Target path; default `specs/agentSpec.yaml` |
| `--force-overwrite` | Overwrite without the confirmation prompt; pass it in automation |
| `--full-interview` | Prompts for every property; never use it in automation |

- **Iterate.** Rerun with `--spec specs/warrantyAgent.yaml` and a sharper `--role` or
  `--company-description`; the generated subagent list improves with the input.
- **Edit freely, regenerate deliberately.** Delete subagents that do not apply and rewrite
  descriptions by hand; only a rerun produces a new generated list.
- **Steer action choice in the description.** A subagent description can say "use only the
  `Check_Claim_Status` action" when that action exists in the org.
- **The spec calls subagents `topics`.** The YAML key keeps the old name.
- **Then build:** `sf agent generate authoring-bundle --spec specs/warrantyAgent.yaml --name "Warranty Agent" --api-name Warranty_Agent`.
  Never `sf agent create --spec`; it builds a scriptless legacy agent.

## 10. General practice

- **Size each action to one self-contained result.** An action whose output means nothing until two
  more calls run is too fine; an action that bundles several decisions belongs in a Flow the agent
  calls. Start slightly coarse and split when tests show the agent needs finer control.
- **Let existing automation own business rules.** Call the Flow or Apex that already enforces a rule
  instead of restating it in instructions (`dya-sf-flow`, `dya-sf-apex`).
- **Use one test per decision, not per conversation.** Routing, action selection and grounding fail
  for different reasons and need separate cases.
- **Version deliberately.** Each publish is a version; activate only tested versions and keep the
  previous one available to reactivate (`references/agent-lifecycle-metadata.md`).
- **Observe after launch.** Read sessions and traces for misroutes and ungrounded answers
  (`references/observability.md`) and turn each finding into a test.

## 11. Security practice

- **Least privilege for the run-as user.** Start read-only; add each create or update permission
  when an action needs it.
- **Filter, do not ask nicely.** Hide business-sensitive tools with `available when`; a customer can
  talk a model past any prose rule.
- **Expose a slice, not a surface.** Prefer a Named Query or a purpose-built Apex or Flow action over
  a generic query or update tool.
- **Validate inside the action.** Treat every model-supplied input as untrusted: check ownership,
  ranges and state in Apex or Flow before acting.
- **Keep secrets and internal Ids out of context.** `filter_from_agent: True` on outputs the model
  does not need to repeat.
- **Keep the groundedness check on** for knowledge answers (`config.runtime.groundedness`), and keep
  `thought_chunks` off on customer-facing channels.
- **Review generated output for external audiences**; grounding reduces hallucination, it does not
  remove it.
- **Agents calling hosted MCP servers act as the authorising user.** Enable only the servers needed,
  prefer the read-only server where reads suffice, and restrict the external client app to the
  permission sets that need it.

## 12. Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Starting from the script before answering §1 | Discovery, then spec, then bundle |
| A subagent per screen or per object | A subagent per outcome |
| Overlapping transition descriptions | Disjoint descriptions with `go_to_` names |
| "Only if the user is verified" in prose | A conditional transition plus `available when` |
| `available when` as the only guard on a mandatory step | Force the step with a top-of-instructions transition |
| A create action the model may call at will | Commit from `after_reasoning` when every input is set, once |
| "Your claim is created" before an Id exists | Confirm from a subagent reached only when the Id is set |
| Escalation added after launch | Design the human exit first and test it on the channel |
| A separate agent for every job | Subagents, until ownership or release cadence differs |
| Expecting a connected agent to return variables | Read its response; values flow one way |
| Contradicting agent-level instructions in a subagent | A `system` override in that subagent |
| Business rules re-described in instructions | Call the Flow or Apex that owns them |
| `--full-interview` or a spec-less bundle in a pipeline | Flags plus `--force-overwrite`, and `--spec` |
