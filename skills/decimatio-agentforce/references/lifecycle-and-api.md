# Agentforce Lifecycle & APIs — Reference Implementation (API v67.0)

Full implementations referenced from SKILL.md §5, §7, §8. Load this when invoking an agent programmatically, testing it, or working with Agent Script.

## Invoking an Agent From Apex / Flow (AI Agent Action)

Any active agent can be triggered from automation. In Flow, add an **Action** element, search the **AI Agent Action** folder, pick the agent, then pass a user message and an optional session id; capture an agent-response output variable. As a best practice bind the message and session id to input variables so they populate dynamically.

In Apex, call the corresponding **Invocable Action** for the agent (the agent's API name is on its detail page in Setup). This lets a Quick Action button, a screen flow, or even a flow-based agent action drive the agent — and enables limited agent-to-agent communication.

## Agent API — Headless Conversations (REST)

The Agent API lets external systems run an agent **without a logged-in user**: start a session, send messages with context, receive structured responses. Conceptual flow:

1. **Authenticate** with OAuth (client-credentials / JWT for server-to-server) and obtain an access token scoped to the agent's connected app.
2. **Start a session** against the agent's API name → returns a `sessionId`.
3. **Send a message** with the user utterance and any context variables → returns the agent's structured response (messages, actions taken, citations).
4. **Continue** the conversation by reusing the `sessionId`.
5. **End the session** when done.

Treat the API like any server integration: store no secrets in the client, scope the token tightly (least privilege), and let the Trust Layer enforce masking/grounding. Use it for customer-facing channels and back-end automation where there's no UI.

## Agentforce DX / CLI — Build and Preview

```bash
# Scaffold a runnable sample agent (Local Info Agent: Apex + Prompt + Flow subagents)
sf agent generate template

# Provision a service agent user in one command (no manual setup)
sf agent generate agent-user

# Scripted interactive preview session (GA): start → send → list → end
sf agent preview start --api-name My_Agent --output-dir ./previews
sf agent preview send  --session-id <id> --message "Where is order 12345?"
sf agent preview sessions
sf agent preview end   --session-id <id>
```

`agent preview` writes **trace files** so you can inspect exactly how the agent classified the topic, which actions it called, and what it returned — the fastest way to debug routing and action selection locally.

## Testing & Evaluation

| Tool | Surface | Use |
|---|---|---|
| **Testing Center** | UI (Agent Builder) | Simulate scenarios with initial state + custom/standard context variables |
| **Testing API** | REST | Batch-test many utterances programmatically; automate before activation |
| **Evaluations** | CLI (Beta) | YAML/JSON-defined eval suites run headlessly |
| **Custom Scoring Evals** | UI/API | Grade *decision quality*, not just whether an action ran |
| **A/B Testing API** | REST | Compare agent versions against real production traffic |

What to test, separately:
- **Topic classification** — does the intended Topic fire for representative utterances (and *not* fire for out-of-scope ones)?
- **Action selection** — does Atlas pick the right action and fill parameters correctly?
- **Grounding accuracy** — is the answer supported by retrieved data (no hallucination)?

Example eval (shape; exact schema evolves):

```yaml
# orders-eval.yaml
name: order-status-eval
testCases:
  - utterance: "Where is my order 12345?"
    expectedTopic: Order_Management
    expectedActions:
      - Get_Order_Status
    contextVariables:
      customerName: "Ada Lovelace"
  - utterance: "I want to return a defective item"
    expectedTopic: Returns
```

## Agent Script — Primer

Agent Script is the GA, open-source language behind the new graph-based Agent Builder. It mixes natural-language instructions with **deterministic expressions**:

- `if/else` conditions and **transitions** between steps.
- **Variables**: set, mutate, compare.
- Explicit **subagent / action selection** instead of leaving it to LLM interpretation.

Pattern: use natural language for conversational, ambiguous handling; use Script expressions for anything that must be reliable (eligibility, pricing, compliance, escalation routing). When migrating a legacy agent, let it auto-convert to Script, then run the optimization tool to inject deterministic controls and boost reliability.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Eyeballing one chat as "testing" | Batch Testing API + evals + trace review |
| Grading only "did the action run" | Custom Scoring Evals on decision quality |
| Broad OAuth scope for Agent API | Least-privilege, agent-scoped token |
| Hard rules left to LLM prose | Agent Script expressions |
| Manual service-user setup | `sf agent generate agent-user` |
| Debugging routing by guesswork | `agent preview` trace files / Session Tracing |
