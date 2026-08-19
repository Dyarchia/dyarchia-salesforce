# Flow HTTP Callout, External Services & Salesforce Connect — Reference (API v67.0)

Load from `dya-integration-outbound` for the no-code/declarative outbound paths and data virtualization. All paths use Named Credentials (`dya-integration-auth`).

## Flow HTTP Callout (No-Code)

Declarative outbound HTTP from Flow Builder. Behind the scenes it creates an External Service + an invocable action. Requires the **Customize Application** permission and a **Named Credential**.

Setup flow:
1. In Flow Builder add an **HTTP Callout** action; choose/create the Named Credential for the base URL.
2. Define the method (**GET/POST/PUT/PATCH/DELETE**, all GA), path, query params, and headers.
3. Provide a **sample response** — Salesforce infers the response structure into Apex-defined types you can reference downstream.
4. Map inputs from Flow variables; consume the parsed response in later elements.

Critical limitations:
- **Only 2xx responses are auto-parsed.** For 4xx/5xx you must define the error response structure and branch with a **Decision** element on the HTTP status — otherwise failures are swallowed or fault the Flow.
- Subject to the same platform callout governor limits as Apex (100/transaction, 120 s, 6/12 MB) — **not adjustable** from Flow.
- No built-in retry/backoff — add fault paths, or drop to Apex when you need resilient retry.

Use it for: simple, well-described REST APIs that an admin should own end-to-end. Drop to Apex (`apex-callouts-async.md`) when you need retry, complex transformation, large/streamed payloads, or callout-after-DML orchestration.

## External Services

Register an API by its **OpenAPI / JSON schema**; Salesforce generates **invocable actions** and **Apex-defined types** usable in Flow and Apex without hand-written callout code.

Setup:
1. Create the Named Credential for the API base URL.
2. Register an External Service, supplying the OpenAPI schema (or a URL to it).
3. Salesforce generates invocable actions per operation; use them in Flow or call from Apex.

Best for: a third-party API with a clean OpenAPI spec you want to reuse declaratively across many Flows. The generated actions inherit the bound Named Credential's auth.

## Outbound Messages (Legacy)

Workflow/flow-triggered **SOAP** messages to a fixed endpoint with **guaranteed delivery** and automatic retry (acknowledge within 24 h, extendable to 7 days).

- **Legacy** and tied to workflow rules (being retired toward Flow). Avoid for new builds.
- Migration: **Platform Events** (modern, decoupled, replayable) for fire-and-forget notification, or **Flow HTTP Callout** for a REST push with logic.
- Where it still shines: legacy middleware that already consumes the Outbound Message SOAP envelope and needs guaranteed-delivery semantics you haven't yet re-platformed.

## Salesforce Connect / External Objects (Data Virtualization)

Surface external data as **External Objects** (`__x`) without copying it; each read is a live callout at access time.

Adapters:
- **OData 2.0 / 4.0** — for systems exposing an OData producer. **OData 4.01** removes the legacy 20,000-callouts/hour cap (effectively unlimited rows); incremental syncs supported.
- **Cross-Org** — Salesforce-to-Salesforce over REST (a successor path for the retiring native Salesforce-to-Salesforce feature).
- **Apex Custom Adapter** (Apex Connector Framework) — implement `DataSource.Connection` / `DataSource.Provider` to virtualize *any* REST API as External Objects.

Use when: large external datasets must *appear* as Salesforce records (related lists, lookups, reports) but must not be stored. Supports external lookups and indirect lookups to relate external rows to standard records.

Avoid when: write-heavy, low-latency-critical, or high-frequency access — every access is a synchronous callout.

```apex
// Apex custom adapter skeleton (virtualize any REST API)
global class MyExternalDataSourceProvider extends DataSource.Provider {
    override global List<DataSource.AuthenticationCapability> getAuthenticationCapabilities() { ... }
    override global List<DataSource.Capability> getCapabilities() { ... }
    override global DataSource.Connection getConnection(DataSource.ConnectionParams p) {
        return new MyConnection(p);
    }
}
```

## Choosing Among These

| Need | Use |
|---|---|
| Simple sync REST call an admin owns | Flow HTTP Callout |
| Declarative reuse of an OpenAPI API across Flows | External Services |
| Legacy guaranteed-delivery SOAP push (existing) | Outbound Messages |
| External data as live records, no copy | Salesforce Connect |
| Virtualize an arbitrary REST API as records | Salesforce Connect + Apex adapter |
| Retry/backoff, transformation, big payloads | Apex callout (`apex-callouts-async.md`) |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Assuming a non-2xx was handled in Flow | Define error schema + Decision on status |
| New Outbound Message | Platform Event / Flow HTTP Callout |
| Salesforce Connect for write-heavy/low-latency | Replicate via Bulk/events instead |
| Hand-coding callouts for a clean OpenAPI API | External Services |
| Hard-coded base URL in Flow | Named Credential |
| Expecting retry from Flow HTTP Callout | Fault paths, or Apex for resilient retry |
