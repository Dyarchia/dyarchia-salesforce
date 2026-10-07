# Where Omni-Channel Deploys and Queries Fail

## The read-path asymmetry

**`ServiceChannel`'s `Metadata` field is not queryable through Tooling SOQL.**

```sql
SELECT Id, Metadata FROM ServiceChannel          -- INVALID_FIELD
SELECT Id, CapacityWeight FROM ServiceChannel    -- INVALID_FIELD
```

`GET /tooling/sobjects/ServiceChannel/<id>` returns `{ "Metadata": null }`: a success that makes
the channel look unconfigured.

**`WorkSkillRouting` does expose a queryable `Metadata` field**, so a helper written for one type and
reused for the other silently returns empty.

To read a `ServiceChannel`'s configuration, retrieve the metadata:

```bash
sf project retrieve start --metadata "ServiceChannel:Cases" --target-org <alias>
```

## The v66 renames

The old `ServiceChannel` element names persist in documentation and StackExchange answers; a deploy
using them fails.

| Before | Now |
|---|---|
| `masterLabel` | **`label`** |
| `relatedEntity` | **`relatedEntityType`** |
| `capacityWeight` | **`capacityModel`** (`TAB_BASED` \| `STATUS_BASED`) |
| `isCustomerVisible` | *removed* |

## `enableOmniChannel` gates everything

Deploy `Settings:OmniChannel` on its own first; bundling it with the rest into one deploy does not
reliably order them.

## The queue that accepts nothing

A `Group` with `Type = 'Queue'` and no `QueueSobject` row for the routed entity deploys, receives
nothing and raises no error. When a specific queue is not receiving, check `QueueSobject` first.

## Diagnosis order

```text
1. Settings:OmniChannel     is enableOmniChannel actually on?
2. ServiceChannel           does one exist for this sObject type?
3. QueueSobject             does the queue accept this sObject?
4. QueueRoutingConfig       does the queue have one at all?
5. ServicePresenceStatus    is any agent in a status that accepts this channel?
6. PresenceUserConfig       is anyone under their capacity?
7. PendingServiceRouting    a backlog here means 1-6 are fine and nobody is free
```
