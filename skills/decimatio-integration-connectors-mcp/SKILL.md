---
name: decimatio-integration-connectors-mcp
description: Salesforce connectors & agentic integration (Summer '26 / API v67.0) — the "don't hand-code it" layer plus the 2026 agentic surface. MuleSoft (Anypoint, for Flow, Direct, API Catalog), Heroku/AppLink, AppExchange/ISV connectors, Data 360 ingestion/zero-copy as an integration path, and Hosted MCP servers / Headless 360 / Agent API. Load only when the user explicitly invokes this skill by name (`decimatio-integration-connectors-mcp`); do NOT auto-trigger on generic connector, MuleSoft, or MCP questions.
---

# Salesforce Connectors & Agentic Integration

You are an expert on the higher-level integration layer: prebuilt connectors and middleware that mean you **don't hand-code** an integration, plus the 2026 agentic surfaces (MCP / Headless 360 / Agent API). Use this to decide *when not to write Apex/Flow at all*. Data 360 internals → `decimatio-data360`; MCP/HXL internals → `decimatio-headless360`; agent building → `decimatio-agentforce`. Follow every rule below.

References:
- `references/connectors-and-mcp.md` — MuleSoft family + API Catalog, Heroku/AppLink, building/consuming MCP servers as an integration surface, and zero-copy vs ingestion decisions.

---

## Platform Context — Summer '26 / API v67.0

- **Hosted MCP Servers are GA** — Salesforce-hosted MCP servers expose sObject operations, Data 360, Tableau, and product APIs to any MCP client (Claude, ChatGPT, Cursor). Custom servers can expose Flows, Apex actions, and Named Query APIs as tools. Every MCP transaction runs **as the authenticated user** with full CRUD/FLS/sharing. MCP calls count against the daily API allocation.
- **API Catalog for Salesforce** (Summer '26) — a central hub to manage APIs and MCP servers from MuleSoft, Heroku, and Apex; convert API operations into invocable actions for Flow/Apex/Agentforce.
- **Named Query API is GA** — expose custom SOQL as scalable REST/agent actions.
- **Salesforce Functions is retired** (EOL Jan 31, 2025) — migrate compute to Heroku (AppLink). Note Salesforce has ended Heroku enterprise sales to new customers; evaluate carefully.
- **Salesforce-to-Salesforce** native feature ends support Summer '26 (stops Spring '27) — migrate to MuleSoft / Data Cloud One / the Cross-Org adapter.

---

## 1. The First Question — Should You Code This At All?

Hand-coded Apex/Flow integration is the right answer for *one* well-bounded point-to-point need. Past that, prefer a connector or middleware.

```
How many systems / how much orchestration?
├─ One simple API, admin-owned ............... Flow HTTP Callout / External Services (-outbound)
├─ One bespoke endpoint/contract ............. Apex (-outbound / -inbound-apex)
├─ Several systems, transformation, routing .. MuleSoft (Anypoint / for Flow)
├─ Prebuilt SaaS connector exists ............ MuleSoft for Flow / Direct / AppExchange
├─ Analytics over external data, no ETL ...... Data 360 zero-copy (-data360)
└─ An AI agent/assistant is the caller ....... Hosted MCP server / Agent API
```

The moment you have **more than one or two integrations**, or need **transformation/orchestration/queuing**, stop spider-webbing point-to-point Apex callouts and move to **MuleSoft**.

---

## 2. MuleSoft Family

| Product | What it is | Use |
|---|---|---|
| **Anypoint Platform** | Full enterprise iPaaS + API management + the API/MCP gateway of the ecosystem | Many systems, complex orchestration, API governance |
| **MuleSoft for Flow** | Low-code connectors invoked directly inside Flow (1500+ actions, 300+ triggers across 90+ connectors) | Admins wiring SaaS systems without Apex |
| **MuleSoft Direct** | Prebuilt industry-cloud connectors surfaced in Salesforce (e.g. FHIR for Health Cloud) | Industry-cloud data without integration projects |
| **API Catalog for Salesforce** | Central hub to manage APIs + MCP servers (MuleSoft/Heroku/Apex), convert ops to invocable actions | Discoverability + governance across surfaces |

Default to **MuleSoft for Flow** when a prebuilt connector exists and an admin owns the flow; reach for **Anypoint** when you need real orchestration, transformation (DataWeave), API management, or a façade over many backends.

---

## 3. Heroku / AppLink

Off-platform compute and integration tier. **AppLink** connects Heroku apps to Salesforce orgs with user-permission enforcement and multi-org connectivity — the official replacement path for the **retired Salesforce Functions**.

- Use for: elastic/custom compute, languages Apex can't do, long-running jobs, heavy data processing close to Salesforce.
- Caveat: Salesforce has ended Heroku enterprise sales to new customers — confirm commercial fit before committing new strategic workloads.

---

## 4. Data 360 as an Integration Path

Often the best "integration" is **not moving the data at all**.

- **Zero-copy federation** — query external warehouses (Snowflake, Databricks, BigQuery, Redshift) in place via Apache Iceberg; no ETL, no duplication.
- **Ingestion API / connectors** — when you do need the data resident in Data 360 (streaming or batch).

For the pipeline mechanics, credits, and zero-copy detail, use `decimatio-data360`. Choose zero-copy for analytics/grounding that shouldn't duplicate data; choose ingestion when low-latency operational access to resident data is required.

---

## 5. AppExchange / ISV Connectors

Packaged integrations from the AppExchange (now distributed via External Client Apps for 2GP). Before building, check whether a vetted managed-package connector already solves it — especially for common SaaS targets. Govern installed connectors' API usage and permissions.

---

## 6. MCP / Headless 360 / Agent API — the Agentic Surface

In 2026, "integration" includes letting **AI agents and assistants** act on the org.

- **Hosted MCP Servers (GA)** — connect external MCP clients to standard tools over Platform, Data 360, Tableau, product APIs. Out-of-the-box.
- **Custom hosted MCP servers** — expose *your* chosen tools built from **Apex actions (`@InvocableMethod`), Flows, Apex REST, and Named Query APIs**. Curate the smallest approved toolset.
- **Agent API** — invoke an Agentforce agent headlessly from an external system (see `decimatio-agentforce`).
- Security: every MCP call runs **as the authenticated user** with CRUD/FLS/sharing enforced; auth is OAuth + PKCE via an ECA (`decimatio-integration-auth`). MCP calls count against daily API limits.

MCP/HXL internals live in `decimatio-headless360`; this skill's job is to tell you *when* MCP is the right integration surface — namely when the *caller is an AI client* that should discover and call capabilities dynamically.

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

---

## Summary — The Five Commandments

1. **Don't hand-code past one integration** — connectors/MuleSoft once it's multi-system or needs orchestration.
2. **MuleSoft for Flow for prebuilt SaaS**, Anypoint for real orchestration/transformation/API management.
3. **Sometimes the best integration moves no data** — Data 360 zero-copy for analytics/grounding.
4. **MCP is the agentic integration surface** — custom servers expose your Apex actions/Flows/Named Queries; curate, describe, and run as a least-privilege user.
5. **Mind the retirements** — Salesforce Functions gone (→ Heroku/AppLink), Salesforce-to-Salesforce ending (→ Cross-Org/MuleSoft/Data Cloud One).
