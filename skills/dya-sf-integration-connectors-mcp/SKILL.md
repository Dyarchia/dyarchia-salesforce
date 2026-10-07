---
name: dya-sf-integration-connectors-mcp
description: Salesforce connectors & agentic integration (Winter '27 / API v68.0) — the "don't hand-code it" layer plus the 2026 agentic surface. MuleSoft (Anypoint, for Flow, Direct, API Catalog), Heroku/AppLink, AppExchange/ISV connectors, Data 360 ingestion/zero-copy as an integration path, and Hosted MCP servers / Headless 360 / Agent API. Applies to MuleSoft flows and API specs, Heroku AppLink apps, hosted MCP server setup, Agent API clients. Load before creating or editing anything in this scope, or when the user invokes this skill by name (`dya-sf-integration-connectors-mcp`).
---

# Salesforce Connectors & Agentic Integration

The higher-level integration layer: prebuilt connectors and middleware so you **do not hand-code**
an integration, plus the 2026 agentic surfaces — MCP, Headless 360, Agent API. It decides *when not
to write Apex or Flow at all*. Data 360 internals are `dya-sf-data360`; MCP and HXL internals
`dya-sf-headless360`; agent building `dya-sf-agentforce`. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — release-coupled facts, including the security defaults an MCP-exposed action inherits.
- `references/connectors-and-mcp.md` — the MuleSoft family and API Catalog, Heroku and AppLink, building and consuming MCP servers as an integration surface, and the zero-copy versus ingestion decision.

An MCP call sees what the calling user's permission model allows — `dya-sf-permissions`.

---

## Platform Context — Winter '27 / API v68.0

| Change | Status | What it gives you |
|---|---|---|
| **MCP interoperability for agents** | GA | An Agentforce agent can discover and call tools on *external* MCP servers through a governed connection — the opposite direction to everything below, turning third-party capability into agent capability |
| **Expanded API Catalog capabilities** | GA | More of the API and MCP estate manageable from one hub |
| **Composite API monitoring** | GA | Visibility into previously opaque composite request behaviour |
| **Salesforce plugin for Claude Code** | GA | Detects a DX project and supplies org context through hosted MCP servers, from the Claude Plugin Marketplace. See `dya-sf-cli` and `dya-sf-headless360` |
| **DevOps Center MCP** | GA | The same programmatic access inside a CI/CD pipeline |

Standing facts:

- **Hosted MCP servers are GA.** Salesforce-hosted servers expose sObject operations, Data 360,
  Tableau and product APIs to any MCP client. Every MCP transaction runs **as the authenticated
  user**, with object, field and sharing enforcement intact, and every call counts against the
  daily API allocation.
- **API Catalog for Salesforce** is the central hub for APIs and MCP servers across MuleSoft, Heroku
  and Apex; it converts API operations into invocable actions for Flow, Apex and Agentforce.
- **Named Query API is GA** — custom SOQL exposed as a scalable REST or agent action.
- **Salesforce Functions is retired** (end of life 31 January 2025); migrate compute to Heroku via
  AppLink. Salesforce has ended Heroku enterprise sales to new customers; confirm commercial fit
  before committing a new strategic workload.
- **Salesforce-to-Salesforce** ended support in Summer '26 and stops functioning in Spring '27 —
  migrate to MuleSoft, Data Cloud One, or the Cross-Org adapter.

---

## 1. The First Question — Should You Code This At All?

Hand-coded Apex or Flow integration suits *one* well-bounded point-to-point need. Past that, prefer
a connector or middleware.

```
How many systems / how much orchestration?
├─ One simple API, admin-owned ............... Flow HTTP Callout / External Services (-outbound)
├─ One bespoke endpoint/contract ............. Apex (-outbound / -inbound-apex)
├─ Several systems, transformation, routing .. MuleSoft (Anypoint / for Flow)
├─ Prebuilt SaaS connector exists ............ MuleSoft for Flow / Direct / AppExchange
├─ Analytics over external data, no ETL ...... Data 360 zero-copy (-data360)
└─ An AI agent/assistant is the caller ....... Hosted MCP server / Agent API
```

At **more than one or two integrations**, or the first need for transformation, orchestration or
queuing, move from point-to-point Apex callouts to **MuleSoft**.

---

## 2. MuleSoft Family

| Product | What it is | Use |
|---|---|---|
| **Anypoint Platform** | Full enterprise iPaaS + API management + the API/MCP gateway of the ecosystem | Many systems, complex orchestration, API governance |
| **MuleSoft for Flow** | Low-code connectors invoked directly inside Flow (1500+ actions, 300+ triggers across 90+ connectors) | Admins wiring SaaS systems without Apex |
| **MuleSoft Direct** | Prebuilt industry-cloud connectors surfaced in Salesforce (e.g. FHIR for Health Cloud) | Industry-cloud data without integration projects |
| **API Catalog for Salesforce** | Central hub to manage APIs + MCP servers (MuleSoft/Heroku/Apex), convert ops to invocable actions | Discoverability + governance across surfaces |

Default to **MuleSoft for Flow** where a prebuilt connector exists and an admin owns the flow. Use
**Anypoint** for real orchestration, DataWeave transformation, API management, or a façade over many
backends.

---

## 3. Heroku / AppLink

The off-platform compute and integration tier. **AppLink** connects Heroku apps to Salesforce orgs
with user-permission enforcement and multi-org connectivity; it is the official replacement for the
**retired Salesforce Functions**.

- Use it for elastic or custom compute, languages other than Apex, long-running jobs, and heavy data
  processing close to Salesforce.
- Caveat: Heroku enterprise sales to new customers have ended. Confirm commercial fit before
  committing new strategic workloads.

---

## 4. Data 360 as an Integration Path

Often the best integration moves no data at all.

- **Zero-copy federation** — query external warehouses (Snowflake, Databricks, BigQuery, Redshift) in
  place via Apache Iceberg: no ETL, no duplication.
- **Ingestion API / connectors** — for data that must be resident in Data 360, streaming or batch.

Pipeline mechanics, credits and zero-copy detail are `dya-sf-data360`. Choose zero-copy for analytics
and grounding that should not duplicate data; ingestion when you need low-latency operational access
to resident data.

---

## 5. AppExchange / ISV Connectors

Packaged AppExchange integrations, now distributed via External Client Apps for 2GP. Before
building, check for a vetted managed-package connector — especially for common SaaS targets. Govern
an installed connector's API usage and permissions.

---

## 6. MCP / Headless 360 / Agent API — the Agentic Surface

In 2026, integration includes **AI agents and assistants** acting on the org.

- **Hosted MCP Servers (GA)** — connect external MCP clients to standard tools over Platform,
  Data 360, Tableau and product APIs, out of the box.
- **Custom hosted MCP servers** — expose *your* chosen tools, built from **Apex actions
  (`@InvocableMethod`), Flows, Apex REST and Named Query APIs**. Curate the smallest approved
  toolset.
- **Agent API** — invoke an Agentforce agent headlessly from an external system (`dya-sf-agentforce`).
- Security: every MCP call runs **as the authenticated user** with CRUD, FLS and sharing enforced,
  auth is OAuth plus PKCE via an ECA (`dya-sf-integration-auth`), and calls count against daily API
  limits.

MCP and HXL internals live in `dya-sf-headless360`. MCP is the right integration surface when the
caller is an AI client that should discover and call capabilities dynamically.

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

---

## Summary — The Five Commandments

1. **Don't hand-code past one integration** — connectors/MuleSoft once it's multi-system or needs orchestration.
2. **MuleSoft for Flow for prebuilt SaaS**, Anypoint for real orchestration/transformation/API management.
3. **Sometimes the best integration moves no data** — Data 360 zero-copy for analytics/grounding.
4. **MCP is the agentic integration surface** — custom servers expose your Apex actions/Flows/Named Queries; curate, describe, and run as a least-privilege user.
5. **Mind the retirements** — Salesforce Functions gone (→ Heroku/AppLink), Salesforce-to-Salesforce ending (→ Cross-Org/MuleSoft/Data Cloud One).
