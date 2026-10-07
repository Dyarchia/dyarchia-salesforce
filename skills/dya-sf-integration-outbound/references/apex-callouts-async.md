# Apex Callouts & Async Patterns — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-outbound`. The canonical async framework (Queueable, Finalizers) lives in `dya-sf-apex`.

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

## The Callout-After-DML Rule

- Use a Queueable for "save record, then notify external".
- Use Continuation for long-running calls, and a Finalizer for guaranteed post-work.

## Queueable Callout

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

For guaranteed post-callout logic, add a Transaction Finalizer (`dya-sf-apex`).

## Continuation

Returns a slow call's result to the user without holding a synchronous thread; **120 s** max. Common in Visualforce/Aura controllers and long LWC-driven operations.

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
- Record failures for reconciliation through the org's existing mechanism — never swallow a `CalloutException` silently, and never stand up a logging object to catch it.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Retrying 4xx | Retry only 429/5xx with backoff |
| Infinite Queueable re-enqueue on failure | Cap attempts; dead-letter |
| Swallowing `CalloutException` | Log durably + signal retry/reconcile |
