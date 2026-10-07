# OmniStudio — Integration Procedures & Data Mappers

Load from `dya-sf-omnistudio`.

## Integration Procedures (IPs)

Build in the Integration Procedure Designer; reference by **Type_SubType**.

### Common actions
- **DataRaptor Extract / Load / Transform** — read/write/reshape Salesforce data.
- **HTTP Action** — external callout.
- **Remote Action** — call Apex (`Callable` / `VlocityOpenInterface2`).
- **Set Values / Response Action** — build/shape the response JSON.
- **Conditional Block / Loop Block** — branching/iteration.
- **Integration Procedure Action** — call another IP (compose).

### Invoke modes
- **Non-blocking** runs the IP while the OmniScript continues; the response returns when done — map the **Response JSON Node / Path** or default-value elements won't receive it.
- **Blocking** waits.
- **Chainable / Queueable Chainable** for long-running work (async).

### Caching
Mind the `VlocityMetadata` / API-response cache partitions for read-heavy IPs; activate/version IPs deliberately.

## `PropertySetConfig` — Element Keys

An IP element is configured through a `PropertySetConfig` JSON block; knowing its keys lets you read
or generate an IP rather than click one.

| Element | Keys |
|---|---|
| DataRaptor Extract / Load / Transform | `bundle`, `additionalInput`, `additionalOutput`, `sendOnlyAdditionalInput`, `responseJSONPath`, `responseJSONNode`, `disableFlushCacheForGet`, `useQueueableApexRemoting` |
| Remote Action | `remoteClass`, `remoteMethod`, the above, plus `useQueueableApexRemoting` and `useFuture` |
| Integration Procedure Action | `ipMethod` (the nested IP's `Type_SubType`), `chainable`, `sendOnlyAdditionalInput` |

### Reading another element's output

**Merge syntax `%ElementName:fieldName%`** passes data between steps:

```json
{ "AccountId": "%GetAccountDetails:Id%" }
```

Each element's output is stored in the IP response **under the element's own name**
(`{"GetAccountDetails": { … }}`), so renaming an element breaks every downstream reference to it.

`sendOnlyAdditionalInput: true` suppresses the accumulated data context and sends only what
`additionalInput` declares. Use it when an element should not see upstream data, for payload size and
least privilege.

### The two async flags

- **`useQueueableApexRemoting`** runs the Remote Action as a Queueable; the IP continues and the
  result is available.
- **`useFuture`** runs it as a `@future` method, which **returns no value**: the element cannot
  contribute to the response, and anything downstream reading its output gets nothing.

When the whole IP is long-running, use `chainable` on an Integration Procedure Action rather than
making individual elements async and losing their outputs.

## Invoking an IP from Apex

```apex
// OmniStudio Standard
Map<String, Object> output = (Map<String, Object>) omnistudio.IntegrationProcedureService
    .runIntegrationService(
        'myType_mySubType',                                   // IP Type_SubType
        new Map<String, Object>{ 'accountId' => acctId },     // input
        new Map<String, Object>());                           // options

// Managed Package equivalent: vlocity_cmt.IntegrationProcedureService.runIntegrationService(...)
```

## Invoking from LWC / REST

- **LWC** — call an IP via the OmniStudio LWC APIs / wire, or through an `@AuraEnabled` Apex method that calls `runIntegrationService`.
- **REST / Connect API** — expose an IP as an API-callable endpoint for external systems (a declarative, high-performance alternative to hand-written Apex REST for orchestration at scale). Authenticate with OAuth (`dya-sf-integration-auth`).

## Data Mappers (DataRaptors)

| Type | Direction | Use |
|---|---|---|
| **Extract** | SF → JSON | Read records (multi-object) into a structured response |
| **Transform** | JSON → JSON | Reshape/merge without DML |
| **Load** | JSON → SF | Insert/update records (DML) |
| **Turbo Extract** | SF → JSON | High-performance single-object read |

Keep mappings field-precise; do not over-extract.

## Choosing IP vs Apex vs Flow (orchestration)

| Situation | Use |
|---|---|
| High-volume transformation/orchestration, reusable | Integration Procedure |
| Maximum control, complex transactional logic | Apex (REST) |
| Simple admin-owned automation | Flow |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Over-extracting whole objects | Field-precise Data Mapper |
| Ignoring non-blocking response mapping | Map Response JSON Node/Path |
| Wrong namespace for `IntegrationProcedureService` | `omnistudio` (Standard) vs `vlocity_*` (Managed) |
| Unbounded loops/extracts in an IP | Bound and bulk-shape the data |
| Long-running IP run synchronously | Chainable / Queueable Chainable |
