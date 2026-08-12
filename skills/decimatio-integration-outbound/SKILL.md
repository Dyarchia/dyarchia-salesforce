---
name: decimatio-integration-outbound
description: Salesforce outbound integration (Summer '26 / API v67.0) — Salesforce calling external systems. Apex HTTP callouts and limits, async callout patterns (Queueable/future/Continuation), the callout-after-DML rule, Flow HTTP Callout, External Services, Outbound Messages (legacy), Salesforce Connect/External Objects, and calling external APIs from LWC (Apex proxy vs fetch/CSP). Load only when the user explicitly invokes this skill by name (`decimatio-integration-outbound`); do NOT auto-trigger on generic callout or integration questions.
---

# Salesforce Outbound Integration

You are an expert at making Salesforce call out to external systems. The core question this skill answers is **"code or no-code, and sync or async?"** Authentication/credentials live in `decimatio-integration-auth`; async/governor depth in `decimatio-apex`; LWS/CSP in `decimatio-lwc`. Follow every rule below.

References:
- `references/apex-callouts-async.md` — `Http`/`HttpRequest`/`HttpResponse`, the callout-after-DML rule, Queueable/future/Batch/Continuation callout patterns, retry/backoff.
- `references/flow-external-services-connect.md` — Flow HTTP Callout, External Services (OpenAPI → invocable actions), Outbound Messages (legacy), and Salesforce Connect / External Objects.

---

## Platform Context — Summer '26 / API v67.0

- **Named Credentials + External Credentials are the standard** for every outbound call — they replace hard-coded endpoints/secrets and **Remote Site Settings**. Use `callout:My_Named_Credential/path`. Full detail in `decimatio-integration-auth`.
- **HTTPS is mandatory.** Never hard-code `http://`.
- **Flow HTTP Callout is GA** (GET/POST/PUT/PATCH/DELETE) — genuine no-code outbound, powered by External Services. It auto-handles only 2xx responses.
- **Apex v67 callout classes** default to `with sharing`/`USER_MODE`; mark `Database.AllowsCallouts` on async callout classes as always.
- **Salesforce Connect** OData 4.01 removes the legacy 20,000-callouts/hour cap; incremental syncs added recently.
- **LWS (Lightning Web Security)** blocks `data:` URIs in the browser — use blob object URLs for client-generated downloads.

---

## 1. Decision — Code or No-Code, Sync or Async

```
Does Salesforce need the answer right now to continue?
├─ YES (request-reply)
│   ├─ Simple, well-described API, admin-owned ....... Flow HTTP Callout (no-code)
│   └─ Complex logic / transformation / many objects . Apex HTTP callout (sync)
├─ NO (fire-and-forget)
│   ├─ Notify and forget ............................. Platform Event (decimatio-integration-events)
│   └─ Do work then call out, after DML .............. Queueable callout (async Apex)
├─ Read external data live, don't store it ........... Salesforce Connect (External Objects)
└─ Push from a button/screen in the UI ............... LWC → Apex proxy → callout
```

Prefer **no-code (Flow HTTP Callout)** for simple, well-described REST APIs an admin can own; drop to **Apex** for complex logic, async, retry, or large payloads.

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

Hard limits (per Apex transaction):
- **100 callouts** maximum per transaction.
- **Timeout 1 ms–120,000 ms (120 s)** per callout; **120 s cumulative** across all callouts in the transaction.
- Payload **6 MB synchronous / 12 MB asynchronous**.
- (The "10" you may have seen is a *different* limit — concurrent synchronous requests running longer than 5 s — not the per-transaction maximum, which is 100.)

### The callout-after-DML rule
You **cannot** make a callout when there is uncommitted DML in the transaction ("You have uncommitted work pending"). Options, in order of preference:
1. **Callout first, DML after** (if the order allows).
2. **Move the callout into a Queueable** (recommended) so it runs in a fresh transaction after the DML commits.
3. Continuation / Transaction Finalizer for specific cases.

Full async callout patterns: `references/apex-callouts-async.md`.

---

## 3. Async Callout Patterns

| Pattern | Use | Marker |
|---|---|---|
| **Queueable** (default) | Callout after DML, chaining, complex state | `implements Queueable, Database.AllowsCallouts` |
| **Continuation** | Long-running callout (up to 3 parallel), keep a synchronous-feeling response | `Continuation` |
| **Batch** | Callout per chunk over large data | `Database.Batchable, Database.AllowsCallouts` (≤100 callouts/execute) |
| **`@future(callout=true)`** | Legacy fire-and-forget | avoid in new code |

Default to **Queueable** for new async callouts; reserve `@future` for legacy. See `decimatio-apex` for the canonical async framework.

---

## 4. Flow HTTP Callout (No-Code)

Declarative outbound HTTP in Flow Builder; generates an External Service + invocable action behind the scenes. Requires the Customize Application permission and a Named Credential.

- Methods: **GET, POST, PUT, PATCH, DELETE** (all GA).
- It **auto-handles only 2xx** responses; for non-2xx you must define the error schema and branch with a Decision element.
- Subject to the same platform callout governor limits as Apex (not adjustable from Flow).
- Use for simple, well-described APIs an admin owns; drop to Apex when you need retry/backoff, complex transformation, or large/streamed payloads.

---

## 5. External Services

Register an API by its **OpenAPI/JSON schema**; Salesforce generates **invocable actions + Apex-defined types** usable from Flow and Apex — no hand-written callout code.

- Best when the external API has a clean OpenAPI spec and you want declarative reuse across Flows.
- The generated actions honour the Named Credential you bind.

---

## 6. Outbound Messages (Legacy)

Workflow/flow-triggered **SOAP** messages to a fixed endpoint, with guaranteed delivery and automatic retry (ack within 24 h, extendable to 7 days).

- **Legacy** — tied to workflow rules (themselves being retired toward Flow). Avoid for new builds.
- Migrate to **Platform Events** (decoupled, modern) or **Flow HTTP Callout** (REST, flexible).

---

## 7. Salesforce Connect / External Objects (Data Virtualization)

Surface external data as **External Objects** without copying it; reads make a real-time callout on access.

- **Adapters:** OData 2.0/4.0 (4.01 removes the 20k-callouts/hour cap), **Cross-Org** (Salesforce-to-Salesforce over REST), and the **Apex Custom Adapter** (Apex Connector Framework) for any REST API.
- Use when you need large external datasets to *appear* as records but must not store them; supports indirect/external lookups and (recently) incremental syncs.
- Not for write-heavy or low-latency-critical flows — every access is a live callout.

---

## 8. Calling External APIs From LWC

The browser cannot call arbitrary Salesforce APIs from JS (only LDS / `lightning/graphql`). For *external* APIs there are two paths:

1. **Apex proxy (recommended)** — the LWC calls an `@AuraEnabled` Apex method that does the callout via a Named Credential. Secrets stay server-side; no CORS needed; reuses all Apex governance.
2. **Direct `fetch()`** — only when the third party explicitly supports browser calls. Requires a **CSP Trusted Site** (`connect-src`) **and** the third party's CORS allowlisting. Secrets would be exposed — never put credentials in JS.

Under **LWS**, `data:` URIs are blocked; build client-side downloads with `URL.createObjectURL(blob)`. See `decimatio-lwc`.

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

---

## Summary — The Five Commandments

1. **Code or no-code, sync or async** — Flow HTTP Callout for simple owned APIs, Apex for complex/async, Salesforce Connect for live reads, Platform Events for fire-and-forget.
2. **Named/External Credentials always** — no hard-coded secrets, no Remote Site Settings, HTTPS only.
3. **Respect the callout-after-DML rule** — callout-first or move it into a Queueable.
4. **Know the numbers** — 100 callouts/transaction, 120 s cumulative, 6/12 MB; budget and go async when tight.
5. **From LWC, proxy through Apex** — keep secrets server-side; `fetch()` only with CSP + CORS and never with credentials.
