# Observability — Native Logging Implementation

Full implementation of the Platform Event + custom log object logging strategy referenced from SKILL.md §11. Load this file when building the logging layer in a new org, extending an existing logger, or debugging why log entries are missing on uncaught exceptions.

## Why Platform Events for Logging

Platform Events publish **outside the calling transaction**. This means log entries survive even when the parent transaction rolls back — which is the only way to guarantee a log on an uncaught exception in synchronous Apex. `System.debug` does not provide this guarantee; debug logs are tied to trace flags, capped in size, and useless in production for error forensics.

## The Platform Event Definition

Create a Platform Event named `Log__e` with the following custom fields. Use the platform field types (no SObject relationships — Platform Events do not support them).

```
Log__e (Platform Event)
├── Level__c       — Picklist (DEBUG, INFO, WARN, ERROR)
├── Class__c       — Text(255)        — originating class name
├── Message__c     — Text(255)        — short human-readable summary
├── Stack__c       — LongTextArea(32000) — stack trace, if any
├── Context__c     — Text(255)        — exception type or context tag
└── User__c        — Text(18)         — running user Id (optional)
```

Match this with a custom log object `Application_Log__c` with the same fields (plus standard audit fields). The Platform Event flows through to this object via a subscriber trigger.

## The Logger Class

```java
public with sharing class Logger {

    public static void error(String message, Exception e) {
        publish('ERROR', message, e?.getStackTraceString(), e?.getTypeName());
    }

    public static void warn(String message) {
        publish('WARN', message, null, null);
    }

    public static void info(String message) {
        publish('INFO', message, null, null);
    }

    private static void publish(String level, String msg, String stack, String ctx) {
        EventBus.publish(new Log__e(
            Level__c   = level,
            Class__c   = inferCallerClass(),
            Message__c = msg?.left(255),
            Stack__c   = stack?.left(32000),
            Context__c = ctx,
            User__c    = UserInfo.getUserId()
        ));
    }

    private static String inferCallerClass() {
        // Parse the second line of the synthetic stack trace to extract the caller.
        // Cheap and good-enough for error attribution; replace with explicit param
        // if you find the parsing becomes a hotspot.
        String trace = new DmlException().getStackTraceString();
        List<String> lines = trace.split('\n');
        return lines.size() > 2 ? lines[2].substringBefore(':').left(255) : null;
    }
}
```

## The Subscriber Trigger

A trigger on `Log__e` persists every published event to `Application_Log__c`. Because the event runs in its own transaction, the persisted log survives even when the parent rolls back.

```java
trigger LogEventSubscriber on Log__e (after insert) {
    LogEventSubscriberHandler.persist(Trigger.new);
}

public with sharing class LogEventSubscriberHandler {

    public static void persist(List<Log__e> events) {
        List<Application_Log__c> records = new List<Application_Log__c>();
        for (Log__e e : events) {
            records.add(new Application_Log__c(
                Level__c   = e.Level__c,
                Class__c   = e.Class__c,
                Message__c = e.Message__c,
                Stack__c   = e.Stack__c,
                Context__c = e.Context__c,
                User__c    = e.User__c
            ));
        }
        // SYSTEM_MODE: this is infrastructure; the running user may legitimately
        // lack create permission on Application_Log__c.
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }
}
```

## Use From a Transaction Finalizer

The combination of Logger + Finalizer is the foolproof async failure logging pattern. See `references/async-patterns.md` for the Finalizer skeleton; the log call inside `FinalizerContext.execute(...)` looks like this:

```java
public void execute(FinalizerContext ctx) {
    if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
        Logger.error(
            'Async job ' + ctx.getAsyncApexJobId() + ' failed',
            ctx.getException()
        );
    }
}
```

Because the Finalizer itself publishes a Platform Event, the log survives even if the Finalizer is then truncated for governor limits.

## Monitoring & Hygiene

- Query `Application_Log__c` for production debugging — build a Lightning report on `Level__c = 'ERROR'` and pin it to a dashboard.
- Query `AsyncApexJob` for batch/queueable health (`Status = 'Failed'`).
- Use `System.purgeOldAsyncJobs(Integer)` (Spring '26) to incrementally purge old completed jobs and avoid filling the AsyncApexJob table. Example: `System.purgeOldAsyncJobs(10000);` deletes up to 10k oldest completed jobs.
- Schedule a recurring job to delete `Application_Log__c` records older than the retention window your DPO defines (typically 30–90 days).
