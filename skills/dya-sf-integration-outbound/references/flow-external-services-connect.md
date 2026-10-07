# Flow HTTP Callout, External Services & Salesforce Connect — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-outbound`. All paths use Named Credentials (`dya-sf-integration-auth`).

## Flow HTTP Callout (No-Code)

Setup:
1. In Flow Builder add an **HTTP Callout** action; choose/create the Named Credential for the base URL.
2. Define the method, path, query params and headers.
3. Provide a **sample response** — Salesforce infers its structure into Apex-defined types referenceable downstream.
4. Map inputs from Flow variables; consume the parsed response in later elements.

Limitations:
- Without an error schema and a **Decision** on the HTTP status, a 4xx/5xx is swallowed or faults the Flow.
- No built-in retry/backoff — add fault paths, or drop to Apex.

Also drop to Apex (`apex-callouts-async.md`) for callout-after-DML orchestration.

## External Services

Setup:
1. Create the Named Credential for the API base URL.
2. Register an External Service, supplying the OpenAPI schema (or a URL to it).
3. Salesforce generates invocable actions per operation; use them in Flow or call from Apex.

## Outbound Messages (Legacy)

- Migration: **Platform Events** (decoupled, replayable) for fire-and-forget notification, or **Flow HTTP Callout** for a REST push with logic.
- Still fits: legacy middleware that already consumes the Outbound Message SOAP envelope and needs guaranteed-delivery semantics not yet re-platformed.

## Salesforce Connect / External Objects (Data Virtualization)

External Objects carry the `__x` suffix.

Adapters:
- **OData 2.0 / 4.0** — for systems exposing an OData producer. Without the 20,000-callouts/hour cap, **OData 4.01** allows effectively unlimited rows.
- **Cross-Org** — Salesforce-to-Salesforce over REST, succeeding the retiring native Salesforce-to-Salesforce feature.
- **Apex Custom Adapter** — implement `DataSource.Connection` / `DataSource.Provider`.

External objects appear in related lists, lookups and reports; external and indirect lookups relate external rows to standard records. Avoid them for high-frequency access too.

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

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Hand-coding callouts for a clean OpenAPI API | External Services |
| Hard-coded base URL in Flow | Named Credential |
| Expecting retry from Flow HTTP Callout | Fault paths, or Apex for resilient retry |
