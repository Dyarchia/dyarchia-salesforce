---
name: decimatio-integration-overview
description: Salesforce integration decision hub (Summer '26 / API v67.0) — the router and decision framework for the decimatio-integration-* family. The six integration patterns, sync vs async, idempotency/retry/governor concerns, the master "I need X with Y in manner Z" decision matrix, the authoring-surface map (Apex/Flow/LWC/no-code), and the API-version-retirement facts. Load only when the user explicitly invokes this skill by name (`decimatio-integration-overview`); do NOT auto-trigger on generic integration questions.
---

# Salesforce Integration — Decision Hub

You are an expert Salesforce integration architect. This skill does not teach individual protocols — it **routes** you to the right one and the right authoring surface, then hands off to a sibling skill. Use it to choose; use the siblings to build. Follow every rule below.

The `decimatio-integration-*` family (load the one the decision points to):

- `decimatio-integration-inbound-apis` — standard APIs external systems call: REST (+composite), SOAP, Bulk 2.0, GraphQL, Connect/UI/Metadata/Tooling.
- `decimatio-integration-inbound-apex` — custom endpoints you expose: Apex REST (`@RestResource`), Apex SOAP, Sites/Experience Cloud.
- `decimatio-integration-outbound` — Salesforce calling out: Apex callouts + async, Flow HTTP Callout, External Services, Outbound Messages, Salesforce Connect, LWC→external.
- `decimatio-integration-events` — Platform Events, Change Data Capture, Pub/Sub API, webhook patterns.
- `decimatio-integration-auth` — OAuth flows, External Client Apps vs Connected Apps, Named/External Credentials, "Any API Auth", SOAP login() retirement.
- `decimatio-integration-connectors-mcp` — MuleSoft, Heroku, AppExchange, Hosted MCP servers / Headless 360 / Agent API.

This family sits **on top of** the core decimatio skills and defers to them: async/governor detail → `decimatio-apex`; Flow mechanics → `decimatio-flow`; LWS/CSP → `decimatio-lwc`; agent actions → `decimatio-agentforce`; Data 360 ingestion → `decimatio-data360`; MCP/HXL → `decimatio-headless360`.

---

## Platform Context — Summer '26 / API v67.0 (integration-relevant)

- **Apex v67 security defaults** flip and they hit integration code hardest: SOQL/SOSL/DML default to `USER_MODE`, omitted sharing defaults to `with sharing`, and `WITH SECURITY_ENFORCED` no longer compiles. Server-to-server code that assumed system-mode access can silently return fewer rows or throw after a class is bumped to 67.0. Behaviour keys off **each class's compiled API version**, not the org — bump deliberately and test. See `decimatio-apex`.
- **SOAP `login()` retires Summer '27** for API 31.0–64.0 (already gone in 65.0+); the new **"Any API Auth"** user permission gates it and is enforced by default in new orgs. Migrate username/password SOAP auth to OAuth via **External Client Apps**. See `decimatio-integration-auth`.
- **Platform API version retirement**: 21.0–30.0 already retired; **31.0–40.0 deprecate Summer '27, retire Summer '28** — integrations must be on **41.0+**. This is about the `vXX.X` in standard-endpoint URLs (`/services/data/…`, SOAP, Bulk); it explicitly **does NOT retire** custom Apex REST/SOAP web services, Apex classes, triggers, or Visualforce.
- **Hosted MCP servers are GA** — a first-class integration surface (`decimatio-integration-connectors-mcp`).
- **HTTPS is mandatory** for all external resources and endpoints.
- **Connect REST API** moved onto the per-org/24h Platform API limit pool (except Chatter-touching calls).
- **Salesforce-to-Salesforce** native feature ends support Summer '26, stops functioning Spring '27 — migrate to MuleSoft / Data Cloud One / Cross-Org adapter.

---

## 1. The Six Integration Patterns (the vocabulary)

Salesforce's official Integration Patterns and Practices defines the canonical patterns. Name the pattern first; the technology follows.

| Pattern | Direction | Sync? | Canonical tech |
|---|---|---|---|
| **Request & Reply** | SF → external | Sync | Apex callout / Flow HTTP Callout (caller waits for the answer) |
| **Fire & Forget** | SF → external | Async | Platform Event / future-Queueable callout (don't wait) |
| **Batch Data Synchronization** | both | Async | Bulk API 2.0 / ETL / MuleSoft |
| **Remote Call-In** | external → SF | Sync | REST/SOAP/Apex REST/Bulk (external system drives) |
| **UI Update Based on Data Changes** | SF → UI/external | Async | CDC / Platform Events over Pub/Sub |
| **Data Virtualization** | SF reads external | Sync | Salesforce Connect / External Objects |

---

## 2. First Cut — Direction and Who Initiates

```
Who starts the interaction?
├─ External system calls Salesforce ........... INBOUND
│    ├─ Standard data ops (CRUD/query/bulk) ... decimatio-integration-inbound-apis
│    └─ Custom endpoint / bespoke contract .... decimatio-integration-inbound-apex
├─ Salesforce calls external .................. OUTBOUND
│    └─ (Apex, Flow, External Services, Connect, LWC) ... decimatio-integration-outbound
├─ Either side reacts to an event ............. EVENT-DRIVEN
│    └─ (Platform Events, CDC, Pub/Sub) ....... decimatio-integration-events
└─ Don't hand-code it ......................... CONNECTORS
     └─ (MuleSoft, MCP, AppExchange) .......... decimatio-integration-connectors-mcp

Cross-cutting on every path: authentication → decimatio-integration-auth
```

---

## 3. Sync vs Async — the Load-Bearing Choice

- **Synchronous (request-reply)** when the caller genuinely needs the answer *now* to proceed (a user is waiting; the next step depends on the result). Costs: tight coupling, the caller blocks, both systems must be up, governor/timeout limits apply hard.
- **Asynchronous (fire-and-forget / event)** for everything else — and prefer it. Decouples availability, absorbs volume, survives the other system being down. Costs: eventual consistency, you must design idempotency and reconciliation.

Default to **async/event** for system-to-system data movement; reserve **sync** for user-facing, answer-now dependencies.

---

## 4. Cross-Cutting Non-Negotiables

- **Idempotency** — any retried or fire-and-forget message must be safe to process twice (dedupe on an external id / event replay id). Upsert by external id, never blind insert.
- **Bulkification & governor limits** — ≤100 callouts per transaction, 6 MB/12 MB sync/async payloads; use Composite/Bulk to collapse API calls; never callout in a loop. Full detail in `decimatio-apex`.
- **Error handling & retry** — Platform Events give 72h replay; Outbound Messages auto-retry; Apex callouts need explicit retry/backoff. Always log failures durably (Platform Events → log object).
- **Security** — OAuth over username/password; External Client Apps over Connected Apps; Named/External Credentials over hard-coded secrets and Remote Site Settings; mandatory HTTPS; least-privilege permission sets; v67 user-mode awareness.
- **Version hygiene** — target API 41.0+ (ideally current); never build new on a soon-retired version.

---

## 5. Master Decision Matrix

| I need to… | …in manner | Use | From | Status |
|---|---|---|---|---|
| Let an external app read/write SF records | real-time, <10k | REST API (Composite for multi-op) | any HTTP client | GA |
| Load millions of rows into/out of SF | batch/ETL | Bulk API 2.0 | client / Data Loader | GA |
| Expose a bespoke endpoint with custom logic | request-reply | Apex REST (`@RestResource`) | Apex | GA |
| Atomic multi-object write in one round trip | transactional | Composite / Composite Graph | any HTTP client | GA |
| Have SF call an external API for an answer | sync | Apex HTTP callout | Apex | GA |
| Have SF call an external API, no code | sync/async | Flow HTTP Callout + Named Credential | Flow | GA |
| Surface external data live without storing it | virtualization | Salesforce Connect (OData/Apex adapter) | declarative/Apex | GA |
| Notify external systems of SF changes | streaming | CDC / Platform Events over Pub/Sub API | external gRPC client | GA |
| Decouple producers/consumers inside SF | pub/sub | Platform Events | Apex/Flow | GA |
| Call an external API from a component UI | browser | Apex proxy (preferred) or `fetch` + CSP | LWC | GA |
| Authenticate a server-to-server integration | token | OAuth JWT Bearer + External Client App | ECA | GA |
| Store outbound credentials securely | any | Named + External Credentials | Apex/Flow | GA |
| Orchestrate across many systems | middleware | MuleSoft Anypoint / for Flow | MuleSoft | GA |
| Let an AI client act on the org | agentic | Hosted MCP server | MCP client | GA (Summer '26) |
| Zero-ETL analytics over external data | federation | Data 360 zero-copy | Data 360 | GA |

---

## 6. Authoring-Surface Map (where can I build it?)

| Surface | Inbound | Outbound | Events | Notes |
|---|---|---|---|---|
| **Apex** | `@RestResource`, `webservice` | `Http` callouts + async | publish/subscribe, CDC triggers | Full power; only place for complex transactional/bulk logic |
| **Flow** | (receives via invoked actions) | HTTP Callout, External Services actions | publish/subscribe Platform Events | No-code outbound + events |
| **LWC** | — | Apex proxy (preferred) or `fetch` + CSP Trusted Sites/CORS | — | LWS blocks `data:` URIs; secrets stay server-side |
| **No-code/declarative** | — | Flow HTTP Callout, External Services, Salesforce Connect, MuleSoft for Flow | Platform Events in Flow | Prefer for simple, well-described APIs |

LWC **cannot** call arbitrary Salesforce APIs from JavaScript (only LDS / `lightning/graphql`); for external APIs use an Apex proxy unless you have a specific reason to `fetch` directly. See `decimatio-integration-outbound` and `decimatio-lwc`.

---

## 7. Decision Thresholds (the numbers that flip the choice)

- **>10,000 records** → Bulk API 2.0, not REST.
- **Need atomic multi-object writes** → Composite / Composite Graph (not separate REST calls).
- **Real-time external data you must not copy** → Salesforce Connect.
- **Decoupling or high event volume** → Platform Events / Pub/Sub.
- **More than one external system, or orchestration/transformation** → MuleSoft, not point-to-point Apex.
- **An AI agent/assistant is the caller** → Hosted MCP server.
- **Latency must be <15 min for analytics** → streaming; otherwise batch (see `decimatio-data360`).

---

## 8. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Point-to-point Apex callouts spider-webbing many systems | Middleware (MuleSoft) once it's >1–2 integrations |
| Synchronous callout where fire-and-forget would do | Platform Event / async |
| Looping single-record REST calls for bulk | Composite / Bulk API 2.0 |
| Hard-coded endpoints/secrets + Remote Site Settings | Named + External Credentials |
| Username/password or SOAP `login()` for new auth | OAuth JWT Bearer + External Client App |
| Blind insert on a retried message | Upsert by external id (idempotency) |
| Building new on API version <41.0 | Target current API version |
| Polling for changes | CDC / Platform Events over Pub/Sub |
| `fetch()` to external API from LWC with secrets in JS | Apex proxy keeps secrets server-side |
| Assuming system-mode in a v67 integration class | Audit for `USER_MODE`/sharing before bumping |

---

## Summary — The Five Commandments

1. **Name the pattern first** — request-reply, fire-and-forget, batch sync, remote call-in, UI-update, or data virtualization; the technology follows the pattern.
2. **Async by default** — reserve synchronous request-reply for answer-now, user-facing dependencies.
3. **Route, then build** — pick the sibling skill from the matrix; this hub chooses, the siblings implement.
4. **Identity is its own concern** — External Client Apps + OAuth + Named/External Credentials, never hard-coded secrets or username/password.
5. **Design for failure and scale** — idempotency, retry, bulkification, and v67 user-mode awareness on every path.
