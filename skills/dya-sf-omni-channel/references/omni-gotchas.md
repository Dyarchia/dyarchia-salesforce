# Where Omni-Channel Deploys and Queries Fail

Almost every wasted hour here is one of two things: a read path that works for one type and not its
neighbour, or an element name that changed while older documentation still shows the old one.

## The read-path asymmetry

**`ServiceChannel`'s `Metadata` field is not queryable through Tooling SOQL.**

```sql
SELECT Id, Metadata FROM ServiceChannel          -- INVALID_FIELD
SELECT Id, CapacityWeight FROM ServiceChannel    -- INVALID_FIELD
```

`GET /tooling/sobjects/ServiceChannel/<id>` returns `{ "Metadata": null }` — a successful, empty
response, worse than an error because the channel looks unconfigured.

**`WorkSkillRouting` does expose a queryable `Metadata` field.** Adjacent types in one feature
behave differently, so a helper written against one and reused for the other silently returns empty.

To read a `ServiceChannel`'s configuration, retrieve the metadata:

```bash
sf project retrieve start --metadata "ServiceChannel:Cases" --target-org <alias>
```

## The v66 renames

Several `ServiceChannel` elements were renamed. The old names persist in documentation and
well-ranked StackExchange answers, and a deploy using them fails on a field that "obviously exists":

| Before | Now |
|---|---|
| `masterLabel` | **`label`** |
| `relatedEntity` | **`relatedEntityType`** |
| `capacityWeight` | **`capacityModel`** (`TAB_BASED` \| `STATUS_BASED`) |
| `isCustomerVisible` | *removed* |

The `capacityWeight` change has a design consequence, not only a mechanical one: it was **replaced**,
not moved. The capacity model now expresses the per-item cost, and the **per-agent total lives on
`PresenceUserConfig.Capacity`**. Looking for an agent's capacity on the channel is looking at the
wrong object, not an older field name.

## `enableOmniChannel` gates everything

With the setting off, every downstream metadata type rejects with **`INVALID_TYPE`** naming the type
you were deploying. The error never mentions the setting, so it reads as a malformed or
unsupported-in-this-org type.

Deploy `Settings:OmniChannel` on its own first, confirm it, then deploy the rest. Bundling them into
one deploy does not reliably order them.

## `enableOmniAutoLoginPrompt` deploys and does nothing

It accepts a value and round-trips through retrieve unchanged, but **does not drive the corresponding
UI radio**: documented, deployable, currently inert. Do not spend an afternoon on it.

## The queue that accepts nothing

A `Group` with `Type = 'Queue'` and no `QueueSobject` row for the entity being routed is a valid,
deployable, completely inert queue. Work never arrives and nothing errors.

When a specific queue is not receiving, check `QueueSobject` first.

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
