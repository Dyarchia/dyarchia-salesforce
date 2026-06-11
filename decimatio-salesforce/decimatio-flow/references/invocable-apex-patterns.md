# Invocable Apex Patterns — Flow → Apex Bridge

Full implementations of the `@InvocableMethod` and `@InvocableVariable` patterns referenced from SKILL.md §6. Load this file when authoring or refactoring an Apex method that will be called from Flow.

## Why `@InvocableMethod`

Flow's "Action" element calls any static Apex method annotated with `@InvocableMethod`. This is the canonical bridge from declarative Flow to imperative Apex — preferred over `@AuraEnabled` (which is for LWC) or `Flow.Interview.start()` from Apex (which is for the opposite direction: Apex orchestrating Flow).

The contract is rigid and easy to get wrong:

- Method must be `static`.
- Method must accept exactly **one parameter**: `List<T>`.
- Method must return either `void` or `List<U>`.
- When returning a list, its length and order MUST match the input list (Flow correlates input row N to output row N).

## Basic Pattern

```java
public with sharing class AccountScorer {

    @InvocableMethod(
        label='Recalculate Account Score'
        description='Recomputes the rollup score for a set of Accounts'
        category='Account'
        callout=false
    )
    public static List<Output> recalculate(List<Input> inputs) {
        // ALWAYS bulk-process. Flow passes a List even when invoked
        // from a single-record context, so the input may contain 1 or 200 items.
        Set<Id> accountIds = new Set<Id>();
        for (Input i : inputs) {
            accountIds.add(i.accountId);
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, AnnualRevenue,
                   (SELECT Amount FROM Opportunities WHERE IsClosed = false)
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ]);

        List<Output> results = new List<Output>();
        for (Input i : inputs) {
            Account a = accountsById.get(i.accountId);
            Decimal score = computeScore(a);
            Output o = new Output();
            o.accountId = i.accountId;
            o.score = score;
            results.add(o);
        }
        return results;
    }

    private static Decimal computeScore(Account a) {
        if (a == null) return 0;
        Decimal pipeline = 0;
        for (Opportunity opp : a.Opportunities) {
            pipeline += opp.Amount ?? 0;
        }
        return (a.AnnualRevenue ?? 0) * 0.1 + pipeline;
    }

    public class Input {
        @InvocableVariable(required=true label='Account Id')
        public Id accountId;
    }

    public class Output {
        @InvocableVariable(label='Account Id')
        public Id accountId;
        @InvocableVariable(label='Computed Score')
        public Decimal score;
    }
}
```

### `@InvocableMethod` annotation properties

- `label` — appears in Flow's Action picker. Make it user-readable.
- `description` — appears as the action's help text. Be explicit about what the action does and what it expects.
- `category` — groups the action in the picker (`Account`, `Order`, `Integrations`). Improves discoverability when an org has dozens of invocable methods.
- `callout=true` — declares the action makes HTTP callouts. Flow uses this to gate where the action can be placed (cannot be on a same-transaction path of a record-triggered flow).

### `@InvocableVariable` annotation properties

- `required=true` — Flow validates the variable is set before invoking the action.
- `label` — displayed in the action's input/output panel.
- `description` — help text on the variable.

## Custom DTOs with `@InvocableVariable`

Input and output types must be classes with `@InvocableVariable`-annotated public fields. Primitives, SObjects, and `List`/`Map` of these types are supported.

```java
public class OrderInput {
    @InvocableVariable(required=true)
    public Id orderId;

    @InvocableVariable
    public Boolean expediteShipping;

    @InvocableVariable
    public String specialInstructions;
}

public class OrderOutput {
    @InvocableVariable
    public Id orderId;

    @InvocableVariable
    public Boolean success;

    @InvocableVariable
    public String errorMessage;

    @InvocableVariable
    public List<Id> createdShipmentIds;
}
```

Lists of DTOs are supported but increase complexity for Flow authors. Prefer flat structures.

## Partial Success — Per-Row Error Handling

When some inputs may succeed and others fail, propagate the result row-by-row in the output rather than throwing.

```java
public static List<OrderOutput> process(List<OrderInput> inputs) {
    List<OrderOutput> results = new List<OrderOutput>();
    Set<Id> orderIds = new Set<Id>();
    for (OrderInput i : inputs) { orderIds.add(i.orderId); }

    Map<Id, Order> ordersById = new Map<Id, Order>([
        SELECT Id, Status FROM Order WHERE Id IN :orderIds WITH USER_MODE
    ]);

    for (OrderInput i : inputs) {
        OrderOutput o = new OrderOutput();
        o.orderId = i.orderId;
        try {
            Order ord = ordersById.get(i.orderId);
            if (ord == null) {
                o.success = false;
                o.errorMessage = 'Order not found or not accessible';
            } else {
                // ... do work, update o.createdShipmentIds, etc. ...
                o.success = true;
            }
        } catch (Exception e) {
            o.success = false;
            o.errorMessage = e.getMessage();
        }
        results.add(o);
    }
    return results;
}
```

In Flow, route on `output[].success` — if any row failed, branch to a fault-handling path. This is more robust than throwing from Apex, because a single throw aborts the entire flow batch.

## Full-Batch Failure — Throwing

If the entire batch should fail when anything goes wrong (e.g., a callout returns an error), throw a clear exception. Flow will route to the action's Fault Path.

```java
public static List<Output> sync(List<Input> inputs) {
    HttpResponse res = makeCallout(inputs);
    if (res.getStatusCode() != 200) {
        throw new ExternalServiceException(
            'External sync failed: ' + res.getStatusCode() + ' — ' + res.getBody()
        );
    }
    // ... process and return ...
}

public class ExternalServiceException extends Exception {}
```

The exception message appears as `{!$Flow.FaultMessage}` in the Fault Path — keep it human-readable.

## `callout=true` Gotcha

```java
@InvocableMethod(label='Fetch External Quote' callout=true)
public static List<QuoteOutput> fetch(List<QuoteInput> inputs) { /* ... */ }
```

When `callout=true`:

- The action CANNOT be placed in a record-triggered flow's main (synchronous) path.
- It CAN be placed in an Asynchronous Path of a record-triggered flow.
- It CAN be placed anywhere in an autolaunched or screen flow.

Forgetting `callout=true` lets Flow place the action where it will fail at runtime with `CalloutException: You have uncommitted work pending`. Always declare it.

## Generic SObject Inputs

If the action must accept any SObject (e.g., a logging utility), use `List<SObject>`:

```java
@InvocableMethod(label='Log Record Change')
public static void logChange(List<SObject> records) {
    // SObject API works generically; cast inside if you need typed access
    for (SObject so : records) {
        Logger.info('Changed: ' + so.getSObjectType() + ' ' + so.Id);
    }
}
```

Flow allows the author to pass any record collection. Use this sparingly — typed DTOs are clearer and catch errors earlier.

## Testing Invocable Methods

```java
@IsTest
private class AccountScorerTest {
    @IsTest
    static void scoresAccountsInBulk() {
        // Insert 200 accounts with opportunities
        List<Account> accts = TestDataFactory.makeAccountsWithOpps(200);

        List<AccountScorer.Input> inputs = new List<AccountScorer.Input>();
        for (Account a : accts) {
            AccountScorer.Input i = new AccountScorer.Input();
            i.accountId = a.Id;
            inputs.add(i);
        }

        Test.startTest();
        List<AccountScorer.Output> results = AccountScorer.recalculate(inputs);
        Test.stopTest();

        Assert.areEqual(200, results.size(), 'Output length must match input');
        for (AccountScorer.Output o : results) {
            Assert.isNotNull(o.score);
        }
    }
}
```

Invocable methods test the same way as any other Apex method — the annotation is metadata for Flow's UI, the method itself is just a static method.
