# Platform Events & Change Data Capture — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-events`. In-org Apex publish/subscribe depth is in `dya-sf-apex`.

## Platform Events

Define fields in Setup or metadata; the API name ends in `__e`.

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

### Publish behaviour

| Behaviour | Fires when | Use |
|---|---|---|
| **Publish After Commit** | Only if the transaction commits | Most business events (don't notify on a rollback) |
| **Publish Immediately** | At call time, even if the transaction later rolls back | Telemetry that must survive a rollback |

### Subscribe options

- **Apex trigger** on the `__e` event — in-org reaction (runs in system mode like all triggers; bulk-safe; can re-publish or do DML).
- **Flow** — record/platform-event-triggered Flow subscribes declaratively.
- **`lightning/empApi`** — an LWC subscribes for live UI updates (CometD underneath, in-org only).
- **Pub/Sub API** — external subscribers (`pubsub-api.md`).

### Publish (Flow)

A Flow can publish a Platform Event with a Create Records-style element on the `__e` object — no code, useful for admin-owned fire-and-forget.

## Change Data Capture (CDC)

- **Enable** per object in Setup (Change Data Capture) or via the standard channel; custom channels can group objects.
- **Payload** = a **ChangeEventHeader** (`changeType`, `changedFields`, `recordIds`, `commitTimestamp`, …) plus the changed field values.
- **Subscribe** in-org via an **Apex CDC trigger** on `XxxChangeEvent`.

```apex
trigger AccountCDCTrigger on AccountChangeEvent (after insert) {
    for (AccountChangeEvent evt : Trigger.new) {
        EventBus.ChangeEventHeader h = evt.ChangeEventHeader;
        // h.getChangeType(), h.getRecordIds(), h.getChangedFields()
        // react in bulk; keep it light — heavy work goes async
    }
}
```

Apply only deltas, using the changed-fields header.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Heavy logic inside a CDC/PE trigger | React lightly; offload to Queueable |
| One Platform Event published per record in a loop | Bulk `EventBus.publish(List)` |
| Assuming `EventBus.publish` throws on failure | Inspect `SaveResult[]` |
