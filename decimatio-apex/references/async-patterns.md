# Async Apex — Reference Implementations

Full implementations of the async patterns referenced from SKILL.md §7 (and the Apex Cursor pattern from §4). Load this file when writing new async code or refactoring legacy Batch / `@future` code.

## Queueable — The Default

```java
public with sharing class AccountEnricher implements Queueable, Database.AllowsCallouts {
    private final List<Id> accountIds;

    public AccountEnricher(List<Id> accountIds) {
        this.accountIds = accountIds;
    }

    public void execute(QueueableContext ctx) {
        // ... do work ...
    }
}

// Enqueue from anywhere:
System.enqueueJob(new AccountEnricher(ids));
```

`implements Database.AllowsCallouts` is required if the job makes HTTP callouts.

## Queueable + Transaction Finalizer

Use a Finalizer when code must run **whether the Queueable succeeds or fails** — retry logic, alerting, callout-after-DML, guaranteed logging.

```java
public with sharing class EnrichmentFinalizer implements Finalizer {
    private final Id parentAccountId;

    public EnrichmentFinalizer(Id parentAccountId) {
        this.parentAccountId = parentAccountId;
    }

    public void execute(FinalizerContext ctx) {
        if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            Logger.error('Enrichment failed', ctx.getException());
            // Callouts ARE allowed here, even after the parent's DML
            ExternalAlertService.notifyOps(ctx.getAsyncApexJobId());
        }
    }
}

public with sharing class AccountEnricher implements Queueable {
    private final Id accountId;

    public AccountEnricher(Id accountId) { this.accountId = accountId; }

    public void execute(QueueableContext ctx) {
        System.attachFinalizer(new EnrichmentFinalizer(accountId));
        // ... do work that may throw ...
    }
}
```

### Finalizer rules

- Only ONE Finalizer per Queueable job.
- The Finalizer runs in its **own** execution context — you cannot reference the parent Queueable's state directly; pass values into the Finalizer's constructor.
- Callouts and DML are both allowed in a Finalizer, even if the parent did DML.
- A Finalizer can enqueue exactly one more async job (Queueable, Batch, or `@future`).

## Apex Cursors + Queueable Chain

For processing up to roughly 5 million records with flexible, bidirectional, serialisable iteration. Cleaner than Batch Apex when you need variable chunk sizes or non-linear traversal.

```java
public with sharing class LargeDataProcessor implements Queueable {
    private Database.Cursor cursor;
    private Integer position;

    public LargeDataProcessor() {
        this.cursor = Database.getCursor(
            'SELECT Id, Status__c FROM Case WHERE LastModifiedDate < LAST_N_DAYS:180'
        );
        this.position = 0;
    }

    public void execute(QueueableContext ctx) {
        Integer chunkSize = 500;
        List<Case> chunk = (List<Case>) cursor.fetch(position, chunkSize);
        // ... process chunk ...
        position += chunk.size();
        if (position < cursor.getNumRecords()) {
            System.enqueueJob(this); // chain to next chunk
        }
    }
}
```

### Cursor limits

- Max 50M rows per cursor.
- **Max 10 `fetch()` calls per transaction** — this is the binding constraint, not the row total.
- Max 10,000 cursors per day.
- Max 100M rows per day aggregate.
- Track usage with `Limits.getApexCursorRows()` and `Limits.getApexCursors()`.

### Cursors vs Batch Apex — the honest trade-off

The "50M rows" headline is real, but the 10-fetches-per-transaction ceiling means you process 50M records by chaining a Queueable across many execution contexts (one fetch per execution, ten contexts of work, then the next chain link). For volumes up to ~5M, Cursors + Queueable is cleaner: flexible chunk sizes, bidirectional traversal, serialisable state across transactions. For >5M records — especially recurring jobs — Batch Apex is usually simpler: its `start/execute/finish` lifecycle handles chunking, retry and scope management for you, and the platform parallelises chunks (cursors do not). Pick by workload, not by hype.

## Mixed DML — Setup vs Non-Setup Objects

You cannot DML setup objects (`User`, `Group`, `GroupMember`, `Permission*`, `UserRole`) and non-setup objects in the same transaction. Split them by enqueueing a Queueable for the second batch.

```java
// Transaction 1: setup DML
insert new User(...);
// Cannot insert Account here — would throw MIXED_DML_OPERATION

// Defer the non-setup DML to a separate transaction
System.enqueueJob(new PostUserSetupJob(accountsToCreate));
```

```java
public with sharing class PostUserSetupJob implements Queueable {
    private final List<Account> accounts;

    public PostUserSetupJob(List<Account> accounts) {
        this.accounts = accounts;
    }

    public void execute(QueueableContext ctx) {
        Database.insert(accounts, AccessLevel.USER_MODE);
    }
}
```
