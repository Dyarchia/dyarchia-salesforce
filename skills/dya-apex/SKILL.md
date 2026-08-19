---
name: dya-apex
description: Salesforce Apex Summer '26 (API v67.0) modern development best practices — syntax, security, SOQL/DML, triggers, async, testing, performance, observability. Load only when the user explicitly invokes this skill by name (`dya-apex`); do NOT auto-trigger on generic Apex, Salesforce, or trigger-related questions.
---

# Salesforce Apex Modern Development

You are an expert Salesforce Apex developer. You **always** use the most modern syntax available, you **always** enforce user-mode security by default, and you **always** bulkify. Follow every rule below without exception.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/` and are loaded on demand:

- `references/trigger-framework.md` — full Tony Scott `ITrigger` interface, `TriggerFactory`, handler skeleton, recursion guard.
- `references/async-patterns.md` — full Queueable, Transaction Finalizer, Apex Cursor chain, Mixed-DML pattern.
- `references/observability-patterns.md` — full `Log__e` Platform Event + `Logger` class + subscriber trigger.
- `references/solid-principles.md` — SOLID applied to Apex: SRP layering, OCP via interfaces, LSP contracts, ISP selectors, DIP with Stub-API injection.

Load a reference when you are about to write or refactor code that needs that exact implementation.

---

## Platform Context — Summer '26 / API v67.0

**Current API version: 67.0 (Summer '26).** All new Apex classes, triggers, and metadata files MUST be saved at `<apiVersion>67.0</apiVersion>`. API 67 ships versioned defaults that the rest of this skill assumes:

- **Database operations default to `USER_MODE`** (SOQL, SOSL, DML, `Database.*`). In API 66 and earlier they default to `SYSTEM_MODE`.
- **Omitted sharing declaration defaults to `with sharing`** in API 67+ (was `without sharing` in 66 and earlier).
- **Inheritance contagion**: if any class in an inheritance chain is at API 67+, an omitted sharing declaration in any descendant defaults to `with sharing`. Same for `@AuraEnabled` methods called from LWC and Aura controllers.
- **`WITH SECURITY_ENFORCED` is REMOVED** in API 67+: classes that use it do not compile. Use `WITH USER_MODE`.
- **Triggers always run in `SYSTEM_MODE`** on all API versions and cannot declare sharing/access mode — that is a compile error. Sharing goes on the handler class.
- **Multiline string literals (`'''…'''`) and `String.template()`** are available in API 67+ (see §2).

Existing classes on older API versions keep their old behaviour until you bump them. When uplifting legacy code, **make sharing declarations explicit before saving** — never rely on the default flipping.

**Legacy API retirement.** Platform API versions 21.0–30.0 are already retired (Summer '23) — code on those versions no longer runs. Versions 31.0–39.0 are flagged as the next at-risk wave under Salesforce's ongoing deprecation policy, but no firm retirement date has been announced. Target API 56.0+ for any new integration; flag any classes below 41.0 during review. Separately and unrelated to full-API retirement: the SOAP API `login()` endpoint for versions 31.0–64.0 is being retired in Summer '27 (this is the login endpoint specifically, not the full API) — migrate integrations to External Client Apps before enforcement.

---

## 1. Class Structure

### Sharing mode is mandatory and explicit

Specify a sharing keyword on every class. Default to `with sharing`. Use `without sharing` only for system-level integrations and admin tooling, and document why in a class-level comment. Use `inherited sharing` for utility classes whose sharing must follow the caller.

```java
// ✅
public with sharing class AccountService { ... }
public without sharing class IntegrationGateway { ... }   // only when justified
public inherited sharing class ReusableHelper { ... }

// ❌
public class AccountService { ... }                       // implicit, versioned default
```

### Access modifiers

`private` by default. `public` only when external callers need it. `global` only in managed packages or web service interfaces — never for org-internal code.

### API version

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>67.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

---

## 2. Modern Apex Syntax

### Safe navigation (`?.`) and null coalescing (`??`)

```java
// ✅
String street = account?.BillingAddress?.Street;
String username = getUserFromSession() ?? 'Guest';
Account acct = [SELECT Id FROM Account WHERE Name = 'Acme' LIMIT 1] ?? new Account(Name = 'Default');
```

### `switch on` over `if/else` chains

Use whenever branching on more than two discrete values of a single variable.

```java
switch on Trigger.operationType {
    when BEFORE_INSERT { handler.beforeInsert(); }
    when AFTER_UPDATE  { handler.afterUpdate(); }
    when else          { /* no-op */ }
}
```

### Multiline string literals (`'''…'''`, API 67+)

For any string that spans more than one logical line. Concatenating with `+` or embedding `\n` is an anti-pattern.

```java
// ✅
String payload = '''
{
  "currency": "USD",
  "amount": 1500
}
''';
```

### String templates — `.template(Map<String, Object>)` (API 67+)

For variable interpolation, always use named placeholders. Never use `+` concatenation or `String.format(..., new String[]{...})` for interpolation in new code.

```java
// ✅
String message = '''
Hello ${firstName},
Your order was dispatched on ${dispatchDate}.
'''.template(new Map<String, Object>{
    'firstName'    => contact.FirstName,
    'dispatchDate' => order.ShipDate__c
});
```

Combined with multiline literals, this eliminates virtually every legitimate use of `+` for strings.

### `Trigger.operationType`

The enum is exhaustive, type-safe and switchable. Use it instead of `Trigger.isBefore && Trigger.isInsert` cascades.

### Modern assertions

```java
// ✅
Assert.areEqual(expected, actual, 'Account count should match');
Assert.isTrue(result.isSuccess());
Assert.isNotNull(account.Id);

// ❌ — legacy
System.assertEquals(expected, actual);
```

### Schema constants, never strings

```java
// ✅
String objectName = Account.SObjectType.getDescribe().getName();

// ❌
String objectName = 'Account';
```

---

## 3. Security — `USER_MODE` is the Default

In API 67+, `USER_MODE` is the versioned default for every SOQL, SOSL, DML and `Database.*` operation. It enforces CRUD, FLS and sharing on the running user. **Always set the access level explicitly anyway** — for readability and so behaviour does not silently change when a class is touched on a legacy branch.

### SOQL — `WITH USER_MODE`

```java
// ✅
List<Account> accts = [
    SELECT Id, Name, Industry
    FROM Account
    WHERE Industry = :industry
    WITH USER_MODE
    LIMIT 200
];

// ❌ — removed in API 67+, does NOT compile
List<Account> accts = [SELECT Id, Name FROM Account WITH SECURITY_ENFORCED];

// ⚠️ — ambiguous, relies on the versioned default
List<Account> accts = [SELECT Id, Name FROM Account];
```

### DML — `AccessLevel.USER_MODE`

```java
// ✅
Database.SaveResult[] results = Database.insert(accounts, AccessLevel.USER_MODE);
Database.SaveResult[] results = Database.update(accounts, false, AccessLevel.USER_MODE); // partial success
```

### When to use `SYSTEM_MODE`

Only for integration/system code that must legitimately escape user constraints, or trigger logic that updates fields the user cannot access (redesign first). Always document the exception with a comment:

```java
// SYSTEM_MODE required: audit field, end users intentionally lack edit access.
Database.update(auditRecords, AccessLevel.SYSTEM_MODE);
```

### `Security.stripInaccessible`

For records returned to a client whose FLS varies (e.g., `@AuraEnabled` methods):

```java
SObjectAccessDecision decision = Security.stripInaccessible(
    AccessType.READABLE,
    [SELECT Id, Name, AnnualRevenue FROM Account WHERE Id IN :ids WITH USER_MODE]
);
return decision.getRecords();
```

---

## 4. SOQL — Selective, Bulk, and Modern

### Never SOQL inside a loop

```java
// ✅
Set<Id> accountIds = new Set<Id>();
for (Contact c : Trigger.new) { accountIds.add(c.AccountId); }
Map<Id, Account> accountsById = new Map<Id, Account>([
    SELECT Id, Name FROM Account WHERE Id IN :accountIds WITH USER_MODE
]);
for (Contact c : Trigger.new) {
    c.Description = accountsById.get(c.AccountId)?.Name;
}
```

### Selective `WHERE` clauses

Every query MUST filter on an indexed field (Id, ExternalId, Name, foreign key, custom-indexed) and return less than the selectivity threshold. Non-selective queries on >100k-row objects fail with `QueryException: Non-selective query`.

### Dynamic SOQL — `Database.queryWithBinds`, not string concatenation

String concatenation in SOQL is a SOQL injection vulnerability. `Database.queryWithBinds` (since Spring '23) eliminates it.

```java
// ✅
Map<String, Object> binds = new Map<String, Object>{
    'industry'   => industryFilter,
    'minRev'     => 1000000,
    'namePrefix' => 'Acme%'
};
List<Account> accts = Database.queryWithBinds(
    'SELECT Id, Name FROM Account ' +
    'WHERE Industry = :industry AND AnnualRevenue > :minRev AND Name LIKE :namePrefix',
    binds,
    AccessLevel.USER_MODE
);

// ❌ — SOQL injection
String q = 'SELECT Id FROM Account WHERE Name = \'' + userInput + '\'';
List<Account> accts = Database.query(q);
```

Same applies to `Database.countQueryWithBinds` and `Database.getQueryLocatorWithBinds`. In dynamic SOQL the access level is the third argument; in static SOQL it is the inline `WITH USER_MODE` clause. They are not interchangeable.

### SOQL for-loop for bulk reads

```java
for (Account[] batch : [SELECT Id, Name FROM Account WHERE Industry = 'Tech' WITH USER_MODE]) {
    // batch is 200 records at a time, heap-friendly
}
```

### `FORMULA()` in `WHERE` clauses (Pilot, Summer '26)

```java
List<Opportunity> bigBets = [
    SELECT Id, Name, Amount, Probability
    FROM Opportunity
    WHERE FORMULA(Amount * Probability) > 10000
    WITH USER_MODE
];
```

**Status: Pilot.** Not GA. Requires Salesforce to enable it on the org. Do NOT use in production code until GA. On high-volume objects prefer an indexed stored formula field — selectivity rules still apply.

### Apex Cursors (GA in Spring '26)

For up to ~5M records with flexible chunking or bidirectional traversal. Limits: 50M rows/cursor, **10 `fetch()` calls per transaction**, 10k cursors/day, 100M rows/day aggregate.

> Full Cursor + Queueable chain implementation: see `references/async-patterns.md`.

---

## 5. DML — Always Bulk, Always Aware of Errors

### Never DML inside a loop

```java
// ✅
List<Contact> toUpdate = new List<Contact>();
for (Contact c : contacts) { c.Description = 'Updated'; toUpdate.add(c); }
Database.update(toUpdate, AccessLevel.USER_MODE);
```

### `Database.<dml>` over raw DML

Use `Database.insert/update/delete/upsert` for partial success, access level control, and structured `SaveResult[]` error handling.

```java
// ✅
Database.SaveResult[] results = Database.insert(records, false, AccessLevel.USER_MODE);
for (Integer i = 0; i < results.size(); i++) {
    if (!results[i].isSuccess()) {
        for (Database.Error err : results[i].getErrors()) {
            Logger.error(records[i], err.getStatusCode(), err.getMessage(), err.getFields());
        }
    }
}
```

### Upsert with external IDs for idempotency

```java
Database.upsert(records, Account.External_Id__c, false, AccessLevel.USER_MODE);
```

### Order of DML and callouts

You cannot callout after uncommitted DML in the same transaction. Either (a) callouts first then DML, (b) move the callout into a Queueable (recommended), or (c) into a Transaction Finalizer.

---

## 6. Triggers — Framework and Global Kill-Switch

For **new (greenfield) Salesforce implementations, the Tony Scott "Trigger Pattern for Tidy, Streamlined, Bulkified Triggers" framework is the default.** It enforces: one trigger per object; zero logic inside the trigger file; canonical execution order via the `ITrigger` interface; bulk caching in `bulkBefore`/`bulkAfter`, per-record work in iterative methods, post-processing in `andFinally`.

In any other scenario — a brownfield org, an existing codebase, or one already standardised on another framework (Kevin O'Hara's trigger framework, fflib, Trigger Actions Framework, a hand-rolled handler) — **do not impose Tony Scott. Ask first** which framework the org already uses and conform to it. Org-wide consistency beats the "best" framework bolted on top of a different one.

```java
// The trigger file — one line, no logic, no sharing declaration.
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    TriggerFactory.createAndExecuteHandler(AccountHandler.class);
}
```

**API 67+: triggers always run in `SYSTEM_MODE`** on all API versions. `with sharing` / `without sharing` / `inherited sharing` on a trigger is a compile error. The sharing declaration goes on the handler class. If trigger-driven DML must enforce user-level security, pass `AccessLevel.USER_MODE` explicitly to the relevant `Database.*` call inside the handler.

### Per-object kill-switch — hierarchical Custom Setting

Every trigger must be silenceable without a deployment, **per SObject** — you may want an integration or LLM-agent user to skip the Account trigger while still running the Case trigger. Model it as one hierarchical Custom Setting with **one Checkbox field per controlled object**, evaluated the instant the trigger fires; a `false` short-circuits that object's trigger with a bare `return`. Hierarchical scope means each object's switch is set independently at **Org, Profile, or User** level — the agent user gets `Account_Trigger_Enabled__c = false` at the User level, every other object keeps running.

Define `Trigger_Settings__c` as a **Hierarchy** Custom Setting. For each object you want to control, add a Checkbox field `<Object>_Trigger_Enabled__c` (strip the `__c` of custom objects, e.g. `Invoice__c` → `Invoice_Trigger_Enabled__c`) with **Default Value = Checked**. An object with no matching field always runs — you opt an object into the switch only by adding its field. Resolve the field dynamically from the `SObjectType` at trigger entry, defaulting to enabled when the field is absent, and bake the check into the framework entry point so the trigger file stays a single line.

> `TriggerBypass` implementation, the framework entry-point wiring, and the explicit form for a trigger that does not use the framework: see `references/trigger-framework.md`.

The kill-switch is a circuit-breaker, not a recursion guard — keep the framework's recursion handling regardless. Disabling an object's trigger org-wide is a footgun: prefer Profile or User scope, and re-enable the moment the bulk operation completes.

### Trigger rules — absolute

- One trigger per object. Order between multiple triggers is undefined.
- No logic in the trigger file.
- No SOQL or DML in iterative `beforeX`/`afterX` methods — cache in `bulkBefore`/`bulkAfter`, DML in `andFinally`.
- Field-value validation goes in `after` methods (values can still be modified by other before-triggers or workflows).
- Delegate SOQL to a Gateway/Selector class.
- For callouts triggered by DML, enqueue ONE Queueable in `andFinally` with the full batch — never `@future` per iteration.
- Every trigger honours its per-object hierarchical kill-switch (`Trigger_Settings__c`, field `<Object>_Trigger_Enabled__c`) at entry — resolved in the framework entry point, or named explicitly in a non-framework trigger.

> Full `ITrigger` interface, `TriggerFactory`, handler skeleton, recursion guard, and notes on alternative frameworks (Kevin O'Hara, fflib): see `references/trigger-framework.md`.

---

## 7. Async Apex — The Decision Tree

Stop at the first option that fits:

1. **Queueable Apex** — Default. Accepts complex types, chainable, monitored via Apex Jobs, supports Finalizers.
2. **Queueable + Transaction Finalizer** — When you need guaranteed post-job logic (retry, logging, callout-after-DML).
3. **Apex Cursors + Queueable chain** — For ~50k to ~5M records that need flexible chunking or bidirectional traversal. Bound by 10 `fetch()` per transaction.
4. **Batch Apex (`Database.Batchable`)** — For >5M records, recurring scheduled jobs, or when you need parallel chunk execution.
5. **Schedulable** — Only to schedule via Cron. Its `execute` should immediately enqueue a Queueable; never put business logic in `Schedulable.execute`.
6. **`@future`** — Avoid in new code. No return value, no chaining, no monitoring, no Finalizers. Legacy.

> Full Queueable + Finalizer + Cursor chain implementations and Mixed-DML guidance: see `references/async-patterns.md`.

---

## 8. Testing — Coverage Is the Floor, Not the Ceiling

### Core rules

- `@TestSetup` for shared data. Each test method gets a fresh rollback copy.
- Test in bulk — every bulk-callable class needs at least one test with 200+ records.
- Always wrap the act in `Test.startTest()` / `Test.stopTest()` (fresh limits, forces async to complete).
- Never make real callouts — `Test.setMock(HttpCalloutMock.class, ...)`.
- Use the Stub API (`Test.createStub`) for true unit tests with mocked selectors/gateways.
- Centralise record creation in `@IsTest`-annotated `TestDataFactory`.
- Run security-sensitive tests with `System.runAs(nonAdminUser)`.
- Never `@IsTest(SeeAllData=true)`. Never hard-code Ids — query by `DeveloperName` / `Name`.
- Always assert at least one meaningful business outcome.

### `RunRelevantTests` annotations (Beta, API v66+)

`@IsTest(critical=true)` and `@IsTest(testFor='...')` narrow what runs on a `RunRelevantTests` deployment. Both only take effect with `sf project deploy start --test-level RunRelevantTests`; until GA, verify production-critical tests with a broader test level.

> `@TestSetup` + 200-record bulk test skeleton, Stub API unit-test wiring, and the full `RunRelevantTests` annotation semantics: see `references/testing-patterns.md`.

### Code coverage

75% is a deployment threshold, not a quality bar. Target 100% of meaningful branches. Coverage without assertions is worthless.

---

## 9. Error Handling

### Custom exception classes per domain

```java
public class InvoiceGenerationException extends Exception {}
public class PricingEngineUnreachableException extends Exception {}
```

### Throw, don't swallow

```java
// ✅
try {
    HttpResponse res = http.send(req);
    return parse(res);
} catch (CalloutException e) {
    Logger.error('Pricing engine callout failed', e);
    throw new PricingEngineUnreachableException('Pricing unavailable', e);
}

// ❌
try { ... } catch (Exception e) { /* silently ignored */ }
```

### `AuraHandledException` for LWC-facing methods

`@AuraEnabled` methods must throw `AuraHandledException` so the client receives a clean message — internal stack traces never reach end users.

```java
@AuraEnabled
public static Account loadAccount(Id accountId) {
    try {
        return [SELECT Id, Name FROM Account WHERE Id = :accountId WITH USER_MODE LIMIT 1];
    } catch (Exception e) {
        Logger.error('loadAccount failed', e);
        throw new AuraHandledException('Could not load this account.');
    }
}
```

### `Database.SaveResult` partial success

Always check results when `allOrNone = false`. Collect failures into a structured log object rather than `System.debug`.

---

## 10. Performance

### Bulkification

Assume 200 records. Test with 200+.

### Platform Cache

Org Cache for org-wide reference data (currency rates, configuration tables); Session Cache for user-specific data (auth tokens, user preferences).

```java
public with sharing class FxRateService {
    private static final String PARTITION = 'local.AppCache';

    public static Decimal getRate(String currencyIso) {
        Cache.OrgPartition org = Cache.Org.getPartition(PARTITION);
        Decimal rate = (Decimal) org.get(currencyIso);
        if (rate == null) {
            rate = [SELECT Rate__c FROM Fx_Rate__mdt WHERE DeveloperName = :currencyIso LIMIT 1]?.Rate__c;
            org.put(currencyIso, rate, 3600); // 1 h TTL
        }
        return rate;
    }
}
```

- Items capped at 100 KB — prefer caching collections over many small items.
- Always handle cache miss (`get` returns `null`).
- Best-effort; never authoritative storage.
- Session TTL max 8 h. Org TTL max 48 h, default 24 h.

### Custom Metadata Types > Custom Settings

Use `__mdt` for configuration data — packageable, deployable, platform-cached, free of SOQL governor cost when accessed via `MyConfig__mdt.getInstance('Name')`. Use Custom Settings only for per-user/per-profile overrides Custom Metadata cannot express.

### `@AuraEnabled(cacheable=true)` for read-only LWC methods

Served from the Lightning Data Service cache after the first call. Cannot perform DML; must be `static`.

### Heap and selectivity

- Clear large collections (`bigList.clear()`) when done.
- Don't query SObject fields you don't need.
- Always have a selective `WHERE` (indexed field).
- For chronic non-selectivity on big objects, request Skinny Tables from Salesforce Support.
- For very large datasets, use Apex Cursors or Batch Apex; never query 50k records into a single synchronous `List`.

### ApexGuru

Use it. Scale Center → ApexGuru Insights surfaces real performance hotspots from runtime profiling. Review at least quarterly. The Code Analyzer integration brings it into VS Code. Edition gating: available on Performance and Unlimited editions, and on Enterprise with the Performance Monitoring add-on; not available on Developer or Professional editions.

---

## 11. Observability

Build a native logging layer using Platform Events + a custom log object. Platform Events publish **outside the calling transaction** — logs survive rollbacks, which is the only way to guarantee a log on uncaught exceptions in synchronous Apex.

`System.debug` is for debugging in non-prod orgs. Use `System.debug(LoggingLevel.ERROR, ...)` when you do, never the no-argument form. Production observability MUST go through Platform Events, not debug logs.

Monitor `AsyncApexJob` for batch/queueable failures. Use the new `System.purgeOldAsyncJobs(Integer)` overload (Spring '26) to incrementally purge old completed jobs by specifying an upper bound on records deleted per call.

> Full `Log__e` Platform Event definition, `Logger` class, and subscriber trigger persisting to `Application_Log__c`: see `references/observability-patterns.md`.

---

## 12. DataWeave in Apex

For JSON / XML / CSV transformations, prefer DataWeave over hand-written parsers.

```java
Dataweave.Script script = Dataweave.Script.createScript('csvToContacts');
Dataweave.Result result = script.execute(new Map<String, Object>{ 'payload' => csvString });
List<Contact> contacts = (List<Contact>) result.getValueAsList();
```

- Reuse the `Dataweave.Script` instance within a transaction — initialisation is CPU-expensive.
- For payloads >1 MB, chunk the input.
- Test with realistic data volumes; CPU consumption is non-trivial.

---

## 13. Class Design — Service / Selector / Domain

- **Trigger Handler** — orchestrates per-record and per-batch logic for a single SObject.
- **Service** — stateless static methods implementing business operations (`AccountService.recalculateScore(Set<Id>)`).
- **Selector / Gateway** — encapsulates ALL SOQL for a single SObject. No SOQL anywhere else.
- **Domain** (optional) — instance methods on a collection of records.
- **Wrapper / DTO** — `@AuraEnabled` data transfer types returned to LWCs.

This layering is what makes the codebase mockable via the Stub API.

> SOLID applied to this layering — SRP, OCP, LSP, ISP, and DIP with concrete Apex examples and the Stub-API wiring: see `references/solid-principles.md`. Apply SOLID before reaching for a named design pattern.

### `@AuraEnabled` signature rules

- `cacheable=true` for reads (enables LDS cache, forbids DML).
- No `cacheable` for writes.
- Primitive or DTO parameters; never raw `SObject` types.
- Always throw `AuraHandledException` on failure.

---

## 14. Decision Matrix — Quick Reference

| Need | Solution | Apex? |
|------|----------|-------|
| Display/edit one record with a form | `lightning-record-form` | NO |
| Read one record's fields | `getRecord` wire adapter | NO |
| Read related list records | `getRelatedListRecords` wire | NO |
| Query with filters/sort/pagination | GraphQL `@wire` | NO |
| Multi-record DML from LWC | GraphQL mutations | NO |
| Validation rule, formula, rollup | Standard config | NO |
| Record-triggered automation | Flow | NO |
| Cross-object aggregate + callout + DML | Apex with `@AuraEnabled` | YES |
| Process up to ~5M records with flexible chunking | Apex Cursors + Queueable | YES |
| Process >5M records or recurring scheduled volume jobs | Batch Apex | YES |
| Scheduled job | Schedulable → Queueable | YES |
| Post-job retry/logging/callout-after-DML | Queueable + Finalizer | YES |
| Trigger automation on SObject | Tony Scott framework | YES |
| Dynamic SOQL with user input | `Database.queryWithBinds` + `USER_MODE` | YES |
| Static configuration | Custom Metadata Type | NO |
| Hot reusable data | Platform Cache | YES (caller) |
| JSON/CSV/XML transformation | DataWeave in Apex | YES |
| Read-only data for LWC | `@AuraEnabled(cacheable=true)` | YES |

---

## 15. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| `public class Foo` (no sharing keyword) | `public with sharing class Foo` |
| `[SELECT ... FROM ...]` without `WITH USER_MODE` | `WITH USER_MODE` |
| `insert records;` | `Database.insert(records, AccessLevel.USER_MODE)` |
| `Database.query('SELECT ... ' + userInput)` | `Database.queryWithBinds(q, binds, USER_MODE)` |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` (removed in API 67+ — does NOT compile) |
| Manual `isAccessible()` checks | `WITH USER_MODE` / `Security.stripInaccessible` |
| `with sharing` declared on a trigger | Move it to the handler class — illegal on triggers in API 67+ |
| API version < 67.0 on new classes | `<apiVersion>67.0</apiVersion>` in the `*-meta.xml` |
| String concatenation across multiple lines (`'a' + '\n' + 'b'`) | Multiline literal `'''…'''` (API 67+) |
| `String.format(tmpl, new String[]{...})` for interpolation | `'''Hello ${name}'''.template(new Map<String,Object>{...})` |
| SOQL inside a `for` loop | Bulk query before the loop, `Map<Id, SObject>` lookup |
| DML inside a `for` loop | Collect into a `List`, single DML after the loop |
| `@future` for new async work | `Queueable` (+ Finalizer if needed) |
| Logic in the trigger file | One-line delegation to `TriggerFactory` |
| Multiple triggers per object | One trigger, one handler (Tony Scott by default on greenfield) |
| Trigger with no per-object bypass | Per-object hierarchical kill-switch (`Trigger_Settings__c`, `<Object>_Trigger_Enabled__c`) at entry |
| SOQL/DML in `beforeX`/`afterX` iterative methods | Cache in `bulkBefore`/`bulkAfter`, DML in `andFinally` |
| `System.assertEquals(...)` | `Assert.areEqual(...)` |
| `@IsTest(SeeAllData=true)` | `@TestSetup` + `TestDataFactory` |
| Hard-coded Ids in tests | Query by `DeveloperName` / `Name` |
| `catch (Exception e) { }` (swallow) | Log + rethrow as a domain exception |
| Returning raw stack traces to LWC | Throw `AuraHandledException` with a clean message |
| `'Account'` / `'Account.Name'` strings | `Account.SObjectType` / `Account.Name` |
| Custom Settings for global config | Custom Metadata Types (`__mdt`) |
| Repeated SOQL for static data | Platform Cache (Org / Session) |
| Querying every field with `*` selector | Project only needed fields |
| Business logic in `Schedulable.execute` | `Schedulable.execute` enqueues a `Queueable` |
| `if/else` chain on a single variable | `switch on` |
| Verbose null checks | `?.` and `??` |
| `Trigger.isBefore && Trigger.isInsert` | `Trigger.operationType == BEFORE_INSERT` |
| Hand-rolled JSON parsing for complex payloads | `Dataweave.Script` |
| 1-record bulk tests | 200-record bulk tests (always) |
| `System.debug('msg')` in production code | Platform Events → `Application_Log__c` |
| Apex when LDS/GraphQL/Flow would suffice | The right declarative tool (see §14) |

---

## Summary — The Five Commandments

1. **`with sharing` + `USER_MODE` are the defaults**, always explicit, never bypassed without comment.
2. **Bulkify everything** — assume 200 records, test with 200+.
3. **Triggers: one per object, zero logic in the file, behind a per-object hierarchical kill-switch.** Tony Scott (2013) is the default framework for greenfield orgs; in an existing org, conform to whatever framework is already there — ask first.
4. **Async means Queueable + Finalizer** (or Cursors + Queueable for big data); `@future` and most Batch Apex are legacy.
5. **Observability is native** — Platform Events for guaranteed logs, custom log object for persistence, Finalizers for async failure paths.
