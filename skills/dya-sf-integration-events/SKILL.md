---
name: dya-sf-integration-events
description: Salesforce event-driven integration (Winter '27, API v68.0) — Platform Events, Change Data Capture, Pub/Sub API, publishing and subscribing from Apex and Flow, replay and retention, legacy streaming, webhooks. Applies to platform event objects (__e), CDC selections, event triggers, EventBus.publish calls, Pub/Sub API clients, event-triggered Flows. Load before creating or editing anything in this scope.
---

# Salesforce Event-Driven Integration

Event-driven integration is the decoupled, asynchronous pub/sub backbone for fire-and-forget
notification, change propagation and high-volume streaming in either direction. Data 360 ingestion
is out of scope (`dya-sf-data360`); Apex publish/subscribe depth is `dya-sf-apex`. Follow every rule
below.

References:

- `references/shared/platform-deltas.md` — release-coupled facts, including the security defaults publish and subscribe code inherits.
- `references/shared/governor-limits.md` — the transaction budget a publisher shares, and why one event beats one callout per record.
- `references/pubsub-api.md` — the Pub/Sub API (gRPC) subscribe and publish flow, Avro schemas, replay and flow control, external-subscriber patterns.
- `references/platform-events-cdc.md` — defining and publishing Platform Events, CDC channels, Apex and Flow publish and subscribe, delivery and replay semantics.
- `references/cdc-metadata.md` — the metadata behind CDC and durable subscriptions: `PlatformEventChannelMember` and `PlatformEventChannel` element inventories, naming rules, enrichment and filter constraints, and `ManagedEventSubscription`.

---

## Platform Context — Winter '27 / API v68.0

Winter '27 changes little here directly. **Agents now discover external tools through governed MCP
connections**; feed them from an event-driven backbone rather than by polling. See
`dya-sf-integration-connectors-mcp`.

Standing facts:

- **The Pub/Sub API (gRPC over HTTP/2) is the single strategic interface** for external systems to
  publish and subscribe to Platform Events, Change Data Capture and Real-Time Event Monitoring. Use
  it over the legacy CometD Streaming API in every new build.
- **Events are retained 72 hours** on the event bus; replay works only within that window.
- **From API 67.0** publish and subscribe code defaults to `with sharing` and `USER_MODE`. CDC and
  Platform Event Apex triggers run in **system mode**, like every trigger, so they see records the
  subscribing user could not.

## Summary — The Five Commandments

1. **Use CDC for "react to changes," Platform Events for "publish a fact"** — and the Pub/Sub API as the one external interface for both.
2. **Choose Pub/Sub over legacy** — PushTopic, Generic Streaming, and CometD are legacy; never build new on them.
3. **Make every consumer idempotent; delivery is at-least-once** — dedupe every consumer; design for replays.
4. **Mind 72 h retention** — track replay ids and reconcile beyond the window.
5. **Compose webhooks from events** — Platform Event → Pub/Sub for durable multi-consumer; Flow HTTP Callout for the simple single target.

---

## 1. The Three Event Types — Choose

| Event type | Source of the event | Schema | Use |
|---|---|---|---|
| **Platform Event** | You publish it explicitly (Apex/Flow/API) | You define the fields | Custom business notifications; fire-and-forget integration |
| **Change Data Capture (CDC)** | Salesforce, automatically on record change | Mirrors the object + change header | Propagate create/update/delete/undelete to external systems |
| **Real-Time Event Monitoring** | Salesforce, on security/audit events | Salesforce-defined | Security/audit streaming |

---

## 2. Pub/Sub API — the External Interface

A **gRPC/HTTP-2** service with Avro-encoded binary payloads, available in many languages, with
**bidirectional streaming** and **pull-based flow control**: the subscriber requests N events at a
time, at most 100 per fetch.

- **Replay:** resubscribe from `LATEST`, `EARLIEST` or a specific **replay id** to recover missed
  events.
- **Efficient:** Avro binary plus flow control make it far lighter than the CometD Streaming API.

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
  After Commit* fires only on commit.
- **Fire-and-forget decoupling:** the publisher neither knows nor waits for subscribers, as in
  "order placed → tell N systems".
- **High volume:** built for throughput; pair with Pub/Sub for external consumers.

Definitions and subscribe patterns: `references/platform-events-cdc.md`.

---

## 4. Change Data Capture (CDC)

Salesforce emits a change event, with no producer code, whenever a record on a CDC-enabled object
is created, updated, deleted or undeleted.

- Subscribe externally via the **Pub/Sub API** (the common ETL and replication pattern) or in-org via
  an **Apex CDC trigger**.
- The payload carries a **change event header** — change type, changed fields, record ids — plus the
  changed field values.

**Enable it with `PlatformEventChannelMember`, and nothing else.** There is no `ChangeDataCapture`
metadata type, no `.changeDataCapture-meta.xml`, no `changeDataCapture/` directory — a file by that
name fails the deploy with "Could not infer a metadata type". Deploy one member per subscribed
entity; add a `PlatformEventChannel` alongside it only when the channel is custom.

Two naming rules disagree on purpose:

- **`<selectedEntity>` is the ChangeEvent type, not the source object.** `Account` becomes
  `AccountChangeEvent`; `Order__c` becomes **`Order__ChangeEvent`**, keeping the double underscore.
  Passing the source object fails with "references an invalid event in the selectedEntity field".
- **The filename uses a single underscore regardless.** `Order__c` is deployed as
  `Order_ChangeEvent.platformEventChannelMember-meta.xml` while its XML says `Order__ChangeEvent`.
  A double-underscore filename is parsed as `<namespace>__<name>` and rejected with "Cannot create a
  new component with the namespace: Order".

Set the default channel value to exactly **`ChangeEvents`** — not `data/ChangeEvents`, which returns
"Unable to find the specified channel". Never author a `PlatformEventChannel` file for it; it is
system-provided.

> Element inventories, enrichment fields, filter expressions and custom channels:
> `references/cdc-metadata.md`.

---

## 5. Legacy — Do Not Build New

| Legacy | Status | Migrate to |
|---|---|---|
| **PushTopic events** | Legacy, not enhanced, limited support | Change Data Capture |
| **Generic Streaming** | Legacy, not enhanced, limited support | Platform Events |
| **CometD Streaming API** | Superseded for external subscribers | Pub/Sub API |

Plan the migration wherever an org has these.

---

## 6. Webhook Patterns (Salesforce has no native outbound webhooks)

| Pattern | How | When |
|---|---|---|
| **Flow HTTP Callout on record-trigger** | Record-triggered Flow → HTTP Callout | Simple, no-code, admin-owned |
| **Apex trigger → Queueable callout** | Trigger handler enqueues a callout after commit | Complex logic, retry, batching |
| **Platform Event → external subscriber** | Publish PE; external app subscribes via Pub/Sub | Decoupled, durable, many consumers |
| **Outbound Message** | Workflow-based SOAP push | Legacy only |

Outbound paths: `dya-sf-integration-outbound`.

---

## 7. Delivery, Replay & Idempotency

- **At-least-once delivery.** Make every handler **idempotent** — dedupe on a business key or the
  replay id; consumers may see an event more than once.
- **72 h retention.** Store the last processed replay id and resume from it; design a
  reconciliation batch for gaps beyond the window. Alternatively, a `ManagedEventSubscription` makes
  the platform track the replay position, consumed through the Pub/Sub **`ManagedSubscribe`** RPC
  instead of `Subscribe`. Use it by default for a long-lived in-platform consumer; keep manual
  replay bookkeeping for an external subscriber with durable state of its own.
- **Order.** Events are delivered in publish order per channel. Never assume cross-channel ordering.
- **Allocations.** Budget for the daily allocations on event publishing and delivery in every
  high-volume design.

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
