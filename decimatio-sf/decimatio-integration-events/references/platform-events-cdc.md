# Platform Events & Change Data Capture — Reference (API v67.0)

Load from `decimatio-integration-events` when defining/publishing Platform Events or wiring Change Data Capture. In-org Apex publish/subscribe depth is in `decimatio-apex`.

## Platform Events

A Platform Event is a custom message with a schema you define (API name ends in `__e`). Define fields in Setup (or metadata); choose the **publish behaviour**.

### Publish (Apex)

```apex
List<Order_Placed__e> events = new List<Order_Placed__e>();
for (Order__c o : changedOrders) {
    events.add(new Order_Placed__e(Order_Id__c = o.Id, Amount__c = o.Amount__c));
}
List<Database.SaveResult> results = EventBus.publish(events);   // bulk publish
for (Database.SaveResult sr : results) {
    if (!sr.isSuccess()) { /* log; EventBus.publish does not throw on per-event failure */ }
}
```

### Publish behaviour — choose deliberately

| Behaviour | Fires when | Use |
|---|---|---|
| **Publish After Commit** | Only if the transaction commits | Most business events (don't notify on a rollback) |
| **Publish Immediately** | At call time, even if the transaction later rolls back | Logging/telemetry that must survive a rollback |

### Subscribe options

- **Apex trigger** on the `__e` event — in-org reaction (runs in system mode like all triggers; bulk-safe; can re-publish or do DML).
- **Flow** — record/platform-event-triggered Flow subscribes declaratively.
- **`lightning/empApi`** — an LWC subscribes for live UI updates (CometD under the hood, in-org only).
- **Pub/Sub API** — external subscribers (`pubsub-api.md`).

### Publish (Flow)

A Flow can publish a Platform Event with a Create Records-style element on the `__e` object — no code, useful for admin-owned fire-and-forget.

## Change Data Capture (CDC)

Salesforce automatically emits a change event when a record on a **CDC-enabled** object is created, updated, deleted, or undeleted. No producer code.

- **Enable** per object in Setup (Change Data Capture) or via the standard channel; custom channels can group objects.
- **Payload** = a **ChangeEventHeader** (`changeType`, `changedFields`, `recordIds`, `commitTimestamp`, …) plus the changed field values.
- **Subscribe** externally via **Pub/Sub API** (the replication/ETL pattern) or in-org via an **Apex CDC trigger** on `XxxChangeEvent`.

```apex
trigger AccountCDCTrigger on AccountChangeEvent (after insert) {
    for (AccountChangeEvent evt : Trigger.new) {
        EventBus.ChangeEventHeader h = evt.ChangeEventHeader;
        // h.getChangeType(), h.getRecordIds(), h.getChangedFields()
        // react in bulk; keep it light — heavy work goes async
    }
}
```

Use CDC to keep an external store in sync **without polling**; use the changed-fields header to apply only deltas.

## Delivery Semantics

- **At-least-once** delivery — design idempotent consumers.
- **72 h** retention on the bus; resume from a stored replay id.
- **Order** preserved per channel in publish order; no cross-channel ordering guarantee.
- **Allocations** apply to publishing and to CDC/PE delivery — high-volume designs must budget them.

## Choosing Platform Events vs CDC

| Situation | Use |
|---|---|
| You want to broadcast a *business fact* with your own shape | Platform Event |
| You want to react to *record changes* you didn't instrument | Change Data Capture |
| You need to notify many decoupled consumers | Platform Event |
| You need an external replica of Salesforce data | CDC over Pub/Sub |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Heavy logic inside a CDC/PE trigger | React lightly; offload to Queueable |
| Publish Immediately when commit semantics were needed | Publish After Commit |
| One Platform Event published per record in a loop | Bulk `EventBus.publish(List)` |
| Non-idempotent subscriber | Dedupe on business key / replay id |
| Polling instead of CDC | Subscribe to change events |
| Assuming `EventBus.publish` throws on failure | Inspect `SaveResult[]` |
