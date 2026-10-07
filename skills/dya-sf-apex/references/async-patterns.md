# Async Apex — Reference Implementations

Full implementations of the async patterns in SKILL.md §7 and the Apex Cursor pattern in §4.

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

// Enqueue from anywhere
System.enqueueJob(new AccountEnricher(ids));
```

`Database.AllowsCallouts` is required if the job makes HTTP callouts.

## Queueable + Transaction Finalizer

Use a Finalizer when code must run **whether the Queueable succeeds or fails** — retry, alerting, callout-after-DML, guaranteed error reporting.

```java
public with sharing class EnrichmentFinalizer implements Finalizer {
    private final Id parentAccountId;

    public EnrichmentFinalizer(Id parentAccountId) {
        this.parentAccountId = parentAccountId;
    }

    public void execute(FinalizerContext ctx) {
        if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            System.debug(LoggingLevel.ERROR, 'Enrichment failed: ' + ctx.getException());
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
- The Finalizer runs in its **own** execution context — it cannot reference the parent Queueable's state directly; pass values into its constructor.
- Callouts and DML are both allowed in a Finalizer, even if the parent did DML.
- A Finalizer can enqueue exactly one more async job (Queueable, Batch, or `@future`).

## Apex Cursors + Queueable Chain

For up to roughly 5 million records needing flexible, bidirectional, serialisable iteration.

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

- **10 `fetch()` calls per transaction** is the binding constraint, not the row total.
- Track usage with `Limits.getApexCursorRows()`, `Limits.getFetchCallsOnApexCursor()` and `Limits.getApexCursors()`.

### Cursors vs Batch Apex

50M rows per cursor is the hard cap, not the practical ceiling. Every fetched row also counts against the 50,000-row SOQL limit, so one Queueable link moves at most ~50k rows, and a 50M-row cursor needs 1,000+ chained links and half the org's 100M rows/day cursor budget. Up to ~5M records (a guideline, not a platform limit), Cursors + Queueable is cleaner: flexible chunk sizes, bidirectional traversal, serialisable state across transactions. Above that, especially for recurring jobs, Batch Apex is usually simpler: its `start/execute/finish` lifecycle handles chunking, retry and scope management, and it does not draw on the cursor daily limits.

## Mixed DML — Setup vs Non-Setup Objects

You cannot DML setup objects (`User`, `Group`, `GroupMember`, `Permission*`, `UserRole`) and non-setup objects in one transaction. Enqueue a Queueable for the second batch.

```java
// Transaction 1: setup DML
insert new User(...);
// Cannot insert Account here — would throw MIXED_DML_OPERATION

// Defer the non-setup DML to another transaction
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
