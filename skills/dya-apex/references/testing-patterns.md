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

## Coverage

75% is the deployment threshold, not the quality bar. Target 100% of meaningful branches. Coverage
without assertions is worthless — a test that executes lines and asserts nothing raises the number
and catches no regression.
