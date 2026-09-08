# Where Omni-Channel Deploys and Queries Fail

Two categories, and almost every wasted hour in this area is one of them: a read path that works for
one type and not its neighbour, and an element name that changed while the old one still appears in
older documentation.

## The read-path asymmetry

**`ServiceChannel`'s `Metadata` field is not queryable through Tooling SOQL.**

```sql
SELECT Id, Metadata FROM ServiceChannel          -- INVALID_FIELD
SELECT Id, CapacityWeight FROM ServiceChannel    -- INVALID_FIELD
```

`GET /tooling/sobjects/ServiceChannel/<id>` returns `{ "Metadata": null }` — a successful response
carrying nothing, which is worse than an error because it looks like the channel is unconfigured.

**`WorkSkillRouting` does expose a queryable `Metadata` field.** Two adjacent types in the same
feature behave differently, so a helper written against one and reused for the other silently returns
empty.

To read a `ServiceChannel`'s configuration, retrieve the metadata:

```bash
sf project retrieve start --metadata "ServiceChannel:Cases" --target-org <alias>
```

## The v66 renames

Several `ServiceChannel` elements changed name. The old ones appear in documentation and in
StackExchange answers that still rank well, and a deploy using them fails on a field that "obviously
exists":

| Before | Now |
|---|---|
| `masterLabel` | **`label`** |
| `relatedEntity` | **`relatedEntityType`** |
| `capacityWeight` | **`capacityModel`** (`TAB_BASED` \| `STATUS_BASED`) |
| `isCustomerVisible` | *removed* |

The `capacityWeight` change is the one with a design consequence rather than a mechanical one. It did
not move — it was **replaced**. The per-item cost is now expressed through the capacity model, and
the **per-agent total lives on `PresenceUserConfig.Capacity`**. Code or documentation looking for an
agent's capacity on the channel is looking at the wrong object, not an older field name.

## `enableOmniChannel` gates everything

With the setting off, every downstream metadata type rejects with **`INVALID_TYPE`** naming the type
you were deploying. The error never mentions the setting, so it reads as a malformed or
unsupported-in-this-org type.

Deploy `Settings:OmniChannel` on its own first, confirm it, then deploy the rest. Bundling them into
one deploy does not reliably order them.

## `enableOmniAutoLoginPrompt` deploys and does nothing

It accepts a value, round-trips through retrieve unchanged, and **does not drive the corresponding
UI radio**. It is documented, it is deployable, and it is currently inert. Do not spend an afternoon
on it.

## The queue that accepts nothing

A `Group` with `Type = 'Queue'` and no `QueueSobject` row for the entity being routed is a valid,
deployable, completely inert queue. Work never arrives and nothing errors.

Check `QueueSobject` before checking anything else when a specific queue is the one not receiving.

## Diagnosis order

When work is not routing, walk the chain rather than sampling it:

```text
1. Settings:OmniChannel     is enableOmniChannel actually on?
2. ServiceChannel           does one exist for this sObject type?
3. QueueSobject             does the queue accept this sObject?
4. QueueRoutingConfig       does the queue have one at all?
5. ServicePresenceStatus    is any agent in a status that accepts this channel?
6. PresenceUserConfig       is anyone under their capacity?
7. PendingServiceRouting    a backlog here means 1-6 are fine and nobody is free
```

Reaching step 7 with records waiting is the good outcome: configuration is correct and the answer is
staffing or capacity, not metadata.
