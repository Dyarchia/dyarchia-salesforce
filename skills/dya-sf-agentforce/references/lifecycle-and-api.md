# Agentforce Lifecycle & APIs — Reference Implementation (Winter '27 / API v68.0)

Invoking agents from Flow and Apex, and the Agent API for headless conversations.

## Invoking an Agent From Apex / Flow (AI Agent Action)

In Flow, add an **Action** element, search the **AI Agent Action** folder, pick the agent, pass a user message and an optional session id, and capture an agent-response output variable. Bind the message and session id to input variables so they populate dynamically.

In Apex, call the agent's **Invocable Action** (its API name is on the agent's detail page in Setup). A Quick Action, a screen flow or a flow-based agent action can then drive the agent, which enables limited agent-to-agent communication.

## Agent API — Headless Conversations (REST)

Call every endpoint below against `https://api.salesforce.com/einstein/ai-agent/v1` — a
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
  Choose it deliberately; this identity governs what the agent can see. See `dya-sf-permissions`.
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

**Increment `sequenceId` with every message in the session**; you own the counter. Reusing or
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

Treat it like any server integration: keep secrets out of the client, use a least-privilege token,
and let the Trust Layer do masking and grounding. Salesforce publishes a Postman collection for the API.

## Agentforce DX — Scaffold, Preview, Test

Start a DX project with the Local Info Agent sample, then provision the agent user in one command:

```bash
sf template generate project --name my-agents --template agent
sf org create agent-user --target-org <alias>
```

`sf agent generate template` is not a scaffold: it packages a `BotTemplate` from a namespaced org for
managed-package distribution and does not work for Agent Script agents. The deploy, publish and
activate commands are in `references/agent-lifecycle-metadata.md`.

- Previews, trace files and production telemetry: `references/observability.md`.
- Test specs, `AiEvaluationDefinition`, the Testing API, custom scorers and CI: `references/testing-and-evaluation.md`.

## Agent Script — Primer

Agent Script is the GA, open-source language behind the new graph-based Agent Builder. It mixes natural-language instructions with **deterministic expressions**:

- `if/else` conditions and **transitions** between steps.
- **Variables**: set, mutate, compare.
- Explicit **subagent / action selection** instead of leaving it to LLM interpretation.

When migrating a legacy agent, let it auto-convert to Script, then run the optimization tool to inject deterministic controls.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Broad OAuth scope for Agent API | Least-privilege, agent-scoped token |
| Reusing or resetting `sequenceId` | Increment it once per message in the session |
| No `externalSessionKey` stored client-side | Generate one per conversation and log it as the correlation key |
| Hard rules left to LLM prose | Agent Script expressions |
| Manual service-user setup | `sf org create agent-user` |
