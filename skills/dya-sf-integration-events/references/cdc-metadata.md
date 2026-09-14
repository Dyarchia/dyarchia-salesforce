# CDC and Managed Subscriptions — the Metadata

Change Data Capture and durable subscriptions are configured entirely through metadata, and almost
every failure at this layer is a naming or element-name mistake rather than a permissions or logic
problem. This file is the element inventory and the error-to-cause map.

Both types have a floor of API 60.0, so nothing here is gated above our target.

## Enabling CDC on an entity

### The only two valid types

`PlatformEventChannelMember` (one per subscribed entity) and `PlatformEventChannel` (custom channels
only). Everything else that sounds right is not a thing: there is no `ChangeDataCapture` metadata
type, no `.changeDataCapture-meta.xml`, no `changeDataCapture/` source directory, no
`EnableChangeDataCapture`. `ManagedEventSubscription` is a real type but a different feature — see
below.

```xml
<!-- force-app/main/default/platformEventChannelMembers/Order_ChangeEvent.platformEventChannelMember-meta.xml -->
<PlatformEventChannelMember xmlns="http://soap.sforce.com/2006/04/metadata">
    <eventChannel>ChangeEvents</eventChannel>
    <selectedEntity>Order__ChangeEvent</selectedEntity>
</PlatformEventChannelMember>
```

### The underscore rule

The two names disagree, and both are correct:

| Source object | `<selectedEntity>` | Filename |
|---|---|---|
| `Account` | `AccountChangeEvent` | `AccountChangeEvent.platformEventChannelMember-meta.xml` |
| `Order__c` | `Order__ChangeEvent` (double) | `Order_ChangeEvent…` (**single**) |

A double-underscore filename is parsed as `<namespace>__<name>` and rejected with "Cannot create a
new component with the namespace: Order". Passing the plain source object in `<selectedEntity>`
fails with "references an invalid event in the selectedEntity field".

### The element inventory

`PlatformEventChannelMember` accepts **exactly four** elements. Anything else — `<description>`,
`<isActive>`, `<masterLabel>` — fails schema validation:

```text
enrichedFields · eventChannel · filterExpression · selectedEntity
```

`PlatformEventChannel` accepts **exactly two**, and note it is `<label>`, not `<masterLabel>`:

```text
channelType · label
```

### Custom channels

DeveloperName is CamelCase plus the literal suffix **`__chn`** — "Partner Sync" becomes
`PartnerSync__chn`, filed as `PartnerSync__chn.platformEventChannel-meta.xml`. The XML **must**
carry `<channelType>data</channelType>` or the channel is rejected for CDC use.

Never author a channel file for the default `ChangeEvents` channel; it is system-provided.

### Enrichment fields

`<enrichedFields>` adds fields to every change event for the entity, whether or not they changed —
which is how a downstream consumer gets a foreign key it needs to route on.

They must be **single-hop API names on the source entity**: `OwnerId`, `ParentId`, `MyLookup__c`,
`Region__c` all validate. Relationship traversal does not — `Owner.Name` and
`Parent.Account.Industry` are rejected with "The selected field, X.Y, isn't valid".

Compound fields use the **flat** name here (`BillingCity`), which is the opposite of the filter
expression below. That inversion is not a typo in either place.

### Filter expressions

`<filterExpression>` is a `WHERE` clause **body with the `WHERE` keyword omitted** — including it
gives "unexpected token: 'WHERE'".

Constraints:

- No `IsDeleted`.
- No relationship traversal.
- **The right-hand side must be a literal.** `BillingCity = ShippingCity` is not valid; you cannot
  compare two fields.
- **DateTime fields support only `=` and `!=`.** Use a named date literal —
  `LastModifiedDate = TODAY` — rather than reaching for `<` or `>`.
- Compound fields use the **dotted** form: `BillingAddress.City = 'X'`. The flat `BillingCity` is
  rejected. This is the inverse of `<enrichedFields>`.

### Deploy behaviour

- Deploying the same member twice returns `DUPLICATE_VALUE`. **CDC does not support upsert on
  members** — retrieve and diff rather than redeploying blindly.
- A custom object's ChangeEvent entity does not exist until the object does. Deploy both in one
  transaction, or sequence them.

## Durable subscriptions — `ManagedEventSubscription`

This is the platform's answer to "store the last processed replay id and resume from it". The
subscription records the position; the consumer stops owning that state.

```xml
<!-- force-app/main/default/managedEventSubscriptions/OrderSync.managedEventSubscription-meta.xml -->
<ManagedEventSubscription xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Order Sync</label>
    <topicName>/data/Order__ChangeEvent</topicName>
    <defaultReplay>LATEST</defaultReplay>
    <errorRecoveryReplay>EARLIEST</errorRecoveryReplay>
    <state>RUN</state>
    <version>68.0</version>
</ManagedEventSubscription>
```

**All six elements are required** — omitting any one fails the deploy. Do not include
`<namespacePrefix>`, `<id>` or `<createdDate>`; they are read-only.

Two field names people reach for that do not exist here: **`eventChannel` and `isActive`**. The
correct names are `topicName` and `state`.

### Values

- `defaultReplay` and `errorRecoveryReplay`: `LATEST` or `EARLIEST`.
- `state`: `RUN` or `STOP`. **`PAUSE` is reserved for internal platform use** and is rejected with
  `INVALID_INPUT: You can create a managed event subscription state field only to RUN or STOP`.

### `topicName` formats

The prefix is mandatory — omitting it gives "The topicName field is invalid":

```text
/event/<Name>__e                event: a custom platform event
/event/<Name>__chn              event: a custom event channel
/data/ChangeEvents              data:  the default CDC channel, all subscribed entities
/data/<Object>ChangeEvent       data:  one standard entity's change events
/data/<Name>__chn               data:  a custom CDC channel
```

**`topicName` is immutable after creation.** Changing it means deleting the subscription and
creating a new one — which discards the stored replay position, so the replacement starts from
`defaultReplay`. Plan that, rather than discovering it during a rename.

### Consuming it

The Pub/Sub API subscribes through the **`ManagedSubscribe`** RPC rather than `Subscribe`,
identifying the subscription by `DeveloperName` or record Id. See `references/pubsub-api.md` for the
surrounding flow.

### Operational facts worth knowing before the first run

- **`ManagedEventSubscription` is queryable only through the Tooling API.** Standard SOQL returns
  `INVALID_TYPE`:

  ```bash
  sf data query --use-tooling-api \
      --query "SELECT Id, DeveloperName FROM ManagedEventSubscription WHERE DeveloperName='OrderSync'"
  ```

- **The Pub/Sub API can take around two minutes to see a create, update or delete.** A `NOT_FOUND`
  from `ManagedSubscribe` immediately after a deploy means wait and retry, not that the deploy
  failed.
- **`EARLIEST` on a busy channel replays up to the full 72-hour retention window on activation.**
  That is the abstract retention figure made concrete: a subscription switched on with `EARLIEST`
  against a high-volume channel will deliver three days of backlog as fast as the consumer accepts
  it. Size the consumer for that, or start at `LATEST` and backfill deliberately.
- Avoid reusing a DeveloperName after deleting a subscription; the replay position does not come
  back with the name.
