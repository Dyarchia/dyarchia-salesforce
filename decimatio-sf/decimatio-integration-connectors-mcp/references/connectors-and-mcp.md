# Connectors, Middleware & MCP — Reference (Summer '26)

Load from `decimatio-integration-connectors-mcp` for the detail behind the "don't hand-code it" choices and the agentic surface. Data 360 internals → `decimatio-data360`; MCP/HXL internals → `decimatio-headless360`.

## MuleSoft — Which One

| Product | Owner | Sweet spot | Avoid for |
|---|---|---|---|
| **Anypoint Platform** | Integration devs | Orchestration, transformation (DataWeave), API management/gateway, many backends, queuing/retry | A single trivial callout |
| **MuleSoft for Flow** | Admins | Prebuilt SaaS connectors invoked in Flow (90+ connectors, 1500+ actions, 300+ triggers) | Complex multi-system orchestration |
| **MuleSoft Direct** | Admins | Industry-cloud prebuilt data (e.g. FHIR for Health Cloud) | Generic custom APIs |
| **API Catalog for Salesforce** | Architects | Central registry/governance of APIs + MCP servers; turn operations into invocable actions | Ad-hoc one-off calls |

Rule: a prebuilt connector + admin ownership → **MuleSoft for Flow**; genuine integration logic (transformation, orchestration, façade, throttling) → **Anypoint**.

## When Point-to-Point Apex Is Still Right

- Exactly one well-bounded integration, owned by developers.
- A bespoke transactional contract the standard APIs/connectors can't express.
- Tight latency where a middleware hop is unacceptable.

Past that, the cost of N point-to-point Apex callouts (coupling, retry, monitoring, secret sprawl) exceeds the cost of middleware. Move to MuleSoft.

## Heroku / AppLink

- **AppLink** links Heroku apps to Salesforce with user-permission enforcement and multi-org connectivity; it's the migration target for the **retired Salesforce Functions**.
- Use for elastic compute, non-Apex languages, long-running/heavy jobs near Salesforce.
- Commercial caveat: enterprise sales to new customers have ended — validate fit before strategic commitment.

## Data 360 — Zero-Copy vs Ingestion (integration lens)

| Choice | Use | Trade-off |
|---|---|---|
| **Zero-copy federation** (Iceberg: Snowflake/Databricks/BigQuery/Redshift) | Analytics/grounding over external data without duplicating | Query-time dependency on the source; query cost |
| **Ingestion** (Ingestion API / connectors) | Low-latency operational access to resident data | Storage + ingestion credits; copy to keep in sync |

Default to **zero-copy** when the need is analytical/grounding and the data shouldn't be duplicated. See `decimatio-data360` for credits and mechanics.

## MCP as an Integration Surface

### Server types (recap; full detail in `decimatio-headless360`)
- **Hosted MCP Servers (GA)** — standard out-of-the-box tools over Platform, Data 360, Tableau, product APIs.
- **Custom hosted MCP servers** — expose your chosen tools.
- **Salesforce DX MCP Server** — developer/IDE tooling, *not* a production business surface.

### Building custom MCP tools
A custom server can expose tools built from existing artefacts — reuse, don't rebuild:
- **Apex action** — an `@InvocableMethod` (the same one an agent uses).
- **Flow** — an autolaunched flow.
- **Apex REST** — a custom REST endpoint.
- **Named Query API** — custom SOQL exposed as a scalable action (GA Summer '26).

### Rules
- **Curate the smallest approved toolset.** A broad, vague tool list is a security and reliability liability (models mis-call).
- **Descriptions are routing logic** — write tool labels/descriptions as carefully as Agentforce action descriptions.
- **Security carries through** — every MCP call runs as the authenticated user with CRUD/FLS/sharing; auth is OAuth + PKCE via an ECA with `mcp_api`/`refresh_token` scopes (`decimatio-integration-auth`). MCP calls count against daily API limits.
- **When to choose MCP** — the *caller is an AI client* that should discover and compose capabilities at runtime, rather than a fixed integration you wrote in advance.

## Connecting an External AI Client (e.g. Claude)

1. Enable the relevant **hosted MCP server** (or stand up a **custom** one exposing only the tools you want).
2. Configure an **External Client App** with OAuth + PKCE and the `mcp_api` scope; the user/token's permissions bound what the tools can do.
3. Register the server in the client; it discovers tools (name + description + input schema), then calls them — running as that user.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| N point-to-point Apex integrations | MuleSoft middleware |
| Rebuilding an existing connector | MuleSoft for Flow / Direct / AppExchange |
| ETL for analytics-only external data | Data 360 zero-copy |
| New build on Salesforce Functions | Heroku / AppLink |
| Whole-org MCP exposure | Least-privilege, curated toolset |
| Separate code for the MCP tool vs the agent action | One `@InvocableMethod` for both |
| DX MCP server as a production business surface | Hosted/custom server for ops; DX for dev |
| Assuming MCP escapes sharing/FLS | It runs as the user with full enforcement |
