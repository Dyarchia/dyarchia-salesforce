---
name: dya-apex
description: Salesforce Apex Winter '27 (API v68.0) modern development best practices — syntax, security and user mode, SOQL/DML, triggers, async, testing, performance, observability, class design. Load only when the user explicitly invokes this skill by name (`dya-apex`); do NOT auto-trigger on generic Apex, Salesforce, or trigger-related questions.
---

# Salesforce Apex Modern Development

You **always** use the most modern syntax available, you **always** enforce user-mode security
explicitly, and you **always** bulkify. Follow every rule below.

References:

- `references/shared/` — the platform fundamentals every rule below rests on: `governor-limits.md`,
  `soql-selectivity.md`, `sharing-and-access.md`, `platform-deltas.md`,
  `metadata-and-api-versions.md`. **Start with the first if you do not already know why
  bulkification is mandatory — this skill's rules are unusable without it.**
- `references/modern-syntax.md` — every modern construct with the legacy form it replaces.
- `references/trigger-framework.md` — `ITrigger`, `TriggerFactory`, handler, recursion guard, `TriggerBypass`.
- `references/async-patterns.md` — Queueable, Finalizer, Cursor chain, Mixed-DML.
- `references/testing-patterns.md` — skeletons, Stub API wiring, `RunRelevantTests` semantics.
- `references/observability-patterns.md` — `Log__e`, `Logger`, subscriber trigger.
- `references/performance-and-caching.md` — Platform Cache, Custom Metadata, DataWeave, ApexGuru, heap.
- `references/static-analysis.md` — Code Analyzer: the seven engines, selectors, and the flags that fail silently.
- `references/solid-principles.md` — SOLID applied to Apex, with Stub-API injection.

Neighbouring skills own their own subjects: permissions and sharing design → `dya-permissions`;
declarative automation and invocable contracts → `dya-flow`; anything LWC-facing beyond the
`@AuraEnabled` contract → `dya-lwc`; callouts and integration patterns → `dya-integration-outbound`;
Platform Events as an integration surface → `dya-integration-events`.

---

## Platform Context — Winter '27 / API v68.0

Stamp new Apex at `<apiVersion>68.0</apiVersion>`. The number is per class, not per org — see
`references/shared/metadata-and-api-versions.md` for what that implies and for retirement status.

**The security defaults this skill assumes turned on at API 67.0 and still hold**: SOQL, SOSL and DML
default to `USER_MODE`; an omitted sharing keyword defaults to `with sharing`, and that default is
contagious down an inheritance chain and into `@AuraEnabled` methods; `WITH SECURITY_ENFORCED` no
longer compiles; a sharing keyword on a trigger no longer compiles. Full table in
`references/shared/platform-deltas.md`. Existing classes keep their old behaviour until you raise
their version, so make sharing explicit **before** you bump, never after.

What Winter '27 adds to Apex specifically:

| Change | Status | What it means for your code |
|---|---|---|
| Heap: 10 MB sync, 25 MB async | GA | Up from 6/12. An org setting can hold the old value during transition — do not assume the ceiling in code shipped to many orgs |
| Only invalid classes and triggers recompile on deploy | GA | Faster deploys in large orgs; no code change |
| `explicitNamespace` on `Database.QueryOptions` | GA | In a managed package, stops a subscriber's same-named field shadowing yours |
| Apex Symbol API (Tooling REST) | Beta | Compiler-grade type metadata for IDEs and AI tooling; not a runtime API |
| `@IntegrationTest` — real callouts in tests | Dev Preview | Async only, one concurrent test, **no automatic rollback** |
| `FORMULA()` in a SOQL `WHERE` clause | Beta | API 68.0+, **sandbox / Developer Edition / scratch orgs only** |
| Execute Data 360 SQL from Apex | GA | Query Data 360 alongside org data. See `dya-data360` |

Beta and Developer Preview features are **not available in production orgs**. Proposing one as the
default produces code that does not deploy.

---

## 1. Class Structure

State a sharing keyword on **every** class. Default `with sharing`. Use `without sharing` only for
system-level integration or admin tooling, with a class comment saying why. From 67.0 it suppresses
**record sharing only** — a query there still throws for a user lacking CRUD or FLS. Use
`inherited sharing` for utilities whose sharing must follow the caller.

```apex
// ✅
public with sharing class AccountService { }
public without sharing class IntegrationGateway { }   // only when justified, and say why
public inherited sharing class ReusableHelper { }

// ❌ — implicit, reader cannot tell the behaviour without knowing the API version
public class AccountService { }
```

`private` by default; `public` only when an external caller needs it; `global` only in managed
packages or web service interfaces, never for org-internal code.

## 2. Modern Syntax

Use `?.` and `??` over null-check ladders, `switch on` over `if/else` chains on one variable,
`Trigger.operationType` over `isBefore && isInsert`, multiline literals `'''…'''` and
`.template(Map<String, Object>)` over string concatenation, `Assert.*` over `System.assert*`, and
schema references over string literals for object and field names.

> Every construct with its legacy equivalent: `references/modern-syntax.md`.

## 3. Security — User Mode, Explicitly

`USER_MODE` enforces object permissions, field-level security and sharing for the running user. It is
the versioned default from 67.0; **write it out anyway**, so the reader knows the behaviour without
checking the file's API version and nothing changes silently on a legacy branch.

```apex
// ✅
List<Account> accts = [
    SELECT Id, Name, Industry FROM Account
    WHERE Industry = :industry WITH USER_MODE LIMIT 200
];
Database.SaveResult[] results = Database.insert(accounts, false, AccessLevel.USER_MODE);

// ❌ — removed at 67.0, does not compile
List<Account> accts = [SELECT Id, Name FROM Account WITH SECURITY_ENFORCED];
```

**System mode** is for code that must legitimately escape user constraints — an integration, or a
trigger writing an audit field the user cannot edit. Redesign first; if you keep it, say why:

```apex
// SYSTEM_MODE required: audit field, end users intentionally lack edit access.
Database.update(auditRecords, AccessLevel.SYSTEM_MODE);
```

Where a *partial* result is acceptable — typically an `@AuraEnabled` method serving users with
differing FLS — `Security.stripInaccessible(AccessType.READABLE, records)` removes the fields the
user cannot see instead of throwing.

> The model behind all of this — profiles, permission sets, OWD, sharing rules:
> `references/shared/sharing-and-access.md`. Design questions belong to `dya-permissions`.

## 4. SOQL

**Never query inside a loop.** Collect the keys, query once, look up from a `Map`:

```apex
Set<Id> accountIds = new Set<Id>();
for (Contact c : Trigger.new) { accountIds.add(c.AccountId); }
Map<Id, Account> byId = new Map<Id, Account>([
    SELECT Id, Name FROM Account WHERE Id IN :accountIds WITH USER_MODE
]);
for (Contact c : Trigger.new) { c.Description = byId.get(c.AccountId)?.Name; }
```

**Every query must be selective**: at least one filter on an indexed field, matching fewer rows than
that index's threshold — 30% of the first million for a standard index, 10% for a custom one. A
non-selective query fails on a large object with `QueryException: Non-selective query`, and it fails
in production long before it fails in a test org. `WHERE Industry = 'Tech'` is a table scan; an
unindexed picklist narrows nothing.

> Thresholds, what is indexed, what defeats an index, how to read a query plan: `references/shared/soql-selectivity.md`.

**Dynamic SOQL binds, never concatenates.** String concatenation is a SOQL injection vulnerability:

```apex
List<Account> accts = Database.queryWithBinds(
    'SELECT Id, Name FROM Account WHERE Industry = :industry AND AnnualRevenue > :minRev',
    new Map<String, Object>{ 'industry' => industryFilter, 'minRev' => 1000000 },
    AccessLevel.USER_MODE
);
```

Same for `Database.countQueryWithBinds` and `Database.getQueryLocatorWithBinds`. In dynamic SOQL the
access level is an argument; in static SOQL it is the inline `WITH USER_MODE` clause — not
interchangeable.

**For bulk reads, iterate the query** (`for (Account[] batch : [SELECT …])`) rather than
materialising it: the for-loop form chunks at 200 records and keeps heap flat.

**Apex Cursors** (GA since Spring '26) handle up to ~50M rows per cursor with flexible and
bidirectional chunking, bounded by **10 `fetch()` calls per transaction**, 10k cursors/day and 100M
rows/day. Use them where Batch Apex's fixed forward chunking does not fit.

> Cursor + Queueable chain: `references/async-patterns.md`.

## 5. DML

**Never DML inside a loop.** Collect into a `List`, one statement after the loop.

Prefer `Database.insert/update/delete/upsert` over bare DML: it gives partial success, an explicit
access level, and a structured `SaveResult[]` you can act on.

```apex
Database.SaveResult[] results = Database.insert(records, false, AccessLevel.USER_MODE);
```

When `allOrNone = false`, walking `results` and logging every `getErrors()` entry against its record
is not optional — silent partial failure is the failure mode this API exists to expose.

**Upsert on an external id for idempotency**, so a replayed message does not duplicate:

```apex
Database.upsert(records, Account.External_Id__c, false, AccessLevel.USER_MODE);
```

**You cannot call out after uncommitted DML in the same transaction.** Either call out first and then
do DML, or move the callout into a Queueable (preferred), or into a Transaction Finalizer.

## 6. Triggers

On **greenfield** orgs the default is the Tony Scott "Trigger Pattern for Tidy, Streamlined,
Bulkified Triggers": one trigger per object, zero logic in the file, canonical execution order through
an `ITrigger` interface, bulk caching in `bulkBefore`/`bulkAfter`, per-record work in the iterative
methods, post-processing in `andFinally`.

On **brownfield** orgs — anything already standardised on Kevin O'Hara, fflib, Trigger Actions or a
hand-rolled handler — do not impose it. **Ask which framework the org uses and conform.** Org-wide
consistency beats a better framework bolted onto a different one.

```apex
// The trigger file - one line, no logic, no sharing keyword.
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    TriggerFactory.createAndExecuteHandler(AccountHandler.class);
}
```

Triggers always run in **system mode**, on every API version, and a sharing keyword on a trigger is a
compile error from 67.0. The sharing keyword goes on the handler class; if trigger-driven DML must
enforce user-level security, pass `AccessLevel.USER_MODE` explicitly to the `Database.*` call.

### The per-object kill-switch

Every trigger must be silenceable without a deployment, **per object** — you may need an integration
or agent user to skip the Account trigger while the Case trigger keeps running.

Model it as one **Hierarchy** Custom Setting resolved at trigger entry. This is the one case where a
Custom Setting beats a Custom Metadata Type: hierarchy resolution (org → profile → user) is exactly
what a per-user bypass needs, and `__mdt` cannot express it. It is a circuit breaker, not a recursion
guard — keep the framework's recursion handling regardless.

> The setting's shape and field naming, `TriggerBypass`, entry-point wiring, and the form for a
> non-framework trigger: `references/trigger-framework.md`.

### Absolute rules

- One trigger per object. Order between multiple triggers on one object is undefined.
- No logic in the trigger file.
- No SOQL or DML in the iterative `beforeX`/`afterX` methods — cache in `bulkBefore`/`bulkAfter`, DML in `andFinally`.
- Field-value validation goes in `after` methods; before-triggers and workflows can still change values.
- All SOQL is delegated to a Selector/Gateway class.
- For callouts caused by DML, enqueue **one** Queueable in `andFinally` with the whole batch — never `@future` per record.
- Every trigger checks its kill-switch at entry.

## 7. Async — The Decision Tree

Stop at the first option that fits.

1. **Queueable** — the default. Accepts complex types, chainable, monitored, supports Finalizers.
2. **Queueable + Transaction Finalizer** — when post-job logic must run whatever happens: retry, logging, callout-after-DML.
3. **Apex Cursors + Queueable chain** — large volumes needing flexible or bidirectional chunking. Bounded by 10 `fetch()` per transaction.
4. **Batch Apex** — very large volumes, recurring scheduled jobs, or parallel chunk execution.
   Still the right answer for those; it is not legacy.
5. **Schedulable** — only to trigger work on a Cron schedule. Its `execute` enqueues a Queueable; business logic never lives there.
6. **`@future`** — avoid in new code. No return value, no chaining, no monitoring, no Finalizers.

> Full implementations and the Mixed-DML pattern (setup and non-setup objects cannot be committed
> in one transaction): `references/async-patterns.md`.

## 8. Testing

- `@TestSetup` for shared data; each test method gets a fresh rolled-back copy.
- **Test in bulk.** Every bulk-callable class needs a test with 200+ records: that is what the
  platform will send, and a one-record test proves nothing about limits.
- Wrap the act in `Test.startTest()` / `Test.stopTest()`: fresh limits, and async work is forced to complete.
- Never make a real callout: `Test.setMock(HttpCalloutMock.class, …)`. Use the Stub API
  (`Test.createStub`) for unit tests with mocked selectors.
- Centralise record creation in an `@IsTest` `TestDataFactory`. Never `@IsTest(SeeAllData=true)`,
  never a hard-coded Id — query by `DeveloperName` or `Name`.
- Run security-sensitive tests under `System.runAs(nonAdminUser)`. Testing only as an admin proves nothing about user mode.
- Assert a meaningful business outcome, with a message. Coverage without assertions is worthless.

75% aggregate coverage is a **production deployment gate**, not a quality bar. Target full coverage
of meaningful branches.

`@IsTest(critical=true)` and `@IsTest(testFor='…')` (Beta, API 66.0+) narrow what runs under
`sf project deploy start --test-level RunRelevantTests`. Until they are GA, verify production-critical
tests with a broader test level.

> Skeletons, Stub API wiring, full annotation semantics: `references/testing-patterns.md`.

## 9. Error Handling

Declare a custom exception per domain — `InvoiceGenerationException`, not `Exception`. It lets a
caller catch what it can actually handle.

Log and rethrow; never swallow:

```apex
// ✅
try {
    return parse(http.send(req));
} catch (CalloutException e) {
    Logger.error('Pricing engine callout failed', e);
    throw new PricingEngineUnreachableException('Pricing unavailable', e);
}

// ❌
try { } catch (Exception e) { }
```

`@AuraEnabled` methods throw **`AuraHandledException`** with a clean message. Any other exception
sends an internal stack trace to the browser.

## 10. Performance

Assume 200 records and test with 200+. Beyond that, the levers are: Platform Cache for hot reference
data, Custom Metadata Types for configuration (`getInstance` costs no SOQL), DataWeave for structured
payload transformation, ApexGuru for finding real hotspots from runtime profiling, and heap
discipline — project only the fields you use, iterate rather than materialise.

> Cache partitions and their setup prerequisite, DataWeave, ApexGuru edition gating, heap rules: `references/performance-and-caching.md`.

## 11. Observability

Production logging goes through **Platform Events**, not debug logs. They publish outside the calling
transaction, so a log survives a rollback — the only way to guarantee a record of an uncaught
exception in synchronous Apex. `System.debug` is a non-production tool; when you use it, pass a level.

Monitor `AsyncApexJob` for Queueable and Batch failures. `System.purgeOldAsyncJobs(Integer)` bounds
how many records a call deletes, so old jobs can be purged incrementally.

> `Log__e` definition, `Logger` class, subscriber trigger persisting to `Application_Log__c`: `references/observability-patterns.md`.

## 12. Class Design

- **Trigger Handler** — per-record and per-batch orchestration for one SObject.
- **Service** — stateless static methods implementing a business operation.
- **Selector / Gateway** — owns *all* SOQL for one SObject. No SOQL anywhere else.
- **Domain** (optional) — instance behaviour over a collection of records.
- **Wrapper / DTO** — the `@AuraEnabled` types returned to a client.

This layering is what makes the code mockable through the Stub API.

The `@AuraEnabled` contract: `cacheable=true` for reads (enables the Lightning Data Service cache,
forbids DML, must be `static`); no `cacheable` for writes; primitive or DTO parameters, never raw
`SObject`; always throw `AuraHandledException` on failure.

> SOLID applied to this layering, with Stub-API injection: `references/solid-principles.md`.
> Apply SOLID before reaching for a named design pattern.

## 13. Decision Matrix — Is This Even Apex?

The best Apex is the Apex you did not write. Reach for it only when the declarative surface cannot
express the requirement.

| Need | Solution | Apex? |
|---|---|---|
| Record-triggered automation | Flow — see `dya-flow` | NO |
| Reading or writing records from a component | Lightning Data Service or GraphQL — see `dya-lwc` | NO |
| Static configuration | Custom Metadata Type | NO |
| Cross-object aggregate plus a callout plus DML | Apex service, `@AuraEnabled` if UI-facing | YES |
| Very large volumes with flexible chunking | Apex Cursors + Queueable | YES |
| Very large volumes, recurring, or parallel chunks | Batch Apex | YES |
| Guaranteed post-job retry or logging | Queueable + Finalizer | YES |
| Dynamic query built from user input | `Database.queryWithBinds` + `USER_MODE` | YES |

## 14. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct approach |
|---|---|
| `public class Foo` with no sharing keyword | State `with sharing` (or the deliberate alternative) |
| SOQL or DML without an explicit access level | `WITH USER_MODE` / `AccessLevel.USER_MODE` |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` — the old form does not compile from 67.0 |
| `Database.query('… ' + userInput)` | `Database.queryWithBinds(q, binds, USER_MODE)` |
| A query with no indexed, selective filter | Filter on an indexed field within its threshold |
| SOQL or DML inside a loop | Query once into a `Map`; collect and DML once after |
| Callout after uncommitted DML in the same transaction | Callout first, or move it into a Queueable or Finalizer |
| Ignoring `SaveResult[]` when `allOrNone = false` | Inspect every result and log the failures |
| Logic in the trigger file, or several triggers per object | One trigger, one handler, one line of delegation |
| `@future` for new async work | Queueable, plus a Finalizer where needed |
| `System.debug` as production observability | Platform Events into a log object |
| A Beta or Developer Preview feature in production code | The GA path; the preview belongs in a scratch org |
| Apex where configuration, Flow or LDS would do | The declarative tool — see §13 |

## Summary — The Five Commandments

1. **Security is explicit.** `with sharing` and `USER_MODE` written out, every time; system mode only with a comment saying why.
2. **Bulkify everything.** Assume 200 records, test with 200+, and know the limits in `references/shared/governor-limits.md` that make it mandatory.
3. **Triggers: one per object, zero logic in the file, behind a per-object kill-switch.** Tony Scott by default on greenfield; in an existing org, conform to what is already there — ask first.
4. **Async means Queueable plus a Finalizer**; Cursors for flexible chunking, Batch Apex for very large or parallel work. `@future` is the only legacy one.
5. **Observability is native.** Platform Events for logs that survive a rollback, a custom log object for persistence, Finalizers for the async failure path.
