# Agentforce Lifecycle & APIs — Reference Implementation (Winter '27 / API v68.0)

Full implementations for SKILL.md §5, §7, §8.

## Invoking an Agent From Apex / Flow (AI Agent Action)

In Flow, add an **Action** element, search the **AI Agent Action** folder, pick the agent, pass a user message and an optional session id, and capture an agent-response output variable. Bind the message and session id to input variables so they populate dynamically.

In Apex, call the agent's **Invocable Action** (its API name is on the agent's detail page in Setup). A Quick Action, a screen flow or a flow-based agent action can then drive the agent, which enables limited agent-to-agent communication.

## Agent API — Headless Conversations (REST)

Every endpoint below is against `https://api.salesforce.com/einstein/ai-agent/v1` — a
Salesforce-wide host, **not** your My Domain URL, which appears separately inside the session
payload.

### 0. Get the agent id

An 18-character id. Where to find it depends on which builder made the agent:

- **Legacy Agentforce Builder** — open the agent from Setup and take the id from the end of the URL:
  `…/lightning/setup/EinsteinCopilot/0XxSB000000IPCr0AO/edit` → `0XxSB000000IPCr0AO`.
- **New Agentforce Builder** — reached through Agentforce Studio in the App Launcher; it has the
  Canvas/Script view picker.

### 1. Authenticate — client credentials

```bash
curl https://{MY_DOMAIN_URL}/services/oauth2/token \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id={CONSUMER_KEY}' \
  --data-urlencode 'client_secret={CONSUMER_SECRET}'
```

Returns `access_token`. `MY_DOMAIN_URL` comes from Setup › My Domain › *Current My Domain URL*.

### 2. Start a session

```bash
curl -X POST https://api.salesforce.com/einstein/ai-agent/v1/agents/{AGENT_ID}/sessions \
  --header 'Content-Type: application/json' \
  --header 'Authorization: Bearer {ACCESS_TOKEN}' \
  --data '{
    "externalSessionKey": "{RANDOM_UUID}",
    "instanceConfig": { "endpoint": "https://{MY_DOMAIN_URL}" },
    "streamingCapabilities": { "chunkTypes": ["Text"] },
    "bypassUser": true
  }'
```

- **`bypassUser`** — `true` runs as the **agent-assigned user**; `false` runs as the token's user.
  This identity governs what the agent can see; choose it deliberately. See `dya-sf-permissions`.
- **`externalSessionKey`** — a UUID you generate to trace this conversation in the agent's event
  logs. Log it on your side too, or you lose the correlation.

The response carries the `sessionId`, a `_links` block with the message/stream/end URLs, and the
agent's opening `messages`.

### 3. Send a message

```bash
curl 'https://api.salesforce.com/einstein/ai-agent/v1/sessions/{SESSION_ID}/messages' \
  --header 'Content-Type: application/json' \
  --header 'Authorization: Bearer {ACCESS_TOKEN}' \
  --data '{
    "message": {
      "sequenceId": {SEQUENCE_ID},
      "type": "Text",
      "text": "Show me the cases associated with Lauren Bailey."
    }
  }'
```

**`sequenceId` increases with every message in the session** — you own the counter. Reusing or
resetting it looks like the agent losing context.

### 4. The rest of the surface

| Endpoint | Method | Purpose |
|---|---|---|
| `/agents/{AGENT_ID}/sessions` | POST | Start a session |
| `/sessions/{SESSION_ID}/messages` | POST | Synchronous message — one response when complete |
| `/sessions/{SESSION_ID}/messages/stream` | POST | Server-sent events — partial chunks as they generate |
| `/sessions/{SESSION_ID}/feedback` | POST | Submit feedback against a message |
| `/sessions/{SESSION_ID}` | DELETE | End the session |

Use the streaming endpoint when a human is waiting; the synchronous one for back-end automation
where partial output has no value.

A response `message` carries `type` (for example `Inform`), the `message` text, `isContentSafe`,
`result`, and `citedReferences` — the citations let you show *why* the agent said something.

Treat it like any server integration: no secrets in the client, least-privilege token, and let the
Trust Layer do masking and grounding. Salesforce publishes a Postman collection for the API.

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

`agent preview` writes **trace files** showing how the agent classified the topic, which actions it called, and what they returned.

## Testing & Evaluation

| Tool | Surface | Use |
|---|---|---|
| **Testing Center** | UI (Agent Builder) | Simulate scenarios with initial state + custom/standard context variables |
| **Testing API** | REST | Batch-test many utterances programmatically; automate before activation |
| **Evaluations** | CLI (Beta) | YAML/JSON-defined eval suites run headlessly |
| **Custom Scoring Evals** | UI/API | Grade *decision quality*, not only whether an action ran |
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

## Agent Health Monitoring Alerts

Agent health alerting runs through the Tableau data-alerts resource, not an agent-shaped endpoint.
**There is no `sf agent alert` subcommand.**

```bash
sf api request rest "/services/data/vXX.X/tableau/dataAlerts" --target-org <alias>
```

Alerts carry `dataAlertType: "agenthealthmonitoring"`. The UI equivalent lives at
`/lightning/n/standard-AgentforceStudio?c__nav=alerts`.

- **`ownerId` is required on the list call.** There is no unfiltered list.
- **A GET for a single alert returns 405.** List and filter client-side. Delete returns 204.
- **Thresholds are raw 0–1 ratios, not display percentages.** 5% is `"0.05"`; `"1"` means 100%, not
  1%. Getting it wrong fires the monitor on everything.
- **The POST field names and casing differ from the GET response.** POST uses `utterance` where GET
  returns `alertName`, and PascalCase `type` discriminators. Posting a GET body straight back fails.

Notification counts from `/connect/notifications/status` are **org-global**, not per alert.

## Agent Script — Primer

Agent Script is the GA, open-source language behind the new graph-based Agent Builder. It mixes natural-language instructions with **deterministic expressions**:

- `if/else` conditions and **transitions** between steps.
- **Variables**: set, mutate, compare.
- Explicit **subagent / action selection** instead of leaving it to LLM interpretation.

When migrating a legacy agent, let it auto-convert to Script, then run the optimization tool to inject deterministic controls.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Eyeballing one chat as "testing" | Batch Testing API + evals + trace review |
| Grading only "did the action run" | Custom Scoring Evals on decision quality |
| Broad OAuth scope for Agent API | Least-privilege, agent-scoped token |
| Hard rules left to LLM prose | Agent Script expressions |
| Manual service-user setup | `sf agent generate agent-user` |
| Debugging routing by guesswork | `agent preview` trace files / Session Tracing |
