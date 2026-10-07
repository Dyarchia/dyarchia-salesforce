# `@AuraEnabled` Controller Contract (Winter '27 / API v68.0)

Companion to §7 of `SKILL.md`, covering only the Apex an LWC needs. For server-side depth — Service /
Selector / Domain layering, the trigger framework, async patterns, observability and testing — load
`dya-sf-apex`.

## SOQL — `WITH USER_MODE`

From API 67.0, `WITH SECURITY_ENFORCED` no longer compiles. `WITH USER_MODE`
(available since API v60.0) enforces object permissions, FLS and sharing, applies to the full query
rather than just the `SELECT` clause, handles polymorphic fields, and returns every access error.

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

Justify Apex in a comment above the method; if you cannot write that sentence, the work
belongs in LDS, GraphQL or Flow. Keep the method body to one line: the controller is a boundary.

From API 67.0, an `@AuraEnabled` class with no sharing keyword defaults to `with sharing`, and SOQL
and DML run in user mode. Declare both anyway, so enforcement does not change silently if the class
is later saved on an older API version. Use `?.` and `??` for null handling.

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
