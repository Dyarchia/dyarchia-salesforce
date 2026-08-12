# `@AuraEnabled` Controller Contract (v67.0)

Companion to §7 of `SKILL.md`. This file covers only the Apex an LWC needs. For server-side depth
— Service / Selector / Domain layering, the trigger framework, async patterns, observability and
testing — load the `decimatio-apex` skill.

## SOQL — `WITH USER_MODE`

In API 67+, `WITH SECURITY_ENFORCED` is **removed**; it no longer compiles. `WITH USER_MODE`
enforces object permissions, FLS and sharing, applies to the full query rather than just the
`SELECT` clause, handles polymorphic fields, and returns the complete set of access errors. It has
been available since API v60.0.

```java
// forward-compatible, enforces FLS + sharing for the running user
List<Account> accounts = [
    SELECT Id, Name FROM Account
    WHERE Industry = :industry
    WITH USER_MODE
    LIMIT 200
];
```

## Minimum Viable Controller

```java
public with sharing class AccountController {

    // Apex required because: GraphQL cannot express cross-object aggregate
    // with custom rollup AND a callout in the same transaction.
    @AuraEnabled(cacheable=true)
    public static List<AccountWrapper> getSummaries(List<Id> accountIds) {
        return AccountService.buildSummaries(accountIds);   // delegate to service layer
    }

    public class AccountWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal openPipelineTotal;
    }
}
```

Two details worth stating out loud. The comment above the method is the justification for using
Apex at all — if you cannot write that sentence, the work belongs in LDS, GraphQL or Flow. And the
method body is one line: the controller is a boundary, not a place for business logic.

In API 67+, an `@AuraEnabled` class with no sharing keyword defaults to `with sharing`, and SOQL and
DML run in user mode by default. Declare both explicitly anyway, so enforcement is intentional and
does not silently change if the class is later touched on a legacy API version. Use `?.` and `??`
for null handling. Throw `AuraHandledException` for failures so the LWC receives a clean message.

## Calling It From LWC

```javascript
// @wire for reads (cacheable)
import getSummaries from '@salesforce/apex/AccountController.getSummaries';
@wire(getSummaries, { accountIds: '$selectedIds' })
summaries;

// imperative for DML or non-cacheable operations
async handleSave() {
    try { await saveRecords({ records: this.modifiedRecords }); }
    catch (error) { /* handle */ }
}

// anti-pattern — imperative call for a read that could be @wire
connectedCallback() {
    getSummaries({ accountIds: this.ids }).then(r => this.data = r);
}
```

The `$` prefix in `'$selectedIds'` makes the wire reactive: the method re-runs whenever the property
changes. An imperative call in `connectedCallback` gives up both the LDS cache and that re-fetch.

`@AuraEnabled(cacheable=true)` reads are served from the Lightning Data Service cache after the
first call. Cacheable methods cannot perform DML and must be `static`.
