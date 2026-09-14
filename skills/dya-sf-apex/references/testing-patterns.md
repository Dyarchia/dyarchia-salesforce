# Apex Testing Patterns

Companion to §8 of `SKILL.md`. The rules live there; the working shapes live here.

## `@TestSetup` + Bulk Test Skeleton

`@TestSetup` data is created once and handed to each test method as a fresh rollback copy. Every
bulk-callable class needs at least one test at 200+ records — a one-record test proves nothing
about governor behaviour.

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
the code under test and forces queued async work to complete before the assertions run.

## Stub API — Unit Test Isolation

The Service / Selector layering exists so the selector can be replaced at test time. With a stub,
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

- `@IsTest(critical=true)` — forces the test to run during every `RunRelevantTests` deployment,
  regardless of what the deployment touches.
- `@IsTest(testFor='ApexClass:AccountService,ApexTrigger:AccountTrigger')` — forces the test to run
  when any of the listed components is part of the deployment.

Both annotations only take effect with:

```bash
sf project deploy start --test-level RunRelevantTests
```

Until the feature reaches GA, production-critical tests should still be verified under a broader
test level. Treat `RunRelevantTests` as a speed optimisation for feature branches, not as the gate
in front of production.

## Raising a class from 66.0 to 67.0 or above

The version stamp is where the security defaults change, so a version bump is a testing exercise, not
a metadata edit. Work through it in this order:

1. Replace `WITH SECURITY_ENFORCED` with `WITH USER_MODE`, or `Security.stripInaccessible` where
   partial results are acceptable.
2. State the sharing keyword explicitly on every class rather than relying on the new `with sharing`
   default.
3. Decide, per operation, whether it runs in user mode or system mode. Document each justified
   `AccessLevel.SYSTEM_MODE` or `WITH SYSTEM_MODE` — including inside `without sharing` classes,
   which from 67.0 suppress record sharing but **not** CRUD or FLS.
4. **Grant the required CRUD and FLS to the test users or permission sets**, then re-run the
   affected tests as a non-administrator.

Step 4 is the one that gets skipped, and it is why the failures look mysterious. `System.runAs` alone
is not enough: the user it runs as has to carry a **permission set granting the object and field
access the code needs**, or every user-mode query throws. A test that passes as an administrator and
fails under `runAs` is usually reporting a missing permission set, not a bug.

Triage a failure by reading the stack trace of the failing SOQL or DML for a CRUD/FLS access error.
Where user-mode behaviour is what you intend, fix the permission set. Where system mode is genuinely
correct, make it explicit and say why.

## Coverage

75% is the deployment threshold, not the quality bar. Target 100% of meaningful branches. Coverage
without assertions is worthless — a test that executes lines and asserts nothing raises the number
and catches no regression.

## Integration tests with real callouts (Developer Preview, Winter '27)

`@IntegrationTest` marks a test that is allowed to make **real HTTP callouts** instead of returning a
mock. It exists for contract verification against a sandbox endpoint — proving your request shape and
parsing survive the actual service — not for ordinary unit testing.

Constraints that change how you write the test:

- **Developer Preview.** Not available in production orgs, and not a substitute for the mocked tests
  that gate a deployment. Keep full `HttpCalloutMock` coverage alongside it.
- **Asynchronous only**, and only one such test runs at a time.
- **No automatic rollback.** A normal `@IsTest` method rolls its data back when it finishes; this one
  does not. You create, you clean up, and a failure midway leaves records behind.
- The endpoint must be reachable and stable. A test that fails when someone else's sandbox is down is
  a test the team will start ignoring.

Treat it as a scheduled contract check, not as part of the deployment gate.
