# Platform Cache, DataWeave and Profiling — Reference (Winter '27 / API v68.0)

Load from `dya-apex` when you are about to cache data, transform a structured payload, or chase a
performance problem. These are consulted rather than obeyed: none of them apply on every invocation.

## Platform Cache

Caching trades a SOQL query for a lookup that costs no governor limit. It is **best-effort storage** —
the platform may evict anything at any time — so it is never the system of record and every read must
handle a miss.

| Partition | Scope | Use for | Max TTL |
|---|---|---|---|
| Org Cache | Every user in the org | Currency rates, configuration tables, reference data | 48 h (default 24 h) |
| Session Cache | One user's session | Auth tokens, user preferences, wizard state | 8 h |

**A partition must exist before any of this compiles usefully.** Create it under Setup › Platform
Cache and allocate capacity to it; the `local.` prefix is the namespace of an unmanaged org. Calling
`Cache.Org.getPartition` for a partition that does not exist throws
`Cache.Org.OrgCacheException` at runtime — a fresh org has no partitions and no allocation.

```apex
public with sharing class FxRateService {
    private static final String PARTITION = 'local.AppCache';

    public static Decimal getRate(String currencyIso) {
        Cache.OrgPartition part = Cache.Org.getPartition(PARTITION);
        Decimal rate = (Decimal) part.get(currencyIso);
        if (rate == null) {                                    // always handle the miss
            rate = [SELECT Rate__c FROM Fx_Rate__mdt WHERE DeveloperName = :currencyIso LIMIT 1]?.Rate__c;
            part.put(currencyIso, rate, 3600);                 // 1 h TTL
        }
        return rate;
    }
}
```

Rules that matter in practice:

- Individual items are capped at **100 KB**. Cache one collection rather than a hundred small keys.
- A cache miss is normal, not exceptional. Code that assumes a hit will fail intermittently in
  production and never in a test.
- Do not cache user-specific data in the Org partition. It is shared across every user in the org.
- Session Cache is empty for guest users and for any API-only integration user.

## Configuration data: Custom Metadata over Custom Settings

`MyConfig__mdt.getInstance('Name')` reads from the platform cache and costs **no SOQL query**, and
the records are deployable and packageable like any other metadata. That makes Custom Metadata Types
the default home for configuration.

Custom Settings remain correct for one thing Custom Metadata cannot express: **hierarchy resolution**,
where a value is set at org level and overridden per profile or per user. The trigger kill-switch in
`references/trigger-framework.md` is exactly that case.

## DataWeave in Apex

For JSON, XML and CSV transformation, DataWeave replaces hand-written parsers and the untyped
`JSON.deserializeUntyped` map-walking that usually follows them.

```apex
Dataweave.Script script = Dataweave.Script.createScript('csvToContacts');
Dataweave.Result result = script.execute(new Map<String, Object>{ 'payload' => csvString });
List<Contact> contacts = (List<Contact>) result.getValueAsList();
```

- `createScript` is CPU-expensive. Create the script once and reuse the instance for every row within
  the transaction.
- Chunk inputs above roughly 1 MB — a single large payload will hit heap before it hits CPU.
- Test with realistic volumes. DataWeave CPU cost is not negligible and does not show up at 10 rows.

## ApexGuru

Scale Center › ApexGuru Insights profiles actual runtime behaviour in the org and surfaces hotspots
that static analysis cannot see, plus duplicate and near-duplicate code detection. It integrates with
VS Code, Cursor and Agentforce Vibes through Code Analyzer.

Edition gating matters before you recommend it: available on Performance and Unlimited, and on
Enterprise with the Performance Monitoring add-on. Not available on Developer or Professional.

Review the insights at least quarterly rather than only when something is already slow.

## Heap discipline

- Iterate a query directly (`for (Account[] batch : [SELECT …])`) instead of materialising the whole
  result into a `List`. The for-loop form chunks at 200 records and keeps heap flat.
- Project only the fields you use. Every extra field is heap on every row.
- `clear()` large collections once you are done with them inside a long transaction.
- Past roughly 50,000 rows, stop trying to fit it in one transaction: Apex Cursors or Batch Apex.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Treating Platform Cache as durable storage | Best-effort; always handle a miss |
| Caching per-user data in the Org partition | Session partition, or key by user id deliberately |
| Many small cache keys | One cached collection under one key |
| Repeated SOQL for static reference data | Custom Metadata (`getInstance`, no SOQL cost) or Platform Cache |
| Custom Settings for global configuration | Custom Metadata Types — unless you need hierarchy overrides |
| `JSON.deserializeUntyped` plus manual map walking | `Dataweave.Script` |
| Re-creating a `Dataweave.Script` per row | Create once, reuse within the transaction |
| Querying 50,000 rows into one synchronous `List` | SOQL for-loop, Apex Cursors, or Batch Apex |
