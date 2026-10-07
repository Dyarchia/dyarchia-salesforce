---
name: dya-sf-integration-connectors-mcp
description: Salesforce connectors and agentic integration (Winter '27, API v68.0) — MuleSoft (Anypoint, for Flow, Direct, API Catalog), Heroku AppLink, AppExchange connectors, Data 360 zero-copy, hosted MCP servers, Agent API. Applies to MuleSoft flows and API specs, Heroku AppLink apps, hosted MCP server setup, Agent API clients. Load before creating or editing anything in this scope.
---

# Salesforce Connectors & Agentic Integration

Prebuilt connectors and middleware so you **do not hand-code** an integration, plus the 2026
agentic surfaces — MCP, Headless 360, Agent API: *when not to write Apex or Flow at all*. Data 360
internals are `dya-sf-data360`; MCP and HXL internals `dya-sf-headless360`; agent building
`dya-sf-agentforce`. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — release-coupled facts, including the security defaults an MCP-exposed action inherits.
- `references/connectors-and-mcp.md` — the MuleSoft family and API Catalog, when point-to-point Apex still fits, building and consuming MCP servers as an integration surface, and the zero-copy versus ingestion decision.

An MCP call sees what the calling user's permission model allows — `dya-sf-permissions`.

---

## Platform Context — Winter '27 / API v68.0

| Change | Status | What it gives you |
|---|---|---|
| **MCP interoperability for agents** | GA | An Agentforce agent can discover and call tools on *external* MCP servers through a governed connection — the opposite direction to everything below |
| **Expanded API Catalog capabilities** | GA | More of the API and MCP estate manageable from one hub |
| **Composite API monitoring** | GA | Visibility into previously opaque composite request behaviour |
| **Salesforce plugin for Claude Code** | GA | Detects a DX project and supplies org context through hosted MCP servers, from the Claude Plugin Marketplace. See `dya-sf-cli` and `dya-sf-headless360` |
| **DevOps Center MCP** | GA | The same programmatic access inside a CI/CD pipeline |

Standing facts:

- **Named Query API is GA** — custom SOQL exposed as a scalable REST or agent action.
- **Salesforce-to-Salesforce** ended support in Summer '26 and stops functioning in Spring '27 —
  migrate to MuleSoft, Data Cloud One, or the Cross-Org adapter.

## Summary — The Five Commandments

1. **Don't hand-code past one integration** — connectors/MuleSoft once it's multi-system or needs orchestration.
2. **Use MuleSoft for Flow for prebuilt SaaS**, Anypoint for real orchestration/transformation/API management.
3. **Move no data when none needs moving** — Data 360 zero-copy for analytics/grounding.
4. **Use MCP as the agentic integration surface** — custom servers expose your Apex actions/Flows/Named Queries; curate, describe, and run as a least-privilege user.
5. **Mind the retirements** — Salesforce Functions gone (→ Heroku/AppLink), Salesforce-to-Salesforce ending (→ Cross-Org/MuleSoft/Data Cloud One).

---

## 1. The First Question — Should You Code This At All?

```
How many systems / how much orchestration?
├─ One simple API, admin-owned ............... Flow HTTP Callout / External Services (-outbound)
├─ One bespoke endpoint/contract ............. Apex (-outbound / -inbound-apex)
├─ Several systems, transformation, routing .. MuleSoft (Anypoint / for Flow)
├─ Prebuilt SaaS connector exists ............ MuleSoft for Flow / Direct / AppExchange
├─ Analytics over external data, no ETL ...... Data 360 zero-copy (-data360)
└─ An AI agent/assistant is the caller ....... Hosted MCP server / Agent API
```

Move from point-to-point Apex callouts to **MuleSoft** at **more than one or two integrations**, or at
the first need for transformation, orchestration or queuing.

---

## 2. MuleSoft Family

| Product | What it is | Use |
|---|---|---|
| **Anypoint Platform** | Full enterprise iPaaS + API management + the API/MCP gateway of the ecosystem | Many systems, complex orchestration, API governance |
| **MuleSoft for Flow** | Low-code connectors invoked directly inside Flow (1500+ actions, 300+ triggers across 90+ connectors) | Admins wiring SaaS systems without Apex |
| **MuleSoft Direct** | Prebuilt industry-cloud connectors surfaced in Salesforce (e.g. FHIR for Health Cloud) | Industry-cloud data without integration projects |
| **API Catalog for Salesforce** | Central hub to manage APIs + MCP servers (MuleSoft/Heroku/Apex), convert ops to invocable actions for Flow, Apex and Agentforce | Discoverability + governance across surfaces |

Default to **MuleSoft for Flow** where a prebuilt connector exists and an admin owns the flow. Use
**Anypoint** for real orchestration, DataWeave transformation, API management, throttling, or a façade over many
backends.

---

## 3. Heroku / AppLink

The off-platform compute and integration tier. **AppLink** connects Heroku apps to Salesforce orgs
with user-permission enforcement and multi-org connectivity; it replaces **Salesforce Functions**,
retired 31 January 2025.

- Use it for elastic or custom compute, languages other than Apex, long-running jobs, and heavy data
  processing close to Salesforce.
- Confirm commercial fit before committing new strategic workloads: Heroku enterprise sales to new
  customers have ended.

---

## 4. Data 360 as an Integration Path

- **Zero-copy federation** — query external warehouses (Snowflake, Databricks, BigQuery, Redshift) in
  place via Apache Iceberg: no ETL, no duplication.
- **Ingestion API / connectors** — for data that must be resident in Data 360, streaming or batch.

Choose zero-copy for analytics and grounding that should not duplicate data; ingestion for
low-latency operational access to resident data. Pipeline mechanics, credits and zero-copy detail:
`dya-sf-data360`.

---

## 5. AppExchange / ISV Connectors

Check for a vetted managed-package connector before building, especially for common SaaS targets.
These are packaged AppExchange integrations, distributed via External Client Apps for 2GP. Govern an
installed connector's API usage and permissions.

---

## 6. MCP / Headless 360 / Agent API — the Agentic Surface

- **Hosted MCP Servers (GA)** — connect any external MCP client to standard tools over sObject
  operations, Data 360, Tableau and product APIs, out of the box.
- **Custom hosted MCP servers** — expose *your* chosen tools, built from **Apex actions
  (`@InvocableMethod`), Flows, Apex REST and Named Query APIs**. Curate the smallest approved
  toolset.
- **Agent API** — invoke an Agentforce agent headlessly from an external system (`dya-sf-agentforce`).
- Security: every MCP call runs **as the authenticated user** with CRUD, FLS and sharing enforced,
  auth is OAuth plus PKCE via an ECA (`dya-sf-integration-auth`), and calls count against the daily
  API allocation.

Choose MCP when the caller is an AI client that should discover and call capabilities dynamically.
MCP and HXL internals: `dya-sf-headless360`.

---

## 7. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| One simple API, no code | Flow HTTP Callout / External Services |
| One bespoke endpoint | Apex (`-inbound-apex` / `-outbound`) |
| Several systems / orchestration / transformation | MuleSoft Anypoint |
| Prebuilt SaaS connector in Flow | MuleSoft for Flow |
| Industry-cloud prebuilt data | MuleSoft Direct |
| Discover/govern APIs + MCP centrally | API Catalog for Salesforce |
| Elastic/custom off-platform compute | Heroku / AppLink |
| Analytics over external data, no copy | Data 360 zero-copy |
| Resident external data in Data 360 | Data 360 Ingestion API/connectors |
| Vetted packaged integration exists | AppExchange / ISV connector |
| AI client acts on the org | Hosted MCP server (custom for your tools) |
| An agent needs a capability that lives outside the org | MCP interoperability — connect the external server, do not rebuild the tool |
| Headless agent invocation | Agent API |
| Replace Salesforce-to-Salesforce | MuleSoft / Data Cloud One / Cross-Org adapter |

---

## 8. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Point-to-point Apex spider-web across many systems | MuleSoft middleware |
| Hand-coding a connector that already exists | MuleSoft for Flow / Direct / AppExchange |
| ETL-copying data only needed for analytics | Data 360 zero-copy federation |
| New build on Salesforce Functions | Heroku / AppLink |
| New build on native Salesforce-to-Salesforce | Cross-Org adapter / MuleSoft / Data Cloud One |
| Exposing the whole org as MCP tools | Curate a least-privilege toolset |
| Vague MCP tool descriptions | Intent-rich descriptions (the model routes on them) |
| Assuming MCP bypasses security | It runs as the user with CRUD/FLS/sharing |
| Rewriting an action as a separate MCP tool | Reuse the `@InvocableMethod` as both |
| Rebuilding an external capability inside the org for an agent | Connect its MCP server through a governed connection |
