# Observability — Native Tools Only

What the platform gives you for free, referenced from SKILL.md §11. Load this file when diagnosing a
production failure, deciding how an async job reports what went wrong, or when someone asks you to
build a logging layer.

## The rule that comes first

**Do not create a logging object, a logging platform event, or a `Logger` class that writes to
either.** You cannot see the target org from here: a `Log__c` or `Log__e` written into a deployment
is a deploy failure when it does not exist, and one more unused custom object when it does. Neither
outcome is observability.

Two legitimate paths, in order:

1. **The org already has a logging framework.** Find it before writing anything — search the org's
   Apex for a `Logger`, `LogService` or similar entry point, or retrieve the object list and look for
   a log-shaped custom object. If it exists, call it, and match its level vocabulary rather than
   inventing your own.
2. **The org has nothing.** Say so. Standing up a logging framework is an architectural decision with
   storage, retention and DPO consequences; it is the org owner's call, not a side effect of the task
   you were asked to do.

Everything below needs no custom metadata at all.

## Debug logs

`System.debug` is a development tool. Pass an explicit level so the line can be filtered:

```java
System.debug(LoggingLevel.ERROR, 'Callout failed for account ' + accountId);
```

What makes debug logs unsuitable as the production record:

- They only exist while a **trace flag** is active on the user, class or trigger.
- A single log is **capped**, and past the cap the body is truncated — the tail you needed is the
  part that gets cut.
- They expire. Debug logs are for reproducing a failure you already know about, not for discovering
  one after the fact.

Set levels per category on the trace flag rather than raising everything to FINEST: a log drowning in
`WORKFLOW` and `VALIDATION` entries hits the size cap before it reaches your Apex.

## Uncaught exceptions

An uncaught exception in Apex sends an **Apex exception email**, natively and with no configuration
beyond choosing the recipients. It carries the exception type, the message and the stack trace.

Recipients are set in Setup under Apex Exception Email, or declaratively with the
`ApexEmailNotification` metadata type, so they travel with the repository:

```xml
<!-- force-app/main/default/apexEmailNotifications/ops.apexEmailNotification-meta.xml -->
<ApexEmailNotification xmlns="http://soap.sforce.com/2006/04/metadata">
    <email>apex-alerts@example.com</email>
</ApexEmailNotification>
```

This is the floor of production error visibility, and most orgs that believe they have "no logging"
already have it and are not reading it.

## Async job health

Queueable, Batch and Schedulable runs are rows in `AsyncApexJob`, which is a standard object:

```java
List<AsyncApexJob> failed = [
    SELECT Id, ApexClass.Name, Status, ExtendedStatus, NumberOfErrors, CompletedDate
    FROM AsyncApexJob
    WHERE Status IN ('Failed', 'Aborted')
      AND CompletedDate = LAST_N_DAYS:1
    WITH USER_MODE
];
```

`ExtendedStatus` carries the first error, which is usually enough to classify the failure without any
logging layer at all. A report on this object, filtered to `Failed`, is a dashboard component and
costs nothing to build.

`System.purgeOldAsyncJobs(Integer)` bounds how many records one call deletes, so a scheduled job can
purge incrementally instead of hitting limits on a single sweep:

```java
System.purgeOldAsyncJobs(10000);
```

## The async failure path

A **Transaction Finalizer** runs after a Queueable completes, including when it died on an unhandled
exception, and it runs in its own execution context — so it survives the failure that killed the job.
See `references/async-patterns.md` for the skeleton.

Report from inside it with the tools above rather than with a logging object:

```java
public void execute(FinalizerContext ctx) {
    if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
        System.debug(LoggingLevel.ERROR, 'Job ' + ctx.getAsyncApexJobId()
            + ' failed: ' + ctx.getException()?.getMessage());   // ✅ visible under a trace flag
        // ✅ If the org has a logging framework, call it here — do not create one.
    }
}
```

A Finalizer can also re-enqueue once, which is the retry path for a transient failure and is often
what the caller actually wanted rather than a log line.

## The licensed tier

Where an org has paid for it, the real answer to "what happened in production" is not Apex at all:

- **Event Monitoring** — login, API, Apex execution and report events as downloadable log files.
- **Scale Center** and **ApexGuru Insights** — runtime profiling and hotspots, gated by edition. See
  `references/performance-and-caching.md`.

Recommend these before proposing that anyone build a logging framework by hand.
