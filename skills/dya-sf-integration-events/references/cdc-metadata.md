# CDC and Managed Subscriptions — the Metadata

Configure Change Data Capture and durable subscriptions entirely through metadata. On a failure,
check naming and element names first; almost every failure is one of those, not a permissions or
logic problem.

Both types have a floor of API 60.0.

## Enabling CDC on an entity

### The only two valid types

`PlatformEventChannelMember` (one per subscribed entity) and `PlatformEventChannel` (custom channels
only). There is no `EnableChangeDataCapture` type either. `ManagedEventSubscription` is a real type
but a different feature — see below.

```xml
<!-- force-app/main/default/platformEventChannelMembers/Order_ChangeEvent.platformEventChannelMember-meta.xml -->
<PlatformEventChannelMember xmlns="http://soap.sforce.com/2006/04/metadata">
    <eventChannel>ChangeEvents</eventChannel>
    <selectedEntity>Order__ChangeEvent</selectedEntity>
</PlatformEventChannelMember>
```

### The underscore rule

| Source object | `<selectedEntity>` | Filename |
|---|---|---|
| `Account` | `AccountChangeEvent` | `AccountChangeEvent.platformEventChannelMember-meta.xml` |
| `Order__c` | `Order__ChangeEvent` (double) | `Order_ChangeEvent…` (**single**) |

### The element inventory

`PlatformEventChannelMember` accepts **exactly four** elements. Anything else — `<description>`,
`<isActive>`, `<masterLabel>` — fails schema validation:

```text
enrichedFields · eventChannel · filterExpression · selectedEntity
```

`PlatformEventChannel` accepts **exactly two** — `<label>`, not `<masterLabel>`:

```text
channelType · label
```

### Custom channels

DeveloperName is CamelCase plus the literal suffix **`__chn`** — "Partner Sync" becomes
`PartnerSync__chn`, filed as `PartnerSync__chn.platformEventChannel-meta.xml`. The XML **must**
carry `<channelType>data</channelType>` or the channel is rejected for CDC use.

### Enrichment fields

Use `<enrichedFields>` to give a downstream consumer a foreign key to route on; it adds fields to
every change event for the entity, changed or not.

List only **single-hop API names on the source entity**: `OwnerId`, `ParentId`, `MyLookup__c`,
`Region__c` all validate. Relationship traversal does not — `Owner.Name` and
`Parent.Account.Industry` are rejected with "The selected field, X.Y, isn't valid".

Compound fields use the **flat** name here (`BillingCity`), the opposite of the filter expression
below.

### Filter expressions

Write `<filterExpression>` as a `WHERE` clause **body with the `WHERE` keyword omitted** — including
it gives "unexpected token: 'WHERE'".

- No `IsDeleted`.
- No relationship traversal.
- **The right-hand side must be a literal.** `BillingCity = ShippingCity` is invalid.
- **DateTime fields support only `=` and `!=`.** Use a named date literal: `LastModifiedDate = TODAY`.
- Compound fields use the **dotted** form: `BillingAddress.City = 'X'`. The flat `BillingCity` is
  rejected. This is the inverse of `<enrichedFields>`.

### Deploy behaviour

- Deploying the same member twice returns `DUPLICATE_VALUE`. **CDC does not support upsert on
  members** — retrieve and diff rather than redeploying blindly.
- Deploy a custom object and its member in one transaction, or sequence them; the object's
  ChangeEvent entity does not exist until the object does.

## Durable subscriptions — `ManagedEventSubscription`

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

Use `topicName` and `state`; **`eventChannel` and `isActive`** do not exist here.

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

**`topicName` is immutable after creation.** Changing it means deleting and recreating the
subscription, which discards the stored replay position, so the replacement starts from
`defaultReplay`.

### Consuming it

`ManagedSubscribe` identifies the subscription by `DeveloperName` or record Id. Surrounding flow:
`references/pubsub-api.md`.

### Operational facts before the first run

- **`ManagedEventSubscription` is queryable only through the Tooling API.** Standard SOQL returns
  `INVALID_TYPE`:

  ```bash
  sf data query --use-tooling-api \
      --query "SELECT Id, DeveloperName FROM ManagedEventSubscription WHERE DeveloperName='OrderSync'"
  ```

- **The Pub/Sub API can take around two minutes to see a create, update or delete.** On a
  `NOT_FOUND` from `ManagedSubscribe` right after a deploy, wait and retry; it is not a failed deploy.
- **`EARLIEST` on a busy channel replays up to the full 72-hour retention window on activation:**
  three days of backlog, delivered as fast as the consumer accepts it. Size the consumer for that,
  or start at `LATEST` and backfill deliberately.
- Avoid reusing a DeveloperName after deleting a subscription; the replay position does not come
  back with the name.
