---
name: dya-integration-outbound
description: Salesforce outbound integration (Winter '27 / API v68.0) — Salesforce calling external systems. Apex HTTP callouts and limits, async callout patterns (Queueable/future/Continuation), the callout-after-DML rule, Flow HTTP Callout, External Services, Outbound Messages (legacy), Salesforce Connect/External Objects, and calling external APIs from LWC (Apex proxy vs fetch/CSP). Load only when the user explicitly invokes this skill by name (`dya-integration-outbound`); do NOT auto-trigger on generic callout or integration questions.
---

# Salesforce Outbound Integration

This skill covers Salesforce calling out to external systems. The question it answers is **"code or
no-code, and sync or async?"** Follow every rule below.

References:

- `references/shared/governor-limits.md` — the transaction budget a callout is spending, and why callouts never go in a loop.
- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults callout classes inherit.
- `references/apex-callouts-async.md` — `Http`/`HttpRequest`/`HttpResponse`, the callout-after-DML rule, Queueable/future/Batch/Continuation patterns, retry and backoff.
- `references/flow-external-services-connect.md` — Flow HTTP Callout, External Services (OpenAPI to invocable actions), Outbound Messages (legacy), Salesforce Connect and External Objects.

Credentials and identity live in `dya-integration-auth`; async and governor depth in `dya-apex`;
Lightning Web Security and CSP in `dya-lwc`; what the calling user is allowed to read in
`dya-permissions`.

---

## Platform Context — Winter '27 / API v68.0

Winter '27 changes little here directly. It changes the budget a callout runs inside: **Apex heap
rises to 10 MB synchronous and 25 MB asynchronous**, which affects how much response you can hold,
not how large a single callout payload may be — that limit is separate and unchanged. See
`references/shared/governor-limits.md`.

Standing facts that govern every outbound call:

- **Named Credentials plus External Credentials are the only correct mechanism.** They replace
  hard-coded endpoints, hard-coded secrets and Remote Site Settings. Reference them as
  `callout:My_Named_Credential/path`. Detail in `dya-integration-auth`.
- **HTTPS is mandatory.** No supported path calls an `http://` endpoint.
- **Flow HTTP Callout is GA** for GET, POST, PUT, PATCH and DELETE — genuine no-code outbound built
  on External Services. It handles only 2xx automatically.
- **From API 67.0 a callout class defaults to `with sharing` and `USER_MODE`.** An async callout
  class must still declare `Database.AllowsCallouts`: the marker interface is what permits the
  callout at all, and omitting it fails at run time, not compile time.
- **Salesforce Connect** with the OData 4.01 adapter removes the legacy 20,000-callouts-per-hour cap
  and supports incremental syncs and external change data capture.
- **Lightning Web Security blocks `data:` URIs** in the browser, so client-generated downloads use
  `URL.createObjectURL(blob)`.

---

## 1. Decision — Code or No-Code, Sync or Async

```
Does Salesforce need the answer right now to continue?
├─ YES (request-reply)
│   ├─ Simple, well-described API, admin-owned ....... Flow HTTP Callout (no-code)
│   └─ Complex logic / transformation / many objects . Apex HTTP callout (sync)
├─ NO (fire-and-forget)
│   ├─ Notify and forget ............................. Platform Event (dya-integration-events)
│   └─ Do work then call out, after DML .............. Queueable callout (async Apex)
├─ Read external data live, don't store it ........... Salesforce Connect (External Objects)
└─ Push from a button/screen in the UI ............... LWC → Apex proxy → callout
```

Prefer **no-code (Flow HTTP Callout)** for simple, well-described REST APIs an admin can own. Drop to
**Apex** for complex logic, async, retry or large payloads.

---

## 2. Apex HTTP Callouts

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Payments_API/v1/charge');   // Named Credential — no secrets, no RSS
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(payload));
req.setTimeout(120000);                               // ms; max 120000 (120 s)
HttpResponse res = new Http().send(req);
if (res.getStatusCode() == 200) { /* parse */ } else { /* handle/log/retry */ }
```

Hard limits, per Apex transaction:
- **100 callouts** maximum.
- **Timeout 1 ms–120,000 ms (120 s)** per callout, and **120 s cumulative** across all of them.
- Callout request or response payload **6 MB synchronous / 12 MB asynchronous**. This is its own
  limit; the Winter '27 heap increase does not raise it.
- The "10" seen elsewhere is a *different* limit — concurrent synchronous requests running longer
  than 5 seconds — not the per-transaction maximum, which is 100.

### The callout-after-DML rule
A callout **cannot** run while uncommitted DML sits in the transaction: "You have uncommitted work
pending". In order of preference:
1. **Callout first, DML after**, where the order allows.
2. **Move the callout into a Queueable** — recommended — so it runs in a fresh transaction after the
   DML commits.
3. Continuation or Transaction Finalizer, for specific cases.

Full async callout patterns: `references/apex-callouts-async.md`.

---

## 3. Async Callout Patterns

| Pattern | Use | Marker |
|---|---|---|
| **Queueable** (default) | Callout after DML, chaining, complex state | `implements Queueable, Database.AllowsCallouts` |
| **Continuation** | Long-running callout (up to 3 parallel), keep a synchronous-feeling response | `Continuation` |
| **Batch** | Callout per chunk over large data | `Database.Batchable, Database.AllowsCallouts` (≤100 callouts/execute) |
| **`@future(callout=true)`** | Legacy fire-and-forget | avoid in new code |

Default to **Queueable** for new async callouts and reserve `@future` for legacy. The canonical async
framework is in `dya-apex`.

---

## 4. Flow HTTP Callout (No-Code)

Declarative outbound HTTP in Flow Builder, generating an External Service and invocable action behind
the scenes. It needs the Customize Application permission and a Named Credential.

- Methods: **GET, POST, PUT, PATCH, DELETE**, all GA.
- It **auto-handles only 2xx**. For anything else, define the error schema and branch with a Decision
  element.
- The same platform callout governor limits as Apex apply, and Flow cannot adjust them.
- Use it for simple, well-described APIs an admin owns; drop to Apex for retry and backoff, complex
  transformation, or large and streamed payloads.

---

## 5. External Services

Register an API by its **OpenAPI/JSON schema** and Salesforce generates **invocable actions plus
Apex-defined types** usable from Flow and Apex, with no hand-written callout code.

- Best where the external API has a clean OpenAPI spec and you want declarative reuse across Flows.
- The generated actions honour the Named Credential you bind.

---

## 6. Outbound Messages (Legacy)

Workflow- or flow-triggered **SOAP** messages to a fixed endpoint, with guaranteed delivery and
automatic retry: ack within 24 h, extendable to 7 days.

- **Legacy**, tied to workflow rules, which are themselves being retired toward Flow. Avoid for new
  builds.
- Migrate to **Platform Events** for decoupling, or **Flow HTTP Callout** for REST flexibility.

---

## 7. Salesforce Connect / External Objects (Data Virtualization)

Surface external data as **External Objects** without copying it. Every read makes a real-time
callout on access.

- **Adapters:** OData 2.0 and 4.0 — the 4.01 adapter removes the 20,000-callouts-per-hour cap and
  supports external change data capture — **Cross-Org** over REST, and the **Apex Custom Adapter**
  (Apex Connector Framework) for any REST API.
- Use it when large external datasets must *appear* as records but must not be stored. It supports
  indirect and external lookups, and incremental syncs.
- Never for write-heavy or latency-critical flows: every access is a live callout.

---

## 8. Calling External APIs From LWC

The browser cannot call arbitrary Salesforce APIs from JS — only LDS and `lightning/graphql`. For
*external* APIs there are two paths:

1. **Apex proxy (recommended)** — the LWC calls an `@AuraEnabled` Apex method that makes the callout
   through a Named Credential. Secrets stay server-side, no CORS is needed, and all Apex governance
   is reused.
2. **Direct `fetch()`** — only where the third party explicitly supports browser calls. It requires a
   **CSP Trusted Site** (`connect-src`) **and** the third party's CORS allowlisting, and it would
   expose any credential. Never put credentials in JS.

Under **LWS** `data:` URIs are blocked; build client-side downloads with `URL.createObjectURL(blob)`.
See `dya-lwc`.

---

## 9. Decision Matrix — Quick Reference

| Need | Use | Code? |
|---|---|---|
| Sync call, simple API, admin-owned | Flow HTTP Callout | No |
| Sync call, complex logic/transform | Apex HTTP callout | Yes |
| Call after DML / fire-and-forget work | Queueable callout | Yes |
| Long-running callout, sync-feeling | Continuation | Yes |
| Callout per chunk over big data | Batch + `AllowsCallouts` | Yes |
| Declarative reuse of an OpenAPI API | External Services | No |
| Live external data as records, no copy | Salesforce Connect | No (or Apex adapter) |
| Call external API from a component | LWC → Apex proxy | Yes |
| Legacy guaranteed-delivery SOAP push | Outbound Messages | No (avoid new) |
| Notify external, decoupled | Platform Event (`-events`) | either |

---

## 10. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Hard-coded endpoint/secret + Remote Site Setting | Named + External Credential (`callout:`) |
| Callout with uncommitted DML | Callout-first, or Queueable after DML |
| Callout inside a loop | Aggregate, then one callout (or bulk endpoint) |
| `@future(callout=true)` for new async | Queueable + `Database.AllowsCallouts` |
| New Outbound Message | Platform Event / Flow HTTP Callout |
| `fetch()` to external API with secrets in LWC JS | Apex proxy via Named Credential |
| Assuming Flow HTTP Callout handled a 4xx/5xx | Define error schema + Decision branch |
| Salesforce Connect for write-heavy/low-latency | Replicate or use REST/events instead |
| `http://` endpoints | HTTPS only |
| Ignoring the 120 s cumulative timeout | Budget callouts; move heavy work async |
| An async callout class without `Database.AllowsCallouts` | Declare it — the failure is at run time, not compile time |
| Assuming a bigger heap means a bigger callout payload | The payload limit is separate and unchanged at 6/12 MB |

---

## Summary — The Five Commandments

1. **Code or no-code, sync or async** — Flow HTTP Callout for simple owned APIs, Apex for complex/async, Salesforce Connect for live reads, Platform Events for fire-and-forget.
2. **Named/External Credentials always** — no hard-coded secrets, no Remote Site Settings, HTTPS only.
3. **Respect the callout-after-DML rule** — callout-first or move it into a Queueable.
4. **Know the numbers** — 100 callouts/transaction, 120 s cumulative, 6/12 MB; budget and go async when tight.
5. **From LWC, proxy through Apex** — keep secrets server-side; `fetch()` only with CSP + CORS and never with credentials.
