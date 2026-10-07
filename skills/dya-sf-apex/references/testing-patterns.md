# Apex Testing Patterns

Companion to §8 of `SKILL.md`: the rules live there, the working shapes here.

## `@TestSetup` + Bulk Test Skeleton

`@TestSetup` data is created once and given to each test method as a fresh rollback copy. Every
bulk-callable class needs at least one 200+ record test — a one-record test proves nothing about
governor behaviour.

```java
@IsTest
private class AccountHandlerTest {

    @TestSetup
    static void makeData() {
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accts.add(new Account(Name = 'Test ' + i, Industry = 'Tech'));
        }
        insert accts;
    }

    @IsTest
    static void afterUpdateRecalculatesScore() {
        List<Account> accts = [SELECT Id FROM Account];

        Test.startTest();
        for (Account a : accts) { a.Industry = 'Finance'; }
        update accts;
        Test.stopTest();

        for (Account a : [SELECT Id, Score__c FROM Account]) {
            Assert.areNotEqual(null, a.Score__c, 'Score must be calculated');
        }
    }
}
```

`Test.startTest()` / `Test.stopTest()` wraps the act, not the arrange: it resets governor limits for
the code under test and forces queued async work to complete before the assertions.

## Stub API — Unit Test Isolation

The Service / Selector layering exists so the selector can be replaced at test time; with a stub,
the test exercises business logic with zero SOQL and zero DML.

```java
IOpportunitySelector stub = (IOpportunitySelector) Test.createStub(
    IOpportunitySelector.class,
    new OpportunitySelectorStub(new List<Opportunity>{
        new Opportunity(Amount = 100), new Opportunity(Amount = 200)
    })
);
Assert.areEqual(300, new OpportunityService(stub).pipelineTotal('001...'));
```

The stub provider class implements `System.StubProvider` and returns canned values from
`handleMethodCall`. Inject the selector through the service constructor — a service that news up
its own selector cannot be stubbed.

## `RunRelevantTests` Annotations (Beta, API v66+)

- `@IsTest(critical=true)` — runs the test in every `RunRelevantTests` deployment, whatever it
  touches.
- `@IsTest(testFor='ApexClass:AccountService,ApexTrigger:AccountTrigger')` — runs the test when any
  listed component is in the deployment.

Both take effect only with:

```bash
sf project deploy start --test-level RunRelevantTests
```

Until GA, verify production-critical tests under a broader test level. `RunRelevantTests` is a
speed optimisation for feature branches, not the gate in front of production.

## Raising a class from 66.0 to 67.0 or above

The version stamp is where the security defaults change, so a bump is a testing exercise, not a
metadata edit. In this order:

1. Replace `WITH SECURITY_ENFORCED` with `WITH USER_MODE`, or `Security.stripInaccessible` where
   partial results are acceptable.
2. State the sharing keyword on every class rather than relying on the new `with sharing` default.
3. Decide, per operation, whether it runs in user mode or system mode. Document each justified
   `AccessLevel.SYSTEM_MODE` or `WITH SYSTEM_MODE` — including inside `without sharing` classes,
   which from 67.0 suppress record sharing but **not** CRUD or FLS.
4. **Grant the required CRUD and FLS to the test users or permission sets**, then re-run the
   affected tests as a non-administrator.

Step 4 gets skipped, which is why the failures look mysterious. `System.runAs` alone is not enough:
its user must carry a **permission set granting the object and field access the code needs**, or
every user-mode query throws. A test that passes as an administrator and fails under `runAs` usually
reports a missing permission set, not a bug.

Triage a failure by checking the failing SOQL or DML's stack trace for a CRUD/FLS access error.
Where user mode is intended, fix the permission set; where system mode is genuinely correct, make it
explicit and say why.

## Coverage

75% is the deployment threshold, not the quality bar. Target 100% of meaningful branches. Coverage
without assertions is worthless: it raises the number and catches no regression.

## Integration tests with real callouts (Developer Preview, Winter '27)

`@IntegrationTest` marks a test allowed to make **real HTTP callouts** instead of using a mock. It
is for contract verification against a sandbox endpoint — proving your request shape and parsing
survive the actual service — not ordinary unit testing.

Constraints:

- **Developer Preview.** Not available in production orgs, and not a substitute for the mocked tests
  that gate a deployment. Keep full `HttpCalloutMock` coverage alongside it.
- **Asynchronous only**, and only one such test runs at a time.
- **No automatic rollback.** Unlike a normal `@IsTest` method, it does not roll its data back: you
  create, you clean up, and a failure midway leaves records behind.
- The endpoint must be reachable and stable; a test that fails when someone else's sandbox is down
  is one the team will start ignoring.

Treat it as a scheduled contract check, not as part of the deployment gate.
