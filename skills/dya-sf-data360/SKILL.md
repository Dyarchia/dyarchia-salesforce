---
name: dya-sf-data360
description: Salesforce Data 360, formerly Data Cloud (Winter '27, API v68.0) — the ingest, DLO, DMO, identity, insight and activation pipeline, Ingestion and Query APIs, zero-copy, segments, data actions, credit governance, Agentforce grounding. Applies to data streams, DLO and DMO mappings, identity rulesets, calculated insights, segments, data actions, Ingestion or Query API clients, Apex and SOQL over DMOs. Load before creating or editing anything in this scope.
---

# Salesforce Data 360 — From Zero to Expert

You **always** filter and project queries tightly, **always** default to batch over streaming, and
**always** treat every operation as costing **credits**. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults Apex query code inherits.
- `references/shared/governor-limits.md` — the transaction budget an Apex query against Data 360 still spends.
- `references/query-api.md` — **the four query surfaces and how to choose**: the `sfsqlquery` Apex namespace, `ConnectApi.CdpQuery`, the Connect REST endpoints, and the `/api/v3/query` Direct API with chunks, metadata and Apache Arrow; endpoints, auth and the `dne_cdpInstanceUrl` trap.
- `references/ingestion-api.md` — streaming and bulk ingestion end to end: connector and schema prerequisites, the job lifecycle, the payload test action.
- `references/query-access.md` — SOQL on DMOs/DLOs in Apex (`__dlm`, `DATASPACE`, governor and credit notes), Connect API in Apex (`ConnectApi`), the Query API (SQL), pagination, and query best practices.
- `references/ingestion-and-modeling.md` — Ingestion API and connectors, streaming vs batch, DLO→DMO mapping, identity resolution, calculated insights, segments, data actions/platform events, and zero-copy federation.
- `references/code-extensions.md` — Data Custom Code: the CLI and Python SDK, project shape, `read_dlo` / `write_to_dmo`, CPU sizing, and the fact that a local run hits real data.

Load a reference when building that exact thing. Data 360 is the **data layer that grounds
Agentforce** (`dya-sf-agentforce`), is increasingly driven headlessly (`dya-sf-headless360`), and its
query code is Apex (`dya-sf-apex`).

---

## Platform Context — Winter '27 / API v68.0

**"Data Cloud" was rebranded to "Data 360" on October 14, 2025.** Same product: "Data Cloud" still
appears in older docs, in API names and in the `Data Cloud Data Access` permission set. Use
"Data 360" in new work.

**Data 360 ships on its own monthly cadence**, not the three-times-a-year platform release. Winter '27
changes are dated around October 2026, and a feature can appear between platform releases, so check
the Data 360 release notes too.

- **Executing Data 360 SQL from Apex is GA.** Keep custom logic and Data 360 data in one class, not
  an integration between them. See `dya-sf-apex`.
- **The Data 360 MCP Server is Developer Preview** — not production. See `dya-sf-headless360`.
- **Apex and SOQL against DMOs run under the 67.0+ security defaults, and every query spends Data
  Services credits.** Credits make an unfiltered query expensive, not merely slow (§8).

> Headless DevOps for Data 360, Data Custom Code and the rest of the release surface:
> `references/release-notes.md`.

---

## 1. Foundations — What Data 360 Is

Treat Data 360 as a separate analytical store, not the CRM database. Queries scan large volumes and
**consume credits**, so treat architecture and query hygiene as cost decisions, not performance
decisions.

Data 360 is Salesforce's **data platform** and single source of truth: it ingests data from many
systems, **unifies** it into a single customer view, and serves analytics, segmentation, automation
and **grounding AI agents**.

```
Sources ──ingest──▶ DLO ──map──▶ DMO ──identity resolution──▶ Unified DMO
                                                   │
                                  ┌────────────────┼────────────────┐
                              Calculated        Segments        Data Actions /
                               Insights        (audiences)      Activation / RAG grounding
```

1. **Ingest** raw data from sources: Salesforce, external apps, files, streams, or *zero-copy* from a
   warehouse.
2. It lands in a **Data Lake Object (DLO)**, the raw building block, preserving the source schema.
3. An admin **maps** DLO fields to a **Data Model Object (DMO)** using the standard **Customer 360
   Data Model**, with 300+ prebuilt object types.
4. **Identity resolution** merges records describing the same person or company into a **Unified
   DMO**, the unified profile.
5. On top sit **Calculated Insights** (metrics), **Segments** (audiences), **Data Actions**
   (real-time triggers), activations, and **grounding** for Agentforce.

---

## 2. Key Objects & Terms

| Term | What it is |
|---|---|
| **DLO** (Data Lake Object, suffix `__dll`) | Raw ingested data, source schema preserved |
| **DMO** (Data Model Object, suffix `__dlm`) | Mapped, standardised object in the Customer 360 model — the queryable "single source of truth" |
| The two suffixes | `__dll` is raw, `__dlm` is modelled. Swapping them returns nothing useful |
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
| **Ingestion API** | Push from external systems (streaming or bulk) | Streaming costs multiples of batch (§8) |
| **Zero-copy federation** (EDLO) | Query a warehouse in place, no ingestion | Avoids ingestion cost; query cost applies |
| **Data Custom Code (Python SDK)** | Custom transforms run inside Data 360 | Author locally, deploy to a sandbox, monitor through a code-extensions DLO |

Rules:
- **Define an explicit schema** for every ingestion pipeline; Data 360 requires it.
- **Ingest through a Salesforce-native connector wherever one exists.** Sales, Service, Marketing
  and Commerce Cloud data is **included at zero credits** (§8); never pay an external pipeline to
  carry it.
- **Default to batch** (§8); stream only where sub-15-minute latency changes the business outcome.
- **Prefer zero-copy** where the source is a supported warehouse and no physical copy is needed.

---

## 4. Modeling & Identity Resolution

Settle identity resolution and the cost model before anything else.

- **Map** DLO fields onto standard DMOs from the Customer 360 model; never invent custom shapes.
  Downstream joins and grounding depend on the standard model.
- Configure **key qualifier fields** on DLO fields used in joins; without them, joins return null and
  performance and cost suffer.
- **Identity resolution** is the **most expensive operation in Data 360**, by three to four orders of
  magnitude over a query (§8). It bills on **rows processed, not rows ingested**, and the processed
  count is almost always larger.
  - Run IR **incrementally**, on a schedule aligned to real data change, never continuously.
  - Align downstream schedules — CIs, segments — to IR's actual incremental behaviour rather than
    recomputing everything on every trickle of new data.

---

## 5. Querying — Choose the Right Method

| Need | Method | Notes |
|---|---|---|
| Read a few DMO records from **Apex** (agent action, trigger-adjacent logic) | **SOQL on DMOs** (`__dlm`) | Cheapest thing that works; consumes credits |
| Run **Data 360 SQL from Apex** | **`sfsqlquery` namespace** | The documented **recommended** Apex approach: `SqlStatement`, `SqlRowIterator`, `SqlQueueable` — iterate and go async instead of materialising a result set in one transaction |
| **Analytical** SQL crossing modeled data, aggregates, joins, from outside | **Connect REST**, or the **`/api/v3/query` Direct API** | Direct API adds chunked retrieval, schema-only metadata and Apache Arrow. Results are cached — re-read with `result_scan` rather than re-running |
| Object-oriented access from an **app/integration** | **Connect REST API** or **Connect API in Apex** (`ConnectApi`) | Profiles, CIs, segments, metadata |
| Fast full-entity profile fetch | **Data Graph API** | Precomputed graph, low latency |

### SOQL on DMOs (from Apex)

```apex
// DMO names end in __dlm. USER_MODE by the 67.0+ defaults. Consumes Data Services credits.
List<UnifiedssotIndividualMain__dlm> people = [
    SELECT Id, FirstName__c, LastName__c, LoyaltyTier__c
    FROM UnifiedssotIndividualMain__dlm
    WHERE LoyaltyTier__c = 'Gold' WITH USER_MODE
    LIMIT 200
];
```

**Do not guess a unified DMO's name.** Identity resolution derives it from the ruleset, so it is
org-specific: `UnifiedssotIndividualMain__dlm` above is one ruleset's output, and a plausible-looking
`UnifiedIndividual__dlm` will not compile. Read the real name off the ruleset in Setup, or list them
with `GET /services/data/vXX.X/ssot/data-model-objects`.

Hard rules for any Data 360 query, SOQL or SQL:
- **Always a selective `WHERE` and a `LIMIT`.** An unfiltered scan of a 100M-row DMO can burn
  hundreds of credits in *one* query.
- **Project only the columns you need** — never `SELECT *`.
- **Querying DLOs requires the `DATASPACE` clause** at the end of the SOQL; without it the query
  returns **zero records**.
- Preview on **sample data** before running exploratory queries at full scale.
- **Paginate** Query API results with `getSqlQueryRows` (offset and rowLimit); re-reading cached
  results within 24h costs nothing extra.

---

## 6. Calculated Insights & Segments

- **Calculated Insights** (`__cio`) define metrics as dimensions plus measures over modeled data:
  lifetime value, engagement scores, RFM. **Run them in batch** unless sub-15-minute latency is
  essential: a streaming CI can cost ~50× batch for identical daily-consumed output.
- **Segments** are filtered audiences for activation. Use aggregate and waterfall filtering; a data
  model that forces complex joins raises segmentation and activation cost by 20–40%.
- Build and manage both programmatically through the **Connect API**.
- Give a CI created through the API a developer name ending in `__cio`.

---

## 7. Data Actions & Automation

Use Data Actions for **real-time responsiveness** such as a purchase or a threshold breach; keep
heavy analytical recomputation in scheduled batch.

A **Data Action** fires when DMO records or calculated insights change, emitting the
`DataObjectDataChgEvent` **platform event**. Supported targets: a **Salesforce Platform Event**, a
**webhook** and **Marketing Cloud**.

Act on the change in a subscriber — a Flow, or Apex on the platform event: update a CRM record, call
an external webhook, launch a personalised offer.

---

## 8. Cost & Governance — Credits Are a First-Class Concern

**Read the current rate card before quoting a number**; the card is versioned and now tiered.
Almost every Data 360 operation consumes credits:

| Operation | Rate card, July 2025 | Flex Credits card, 2026 (base tier) |
|---|---|---|
| Ingestion through a **Salesforce-native connector** | **0 — included** | **0 — included** |
| Data queries | 2 / M rows | 3 / M rows |
| Calculated Insight, batch | 15 / M rows | — |
| Segmentation | — | 50 / M rows |
| External ingestion / data prep | 2,000 / M rows | 40 / M rows |
| Calculated Insight, streaming | 800 / M rows | — |
| Streaming pipeline | 5,000 / M rows | 3,500 / M rows |
| **Identity resolution** (*Profile Unification*) | **100,000 / M rows** | **75,000 / M rows** |

The Flex Credits card adds four volume tiers that reset monthly and take the multiplier to 80%, 40% and 20%
of base past 300k, 1.5M and 12.5M credits — a high-volume org's marginal cost is a fifth of the
headline rate. Both cards come from Salesforce's *Customer Data Cloud Rate Card*; the usage types
are defined in Salesforce Help under *Data Services Billable Usage Types for Data 360*.

Four things hold on every card revision:

- **Native-connector ingestion is free.**
- **Identity resolution dwarfs everything else**; feeding it un-deduplicated source data drains the
  credit pool.
- **Streaming costs multiples of batch** for both ingestion and calculated insights.
- **Queries are the cheapest line on the card**, so an unfiltered scan is a volume problem, not a
  rate problem.

Review exploratory queries on large DMOs before they run. Treat a Data 360 design review as a
credit-consumption review.

---

## 9. Grounding for Agentforce & RAG

Ground agents in Data 360 rather than baking facts into a model; grounding keeps Agentforce answers
accurate, explainable, fresh, governed and auditable.

- **Structured grounding** — expose unified profiles and calculated insights so an agent reasons over
  real, permission-aware customer data. See `dya-sf-agentforce` §6.
- **Unstructured + vector search** — ingest documents and images into **UDLOs**, vectorise them, and
  use **vector search** for RAG so agents can cite source content.
- **Custom retrievers** — build domain-specific retrievers for the grounding step.

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
| Custom in-platform transform | Data Custom Code (Python SDK) — `references/code-extensions.md` |
| Drive Data 360 from a coding agent | Data 360 MCP Server (`dya-sf-headless360`) |

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
2. **Let credits govern design** — batch by default, identity resolution incrementally, every query filtered and limited; a design review is a cost review.
3. **Model to the Customer 360 standard** — map to standard DMOs, configure key qualifiers, avoid join-heavy models.
4. **Query by where the logic lives** — SOQL on `__dlm` from Apex, Query API SQL for analytics, Connect API for apps, Data Graph for fast profiles; always `WHERE`/`LIMIT`/`DATASPACE`.
5. **Ground the AI in Data 360** — structured profiles + CIs and unstructured vector search make Agentforce accurate, fresh, and auditable.
