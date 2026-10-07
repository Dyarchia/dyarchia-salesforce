# Platform Cache, DataWeave and Profiling — Reference (Winter '27 / API v68.0)

## Platform Cache

Caching trades a SOQL query for a lookup that costs no governor limit. It is **best-effort storage** —
the platform may evict anything at any time — so never the system of record, and every read must
handle a miss.

| Partition | Scope | Use for | Max TTL |
|---|---|---|---|
| Org Cache | Every user in the org | Currency rates, configuration tables, reference data | 48 h (default 24 h) |
| Session Cache | One user's session | Auth tokens, user preferences, wizard state | 8 h |

**A partition must exist first.** Create it under Setup › Platform Cache and allocate capacity; the
`local.` prefix is the namespace of an unmanaged org. `Cache.Org.getPartition` on a missing partition
throws `Cache.Org.OrgCacheException` at runtime — a fresh org has no partitions and no allocation.

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

- Individual items are capped at **100 KB**. Cache one collection rather than a hundred small keys.
- Code that assumes a cache hit fails intermittently in production and never in a test.
- Do not cache user-specific data in the Org partition; it is shared across every user.
- Session Cache is empty for guest users and for any API-only integration user.

## Configuration data: Custom Metadata over Custom Settings

`MyConfig__mdt.getInstance('Name')` reads from the platform cache with **no SOQL query**, and the
records deploy and package like other metadata, so Custom Metadata Types are the default for
configuration.

Custom Settings are correct only for **hierarchy resolution** — a value set at org level and
overridden per profile or user — as in the trigger kill-switch (`references/trigger-framework.md`).

## DataWeave in Apex

For JSON, XML and CSV transformation, DataWeave replaces hand-written parsers and the untyped
`JSON.deserializeUntyped` map-walking that follows them.

```apex
Dataweave.Script script = Dataweave.Script.createScript('csvToContacts');
Dataweave.Result result = script.execute(new Map<String, Object>{ 'payload' => csvString });
List<Contact> contacts = (List<Contact>) result.getValueAsList();
```

- `createScript` is CPU-expensive. Create the script once and reuse it for every row in the
  transaction.
- Chunk inputs above roughly 1 MB — a single large payload hits heap before CPU.
- Test with realistic volumes; DataWeave CPU cost does not show at 10 rows.

## ApexGuru

Scale Center › ApexGuru Insights profiles runtime behaviour in the org, surfaces hotspots static
analysis cannot see, and detects duplicate and near-duplicate code. It integrates with
VS Code, Cursor and Agentforce Vibes through Code Analyzer.

Check the edition before recommending it: available on Performance and Unlimited, and on
Enterprise with the Performance Monitoring add-on; not on Developer or Professional.

Review the insights at least quarterly, not only when something is already slow.

## Heap discipline

- Every extra projected field is heap on every row.
- `clear()` large collections once done with them inside a long transaction.
- Past roughly 50,000 rows, stop fitting it in one transaction: Apex Cursors or Batch Apex.

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
