# Apex Callouts & Async Patterns — Reference (API v67.0)

Load from `dya-integration-outbound` for the callout mechanics, the callout-after-DML rule, and async callout patterns. The canonical async framework (Queueable, Finalizers) lives in `dya-apex`; this file is the integration-specific slice. All examples use Named Credentials (`callout:`) — see `dya-integration-auth`.

## Synchronous Callout

```apex
public with sharing class PaymentGateway {
    public class Result { public Boolean ok; public String message; }

    public static Result charge(Decimal amount, String currency) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Payments_API/v1/charge');   // no secret, no Remote Site Setting
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);                               // ms (max 120000)
        req.setBody(JSON.serialize(new Map<String,Object>{ 'amount' => amount, 'currency' => currency }));

        Result r = new Result();
        try {
            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();
            if (code >= 200 && code < 300) {
                r.ok = true; r.message = 'OK';
            } else if (code == 429 || code >= 500) {
                r.ok = false; r.message = 'Retryable: ' + code;   // signal retry upstream
            } else {
                r.ok = false; r.message = 'Permanent: ' + code;   // 4xx — don't retry
            }
        } catch (System.CalloutException e) {
            r.ok = false; r.message = 'Callout failed: ' + e.getMessage();
        }
        return r;
    }
}
```

Limits (per transaction): **100 callouts**; **timeout 1–120000 ms** per callout and **120 s cumulative**; **6 MB sync / 12 MB async** payload. Classify responses: 2xx success, 4xx permanent (don't retry), 429/5xx retryable.

## The Callout-After-DML Rule

You cannot call out once the transaction has uncommitted DML. Resolve in this order:

1. **Reorder** — do the callout before the DML.
2. **Queueable** — commit DML, then enqueue a Queueable that calls out in its own transaction (preferred for "save record, then notify external").
3. **Continuation / Finalizer** — for long-running or guaranteed-post-work cases.

## Queueable Callout (the default async pattern)

```apex
public with sharing class NotifyExternalQueueable implements Queueable, Database.AllowsCallouts {
    private final Set<Id> recordIds;
    public NotifyExternalQueueable(Set<Id> ids) { this.recordIds = ids; }

    public void execute(QueueableContext ctx) {
        // Aggregate one payload for the whole batch — never one callout per record
        List<Account> accts = [SELECT Id, Name FROM Account WHERE Id IN :recordIds WITH USER_MODE];
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:CRM_Sync/v1/accounts');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(accts));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() >= 500) {
            // re-enqueue with backoff (guard against infinite chains)
        }
    }
}
// Enqueue AFTER the DML commits (e.g. from a trigger handler's andFinally):
System.enqueueJob(new NotifyExternalQueueable(idSet));
```

Rules: implement `Database.AllowsCallouts`; **aggregate** — one callout for the whole batch, never per record; guard re-enqueue chains; for guaranteed post-callout logic add a Transaction Finalizer (`dya-apex`).

## Continuation (long-running, sync-feeling)

Use when an external call is slow but you want to return a result to the user without holding a synchronous thread. Up to **3 parallel** callouts, **120 s** max. Common in Visualforce/Aura controllers and long LWC-driven operations.

## Batch Callout

```apex
public class SyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id, Name FROM Account WITH USER_MODE]);
    }
    public void execute(Database.BatchableContext bc, List<Account> scope) {
        // one callout per chunk — ≤100 callouts per execute
    }
    public void finish(Database.BatchableContext bc) {}
}
```

## Retry & Idempotency

- Make the remote operation **idempotent** (send a client-generated request id) so retries don't double-charge/double-create.
- Retry only **429/5xx**; back off (exponential where possible); cap attempts.
- Persist failures durably (Platform Event → log object) for reconciliation; never swallow a `CalloutException` silently.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Callout per record in a loop | Aggregate into one batched callout |
| Callout with uncommitted DML | Queueable after DML / callout-first |
| `@future(callout=true)` for new work | Queueable + `Database.AllowsCallouts` |
| Hard-coded URL/secret | Named Credential `callout:` |
| Retrying 4xx | Retry only 429/5xx with backoff |
| Infinite Queueable re-enqueue on failure | Cap attempts; dead-letter |
| Swallowing `CalloutException` | Log durably + signal retry/reconcile |
| Ignoring the 120 s cumulative budget | Split work across async jobs |
