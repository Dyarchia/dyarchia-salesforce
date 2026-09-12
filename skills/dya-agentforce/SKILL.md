---
name: dya-agentforce
description: Salesforce Agentforce Winter '27 (API v68.0) — from zero to expert. What an AI agent is and how Atlas reasons; agent anatomy (Topics, Instructions, Actions); Agent Script; designing and building Apex/Flow/Prompt-Template actions; grounding with Data 360; invoking agents headlessly (Agent API); testing, evals, and observability; multi-agent orchestration; security and the Trust Layer. Load only when the user explicitly invokes this skill by name (`dya-agentforce`); do NOT auto-trigger on generic Agentforce, AI, or Salesforce questions.
---

# Salesforce Agentforce — From Zero to Expert

You are an expert Agentforce architect and developer. The reader may be **new to Agentforce**, so
this skill builds the mental model first, then the implementation rules, then what this release
changes. You **always** keep actions deterministic and bulkified, **always** ground answers in
trusted data, and **always** enforce security through the Trust Layer. Follow every rule below.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/`:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults an Apex action inherits.
- `references/shared/sharing-and-access.md` — the permission model an agent's run-as identity is bound by. **Read this before designing a customer-facing agent.**
- `references/shared/governor-limits.md` — the budget an action spends, and why "one transaction per action" is not a licence to skip bulkification.
- `references/building-an-agent.md` — **the end-to-end path**: prerequisites and org setup, the two authoring workflows, the CLI commands, testing and activation. Start here if you have never built one.
- `references/agent-script.md` — the actual syntax: blocks, `->` logic versus `|` prompt instructions, variables, routing, `available when` guards.
- `references/agent-control-flow-pitfalls.md` — the constructs that compile and then behave differently from how they read. Read before debugging an agent that "ignores" its script.
- `references/agent-lifecycle-metadata.md` — the bundle on disk, why deploy is not publish, the writable-versus-snapshot bundle trap, and the `sf agent` surface.
- `references/apex-actions.md` — `@InvocableMethod` / `@InvocableVariable` actions, action-type comparison, security, bulkification, error handling.
- `references/prompt-templates.md` — calling a template from code, batch generation with `AiJobRun`, moving templates between orgs.
- `references/lifecycle-and-api.md` — the Agent API with real endpoints and payloads, invoking agents from Apex/Flow, `agent preview`, testing and evaluations.

Load a reference when building that exact thing. Agentforce actions are Apex and Flow: for deep Apex
rules load `dya-apex`, for the data layer that grounds agents `dya-data360`, and for exposing agents
across surfaces `dya-headless360`.

---

## Platform Context — Winter '27 / API v68.0

Save Agentforce metadata and the Apex or Flow behind actions at `68.0`. Four facts gate what you can
build:

- **`AiAgentDefinition` / `AiAgentDefinitionVersion` are GA at 68.0, and both orgs must be on 68.0.**
  A deploy from a 68.0 sandbox into a 67.0 org carries neither, silently.
- **The 24 additional conversation languages are Beta** — not production. Check the list before
  promising a language.
- **An Apex action is Apex**, so it inherits the 67.0+ security defaults: `with sharing` and
  `USER_MODE`, and `WITH SECURITY_ENFORCED` no longer compiles. See §4 and `dya-apex`.
- **Since April 2026 a Topic is a subagent.** The functionality did not change, and older
  documentation, parts of the UI and help-article URLs still say "topic". This skill says
  **subagent**; they are the same thing.

> Everything else Winter '27 adds — MCP interoperability, observability and custom scorers, Voice
> improvements, Data 360 SQL from Apex, and the standing facts about Atlas 3.0, Agent Script and
> Agentforce DX: `references/release-notes.md`.

---

## 1. Foundations — What Agentforce Is and How It Reasons

Agentforce builds **autonomous AI agents**: software that understands a request in natural language,
**reasons** about what to do, **plans** a sequence of steps, **acts** by calling real business logic
and **responds**, all grounded in your Salesforce data.

The brain is the **Atlas Reasoning Engine**. It runs no fixed decision tree; on every request it
reasons from the descriptions you wrote:

1. **Intent classification** — Atlas reads the user's message and picks the most relevant
   **subagent**.
2. **Plan** — it reads that subagent's scope, instructions and the descriptions of the available
   **Actions**, then decides what to do: ask a question, run an action, use a prompt template.
3. **Ground (RAG)** — it pulls live, trusted context from Salesforce, **Data 360** or external
   systems via MCP.
4. **Act** — it executes the chosen actions (Apex, Flow, Prompt Template) and checks results,
   looping if needed.
5. **Respond** — the final answer passes through the **Einstein Trust Layer** — masking, grounding
   checks, zero-retention — before it reaches the user.

**The single most important consequence:** Atlas chooses subagents and actions by reading their
**natural-language descriptions**. Vague descriptions route wrongly. Your descriptions *are* the
program; treat them as carefully as code.

---

## 2. Anatomy of an Agent

| Building block | What it is | Who owns it |
|---|---|---|
| **Agent** | The deployed assistant, with a role, channels, and a user/permission context | Builder |
| **Subagent** (formerly Topic) | A bounded job-to-be-done, e.g. "Order Management". Holds the classification description, scope and instructions | Builder |
| **Classification description** | Tells Atlas *when* this subagent applies | Builder |
| **Scope** | What the agent may and may not do within the subagent — a guardrail | Builder |
| **Instructions** | Natural-language rules (prompt-like) that shape behaviour and reference actions | Builder |
| **Action** | A concrete capability the agent can invoke: Apex, Flow, Prompt Template, Apex REST, Named Query | Developer |

### Writing Instructions (the high-leverage skill)

- One subagent covers one coherent set of tasks. Never build a mega-subagent.
- Instructions live *inside* the subagent, not as separate metadata, and may reference Actions by
  name.
- Be explicit and imperative. State preconditions and the order of operations.
- Use them as guardrails: say what *not* to do, not only what to do.
- Encode hard business rules in **Agent Script** (§5) rather than hoping the LLM follows prose.

---

## 3. Designing Actions — Choose the Right Type

Actions are how the agent *does* things. Pick the least-code option that fits, and write a crisp
label and description so Atlas can match intent.

| Need | Action type | Code? |
|---|---|---|
| Multi-step declarative automation, approvals, record updates | **Flow** (autolaunched) | NO |
| Generate/transform text grounded in records | **Prompt Template** | NO |
| Expose an existing SOQL query as an action | **Named Query** action | NO |
| Deterministic business logic, callouts, complex cross-object work | **Apex `@InvocableMethod`** | YES |
| Expose an existing Apex REST endpoint | **Apex REST agent action** (OpenAPI) | YES |
| Call another active agent | **AI Agent action** (Apex/Flow) | maybe |

**Declarative for orchestration, Apex for deterministic logic the LLM must not improvise.** Keep each
action narrow and single-purpose: Atlas composes small, well-described actions better than it drives
one giant one.

---

## 4. Apex Actions — Best Practices

An Apex action is an `@InvocableMethod`, and its labels and descriptions are read by Atlas, so they
are part of the contract.

The full class skeleton — request and result wrappers, `@InvocableVariable` labelling, the bulk-in
bulk-out signature: `references/apex-actions.md`.

Absolute rules:

- **Bulkify anyway.** An agent invokes an action **once per turn, in its own transaction**, so the
  agent itself will not hand you 200 records. Write for the batch regardless, because the same
  `@InvocableMethod` is routinely reused from a Flow — and **Flow always passes a `List`**, often the
  whole 200-record trigger batch. Take `List<Request>`, return `List<Result>`: the cost is nothing,
  and the alternative is a governor limit the first time an admin wires it into a record-triggered
  flow. See `dya-flow`.
- **One input and output wrapper class** with `@InvocableVariable`s; primitives or DTOs, never a raw
  `SObject` you do not control.
- **`with sharing` + `WITH USER_MODE`** — the defaults from API 67.0, but state them.
  `WITH SECURITY_ENFORCED` no longer compiles.
- **Descriptions are prompts.** Write a clear `label` and `description` on the method and every
  variable, and keep them in sync with the action config in Agent Builder.
- **Handle errors gracefully, for the agent.** Return a structured result with a success flag and a
  human-readable message the agent can relay; a thrown exception gives it something it cannot explain
  to a user. This is the **opposite** of what a Flow-facing action wants, where throwing is how the
  fault message reaches a Fault Path. When one method serves both callers, return the structured
  result and let the Flow branch on it. Log failures durably through Platform Events (`dya-apex`).
- Keep actions **deterministic**. They exist precisely so the LLM does not improvise critical logic.

> Full skeletons, error patterns and the action-type deep dive: `references/apex-actions.md`.

---

## 5. Agent Script — Deterministic Control (GA)

Agent Script is the compiled language behind Agentforce Builder, and its whole design is one
distinction: **`->` logic instructions run deterministically every time; `|` prompt instructions go to
the LLM to interpret.**

```agentscript
instructions: ->
    if @variables.isPremiumUser:
        | ask the user if they want to redeem their Premium points
    else:
        | ask the user if they want to upgrade to Premium service
```

The decision is deterministic; the wording is the model's. Encode compliance, pricing, eligibility and
routing after `->`; leave the conversational parts to `|`. Guard every subagent transition with
`available when` so a persuasive customer cannot talk the agent past a check.

> Blocks, variables, action targets, routing and the full syntax: `references/agent-script.md`.

---

## 6. Grounding & Prompt Templates

An agent is only as good as the context it reasons over. **Grounding** injects trusted data into the
prompt, which is what makes answers accurate and explainable and what reduces hallucination.

- **Prompt Templates** — reusable, parameterised prompts that merge record data and call the LLM, for
  summaries, drafts and classifications. Reach them from Agent Script with a `prompt://` target.
  Calling one from code, batch generation and cross-org deployment: `references/prompt-templates.md`.
- **RAG grounding via Data 360** — retrieve unified profile data, calculated insights and
  unstructured content through vector search. Build **custom retrievers** for domain-specific
  context. See `dya-data360`.
- **MCP** — ground from external systems exposed as MCP tools (`dya-headless360`).

Prefer grounding over fine-tuning for enterprise accuracy: it keeps data fresh, permission-aware and
auditable.

---

## 7. Invoking Agents Headlessly

Agents are not only chat windows:

- **Agent API** (REST) — start a session, send messages with context, receive structured responses,
  with **no logged-in user**. For server-side and customer-facing integrations.
- **AI Agent action** (Apex / Flow) — trigger any active agent from automation: a Quick Action, a
  screen flow, or limited agent-to-agent calls. Pass a user message and optional session id, then
  capture the response.

Endpoints, payloads, the `bypassUser` identity switch and the `sequenceId` counter:
`references/lifecycle-and-api.md`.

---

## 8. Testing & Evaluation — Non-Negotiable Before Launch

A non-deterministic system is tested at scale, never by eyeballing one chat.

- **Testing Center** (UI) — simulate scenarios with initial state and context variables.
- **Testing API** (REST) — batch-test many utterances; automate before activating.
- **Evaluations** (Agentforce DX, Beta) — YAML/JSON eval suites from the CLI. **Custom Scoring Evals**
  grade *decision quality*, not just whether an action ran.
- **`agent preview`** (CLI, GA) — scripted sessions with **trace files** showing how the agent routed.
  Unimplemented actions are mocked, so routing can be tested before they are written.
- **A/B Testing API** — compare agent versions against real traffic after launch.

Test subagent classification, action selection and grounding accuracy separately.

---

## 9. Observability

Once live, instrument it. **Agent Platform Tracing** writes a **span** per action execution into
**Data 360 DMOs**, queryable via SOQL and nested by parent. Reading them needs the Data Cloud Data
Access permission set. Query `ssot__AiAgentSession__dlm`, `ssot__AiAgentInteraction__dlm` and
`ssot__AiAgentInteractionStep__dlm`, plus `GenAIGatewayRequest__dlm` and `GenAIGeneration__dlm` for
prompts, tokens and model. `ssot__TelemetryTraceSpan__dlm` needs separate provisioning and its key on
steps is often empty — do not start there. `__dlm` marks a Data Model Object; see `dya-data360`.
**Session Tracing** and the Observability dashboards surface routing errors, slow actions and
ungrounded answers.

---

## 10. Security & the Trust Layer

- The **Einstein Trust Layer** enforces data masking, dynamic grounding, FLS and zero-data-retention
  with LLM providers on every session, however the agent is invoked — UI, API or MCP.
- Agents run with a **user and permission context**: an employee-facing agent acts with the running
  user's permissions, a customer-facing agent under a dedicated guest or service profile. Whatever
  that identity can see, the agent can surface, so scope it to the minimum deliberately. See
  `dya-permissions`.
- Apex actions enforce `with sharing` and `USER_MODE`. Never widen permissions to make a user-mode
  error disappear — that leaks the same data into reports and APIs.
- Treat agent instructions as an untrusted-input boundary: guard against prompt injection by scoping
  subagents tightly and validating action inputs in Apex.

---

## 11. Multi-Agent Orchestration (GA)

For complex domains, deploy **specialist subagents** coordinated by an **orchestrator** agent. The
orchestrator inspects each registered subagent's description and actions and routes to the best fit —
it *reasons* from descriptions rather than following a hard-coded map.

- **Agent and subagent descriptions become routing logic.** Make them precise and non-overlapping.
- Keep subagents focused on one domain; overlapping scopes cause mis-routing, the seam problem.
- Subagents can be backed by Apex, Flow and Prompt Template actions independently.
- Interop standards A2A and MCP let agents coordinate with tools and with other agents.
- **Handing off to a human is Omni-Channel's job.** The `routeWork` Flow action carries the work to a
  queue, and the same action routes work *to* an agent through `agentforceEmployeeAgentId`. Both
  directions of that seam are in `dya-omni-channel`.

---

## 12. Decision Matrix — Quick Reference

| Need | Solution |
|---|---|
| Decide when a capability applies | Subagent + classification description |
| Constrain what the agent may do | Subagent scope + Agent Script `available when` guards |
| Multi-step declarative automation | Flow action |
| Deterministic logic / callouts / cross-object | Apex `@InvocableMethod` action |
| Generate or transform text from records | Prompt Template action |
| Reuse an existing SOQL query as a capability | Named Query action |
| Hard business rule that must never be improvised | Agent Script expression |
| Ground answers in unified/customer data | Data 360 grounding + custom retriever |
| Ground from an external system | MCP tool (`dya-headless360`) |
| Run an agent server-side, no UI | Agent API |
| Trigger an agent from automation | AI Agent action (Apex/Flow) |
| Batch-test utterances | Testing API / Testing Center |
| Grade decision quality | Custom Scoring Evals |
| See how the agent routed | `agent preview` trace files / Session Tracing |
| Coordinate specialist agents | Multi-agent orchestration |
| Render agent output across channels | Agentforce Experience Layer (`dya-headless360`) |

---

## 13. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Vague subagent or action descriptions | Precise, intent-rich descriptions — they *are* the routing logic |
| One mega-subagent covering everything | One subagent per bounded job-to-be-done |
| Hoping the LLM follows a critical rule in prose | Encode it as an Agent Script expression |
| Non-bulkified Apex action | `List<Request>` in, `List<Result>` out; assume 200 |
| `WITH SECURITY_ENFORCED` in an action | `WITH USER_MODE` (removed in API 67+) |
| Apex action without a sharing keyword | `with sharing` + `WITH USER_MODE` |
| Raw `SObject` params / throwing raw exceptions to the agent | DTO wrappers + structured error results |
| Apex for what a Flow or Prompt Template handles | Declarative action |
| Widening a profile to silence a user-mode error | Grant only the minimum; fix the query |
| Shipping without batch testing | Testing API/Center + evals before activation |
| Overlapping subagent scopes | Focused, non-overlapping subagents |
| Fine-tuning for fresh enterprise facts | Ground via Data 360 (fresh, permission-aware) |
| Treating user input as trusted | Tight subagent scope + Apex input validation (prompt-injection guard) |

---

## Summary — The Five Commandments

1. **Descriptions are the program** — Atlas routes by reading subagent and action descriptions; write them like code.
2. **Determinism where it matters** — Agent Script and Apex actions for business-critical logic; let the LLM handle only the fuzzy, conversational parts.
3. **Ground everything** — Data 360 / retrievers / MCP for trusted, permission-aware context; prefer grounding over fine-tuning.
4. **Actions are Apex citizens** — bulkified, `with sharing`, `WITH USER_MODE`, structured errors; narrow and single-purpose.
5. **Test, evaluate, observe, and trust** — batch tests + Custom Scoring Evals before launch, Session Tracing after; the Einstein Trust Layer and least-privilege profiles on every path.
