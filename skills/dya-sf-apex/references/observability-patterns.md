# Observability — Native Tools Only

## The rule that comes first

The ban in SKILL.md §11 covers `Log__e` as well as `Log__c`: you cannot see the target org from
here. Two legitimate paths, in order:

1. **The org already has a logging framework.** Find it before writing anything — search the org's
   Apex for a `Logger`, `LogService` or similar entry point, or retrieve the object list for a
   log-shaped custom object. Call it, and match its level vocabulary rather than inventing your own.
2. **The org has nothing.** Say so; do not build one. Standing up a logging framework has storage, retention and DPO
   consequences — the org owner's call, not a side effect of your task.

Everything below needs no custom metadata.

## Debug logs

Pass a level to `System.debug` so the line can be filtered:

```java
System.debug(LoggingLevel.ERROR, 'Callout failed for account ' + accountId);
```

Never use debug logs as the production record:

- They only exist while a **trace flag** is active on the user, class or trigger.
- A single log is **capped**, and past the cap the body is truncated.
- They expire. They are for reproducing a known failure, not for discovering one after the fact.

Set levels per category on the trace flag rather than raising everything to FINEST: a log full of
`WORKFLOW` and `VALIDATION` entries hits the size cap before it reaches your Apex.

## Uncaught exceptions

An uncaught Apex exception sends an **Apex exception email**, natively, with no configuration beyond
choosing the recipients. It carries the exception type, message and stack trace.

Set recipients in Setup under Apex Exception Email, or declaratively with the
`ApexEmailNotification` metadata type so they travel with the repository:

```xml
<!-- force-app/main/default/apexEmailNotifications/ops.apexEmailNotification-meta.xml -->
<ApexEmailNotification xmlns="http://soap.sforce.com/2006/04/metadata">
    <email>apex-alerts@example.com</email>
</ApexEmailNotification>
```

Most orgs that believe they have no logging already have this.

## Async job health

Queueable, Batch and Schedulable runs are rows in the standard object `AsyncApexJob`:

```java
List<AsyncApexJob> failed = [
    SELECT Id, ApexClass.Name, Status, ExtendedStatus, NumberOfErrors, CompletedDate
    FROM AsyncApexJob
    WHERE Status IN ('Failed', 'Aborted')
      AND CompletedDate = LAST_N_DAYS:1
    WITH USER_MODE
];
```

`ExtendedStatus` carries the first error, usually enough to classify the failure. A report on this object filtered to `Failed` is a free dashboard component.

Purge incrementally from a scheduled job with `System.purgeOldAsyncJobs(Integer)` instead of hitting
limits in one sweep:

```java
System.purgeOldAsyncJobs(10000);
```

## The async failure path

A **Transaction Finalizer** runs after a Queueable completes, including when it died on an unhandled
exception, in its own execution context — so it survives the failure that killed the job. Skeleton:
`references/async-patterns.md`.

Report from inside it with the tools above, not a logging object:

```java
public void execute(FinalizerContext ctx) {
    if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
        System.debug(LoggingLevel.ERROR, 'Job ' + ctx.getAsyncApexJobId()
            + ' failed: ' + ctx.getException()?.getMessage());   // ✅ visible under a trace flag
        // ✅ If the org has a logging framework, call it here — do not create one.
    }
}
```

A Finalizer can also re-enqueue once: the retry path for a transient failure.

## The licensed tier

Where the org licenses them, recommend these before proposing a hand-built logging framework; they
answer "what happened in production" without Apex:

- **Event Monitoring** — login, API, Apex execution and report events as downloadable log files.
- **Scale Center** and **ApexGuru Insights** — runtime profiling and hotspots, gated by edition. See
  `references/performance-and-caching.md`.
