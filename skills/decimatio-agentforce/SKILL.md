---
name: decimatio-agentforce
description: Salesforce Agentforce Summer '26 (API v67.0) — from zero to expert. What an AI agent is and how Atlas reasons; agent anatomy (Topics, Instructions, Actions); Agent Script; designing and building Apex/Flow/Prompt-Template actions; grounding with Data 360; invoking agents headlessly (Agent API); testing, evals, and observability; multi-agent orchestration; security and the Trust Layer. Load only when the user explicitly invokes this skill by name (`decimatio-agentforce`); do NOT auto-trigger on generic Agentforce, AI, or Salesforce questions.
---

# Salesforce Agentforce — From Zero to Expert

You are an expert Agentforce architect and developer. The reader may be **new to Agentforce**, so this skill builds the mental model first, then the implementation rules, then what changed in Summer '26. You **always** keep actions deterministic and bulkified, **always** ground answers in trusted data, and **always** enforce security through the Trust Layer. Follow every rule below.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/`:

- `references/apex-actions.md` — full `@InvocableMethod` / `@InvocableVariable` action, action-type comparison, security, bulkification, error handling, and how descriptions feed Atlas.
- `references/lifecycle-and-api.md` — Agent API (headless conversations), invoking agents from Apex/Flow, Agentforce DX/CLI `agent preview`, Testing API/Center, evaluations, and a primer on Agent Script.

Load a reference when building that exact thing. Agentforce actions are Apex/Flow — for deep Apex rules load `decimatio-apex`; for the data layer that grounds agents load `decimatio-data360`; for exposing/serving agents across surfaces load `decimatio-headless360`.

---

## Platform Context — Summer '26 / API v67.0

**Current API version: 67.0 (Summer '26).** Agentforce metadata and the Apex/Flow behind actions are saved at `67.0`. This release is a major step for Agentforce:

- **Atlas Reasoning Engine 3.0** powers reasoning and the new multi-agent routing.
- **Multi-Agent Orchestration is GA** (Summer '26) — an orchestrator agent routes work to specialist subagents based on their descriptions and actions. See §11.
- **Agent Script is GA and open source** — a hybrid language combining natural-language instructions with deterministic programmatic expressions (if/else, transitions, variables, subagent/action selection). The new Agent Builder uses a graph-based engine. Legacy agents can auto-migrate to Agent Script. See §5.
- **Agentforce DX matures** — `agent preview` is GA (scriptable test sessions), agent project scaffolding, one-command agent users, trace files, and richer YAML/JSON-defined evaluations (Beta). See §8.
- **Agentforce Experience Layer (AXL)** — the agent-facing half of Headless 360's experience layer: define an interaction once, render natively across Slack, Teams, Voice, mobile, ChatGPT, Claude, Gemini. See `decimatio-headless360`.
- **Apex actions inherit API 67 security defaults** — `with sharing` and `USER_MODE` by default; `WITH SECURITY_ENFORCED` no longer compiles. See §4 and `decimatio-apex`.

---

## 1. Foundations — What Agentforce Is and How It Reasons

Agentforce is Salesforce's platform for building **autonomous AI agents**: software that can understand a request in natural language, **reason** about what to do, **plan** a sequence of steps, **act** by calling real business logic, and **respond** — all grounded in your Salesforce data.

The brain is the **Atlas Reasoning Engine**. It does not run a fixed decision tree; on every request it *reasons* from the descriptions you wrote. The loop:

1. **Intent / topic classification** — Atlas reads the user's message and picks the most relevant **Topic**.
2. **Plan** — it reads that Topic's scope, instructions, and the descriptions of the **Actions** available, and decides what to do (ask a question, run an action, use a prompt template).
3. **Ground (RAG)** — it pulls live, trusted context from Salesforce, **Data 360**, or external systems via MCP.
4. **Act** — it executes the chosen actions (Apex, Flow, Prompt Template, …) and checks results, looping if needed.
5. **Respond** — the final answer passes through the **Einstein Trust Layer** (masking, grounding checks, zero-retention) before it reaches the user.

**The single most important consequence:** Atlas chooses topics and actions by reading their **natural-language descriptions**. Vague descriptions = wrong routing. Your descriptions *are* the program. Treat them as carefully as code.

---

## 2. Anatomy of an Agent

| Building block | What it is | Who owns it |
|---|---|---|
| **Agent** | The deployed assistant, with a role, channels, and a user/permission context | Builder |
| **Topic** | A bounded job-to-be-done (e.g. "Order Management"). Holds the classification description, scope, and instructions | Builder |
| **Classification description** | Tells Atlas *when* this topic applies | Builder |
| **Scope** | What the agent may and may not do within the topic — a guardrail | Builder |
| **Instructions** | Natural-language rules (prompt-like) that shape behaviour and reference actions | Builder |
| **Action** | A concrete capability the agent can invoke: Apex, Flow, Prompt Template, Apex REST, Named Query | Developer |

### Writing Instructions (the high-leverage skill)

- One Topic = one coherent set of tasks. Don't make a mega-topic.
- Instructions live *inside* the Topic (not a separate metadata item) and may reference Actions by name.
- Be explicit and imperative; state preconditions and the order of operations.
- Use them as guardrails: say what *not* to do, not just what to do.
- Prefer **Agent Script** (§5) to encode hard business rules deterministically instead of hoping the LLM follows prose.

---

## 3. Designing Actions — Choose the Right Type

Actions are how the agent *does* things. Pick the least-code option that fits, and write a crisp label + description so Atlas can match intent.

| Need | Action type | Code? |
|---|---|---|
| Multi-step declarative automation, approvals, record updates | **Flow** (autolaunched) | NO |
| Generate/transform text grounded in records | **Prompt Template** | NO |
| Expose an existing SOQL query as an action | **Named Query** action | NO |
| Deterministic business logic, callouts, complex cross-object work | **Apex `@InvocableMethod`** | YES |
| Expose an existing Apex REST endpoint | **Apex REST agent action** (OpenAPI) | YES |
| Call another active agent | **AI Agent action** (Apex/Flow) | maybe |

Rule of thumb: **declarative for orchestration, Apex for deterministic logic the LLM must not improvise.** Keep each action narrow and single-purpose — Atlas composes small, well-described actions better than it drives one giant one.

---

## 4. Apex Actions — Best Practices

An Apex action is an `@InvocableMethod`. Its labels and descriptions are read by Atlas, so they are part of the contract.

```java
public with sharing class GetOrderStatusAction {

    public class Request {
        @InvocableVariable(label='Order Number' description='The customer order number to look up' required=true)
        public String orderNumber;
    }
    public class Result {
        @InvocableVariable(label='Status' description='Current fulfilment status of the order')
        public String status;
    }

    @InvocableMethod(
        label='Get Order Status'
        description='Returns the current fulfilment status for a given order number. Use when a customer asks where their order is.'
    )
    public static List<Result> run(List<Request> requests) {   // bulk in, bulk out
        Set<String> numbers = new Set<String>();
        for (Request r : requests) { numbers.add(r.orderNumber); }

        Map<String, Order> byNumber = new Map<String, Order>();
        for (Order o : [SELECT OrderNumber, Status FROM Order
                        WHERE OrderNumber IN :numbers WITH USER_MODE]) {
            byNumber.put(o.OrderNumber, o);
        }

        List<Result> results = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            res.status = byNumber.containsKey(r.orderNumber)
                ? byNumber.get(r.orderNumber).Status
                : 'Not found';
            results.add(res);
        }
        return results;
    }
}
```

Absolute rules:

- **Bulkify.** Actions do **not** bulkify automatically and each runs in its own transaction; if the same Apex is reused in Flow it can hit governor limits. Write every action as if it processes 200 records. Take `List<Request>`, return `List<Result>`.
- **One input/output wrapper class** with `@InvocableVariable`s; primitives or DTOs, never raw `SObject` you don't control.
- **`with sharing` + `WITH USER_MODE`** (API 67 defaults, but be explicit). `WITH SECURITY_ENFORCED` no longer compiles.
- **Descriptions are prompts.** Write a clear `label` and `description` on the method and every variable; keep them in sync with the action config in Agent Builder.
- **Handle errors gracefully** — return a structured result the agent can explain, don't throw raw exceptions; log via Platform Events (`decimatio-apex` §11).
- Keep actions **deterministic** — they exist precisely so the LLM does *not* improvise critical logic.

Full action skeletons, error patterns, and the action-type deep dive: `references/apex-actions.md`.

---

## 5. Agent Script — Deterministic Control (GA Summer '26)

Agent Script is the language behind the new Agent Builder. It blends natural-language instructions for conversational nuance with **programmatic expressions** for the parts that must be reliable.

Use Script expressions to: define `if/else` conditions and transitions; set, compare and mutate variables; and explicitly select which subagent or action runs. This produces **predictable, context-aware workflows that don't depend on LLM interpretation** for business-critical paths.

Guidance:
- Encode compliance, pricing, eligibility, and routing rules as Script expressions — never as hopeful prose.
- Let natural language handle the conversational, fuzzy parts; let Script handle the "must always happen" parts.
- After migrating a legacy agent to Script, run the built-in optimization tool to add deterministic controls.

---

## 6. Grounding & Prompt Templates

An agent is only as good as the context it reasons over. **Grounding** injects trusted data into the prompt so answers are accurate and explainable, reducing hallucination.

- **Prompt Templates** — reusable, parameterised prompts that merge in record/field data and call the LLM. Use for summaries, drafts, classifications.
- **RAG grounding via Data 360** — retrieve unified profile data, calculated insights, and unstructured content (via vector search) to ground responses. Build **custom retrievers** for domain-specific context. See `decimatio-data360`.
- **MCP** — ground from external systems exposed as MCP tools (see `decimatio-headless360`).

Always prefer grounding over fine-tuning for enterprise accuracy: it keeps data fresh, permission-aware, and auditable.

---

## 7. Invoking Agents Headlessly

Agents aren't only chat windows. You can drive them programmatically:

- **Agent API** (REST) — start a session, send messages with context, receive structured responses, with **no logged-in user** — for server-side and customer-facing integrations.
- **AI Agent action** (Apex / Flow) — trigger any active agent from automation: a Quick Action, a screen flow, or even limited agent-to-agent calls. Pass a user message + optional session id; capture the response.

Full Agent API flow and the Apex/Flow invocation pattern: `references/lifecycle-and-api.md`.

---

## 8. Testing & Evaluation — Non-Negotiable Before Launch

A non-deterministic system must be tested at scale, not by eyeballing one chat.

- **Testing Center** (UI) — simulate scenarios with initial conversation state and context variables (custom + standard) to check routing and personalisation.
- **Testing API** (REST) — batch-test many utterances programmatically; automate the eval before activating.
- **Evaluations** (Agentforce DX, Beta) — YAML/JSON-defined eval tests run from the CLI; **Custom Scoring Evals** grade *decision quality*, not just whether an action ran.
- **`agent preview`** (CLI, GA) — scripted interactive sessions (`start`/`send`/`sessions`/`end`) with **trace files** showing exactly how the agent routed and acted.
- **A/B Testing API** — run multiple agent versions against real traffic post-launch.

Test topic classification (does the right topic fire?), action selection, and grounding accuracy separately.

---

## 9. Observability

Once live, instrument it. **Agent Platform Tracing** writes a **span** for every action execution into **Data 360 DMOs** (e.g. `ssot__TelemetryTraceSpan__dlm`), queryable via SOQL — each span records its parent, giving you a trace tree of the agent's reasoning and actions. Require the Data Cloud Data Access permission set to read it. Use **Session Tracing** and the Observability dashboards to find routing errors, slow actions, and ungrounded answers.

---

## 10. Security & the Trust Layer

- The **Einstein Trust Layer** enforces data masking, dynamic grounding, FLS, and zero-data-retention with LLM providers on every session — regardless of how the agent is invoked (UI, API, MCP).
- Agents run with a **user/permission context**: employee-facing agents act with the user's permissions; customer-facing agents use a dedicated guest/service profile. Scope that profile to the minimum.
- Apex actions enforce `with sharing` + `USER_MODE`. Never widen permissions just to make a user-mode error disappear — that leaks data into reports/APIs too.
- Treat agent instructions as untrusted-input boundaries: guard against prompt injection by scoping topics tightly and validating action inputs in Apex.

---

## 11. Multi-Agent Orchestration (GA Summer '26)

For complex domains, deploy **specialist subagents** coordinated by an **orchestrator** agent. The orchestrator inspects each registered subagent's description and actions and routes the request to the best fit — it *reasons* from descriptions, it does not follow a hard-coded map.

Implications:
- **Agent and subagent descriptions become routing logic.** Make them precise and non-overlapping.
- Keep subagents focused on one domain; overlapping scopes cause mis-routing ("the seam problem").
- Subagents can be backed by Apex, Flow, and Prompt Template actions independently.
- Interop standards: A2A (agent-to-agent) and MCP let agents coordinate with tools and other agents.

---

## 12. Decision Matrix — Quick Reference

| Need | Solution |
|---|---|
| Decide when a capability applies | Topic + classification description |
| Constrain what the agent may do | Topic scope + Agent Script guardrails |
| Multi-step declarative automation | Flow action |
| Deterministic logic / callouts / cross-object | Apex `@InvocableMethod` action |
| Generate or transform text from records | Prompt Template action |
| Reuse an existing SOQL query as a capability | Named Query action |
| Hard business rule that must never be improvised | Agent Script expression |
| Ground answers in unified/customer data | Data 360 grounding + custom retriever |
| Ground from an external system | MCP tool (`decimatio-headless360`) |
| Run an agent server-side, no UI | Agent API |
| Trigger an agent from automation | AI Agent action (Apex/Flow) |
| Batch-test utterances | Testing API / Testing Center |
| Grade decision quality | Custom Scoring Evals |
| See how the agent routed | `agent preview` trace files / Session Tracing |
| Coordinate specialist agents | Multi-agent orchestration |
| Render agent output across channels | Agentforce Experience Layer (`decimatio-headless360`) |

---

## 13. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Vague Topic/Action descriptions | Precise, intent-rich descriptions — they *are* the routing logic |
| One mega-Topic covering everything | One Topic per bounded job-to-be-done |
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
| Treating user input as trusted | Tight topic scope + Apex input validation (prompt-injection guard) |

---

## Summary — The Five Commandments

1. **Descriptions are the program** — Atlas routes by reading Topic and Action descriptions; write them like code.
2. **Determinism where it matters** — Agent Script and Apex actions for business-critical logic; let the LLM handle only the fuzzy, conversational parts.
3. **Ground everything** — Data 360 / retrievers / MCP for trusted, permission-aware context; prefer grounding over fine-tuning.
4. **Actions are Apex citizens** — bulkified, `with sharing`, `WITH USER_MODE`, structured errors; narrow and single-purpose.
5. **Test, evaluate, observe, and trust** — batch tests + Custom Scoring Evals before launch, Session Tracing after; the Einstein Trust Layer and least-privilege profiles on every path.
