# Data 360 Query & Access — Reference Implementation (Summer '26)

Full implementations referenced from SKILL.md §5. Load this when reading Data 360 data programmatically. Three methods exist; choose by where the logic runs. Every method consumes Data Services credits, so query hygiene (§ "Rules") is mandatory.

## Method 1 — SOQL on DMOs From Apex

Best when the logic is on-platform (an Agentforce Apex action, platform-event subscriber, controller). DMO API names end in `__dlm`; DLOs in `__dll`.

```java
public with sharing class LoyaltyService {
    // Static SOQL against a DMO. USER_MODE under API 67. Consumes credits.
    public static List<UnifiedIndividual__dlm> goldMembers(String region) {
        return [
            SELECT Id, FirstName__c, LastName__c, LoyaltyPoints__c
            FROM UnifiedIndividual__dlm
            WHERE LoyaltyTier__c = 'Gold' AND Region__c = :region
            WITH USER_MODE
            ORDER BY LoyaltyPoints__c DESC
            LIMIT 200
        ];
    }
}
```

Notes and limits:
- Static SOQL on DMOs is supported as a direct alternative to dynamic SOQL / ConnectApi.
- `Database.QueryLocator` and SOQL FOR loops are supported in API 61.0+; below that only the first ~201 records return.
- Batch Apex via `QueryLocator` is **blocked** against DMOs — use `Iterable` instead.
- **DLO queries require a `DATASPACE` clause** at the very end; omit it and the query returns zero rows:
  ```
  SELECT ... FROM MyRaw__dll WHERE ... DATASPACE default
  ```
- Be cautious with FOR loops, query locators, and recursion — each can fan out into multiple billable Data 360 queries.

## Method 2 — Query API (Data 360 SQL)

Best for analytical SQL: cross-object joins, aggregates, windowing. Uses Connect REST endpoints (and Apex). Asynchronous + synchronous responses; paginate and reuse the cached result.

```sql
-- ANSI SQL against modeled data. Fictional API names — replace with yours.
SELECT CustomerId__c,
       COUNT(*)            AS OrderCount,
       SUM(OrderAmount__c) AS LifetimeOrderValue
FROM   WebOrder__dlm
WHERE  OrderDate__c >= DATE '2026-01-01'
GROUP  BY CustomerId__c
ORDER  BY LifetimeOrderValue DESC
LIMIT  100;
```

Execution pattern:
1. `createSqlQuery` → submit the SQL, get a query id.
2. `getSqlQueryRows` with `offset` + `rowLimit` → page through results.
3. You can re-read those results for **24 hours without extra consumption** — `getSqlQueryRows` is faster and cheaper than re-running `createSqlQuery`.

Performance/cost rules:
- Filter early with `WHERE`; never `SELECT *`.
- Use the DMO's primary index (or a secondary index) in the predicate.
- Include **key qualifier fields** in joins — null key qualifiers mean the join silently degrades.
- Handle both async and sync responses in your client.

## Method 3 — Connect API in Apex (`ConnectApi`)

Best for object-oriented operations from on-platform code: profiles, calculated insights, segments, metadata. The Apex `ConnectApi` namespace exposes a subset of the Connect REST API.

```java
// Illustrative shape — consult the ConnectApi Data 360 classes for exact method names.
ConnectApi.CdpQueryInput query = new ConnectApi.CdpQueryInput();
query.sql = 'SELECT Id__c FROM UnifiedIndividual__dlm LIMIT 50';
ConnectApi.CdpQueryOutputV2 result = ConnectApi.CdpQuery.queryANSISql(query);
```

Use Connect REST API (off-platform) or `ConnectApi` (on-platform) for managing CIs/segments/identity rulesets programmatically; use the Query API for raw analytical SQL; use SOQL for simple on-platform reads.

## Choosing — Decision Table

| Situation | Method |
|---|---|
| Simple DMO read inside Apex | SOQL on `__dlm` |
| Raw DLO read inside Apex | SOQL + `DATASPACE` clause |
| Joins / aggregates / analytics | Query API (SQL) |
| Manage CIs, segments, rulesets | Connect API (REST or `ConnectApi`) |
| Full related-entity profile, low latency | Data Graph API |
| Large result set | Query API + paginated `getSqlQueryRows` |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Query with no `WHERE`/`LIMIT` | Always selective predicate + limit |
| `SELECT *` | Project only needed columns |
| DLO query without `DATASPACE` | Append the `DATASPACE` clause |
| `Database.QueryLocator` Batch over a DMO | Use `Iterable` |
| Re-running `createSqlQuery` for the same data | Page the 24h-cached result via `getSqlQueryRows` |
| Joins without key qualifiers | Configure key qualifier fields |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` |
| SOQL FOR loop fanning out billable queries | Bulk, bounded queries; mind consumption |
