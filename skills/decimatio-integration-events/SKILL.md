---
name: decimatio-integration-events
description: Salesforce event-driven integration (Summer '26 / API v67.0) — Platform Events, Change Data Capture (CDC), and the Pub/Sub API (gRPC) as the strategic streaming interface; publish/subscribe from Apex and Flow; replay/retention and delivery semantics; legacy PushTopic/Generic/Streaming API status; and webhook patterns. Load only when the user explicitly invokes this skill by name (`decimatio-integration-events`); do NOT auto-trigger on generic event or integration questions.
---

# Salesforce Event-Driven Integration

You are an expert at event-driven integration on Salesforce — the decoupled, asynchronous, pub/sub backbone. Use this for fire-and-forget notification, change propagation, and high-volume streaming in either direction. Data 360 ingestion is out of scope here (see `decimatio-data360`); Apex publish/subscribe depth is in `decimatio-apex`. Follow every rule below.

References:
- `references/pubsub-api.md` — the Pub/Sub API (gRPC) subscribe/publish flow, Avro schemas, replay/flow control, and external-subscriber patterns.
- `references/platform-events-cdc.md` — defining and publishing Platform Events, CDC channels, Apex/Flow publish & subscribe, and delivery/replay semantics.

---

## Platform Context — Summer '26 / API v67.0

- **The Pub/Sub API (gRPC/HTTP-2) is the strategic, single interface** to publish and subscribe to Platform Events, Change Data Capture, and Real-Time Event Monitoring events — for external systems. Use it over the legacy CometD Streaming API.
- **PushTopic and Generic Streaming are legacy** — no longer enhanced, limited support. Migrate PushTopic → CDC, Generic → Platform Events.
- **Events are retained 72 hours** on the event bus; subscribers can replay from a stored replay id within that window.
- **Apex v67** publish/subscribe code defaults to `with sharing`/`USER_MODE`; CDC/PE Apex triggers run in system mode like all triggers.

---

## 1. The Three Event Types — Choose

| Event type | Source of the event | Schema | Use |
|---|---|---|---|
| **Platform Event** | You publish it explicitly (Apex/Flow/API) | You define the fields | Custom business notifications; fire-and-forget integration |
| **Change Data Capture (CDC)** | Salesforce, automatically on record change | Mirrors the object + change header | Propagate create/update/delete/undelete to external systems |
| **Real-Time Event Monitoring** | Salesforce, on security/audit events | Salesforce-defined | Security/audit streaming |

Rule of thumb: **CDC** when you want to react to *record changes* you didn't have to instrument; **Platform Events** when you want to publish a *business fact* with a shape you control.

---

## 2. Pub/Sub API — the External Interface

The Pub/Sub API is a **gRPC/HTTP-2** service with Avro-encoded binary payloads, available in many languages, with **bidirectional streaming** and **pull-based flow control** (the subscriber requests N events at a time, max 100 per fetch).

- **One interface for all three event types** — subscribe to Platform Events, CDC, and RTEM through the same API.
- **Replay:** events live on the bus for **72 hours**; resubscribe from `LATEST`, `EARLIEST`, or a specific **replay id** to recover missed events.
- **Efficient:** Avro binary + flow control make it far lighter than the old CometD Streaming API; prefer it for every new external subscriber/publisher.

Subscribe/publish flow and replay handling: `references/pubsub-api.md`.

---

## 3. Platform Events

Custom pub/sub messages with a schema you define (`__e`). Publish from Apex, Flow, Process, or the API; subscribe from Apex triggers, Flow, `lightning/empApi` (in-org UI), or externally via Pub/Sub.

```apex
// Publish (Apex)
EventBus.publish(new Order_Placed__e(Order_Id__c = ordId, Amount__c = amt));
```

- **Publish behaviour:** *Publish Immediately* (fires even if the transaction rolls back) vs *Publish After Commit* (fires only on commit) — choose deliberately.
- **Fire-and-forget decoupling:** the publisher doesn't know or wait for subscribers. Ideal for "order placed → tell N systems."
- **High volume:** designed for throughput; pair with Pub/Sub for external consumers.

Definitions and subscribe patterns: `references/platform-events-cdc.md`.

---

## 4. Change Data Capture (CDC)

Salesforce emits a change event whenever a record is created/updated/deleted/undeleted on a CDC-enabled object — no code to produce it.

- Subscribe externally via **Pub/Sub API** (the common ETL/replication pattern) or in-org via an **Apex CDC trigger**.
- The payload carries a **change event header** (change type, changed fields, record ids) plus the changed field values.
- Use for keeping an external store in sync with Salesforce without polling.

---

## 5. Legacy — Do Not Build New

| Legacy | Status | Migrate to |
|---|---|---|
| **PushTopic events** | Legacy, not enhanced | Change Data Capture |
| **Generic Streaming** | Legacy, not enhanced | Platform Events |
| **CometD Streaming API** | Superseded for external subscribers | Pub/Sub API |

If you find these in an org, plan migration; never start new work on them.

---

## 6. Webhook Patterns (Salesforce has no native outbound webhooks)

To "call a URL when something happens," compose existing primitives:

| Pattern | How | When |
|---|---|---|
| **Flow HTTP Callout on record-trigger** | Record-triggered Flow → HTTP Callout | Simple, no-code, admin-owned |
| **Apex trigger → Queueable callout** | Trigger handler enqueues a callout after commit | Complex logic, retry, batching |
| **Platform Event → external subscriber** | Publish PE; external app subscribes via Pub/Sub | Decoupled, durable, many consumers |
| **Outbound Message** | Workflow-based SOAP push | Legacy only |

Prefer **Platform Event → Pub/Sub** for durable, multi-consumer, decoupled "webhooks"; use Flow HTTP Callout for the simple single-target case. (Outbound paths: `decimatio-integration-outbound`.)

---

## 7. Delivery, Replay & Idempotency

- **At-least-once delivery** — consumers may see an event more than once; make handlers **idempotent** (dedupe on a business key or the replay id).
- **72 h retention** — store the last processed replay id and resume from it; design a reconciliation batch for gaps beyond the window.
- **Order** — events are delivered in publish order per channel, but don't assume cross-channel ordering.
- **Allocations** — event publishing and delivery (CDC/PE) have daily allocations; high-volume designs must account for them.

---

## 8. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| React to record changes, no instrumentation | Change Data Capture |
| Publish a business fact with a custom shape | Platform Event |
| External system subscribes to SF events | Pub/Sub API (gRPC) |
| In-org component reacts to events | `lightning/empApi` (LWC) |
| In-org Apex reacts to events | PE/CDC Apex trigger |
| Decoupled "webhook" to many consumers | Platform Event → Pub/Sub |
| Simple single-target webhook | Flow HTTP Callout (`-outbound`) |
| Security/audit event streaming | Real-Time Event Monitoring via Pub/Sub |
| Replace PushTopic / Generic / CometD | CDC / Platform Events / Pub/Sub |

---

## 9. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Polling for record changes | Change Data Capture over Pub/Sub |
| New build on PushTopic / Generic / CometD | CDC / Platform Events / Pub/Sub |
| Non-idempotent event handler | Dedupe on business key / replay id |
| Assuming exactly-once delivery | Design for at-least-once |
| Ignoring 72 h retention | Persist last replay id; reconcile gaps |
| Publish-immediately when you needed commit semantics | Choose Publish After Commit deliberately |
| Synchronous callout where an event fits | Publish a Platform Event (fire-and-forget) |
| One callout per record instead of an event | Publish events; let subscribers fan out |

---

## Summary — The Five Commandments

1. **CDC for "react to changes," Platform Events for "publish a fact"** — and the Pub/Sub API as the one external interface for both.
2. **Pub/Sub over legacy** — PushTopic, Generic Streaming, and CometD are legacy; never build new on them.
3. **At-least-once means idempotent** — dedupe every consumer; design for replays.
4. **Mind 72 h retention** — track replay ids and reconcile beyond the window.
5. **Compose webhooks from events** — Platform Event → Pub/Sub for durable multi-consumer; Flow HTTP Callout for the simple single target.
