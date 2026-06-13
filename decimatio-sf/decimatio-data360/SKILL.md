---
name: decimatio-data360
description: Salesforce Data 360 (formerly Data Cloud) Summer '26 — from zero to expert. What Data 360 is and the ingest→DLO→DMO→identity→insights→activation pipeline; key objects (DLO, DMO, UDLO, EDLO, CI, segments, data graphs, dataspaces); getting data in (Ingestion API, connectors, zero-copy); modeling and identity resolution; querying (SOQL on DMOs in Apex, Query API SQL, Connect API); calculated insights and segments; data actions and automation; credit/cost governance; grounding for Agentforce and RAG. Load only when the user explicitly invokes this skill by name (`decimatio-data360`); do NOT auto-trigger on generic Data Cloud, data, or Salesforce questions.
---

# Salesforce Data 360 — From Zero to Expert

You are an expert Data 360 architect and developer. The reader may be **new to Data 360**, so this skill builds the mental model first, then the implementation rules, then what changed in Summer '26. You **always** filter and project queries tightly, **always** default to batch over streaming, and **always** treat every operation as costing **credits**. Follow every rule below.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/`:

- `references/query-access.md` — SOQL on DMOs/DLOs in Apex (`__dlm`, `DATASPACE`, governor and credit notes), Connect API in Apex (`ConnectApi`), the Query API (SQL), pagination, and query best practices.
- `references/ingestion-and-modeling.md` — Ingestion API and connectors, streaming vs batch, DLO→DMO mapping, identity resolution, calculated insights, segments, data actions/platform events, and zero-copy federation.

Load a reference when building that exact thing. Data 360 is the **data layer that grounds Agentforce** (`decimatio-agentforce`) and is increasingly driven headlessly (`decimatio-headless360`); query code is Apex (`decimatio-apex`).

---

## Platform Context — Summer '26

- **"Data Cloud" was rebranded to "Data 360" on October 14, 2025.** Same product; you'll still see "Data Cloud" in older docs, API names, and the `Data Cloud Data Access` permission set. Use "Data 360" in new work.
- **Data 360 MCP Server (Developer Preview)** — an open-source MCP server fronting ~200 REST operations behind three facade tools (`search`, `payload_examples`, …) so coding agents can drive Data 360. Part of Headless 360. See `decimatio-headless360`.
- **Headless DevOps for Data 360** — CI/CD pipelines can now promote Data 360 logic (data transforms, code extensions) the same way they promote Apex and LWC metadata, via DevOps data kits.
- **Data Custom Code (Python SDK)** — author Python data-processing code locally with the Data Custom Code Python SDK + Salesforce CLI, validate against a sandbox, deploy and monitor (logs surface in a code-extensions DLO).
- **Apex/SOQL access to DMOs** continues to evolve; queries run under API 67 controls when issued from Apex. Querying DMOs consumes **Data Services credits** — see §8.

---

## 1. Foundations — What Data 360 Is

Data 360 is Salesforce's **data platform**: it ingests data from many systems, **unifies** it into a single customer view, and makes it usable for analytics, segmentation, automation, and — crucially — **grounding AI agents**. It is the "single source of truth" layer that sits beneath the rest of the platform.

The pipeline, end to end:

```
Sources ──ingest──▶ DLO ──map──▶ DMO ──identity resolution──▶ Unified DMO
                                                   │
                                  ┌────────────────┼────────────────┐
                              Calculated        Segments        Data Actions /
                               Insights        (audiences)      Activation / RAG grounding
```

1. **Ingest** raw data from sources (Salesforce, external apps, files, streams, or *zero-copy* from a warehouse).
2. It lands in a **Data Lake Object (DLO)** — the raw building block, preserving the source schema.
3. An admin **maps** DLO fields to a **Data Model Object (DMO)** using the standard **Customer 360 Data Model** (300+ prebuilt object types).
4. **Identity resolution** rules merge records describing the same person/company into a **Unified DMO** (the unified profile).
5. On top you build **Calculated Insights** (metrics), **Segments** (audiences), **Data Actions** (real-time triggers), activations, and **grounding** for Agentforce.

**The most important mental shift:** Data 360 is a separate analytical store, not your CRM database. Queries scan large volumes and **consume credits**. Architecture and query hygiene are cost decisions, not just performance decisions.

---

## 2. Key Objects & Terms

| Term | What it is |
|---|---|
| **DLO** (Data Lake Object, `__dll`/`__dlm` in queries) | Raw ingested data, source schema preserved |
| **DMO** (Data Model Object, `__dlm`) | Mapped, standardised object in the Customer 360 model — the queryable "single source of truth" |
| **UDLO** | Unstructured DLO — documents/images for AI/RAG |
| **EDLO** | External DLO — metadata pointer to an external warehouse (Snowflake, Databricks, Redshift) for **zero-copy** federation |
| **Unified Profile / Unified DMO** | Records merged by identity resolution |
| **Calculated Insight (CI, `__cio`)** | A metric/measure computed over modeled data (e.g. lifetime value) |
| **Segment** | A filtered audience built for activation |
| **Data Graph** | A precomputed JSON view of related objects around an entity (fast profile retrieval) |
| **Dataspace** | A logical partition of data (org/brand/region). Required on DLO queries |
| **Data Action** | A trigger that emits a platform event / webhook on data change |

---

## 3. Getting Data In

| Method | Use | Cost posture |
|---|---|---|
| **Connectors** (Salesforce CRM, S3, marketing, 3rd-party) | Standard sources | Batch by default |
| **Ingestion API** | Push from external systems (streaming or bulk) | Streaming ~2.5× batch |
| **Zero-copy federation** (EDLO) | Query a warehouse in place, no ingestion | Avoids ingestion cost; query cost applies |
| **Data Custom Code (Python SDK)** | Custom transforms run inside Data 360 | New in Summer '26 |

Rules:
- **Define an explicit schema** for every ingestion pipeline — Data 360 requires it for structural integrity.
- **Default to batch ingestion.** Streaming costs roughly 2.5× batch (≈5,000 vs ≈2,000 credits per million rows). Use streaming only when sub-15-minute latency genuinely changes the business outcome.
- **Prefer zero-copy** when the source is a supported warehouse and you don't need a physical copy — you skip ingestion cost entirely and query in place.

Full ingestion patterns: `references/ingestion-and-modeling.md`.

---

## 4. Modeling & Identity Resolution

- **Map** DLO fields onto standard DMOs from the Customer 360 model rather than inventing custom shapes — consistency makes downstream joins and grounding work.
- Configure **key qualifier fields** on DLO fields used in joins — without them, joins return null and performance/cost suffer.
- **Identity resolution** unifies records into a single profile. It is the **single most expensive operation in Data 360** — roughly 50× external ingestion and thousands of times a batch calculated insight. A single IR run over 10M source profiles can burn ~1,000,000 credits.
  - Run IR **incrementally**, on a schedule aligned to real data change — not continuously.
  - Align downstream schedules (CIs, segments) to IR's actual incremental behaviour; don't recompute everything on every trickle of new data.

Identity resolution and the cost model are the two things a Data 360 architect must get right before anything else.

---

## 5. Querying — Choose the Right Method

There are three programmatic ways to read Data 360 data. Pick by where the logic lives.

| Need | Method | Notes |
|---|---|---|
| Query DMOs from **Apex on-platform** (agent action, trigger-adjacent logic) | **SOQL on DMOs** (`__dlm`) | Static SOQL supported; query locators/FOR loops API 61+; consumes credits |
| **Analytical** SQL crossing modeled data, aggregates, joins | **Query API (Data 360 SQL)** | `createSqlQuery` + paginated `getSqlQueryRows`; results cached 24h |
| Object-oriented access from an **app/integration** | **Connect REST API** or **Connect API in Apex** (`ConnectApi`) | Profiles, CIs, segments, metadata |
| Fast full-entity profile fetch | **Data Graph API** | Precomputed graph, low latency |

### SOQL on DMOs (from Apex)

```java
// DMO names end in __dlm. USER_MODE under API 67. This consumes Data Services credits.
List<UnifiedIndividual__dlm> people = [
    SELECT Id, FirstName__c, LastName__c, LoyaltyTier__c
    FROM UnifiedIndividual__dlm
    WHERE LoyaltyTier__c = 'Gold' WITH USER_MODE
    LIMIT 200
];
```

Hard rules for any Data 360 query (SOQL or SQL):
- **Always a selective `WHERE`** and a `LIMIT`. An unfiltered scan of a 100M-row DMO can burn hundreds of credits in *one* query.
- **Project only the columns you need** — never `SELECT *`.
- **Querying DLOs requires the `DATASPACE` clause** at the end of the SOQL; omit it and the query returns **zero records**.
- Preview on **sample data** before running exploratory queries at full scale.
- For the Query API, **paginate** with `getSqlQueryRows` (offset/rowLimit) — re-reading cached results within 24h is free of extra consumption.

Full query patterns, Connect API in Apex, and pagination: `references/query-access.md`.

---

## 6. Calculated Insights & Segments

- **Calculated Insights** (`__cio`) — define metrics (dimensions + measures) over modeled data: lifetime value, engagement scores, RFM. **Run them in batch** unless sub-15-minute latency is essential; streaming CIs can cost ~50× batch for identical daily-consumed output.
- **Segments** — filtered audiences for activation. Use **aggregate/waterfall** filtering thoughtfully; poor data-model design that forces complex joins raises segmentation/activation cost 20–40%.
- Build/manage both programmatically via the **Connect API** (CIs created via the API must have a developer name ending in `__cio`).

---

## 7. Data Actions & Automation

Data 360 reacts to change. A **Data Action** fires when DMO records or calculated insights change, emitting the `DataObjectDataChgEvent` **platform event**. Supported targets: **Salesforce Platform Event**, **webhook**, **Marketing Cloud**.

Pattern: a subscriber (e.g. a Flow, or Apex on the platform event) performs work on the change — update a CRM record, call an external webhook, launch a personalised offer. Use Data Actions for **real-time responsiveness** (a purchase, a threshold breach); keep heavy analytical recomputation in scheduled batch.

---

## 8. Cost & Governance — Credits Are a First-Class Concern

Unlike core CRM, **almost every Data 360 operation consumes credits.** Internalise the relative costs:

| Operation | Relative cost (orientation) |
|---|---|
| Calculated Insight (batch) | cheapest |
| Query (per million rows scanned) | ~2 credits/M rows — but unfiltered scans multiply fast |
| External batch ingestion | ~2,000 credits/M rows |
| Streaming ingestion | ~5,000 credits/M rows (~2.5× batch) |
| Streaming Calculated Insight | up to ~50× batch CI |
| **Identity Resolution** | the single largest consumer — ~1,000,000 credits per 10M-profile run |

Governance rules:
- **Batch by default.** Only use streaming where business value degrades within 15 minutes.
- **Run identity resolution incrementally**, scheduled to real change.
- **Every query gets a `WHERE` and a `LIMIT`;** preview on samples; establish review for exploratory queries on large DMOs.
- **Design the data model to avoid complex joins** at segmentation/activation time.
- **Cache and reuse** Query API results within the 24h window instead of re-running.

A Data 360 design review is, in large part, a credit-consumption review.

---

## 9. Grounding for Agentforce & RAG

Data 360 is what makes Agentforce answers accurate and explainable:

- **Structured grounding** — expose unified profiles and calculated insights so an agent reasons over real, permission-aware customer data (see `decimatio-agentforce` §6).
- **Unstructured + vector search** — ingest documents/images into **UDLOs**, vectorise them, and use **vector search** for RAG so agents can cite source content.
- **Custom retrievers** — build domain-specific retrievers for the grounding step.

Grounding keeps the agent's knowledge fresh, governed, and auditable — always prefer it over baking facts into a model.

---

## 10. Decision Matrix — Quick Reference

| Need | Solution |
|---|---|
| Push external data in | Ingestion API / connector (batch by default) |
| Query a warehouse without copying | Zero-copy federation (EDLO) |
| Land raw data | DLO |
| Standardise into the unified model | Map DLO → DMO (Customer 360 model) |
| Merge duplicate people/companies | Identity resolution (incremental!) |
| Query DMOs from Apex | SOQL on `__dlm` + `WITH USER_MODE` + `WHERE`/`LIMIT` |
| Analytical SQL with joins/aggregates | Query API (`createSqlQuery`/`getSqlQueryRows`) |
| Object-oriented access from an app | Connect REST API / `ConnectApi` in Apex |
| Fast full-profile fetch | Data Graph API |
| Define a metric | Calculated Insight (batch) |
| Build an audience | Segment |
| React to data change in real time | Data Action → platform event/webhook |
| Ground an agent in structured data | Unified profile + CI grounding |
| Ground an agent in documents | UDLO + vector search (RAG) |
| Custom in-platform transform | Data Custom Code (Python SDK) |
| Drive Data 360 from a coding agent | Data 360 MCP Server (`decimatio-headless360`) |

---

## 11. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Unfiltered query on a large DMO | Always `WHERE` + `LIMIT`; preview on samples |
| `SELECT *` style projection | Project only needed columns |
| Omitting `DATASPACE` on a DLO query | Add the `DATASPACE` clause (else zero records) |
| Streaming everything | Batch by default; streaming only for <15-min business value |
| Continuous / full identity resolution | Incremental IR aligned to real change |
| Re-running Query API instead of paging cache | Reuse cached results within 24h via `getSqlQueryRows` |
| Custom object shapes ignoring the C360 model | Map to standard DMOs |
| Joins without key qualifiers | Configure key qualifier fields |
| Treating Data 360 like the CRM transactional DB | It's an analytical store; every op costs credits |
| Streaming calculated insights for daily-consumed output | Batch CI |
| Fine-tuning a model for fresh facts | Ground via Data 360 (fresh, governed) |
| `WITH SECURITY_ENFORCED` in query Apex | `WITH USER_MODE` (removed in API 67+) |

---

## Summary — The Five Commandments

1. **Know the pipeline** — ingest → DLO → map → DMO → identity resolution → insights/segments/activation; Data 360 is the unified source of truth, not your CRM DB.
2. **Credits govern design** — batch by default, identity resolution incrementally, every query filtered and limited; a design review is a cost review.
3. **Model to the Customer 360 standard** — map to standard DMOs, configure key qualifiers, avoid join-heavy models.
4. **Query by where the logic lives** — SOQL on `__dlm` from Apex, Query API SQL for analytics, Connect API for apps, Data Graph for fast profiles; always `WHERE`/`LIMIT`/`DATASPACE`.
5. **Data 360 grounds the AI** — structured profiles + CIs and unstructured vector search make Agentforce accurate, fresh, and auditable.
