# Connectors, Middleware & MCP — Reference (Winter '27 / API v68.0)

Detail behind `dya-sf-integration-connectors-mcp`'s choices.

## MuleSoft — Which One

| Product | Owner | Sweet spot | Avoid for |
|---|---|---|---|
| **Anypoint Platform** | Integration devs | Orchestration, transformation (DataWeave), API management/gateway, many backends, queuing/retry | A single trivial callout |
| **MuleSoft for Flow** | Admins | Prebuilt SaaS connectors invoked in Flow (90+ connectors, 1500+ actions, 300+ triggers) | Complex multi-system orchestration |
| **MuleSoft Direct** | Admins | Industry-cloud prebuilt data (e.g. FHIR for Health Cloud) | Generic custom APIs |
| **API Catalog for Salesforce** | Architects | Central registry/governance of APIs + MCP servers; turn operations into invocable actions | Ad-hoc one-off calls |

## When Point-to-Point Apex Is Still Right

- Exactly one well-bounded integration, owned by developers.
- A bespoke transactional contract the standard APIs/connectors can't express.
- Tight latency where a middleware hop is unacceptable.

Past that, N point-to-point Apex callouts cost more than middleware in coupling, retry, monitoring and secret sprawl.

## Data 360 — Zero-Copy vs Ingestion (integration lens)

| Choice | Use | Trade-off |
|---|---|---|
| **Zero-copy federation** (Iceberg: Snowflake/Databricks/BigQuery/Redshift) | Analytics/grounding over external data without duplicating | Query-time dependency on the source; query cost |
| **Ingestion** (Ingestion API / connectors) | Low-latency operational access to resident data | Storage + ingestion credits; copy to keep in sync |

## MCP as an Integration Surface

The **Salesforce DX MCP Server** is developer/IDE tooling, *not* a production business surface.

### Building custom MCP tools
A custom server reuses existing artefacts as tools:
- **Apex action** — an `@InvocableMethod` (the same one an agent uses).
- **Flow** — an autolaunched flow.
- **Apex REST** — a custom REST endpoint.
- **Named Query API** — custom SOQL exposed as a scalable action (GA).

### Rules
- **Curate the smallest approved toolset.** A broad, vague tool list is a security and reliability liability (models mis-call).
- **Descriptions are routing logic** — write tool labels/descriptions as carefully as Agentforce action descriptions.
- **OAuth scopes** — the ECA needs `mcp_api` and `refresh_token`.

## Connecting an External AI Client (e.g. Claude)

1. Enable the relevant **hosted MCP server** (or a **custom** one exposing only the tools you want).
2. Configure an **External Client App** with OAuth + PKCE and the `mcp_api` scope; the user/token's permissions bound what the tools can do.
3. Register the server in the client; it discovers tools (name + description + input schema) and calls them as that user.
