# OmniStudio — Integration Procedures & Data Mappers

Load from `decimatio-omnistudio`. Server-side orchestration (IPs), data shaping (Data Mappers), and invoking them from code. Standard (`omnistudio`) and Managed Package (`vlocity_*`) differ in namespace — confirm the org's flavor.

## Integration Procedures (IPs)

A declarative, **server-side** process that runs **multiple actions in a single server call** — the controller behind OmniScripts/FlexCards and a reusable orchestration unit. Build in the Integration Procedure Designer; reference by **Type_SubType**.

### Common actions
- **DataRaptor Extract / Load / Transform** — read/write/reshape Salesforce data.
- **HTTP Action** — external callout.
- **Remote Action** — call Apex (`Callable` / `VlocityOpenInterface2`).
- **Set Values / Response Action** — build/shape the response JSON.
- **Conditional Block / Loop Block** — branching/iteration.
- **Integration Procedure Action** — call another IP (compose).

### Invoke modes
- **Non-blocking** runs the IP while the OmniScript continues; the response returns when done — you must map the **Response JSON Node / Path** or default-value elements won't receive it.
- **Blocking** waits.
- **Chainable / Queueable Chainable** for long-running work (async).

### Caching
Mind the `VlocityMetadata` / API-response cache partitions for read-heavy IPs; activate/version IPs deliberately.

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

Use this to reuse an IP's orchestration from server code. For long-running IPs, configure Chainable/Queueable Chainable and invoke accordingly.

## Invoking from LWC / REST

- **LWC** — call an IP via the OmniStudio LWC APIs / wire, or through an `@AuraEnabled` Apex method that calls `runIntegrationService`.
- **REST / Connect API** — expose an IP as an API-callable endpoint for external systems (a high-performance, declarative alternative to hand-written Apex REST for transformation/orchestration at scale). Authenticate with OAuth (`decimatio-integration-auth`).

## Data Mappers (DataRaptors)

| Type | Direction | Use |
|---|---|---|
| **Extract** | SF → JSON | Read records (multi-object) into a structured response |
| **Transform** | JSON → JSON | Reshape/merge without DML |
| **Load** | JSON → SF | Insert/update records (DML) |
| **Turbo Extract** | SF → JSON | High-performance single-object read |

Prefer Data Mappers for standard read/transform/write inside IPs; reserve Apex Remote Actions for logic they can't express. Keep mappings field-precise (don't over-extract).

## Choosing IP vs Apex vs Flow (orchestration)

| Situation | Use |
|---|---|
| High-volume transformation/orchestration, reusable | Integration Procedure |
| Maximum control, complex transactional logic | Apex (REST) |
| Simple admin-owned automation | Flow |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Per-element server calls from an OmniScript | One IP bundling the actions |
| Apex for standard read/transform/write | Data Mappers |
| Over-extracting whole objects | Field-precise Data Mapper |
| Ignoring non-blocking response mapping | Map Response JSON Node/Path |
| Wrong namespace for `IntegrationProcedureService` | `omnistudio` (Standard) vs `vlocity_*` (Managed) |
| Unbounded loops/extracts in an IP | Bound and bulk-shape the data |
| Long-running IP run synchronously | Chainable / Queueable Chainable |
