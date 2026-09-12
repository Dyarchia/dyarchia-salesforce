---
name: dya-integration-overview
description: Salesforce integration decision hub (Winter '27 / API v68.0) — the router and decision framework for the dya-integration-* family. The six integration patterns, sync vs async, idempotency/retry/governor concerns, the master "I need X with Y in manner Z" decision matrix, the authoring-surface map (Apex/Flow/LWC/no-code), and the API-version-retirement facts. Load only when the user explicitly invokes this skill by name (`dya-integration-overview`); do NOT auto-trigger on generic integration questions.
---

# Salesforce Integration — Decision Hub

This skill does not teach individual protocols — it **routes** you to the right one and the right
authoring surface, then hands off to a sibling. Use it to choose; use the siblings to build. Follow
every rule below.

The `dya-integration-*` family (load the one the decision points to):

- `dya-integration-inbound-apis` — the standard APIs external systems call: REST and composite, SOAP, Bulk 2.0, GraphQL, Connect/UI/Metadata/Tooling.
- `dya-integration-inbound-apex` — custom endpoints you expose: Apex REST (`@RestResource`), Apex SOAP, Sites and Experience Cloud.
- `dya-integration-outbound` — Salesforce calling out: Apex callouts and async patterns, Flow HTTP Callout, External Services, Outbound Messages, Salesforce Connect, LWC to external.
- `dya-integration-events` — Platform Events, Change Data Capture, Pub/Sub API, webhook patterns.
- `dya-integration-auth` — OAuth flows, External Client Apps vs Connected Apps, Named and External Credentials, the username-password and SOAP `login()` retirements.
- `dya-integration-connectors-mcp` — MuleSoft, Heroku, AppExchange, hosted MCP servers, Headless 360, Agent API.

References:

- `references/shared/metadata-and-api-versions.md` — the single source of truth for API version semantics and retirement status across this library.
- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults integration code trips over.
- `references/shared/governor-limits.md` — the transaction budget every synchronous integration shares.
- `references/patterns-and-versions.md` — each of the six patterns in depth, with the implementation and constraints behind the one-line summary here.

This family sits **on top of** the core skills and defers to them: async and governor detail →
`dya-apex`; Flow mechanics → `dya-flow`; Lightning Web Security and CSP → `dya-lwc`; who the
integration user is allowed to be → `dya-permissions`; agent actions → `dya-agentforce`; Data 360
ingestion → `dya-data360`; MCP and the experience layer → `dya-headless360`.

---

## Platform Context — Winter '27 / API v68.0

| Change | Status | Why it matters here |
|---|---|---|
| **REST API `/latest` alias** | GA | `/services/data/latest/sobjects/Account` resolves to the newest version. Fine for exploration; **pin an explicit version in production**, or the integration's behaviour changes three times a year with no deploy |
| **OAuth username-password flow retired** | Enforced **20 February 2027** | Anything posting `grant_type=password` stops receiving a token on that date. See `dya-integration-auth` |
| **Update Instanced URLs in API Traffic** | Postponed to Spring '27 | Instance-based endpoints must become the org's My Domain URL. Testable today with the My Domain blocking setting |
| **MCP interoperability for agents** | GA | Agents discover external tools through governed connections — a first-class integration surface. See `dya-integration-connectors-mcp` |

Standing facts that decide designs, not just prose:

- **The Apex security defaults from API 67.0 hit integration code hardest.** SOQL, SOSL and DML
  default to `USER_MODE`, and an omitted sharing keyword defaults to `with sharing`. Server-to-server
  code that assumed system-mode access silently returns fewer rows once its class is raised to 67.0
  or above. Behaviour keys off **each class's compiled version**, not the org's. See
  `references/shared/platform-deltas.md` and `dya-apex`.
- **API endpoint versions**: 41.0 is the floor and 31.0–40.0 are deprecated and scheduled for
  retirement. This concerns the `vXX.X` in standard endpoint URLs only — it does **not** retire your
  Apex REST or SOAP services, classes, triggers or Visualforce. Full status in
  `references/shared/metadata-and-api-versions.md`.
- **Hosted MCP servers are GA.** HTTPS is mandatory for every external endpoint. Connect REST API
  draws on the per-org 24-hour Platform API limit pool, except for Chatter-touching calls.
- **Salesforce-to-Salesforce** ended support in Summer '26 and stops functioning in Spring '27 —
  migrate to MuleSoft, Data Cloud One, or the cross-org adapter.

---

## 1. The Six Patterns — the Vocabulary

Salesforce's Integration Patterns and Practices defines the canonical set. **Name the pattern first;
the technology follows.** Picking a technology before naming the pattern is how point-to-point
spaghetti gets built.

| Pattern | Direction | Sync? | Canonical technology |
|---|---|---|---|
| **Request & Reply** | SF → external | Sync | Apex callout, Flow HTTP Callout — the caller waits |
| **Fire & Forget** | SF → external | Async | Platform Event, or a Queueable callout |
| **Batch Data Synchronization** | Both | Async | Bulk API 2.0, ETL, MuleSoft |
| **Remote Call-In** | External → SF | Sync | REST, SOAP, Apex REST, Bulk — the external system drives |
| **UI Update Based on Data Changes** | SF → UI/external | Async | CDC or Platform Events over Pub/Sub |
| **Data Virtualization** | SF reads external | Sync | Salesforce Connect and External Objects |

> Each pattern in depth, with its implementation and constraints: `references/patterns-and-versions.md`.

## 2. First Cut — Direction and Who Initiates

```text
Who starts the interaction?
├─ External system calls Salesforce ........... INBOUND
│    ├─ Standard data operations (CRUD/query/bulk) ... dya-integration-inbound-apis
│    └─ Custom endpoint / bespoke contract .......... dya-integration-inbound-apex
├─ Salesforce calls external .................. OUTBOUND
│    └─ Apex, Flow, External Services, Connect, LWC . dya-integration-outbound
├─ Either side reacts to an event ............. EVENT-DRIVEN
│    └─ Platform Events, CDC, Pub/Sub .............. dya-integration-events
└─ Don't hand-code it ......................... CONNECTORS
     └─ MuleSoft, MCP, AppExchange ................ dya-integration-connectors-mcp

Cross-cutting on every path: authentication → dya-integration-auth
```

## 3. Sync vs Async — the Load-Bearing Choice

**Synchronous** when the caller genuinely needs the answer *now* to proceed — a user is waiting, or
the next step depends on the result. The costs are real: tight coupling, a blocked caller, both
systems up simultaneously, and the transaction's governor and timeout limits applying hard.

**Asynchronous** for everything else, and prefer it. It decouples availability, absorbs volume, and
survives the other system being down. The costs are eventual consistency and the obligation to design
idempotency and reconciliation yourself.

Default to **async or event-driven** for system-to-system data movement. Reserve **synchronous** for
user-facing, answer-now dependencies.

## 4. Cross-Cutting Non-Negotiables

- **Idempotency.** Any retried or fire-and-forget message must be safe to process twice. Upsert on an
  external id, or dedupe on a replay id; never blind insert. A retry that duplicates data is worse
  than a retry that fails.
- **Bulkification and limits.** 100 callouts per transaction, 120 seconds cumulative. Collapse calls
  with Composite or Bulk; never call out inside a loop. Full budget in
  `references/shared/governor-limits.md`.
- **Error handling and retry.** Platform Events give 72 hours of replay; Outbound Messages retry
  automatically; Apex callouts need explicit retry and backoff. Log failures durably — a failure
  visible only in a debug log is a failure nobody will see.
- **Security.** OAuth over passwords; External Client Apps over Connected Apps; Named and External
  Credentials over hard-coded secrets and Remote Site Settings; HTTPS always; a purpose-built
  least-privilege integration user, whose own object and field access now governs what its code reads.
- **Version hygiene.** Target the current API version; 41.0 is the floor. Never build new on a version
  already scheduled for retirement.

## 5. Master Decision Matrix

| I need to… | …in this manner | Use | Called from | Status |
|---|---|---|---|---|
| Let an external app read/write records | Real-time, moderate volume | REST API, Composite for multi-operation | Any HTTP client | GA |
| Load or extract millions of rows | Batch / ETL | Bulk API 2.0 | Client, Data Loader | GA |
| Expose a bespoke endpoint with custom logic | Request-reply | Apex REST (`@RestResource`) | Apex | GA |
| Write to several objects atomically in one round trip | Transactional | Composite / Composite Graph | Any HTTP client | GA |
| Have Salesforce call an external API for an answer | Sync | Apex HTTP callout | Apex | GA |
| Have Salesforce call an external API without code | Sync or async | Flow HTTP Callout + Named Credential | Flow | GA |
| Surface external data live without storing it | Virtualization | Salesforce Connect (OData or Apex adapter) | Declarative or Apex | GA |
| Notify external systems of changes in Salesforce | Streaming | CDC or Platform Events over Pub/Sub | External gRPC client | GA |
| Decouple producers and consumers inside Salesforce | Pub/sub | Platform Events | Apex, Flow | GA |
| Call an external API from a component's UI | Browser | Apex proxy (preferred), or `fetch` with CSP | LWC | GA |
| Authenticate a server-to-server integration | Token | JWT Bearer + External Client App | ECA | GA |
| Store outbound credentials securely | Any | Named + External Credentials | Apex, Flow | GA |
| Orchestrate across many systems | Middleware | MuleSoft Anypoint, or MuleSoft for Flow | MuleSoft | GA |
| Let an AI client act on the org | Agentic | Hosted MCP server | MCP client | GA |
| Analytics over external data without copying it | Federation | Data 360 zero-copy | Data 360 | GA |

## 6. Authoring-Surface Map

| Surface | Inbound | Outbound | Events | Notes |
|---|---|---|---|---|
| **Apex** | `@RestResource`, `webservice` | `Http` callouts, sync and async | Publish, subscribe, CDC triggers | Full power; the only place for complex transactional or bulk logic |
| **Flow** | Receives via invocable actions | HTTP Callout, External Services | Publish and subscribe | No-code outbound and events |
| **LWC** | — | Apex proxy (preferred), or `fetch` with CSP Trusted Sites and CORS | — | Lightning Web Security constrains what the browser may do; secrets stay server-side |
| **No-code** | — | Flow HTTP Callout, External Services, Salesforce Connect, MuleSoft for Flow | Platform Events in Flow | Prefer for simple, well-described APIs |

An LWC **cannot** call arbitrary Salesforce APIs from JavaScript — only Lightning Data Service and
`lightning/graphql`. For an external API use an Apex proxy unless you have a specific reason to
`fetch` directly. See `dya-integration-outbound` and `dya-lwc`.

## 7. Decision Thresholds — the Numbers That Flip the Choice

- **More than ~10,000 records** → Bulk API 2.0, not REST.
- **Atomic multi-object writes needed** → Composite or Composite Graph, not separate REST calls.
- **Real-time external data you must not copy** → Salesforce Connect.
- **Decoupling, or high event volume** → Platform Events over Pub/Sub.
- **More than one or two external systems, or any orchestration and transformation** → middleware, not point-to-point Apex.
- **An AI agent is the caller** → a hosted MCP server.
- **Analytics latency under 15 minutes** → streaming; otherwise batch. See `dya-data360`.

## 8. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct approach |
|---|---|
| Choosing a technology before naming the pattern | Name the pattern; the technology follows |
| Point-to-point Apex callouts spidering across many systems | Middleware, once it is more than one or two integrations |
| A synchronous callout where fire-and-forget would do | A Platform Event, or async |
| Looping single-record REST calls for bulk work | Composite or Bulk API 2.0 |
| A hard-coded endpoint or secret, plus a Remote Site Setting | Named and External Credentials |
| Username-password or SOAP `login()` for new authentication | OAuth with an External Client App |
| A blind insert on a message that may be retried | Upsert on an external id |
| Building new on an API version below 41.0 | The current version |
| Pinning production to the `/latest` alias | An explicit version you upgrade deliberately |
| Polling for changes | CDC or Platform Events over Pub/Sub |
| `fetch()` to an external API from LWC with a secret in JavaScript | An Apex proxy — secrets stay server-side |
| Assuming system-mode access in an integration class at 67.0 or above | Audit sharing and user mode before raising the version |
| A failure logged only to the debug log | Durable logging the operations team can actually see |

## Summary — The Five Commandments

1. **Name the pattern first** — request-reply, fire-and-forget, batch sync, remote call-in, UI update, or data virtualization. The technology follows the pattern.
2. **Async by default.** Reserve synchronous request-reply for answer-now, user-facing dependencies.
3. **Route, then build.** This hub chooses; the siblings implement.
4. **Identity is its own concern** — External Client Apps, OAuth, Named and External Credentials. Never a hard-coded secret, never a password flow.
5. **Design for failure and scale** — idempotency, retry with backoff, bulkification, durable logging, and user-mode awareness on every path.
