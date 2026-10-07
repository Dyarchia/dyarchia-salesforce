# Invocable Apex Patterns — Flow → Apex Bridge

Full implementations of the patterns from SKILL.md §6. Load when authoring or refactoring an Apex method called from Flow.

Flow's Action element calls any static Apex method annotated with `@InvocableMethod` — the bridge from Flow to Apex, not `@AuraEnabled` (for LWC) or `Flow.Interview.start()` (Apex orchestrating Flow). The return list must match the input in length and order because Flow correlates input row N to output row N.

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
        // ALWAYS bulk-process: expect 1 to 200 items.
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

- `label` — shown in Flow's Action picker. Make it user-readable.
- `description` — the action's help text: what it does and expects.
- `category` — groups the action in the picker (`Account`, `Order`, `Integrations`).
- `callout=true` — declares HTTP callouts; Flow gates placement on it (see below).

### `@InvocableVariable` annotation properties

- `required=true` — Flow validates the variable is set before invoking the action.
- `label` — displayed in the action's input/output panel.
- `description` — help text on the variable.

## Custom DTOs with `@InvocableVariable`

Input and output types are classes with `@InvocableVariable`-annotated public fields of primitives, SObjects, or `List`/`Map` of these.

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

Lists of DTOs are supported but harder for Flow authors. Prefer flat structures.

## Partial Success — Per-Row Error Handling

When some inputs may succeed and others fail, return the result per row instead of throwing.

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

In Flow, route on `output[].success`; if any row failed, branch to a fault-handling path. A single throw would abort the entire flow batch.

## Full-Batch Failure — Throwing

If the whole batch should fail when anything goes wrong (e.g., a callout returns an error), throw; Flow routes to the action's Fault Path.

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

Keep the message human-readable; it becomes `{!$Flow.FaultMessage}`.

## `callout=true`

```java
@InvocableMethod(label='Fetch External Quote' callout=true)
public static List<QuoteOutput> fetch(List<QuoteInput> inputs) { /* ... */ }
```

With `callout=true`, the action:

- CANNOT be placed in a record-triggered flow's main (synchronous) path.
- CAN be placed in an Asynchronous Path of a record-triggered flow.
- CAN be placed anywhere in an autolaunched or screen flow.

Without `callout=true`, Flow lets you place the action where it fails at runtime with `CalloutException: You have uncommitted work pending`.

## Generic SObject Inputs

For an action that accepts any SObject (e.g., a logging utility), use `List<SObject>`:

```java
@InvocableMethod(label='Log Record Change')
public static void logChange(List<SObject> records) {
    // Generic SObject API; cast inside for typed access
    for (SObject so : records) {
        System.debug(LoggingLevel.INFO, 'Changed: ' + so.getSObjectType() + ' ' + so.Id);
    }
}
```

Use sparingly — typed DTOs are clearer and catch errors earlier.

## Custom Input Types Need a No-Argument Constructor (API 67.0+)

A class with only a parameterised constructor fails at runtime; if you add a non-default constructor, add the no-arg one back.

```java
public class OrderInput {
    @InvocableVariable(required=true)
    public Id orderId;

    @InvocableVariable
    public String specialInstructions;

    public OrderInput() {}

    public OrderInput(Id orderId) {
        this.orderId = orderId;
    }
}
```

## Configuring the Action in Flow Builder — `InvocableActionExtension`

The `InvocableActionExtension` metadata type (GA; Enterprise, Performance, Unlimited and Developer editions) defines the **design-time experience** of an admin configuring the action:

- **Per-input custom property editor** — a custom LWC editor on one input; the others keep the standard editor.
- **Picklist values for an input** — a fixed dropdown for a `String` input.
- **Custom header** — a custom component above the inputs (instructions, a link, a summary of the action).

Deploy the metadata alongside the Apex class; the Metadata API reference gives the exact element shape.

## Testing Invocable Methods

```java
@IsTest
private class AccountScorerTest {
    @IsTest
    static void scoresAccountsInBulk() {
        // 200 accounts with opportunities
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

Test invocable methods like any static Apex method; the annotation is only metadata for Flow's UI.

## The Reverse Direction — Calling a Flow from Apex

When Apex orchestrates and a Flow is the step, use `Flow.Interview`:

```apex
Map<String, Object> inputs = new Map<String, Object>{
    'accountId' => acc.Id,
    'newRating' => 'Hot'
};
Flow.Interview interview = Flow.Interview.createInterview('My_Autolaunched_Flow', inputs);
interview.start();
Object output = interview.getVariableValue('outputVariableName');
```

The flow's API name and the map keys (the flow's input variable names) are unchecked at compile
time; a rename in Flow Builder breaks this at runtime, not at deploy. Cover it with a test.

`Flow.Interview` runs autolaunched flows only; a screen flow cannot run headlessly.

From a Lightning Web Component, embed a flow with `lightning/flowSupport`, or navigate to a screen
flow with a `standard__flow` PageReference: `dya-sf-lwc`.

## Who Is Calling? Flow and Agentforce Bulk Differently

| | Called from Flow | Called as an Agentforce action |
|---|---|---|
| Batching | Always a `List`, even from a single-record context — a record-triggered flow passes the whole 200-record batch | One invocation per agent turn, each in its own transaction; no batching across turns |
| On failure | Throwing surfaces the message as `{!$Flow.FaultMessage}` for a Fault Path to handle | Throwing gives the agent a raw exception it cannot explain to a user |

Handle a list of any size — that satisfies Flow and costs an agent nothing. A Flow-facing action
throws on full-batch failure; an agent-facing action returns a success flag and a human-readable
message the agent can relay. If one method serves both, return that result and let the Flow branch
on it. The agent side: `dya-sf-agentforce`.
