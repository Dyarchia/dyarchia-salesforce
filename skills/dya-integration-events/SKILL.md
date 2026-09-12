---
name: dya-integration-events
description: Salesforce event-driven integration (Winter '27 / API v68.0) — Platform Events, Change Data Capture (CDC), and the Pub/Sub API (gRPC) as the strategic streaming interface; publish/subscribe from Apex and Flow; replay/retention and delivery semantics; legacy PushTopic/Generic/Streaming API status; and webhook patterns. Load only when the user explicitly invokes this skill by name (`dya-integration-events`); do NOT auto-trigger on generic event or integration questions.
---

# Salesforce Event-Driven Integration

Event-driven integration is the decoupled, asynchronous pub/sub backbone for fire-and-forget
notification, change propagation and high-volume streaming in either direction. Data 360 ingestion
is out of scope (`dya-data360`); Apex publish/subscribe depth is `dya-apex`. Follow every rule
below.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults publish and subscribe code inherits.
- `references/shared/governor-limits.md` — the transaction budget a publisher shares, and why one event beats one callout per record.
- `references/pubsub-api.md` — the Pub/Sub API (gRPC) subscribe and publish flow, Avro schemas, replay and flow control, external-subscriber patterns.
- `references/platform-events-cdc.md` — defining and publishing Platform Events, CDC channels, Apex and Flow publish and subscribe, delivery and replay semantics.
- `references/cdc-metadata.md` — the metadata behind CDC and durable subscriptions: `PlatformEventChannelMember` and `PlatformEventChannel` element inventories, the naming rules, enrichment and filter constraints, and `ManagedEventSubscription`.

---

## Platform Context — Winter '27 / API v68.0

Winter '27 changes little here directly. It changes the surrounding surface: **agents now discover
external tools through governed MCP connections**, which makes an event-driven backbone the natural
way to feed them without polling. See `dya-integration-connectors-mcp`.

Standing facts that decide designs here:

- **The Pub/Sub API (gRPC over HTTP/2) is the single strategic interface** for external systems to
  publish and subscribe to Platform Events, Change Data Capture and Real-Time Event Monitoring. Use
  it over the legacy CometD Streaming API in every new build.
- **PushTopic and Generic Streaming are legacy** — no longer enhanced, limited support. Migrate
  PushTopic to CDC and Generic Streaming to Platform Events.
- **Events are retained 72 hours** on the event bus. A subscriber replays from a stored replay id
  within that window and no further; beyond it, only a reconciliation batch recovers the gap.
- **From API 67.0** publish and subscribe code defaults to `with sharing` and `USER_MODE`. CDC and
  Platform Event Apex triggers run in **system mode**, like every trigger, so they see records the
  subscribing user could not.

---

## 1. The Three Event Types — Choose

| Event type | Source of the event | Schema | Use |
|---|---|---|---|
| **Platform Event** | You publish it explicitly (Apex/Flow/API) | You define the fields | Custom business notifications; fire-and-forget integration |
| **Change Data Capture (CDC)** | Salesforce, automatically on record change | Mirrors the object + change header | Propagate create/update/delete/undelete to external systems |
| **Real-Time Event Monitoring** | Salesforce, on security/audit events | Salesforce-defined | Security/audit streaming |

**CDC** reacts to *record changes* you never had to instrument. **Platform Events** publish a
*business fact* whose shape you control.

---

## 2. Pub/Sub API — the External Interface

A **gRPC/HTTP-2** service with Avro-encoded binary payloads, available in many languages, with
**bidirectional streaming** and **pull-based flow control**: the subscriber requests N events at a
time, at most 100 per fetch.

- **One interface for all three event types** — Platform Events, CDC and RTEM.
- **Replay:** events live on the bus for **72 hours**; resubscribe from `LATEST`, `EARLIEST` or a
  specific **replay id** to recover missed events.
- **Efficient:** Avro binary plus flow control make it far lighter than the old CometD Streaming API.
  Prefer it for every new external subscriber or publisher.

Subscribe/publish flow and replay handling: `references/pubsub-api.md`.

---

## 3. Platform Events

Custom pub/sub messages with a schema you define (`__e`). Publish from Apex, Flow, Process or the
API; subscribe from Apex triggers, Flow, `lightning/empApi` for in-org UI, or externally via Pub/Sub.

```apex
// Publish (Apex)
EventBus.publish(new Order_Placed__e(Order_Id__c = ordId, Amount__c = amt));
```

- **Publish behaviour:** *Publish Immediately* fires even if the transaction rolls back; *Publish
  After Commit* fires only on commit. Choose deliberately.
- **Fire-and-forget decoupling:** the publisher neither knows nor waits for subscribers — ideal for
  "order placed → tell N systems".
- **High volume:** designed for throughput; pair it with Pub/Sub for external consumers.

Definitions and subscribe patterns: `references/platform-events-cdc.md`.

---

## 4. Change Data Capture (CDC)

Salesforce emits a change event whenever a record is created, updated, deleted or undeleted on a
CDC-enabled object, with no code to produce it.

- Subscribe externally via the **Pub/Sub API**, the common ETL and replication pattern, or in-org via
  an **Apex CDC trigger**.
- The payload carries a **change event header** — change type, changed fields, record ids — plus the
  changed field values.
- Use it to keep an external store in sync with Salesforce without polling.

**Enabling it is `PlatformEventChannelMember`, and nothing else.** There is no `ChangeDataCapture`
metadata type, no `.changeDataCapture-meta.xml`, no `changeDataCapture/` directory — a file by that
name fails the deploy with "Could not infer a metadata type". One member per subscribed entity; a
`PlatformEventChannel` alongside it only when the channel is custom.

Two naming rules trip up every first attempt, and they disagree with each other on purpose:

- **`<selectedEntity>` is the ChangeEvent type, not the source object.** `Account` becomes
  `AccountChangeEvent`; `Order__c` becomes **`Order__ChangeEvent`**, keeping the double underscore.
  Passing the source object fails with "references an invalid event in the selectedEntity field".
- **The filename uses a single underscore regardless.** `Order__c` is deployed as
  `Order_ChangeEvent.platformEventChannelMember-meta.xml` while its XML says `Order__ChangeEvent`.
  A double-underscore filename is parsed as `<namespace>__<name>` and rejected with "Cannot create a
  new component with the namespace: Order".

The default channel value is exactly **`ChangeEvents`** — not `data/ChangeEvents`, which returns
"Unable to find the specified channel" — and it is system-provided, so never author a
`PlatformEventChannel` file for it.

> Element inventories, enrichment fields, filter expressions and custom channels:
> `references/cdc-metadata.md`.

---

## 5. Legacy — Do Not Build New

| Legacy | Status | Migrate to |
|---|---|---|
| **PushTopic events** | Legacy, not enhanced | Change Data Capture |
| **Generic Streaming** | Legacy, not enhanced | Platform Events |
| **CometD Streaming API** | Superseded for external subscribers | Pub/Sub API |

Where you find these in an org, plan the migration. Never start new work on them.

---

## 6. Webhook Patterns (Salesforce has no native outbound webhooks)

"Call a URL when something happens" is composed from existing primitives:

| Pattern | How | When |
|---|---|---|
| **Flow HTTP Callout on record-trigger** | Record-triggered Flow → HTTP Callout | Simple, no-code, admin-owned |
| **Apex trigger → Queueable callout** | Trigger handler enqueues a callout after commit | Complex logic, retry, batching |
| **Platform Event → external subscriber** | Publish PE; external app subscribes via Pub/Sub | Decoupled, durable, many consumers |
| **Outbound Message** | Workflow-based SOAP push | Legacy only |

Prefer **Platform Event → Pub/Sub** for durable, multi-consumer, decoupled webhooks, and Flow HTTP
Callout for the simple single target. Outbound paths: `dya-integration-outbound`.

---

## 7. Delivery, Replay & Idempotency

- **At-least-once delivery.** Consumers may see an event more than once, so every handler is
  **idempotent** — dedupe on a business key or the replay id.
- **72 h retention.** Store the last processed replay id and resume from it, and design a
  reconciliation batch for gaps beyond the window. **Or do not hand-roll it at all:** a
  `ManagedEventSubscription` makes the platform track the replay position, and the Pub/Sub API
  consumes it through the **`ManagedSubscribe`** RPC instead of `Subscribe`. That is the right
  default for a long-lived in-platform consumer; keep manual replay bookkeeping for an external
  subscriber that already has durable state of its own.
- **Order.** Events are delivered in publish order per channel. Never assume cross-channel ordering.
- **Allocations.** Event publishing and delivery carry daily allocations; a high-volume design
  accounts for them.

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
