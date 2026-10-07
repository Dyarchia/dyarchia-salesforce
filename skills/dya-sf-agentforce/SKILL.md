---
name: dya-sf-agentforce
description: Salesforce Agentforce (Winter '27, API v68.0) — agent design, Agent Script, Apex, Flow and prompt-template actions, Data 360 grounding, Agent API, testing and evals, Trust Layer. Applies to GenAiPlannerBundle, GenAiPlugin, GenAiFunction and GenAiPromptTemplate metadata, Agent Script files, agent actions, agent tests and evals. Load before creating or editing anything in this scope.
---

# Salesforce Agentforce — From Zero to Expert

You **always** keep actions deterministic and bulkified, **always** ground answers in trusted data,
and **always** enforce security through the Trust Layer. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — release-coupled facts, including the security defaults an Apex action inherits.
- `references/shared/sharing-and-access.md` — the permission model binding an agent's run-as identity. **Read before designing a customer-facing agent.**
- `references/shared/governor-limits.md` — the budget an action spends, and why "one transaction per action" is no licence to skip bulkification.
- `references/building-an-agent.md` — **the end-to-end path**: prerequisites and org setup, the two authoring workflows, CLI commands, testing and activation. Start here if you have never built one.
- `references/agent-script.md` — the syntax: blocks, `->` logic versus `|` prompt instructions, variables, routing, `available when` guards.
- `references/agent-control-flow-pitfalls.md` — constructs that compile but behave differently from how they read. Read before debugging an agent that "ignores" its script.
- `references/agent-lifecycle-metadata.md` — the bundle on disk, why deploy is not publish, the writable-versus-snapshot bundle trap, and the `sf agent` surface.
- `references/apex-actions.md` — `@InvocableMethod` / `@InvocableVariable` actions, action-type comparison, security, bulkification, error handling.
- `references/prompt-templates.md` — calling a template from code, batch generation with `AiJobRun`, moving templates between orgs.
- `references/lifecycle-and-api.md` — the Agent API with real endpoints and payloads, invoking agents from Apex/Flow, `agent preview`, testing and evaluations.

Agentforce actions are Apex and Flow: deep Apex rules are `dya-sf-apex`, the data layer that grounds
agents is `dya-sf-data360`, and exposing agents across surfaces is `dya-sf-headless360`.

---

## Platform Context — Winter '27 / API v68.0

Save Agentforce metadata and the Apex or Flow behind actions at `68.0`.

- **`AiAgentDefinition` / `AiAgentDefinitionVersion` are GA at 68.0, and both orgs must be on 68.0.**
  A deploy from a 68.0 sandbox into a 67.0 org carries neither, silently.
- **The 24 additional conversation languages are Beta**, not for production. Check the list
  before promising a language.
- **An Apex action is Apex**, so it inherits the 67.0+ security defaults: `with sharing` and
  `USER_MODE`, and `WITH SECURITY_ENFORCED` no longer compiles. See §4 and `dya-sf-apex`.
- **Since April 2026 a Topic is a subagent.** Functionality is unchanged; older documentation,
  parts of the UI and help-article URLs still say "topic". This skill says **subagent**.

> Everything else Winter '27 adds — MCP interoperability, observability and custom scorers, Voice
> improvements, Data 360 SQL from Apex, and the standing facts about Atlas 3.0, Agent Script and
> Agentforce DX: `references/release-notes.md`.

## Summary — The Five Commandments

1. **Write descriptions as the program** — Atlas routes by reading subagent and action descriptions; write them like code.
2. **Enforce determinism where it matters** — use Agent Script and Apex actions for business-critical logic; let the LLM handle only the fuzzy, conversational parts.
3. **Ground everything** — use Data 360 / retrievers / MCP for trusted, permission-aware context; prefer grounding over fine-tuning.
4. **Build actions as Apex citizens** — bulkified, `with sharing`, `WITH USER_MODE`, structured errors; narrow and single-purpose.
5. **Test, evaluate, observe, and trust** — run batch tests + Custom Scoring Evals before launch and Session Tracing after; keep the Einstein Trust Layer and least-privilege profiles on every path.

---

## 1. Foundations — What Agentforce Is and How It Reasons

An agent understands a request in natural language and acts on it, grounded in your Salesforce data.

The **Atlas Reasoning Engine** has no fixed decision tree; it reasons on every request.

1. **Intent classification** — Atlas reads the message and picks the most relevant **subagent**.
2. **Plan** — it reads that subagent's scope, instructions and available **Actions**' descriptions,
   then decides: ask a question, run an action, use a prompt template.
3. **Ground (RAG)** — it pulls live, trusted context from Salesforce, **Data 360** or external
   systems via MCP.
4. **Act** — it runs the chosen actions (Apex, Flow, Prompt Template) and checks results, looping
   if needed.
5. **Respond** — the answer passes through the **Einstein Trust Layer** (masking, grounding checks,
   zero-retention) before reaching the user.

Treat descriptions as code: Atlas chooses subagents and actions by reading their
**natural-language descriptions**, so vague descriptions route wrongly.

---

## 2. Anatomy of an Agent

| Building block | What it is | Who owns it |
|---|---|---|
| **Agent** | The deployed assistant, with a role, channels and a user/permission context | Builder |
| **Subagent** (formerly Topic) | A bounded job-to-be-done, e.g. "Order Management". Holds the classification description, scope and instructions | Builder |
| **Classification description** | Tells Atlas *when* this subagent applies | Builder |
| **Scope** | What the agent may and may not do within the subagent — a guardrail | Builder |
| **Instructions** | Natural-language rules (prompt-like) that shape behaviour and reference actions | Builder |
| **Action** | A capability the agent invokes: Apex, Flow, Prompt Template, Apex REST, Named Query | Developer |

### Writing Instructions

- Build one subagent per coherent set of tasks. Never build a mega-subagent.
- Write instructions *inside* the subagent, not as separate metadata; they may reference Actions by
  name.
- Write instructions explicitly and imperatively. State preconditions and the order of operations.
- State what *not* to do, too.
- Encode hard business rules in **Agent Script** (§5) rather than hoping the LLM follows prose.

---

## 3. Designing Actions — Choose the Right Type

Pick the least-code option that fits, with a crisp label and description so Atlas can match intent.

| Need | Action type | Code? |
|---|---|---|
| Multi-step declarative automation, approvals, record updates | **Flow** (autolaunched) | NO |
| Generate/transform text grounded in records | **Prompt Template** | NO |
| Expose an existing SOQL query as an action | **Named Query** action | NO |
| Deterministic business logic, callouts, complex cross-object work | **Apex `@InvocableMethod`** | YES |
| Expose an existing Apex REST endpoint | **Apex REST agent action** (OpenAPI) | YES |
| Call another active agent | **AI Agent action** (Apex/Flow) | maybe |

**Declarative for orchestration, Apex for deterministic logic the LLM must not improvise.** Keep each
action narrow and single-purpose: Atlas composes small, well-described actions better than one giant
one.

---

## 4. Apex Actions — Best Practices

Class skeleton, wrappers and the bulk-in bulk-out signature: `references/apex-actions.md`.

- **Bulkify anyway.** An agent invokes an action **once per turn, in its own transaction**, so it
  never passes 200 records — but a Flow reusing the same `@InvocableMethod` **always passes a
  `List`**, often the whole 200-record trigger batch. Take `List<Request>`, return `List<Result>`.
  See `dya-sf-flow`.
- **Use one input and one output wrapper class** with `@InvocableVariable`s; use primitives or DTOs,
  never a raw `SObject` you do not control.
- **Declare `with sharing` and `WITH USER_MODE`** explicitly, although they are the defaults from
  API 67.0.
- **Write descriptions as prompts.** Put a clear `label` and `description` on the method and every
  variable, and keep them in sync with the action config in Agent Builder.
- **Return structured errors; do not throw.** Return a success flag and a human-readable message the
  agent can relay; the agent cannot explain a thrown exception to a user. A Flow-facing action is the
  **opposite**: throwing is how the fault message reaches a Fault Path. In a method serving both,
  return the result and let the Flow branch on it. Log failures durably through Platform Events
  (`dya-sf-apex`).

---

## 5. Agent Script — Deterministic Control (GA)

Agent Script is the compiled language behind Agentforce Builder.
**`->` logic instructions run deterministically every time; `|` prompt instructions go to the LLM to
interpret.**

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

Ground answers by injecting trusted data into the prompt, so they are accurate and explainable.

- **Prompt Templates** — reusable, parameterised prompts that merge record data and call the LLM, for
  summaries, drafts and classifications. Reach them from Agent Script with a `prompt://` target.
  Calling one from code, batch generation and cross-org deployment: `references/prompt-templates.md`.
- **RAG grounding via Data 360** — retrieve unified profile data, calculated insights and
  unstructured content through vector search. Build **custom retrievers** for domain-specific
  context. See `dya-sf-data360`.
- **MCP** — ground from external systems exposed as MCP tools (`dya-sf-headless360`).

Prefer grounding over fine-tuning for enterprise accuracy; grounding keeps data fresh,
permission-aware and auditable.

---

## 7. Invoking Agents Headlessly

- **Agent API** (REST) — start a session, send messages with context, receive structured responses,
  with **no logged-in user**. For server-side and customer-facing integrations.
- **AI Agent action** (Apex / Flow) — trigger any active agent from automation: a Quick Action, a
  screen flow, or limited agent-to-agent calls. Pass a user message and optional session id; capture
  the response.

Endpoints, payloads, the `bypassUser` identity switch and the `sequenceId` counter:
`references/lifecycle-and-api.md`.

---

## 8. Testing & Evaluation — Non-Negotiable Before Launch

Test at scale before launch; one chat proves nothing.

- **Testing Center** (UI) — simulate scenarios with initial state and context variables.
- **Testing API** (REST) — batch-test many utterances; automate before activating.
- **Evaluations** (Agentforce DX, Beta) — YAML/JSON eval suites from the CLI. **Custom Scoring Evals**
  grade *decision quality*, not only whether an action ran.
- **`agent preview`** (CLI, GA) — scripted sessions with **trace files** showing how the agent routed.
  Unimplemented actions are mocked, so routing is testable before they are written.
- **A/B Testing API** — compare agent versions against real traffic after launch.

Test subagent classification, action selection and grounding accuracy separately.

---

## 9. Observability

Query `ssot__AiAgentSession__dlm`, `ssot__AiAgentInteraction__dlm` and
`ssot__AiAgentInteractionStep__dlm`, plus `GenAIGatewayRequest__dlm` and `GenAIGeneration__dlm` for
prompts, tokens and model. Do not start from `ssot__TelemetryTraceSpan__dlm`: it needs separate
provisioning and its key on steps is often empty.

**Agent Platform Tracing** writes a **span** per action execution into **Data 360 DMOs**, queryable
via SOQL and nested by parent. Reading them needs the Data Cloud Data Access permission set.
`__dlm` marks a Data Model Object; see `dya-sf-data360`.
**Session Tracing** and the Observability dashboards surface routing errors, slow actions and
ungrounded answers.

---

## 10. Security & the Trust Layer

- The **Einstein Trust Layer** enforces data masking, dynamic grounding, FLS and zero-data-retention
  with LLM providers on every session, whether invoked by UI, API or MCP.
- Scope the agent's **user and permission context** to the minimum; the agent can surface whatever
  that identity sees. An employee-facing agent acts with the running user's permissions, a
  customer-facing agent under a dedicated guest or service profile. See `dya-sf-permissions`.
- Never widen permissions to make a user-mode error disappear; that leaks the same data into reports
  and APIs.
- Treat agent instructions as an untrusted-input boundary: guard against prompt injection by scoping
  subagents tightly and validating action inputs in Apex.

---

## 11. Multi-Agent Orchestration (GA)

An **orchestrator** agent routes to **specialist subagents** by reading their descriptions and
actions — reasoning, not a hard-coded map.

- Make agent and subagent descriptions precise and non-overlapping.
- Keep each subagent to one domain; overlapping scopes cause mis-routing, the seam problem.
- Back each subagent with Apex, Flow and Prompt Template actions independently, as it needs.
- Use the interop standards A2A and MCP to let agents coordinate with tools and other agents.
- **Hand off to a human through Omni-Channel.** The `routeWork` Flow action carries the work to a
  queue, and the same action routes work *to* an agent through `agentforceEmployeeAgentId`. Both
  directions of that seam are in `dya-sf-omni-channel`.

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
| Ground from an external system | MCP tool (`dya-sf-headless360`) |
| Run an agent server-side, no UI | Agent API |
| Trigger an agent from automation | AI Agent action (Apex/Flow) |
| Batch-test utterances | Testing API / Testing Center |
| Grade decision quality | Custom Scoring Evals |
| See how the agent routed | `agent preview` trace files / Session Tracing |
| Coordinate specialist agents | Multi-agent orchestration |
| Render agent output across channels | Agentforce Experience Layer (`dya-sf-headless360`) |

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
