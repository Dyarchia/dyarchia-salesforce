---
name: dya-data360
description: Salesforce Data 360 (formerly Data Cloud) Winter '27 (API v68.0) — from zero to expert. What Data 360 is and the ingest→DLO→DMO→identity→insights→activation pipeline; key objects (DLO, DMO, UDLO, EDLO, CI, segments, data graphs, dataspaces); getting data in (Ingestion API, connectors, zero-copy); modeling and identity resolution; querying (SOQL on DMOs in Apex, Query API SQL, Connect API); calculated insights and segments; data actions and automation; credit/cost governance; grounding for Agentforce and RAG. Load only when the user explicitly invokes this skill by name (`dya-data360`); do NOT auto-trigger on generic Data Cloud, data, or Salesforce questions.
---

# Salesforce Data 360 — From Zero to Expert

You are an expert Data 360 architect and developer. The reader may be **new to Data 360**, so this
skill builds the mental model first, then the implementation rules, then what this release changes.
You **always** filter and project queries tightly, **always** default to batch over streaming, and
**always** treat every operation as costing **credits**. Follow every rule below.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/`:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults Apex query code inherits.
- `references/shared/governor-limits.md` — the transaction budget an Apex query against Data 360 still spends.
- `references/query-api.md` — **the four query surfaces and how to choose**: the `sfsqlquery` Apex namespace, `ConnectApi.CdpQuery`, the Connect REST endpoints, and the `/api/v3/query` Direct API with chunks, metadata and Apache Arrow.
- `references/ingestion-api.md` — streaming and bulk ingestion end to end: connector and schema prerequisites, the job lifecycle, the payload test action.
- `references/query-access.md` — SOQL on DMOs/DLOs in Apex (`__dlm`, `DATASPACE`, governor and credit notes), Connect API in Apex (`ConnectApi`), the Query API (SQL), pagination, and query best practices.
- `references/ingestion-and-modeling.md` — Ingestion API and connectors, streaming vs batch, DLO→DMO mapping, identity resolution, calculated insights, segments, data actions/platform events, and zero-copy federation.
- `references/code-extensions.md` — Data Custom Code: the CLI and Python SDK, project shape, `read_dlo` / `write_to_dmo`, CPU sizing, and the fact that a local run hits real data.

Load a reference when building that exact thing. Data 360 is the **data layer that grounds
Agentforce** (`dya-agentforce`), is increasingly driven headlessly (`dya-headless360`), and its query
code is Apex (`dya-apex`).

---

## Platform Context — Winter '27 / API v68.0

**"Data Cloud" was rebranded to "Data 360" on October 14, 2025.** Same product: you will still meet
"Data Cloud" in older docs, in API names and in the `Data Cloud Data Access` permission set. Use
"Data 360" in new work.

**Data 360 ships on its own monthly cadence**, not the three-times-a-year platform release. Winter '27
changes are dated around October 2026, and a feature can appear between platform releases — check the
Data 360 release notes rather than assuming the platform set is complete.

Three facts gate the work:

- **Executing Data 360 SQL from Apex is GA**, so custom logic and Data 360 data live in one class
  instead of an integration between them. See `dya-apex`.
- **The Data 360 MCP Server is Developer Preview** — not production. See `dya-headless360`.
- **Apex and SOQL against DMOs run under the 67.0+ security defaults, and every query spends Data
  Services credits.** Credits are what make an unfiltered query expensive rather than merely slow,
  which is why §8 exists and why the selectivity rules here are not style advice.

> Headless DevOps for Data 360, Data Custom Code and the rest of the release surface:
> `references/release-notes.md`.

---

## 1. Foundations — What Data 360 Is

Data 360 is Salesforce's **data platform**: it ingests data from many systems, **unifies** it into a
single customer view, and makes it usable for analytics, segmentation, automation and — crucially —
**grounding AI agents**. It is the single-source-of-truth layer beneath the rest of the platform.

The pipeline, end to end:

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
5. On top you build **Calculated Insights** (metrics), **Segments** (audiences), **Data Actions**
   (real-time triggers), activations, and **grounding** for Agentforce.

**The most important mental shift:** Data 360 is a separate analytical store, not your CRM database.
Queries scan large volumes and **consume credits**, so architecture and query hygiene are cost
decisions rather than performance decisions.

---

## 2. Key Objects & Terms

| Term | What it is |
|---|---|
| **DLO** (Data Lake Object, suffix `__dll`) | Raw ingested data, source schema preserved |
| **DMO** (Data Model Object, suffix `__dlm`) | Mapped, standardised object in the Customer 360 model — the queryable "single source of truth" |
| The two suffixes | `__dll` is raw, `__dlm` is modelled. Getting them the wrong way round is the most common beginner error, and the query simply returns nothing useful |
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
| **Data Custom Code (Python SDK)** | Custom transforms run inside Data 360 | Author locally, deploy to a sandbox, monitor through a code-extensions DLO |

Rules:
- **Define an explicit schema** for every ingestion pipeline. Data 360 requires it for structural
  integrity.
- **Default to batch ingestion.** Streaming costs roughly 2.5× batch — about 5,000 against 2,000
  credits per million rows — so use it only where sub-15-minute latency genuinely changes the
  business outcome.
- **Prefer zero-copy** where the source is a supported warehouse and no physical copy is needed: it
  skips ingestion cost entirely and queries in place.

> The API itself — connector and schema prerequisites, streaming versus the bulk job lifecycle,
> the payload test action: `references/ingestion-api.md`. Modelling, identity resolution and
> activation: `references/ingestion-and-modeling.md`.

---

## 4. Modeling & Identity Resolution

- **Map** DLO fields onto standard DMOs from the Customer 360 model rather than inventing custom
  shapes: consistency is what makes downstream joins and grounding work.
- Configure **key qualifier fields** on DLO fields used in joins. Without them, joins return null and
  both performance and cost suffer.
- **Identity resolution** unifies records into a single profile, and it is the **single most
  expensive operation in Data 360** — roughly 50× external ingestion and thousands of times a batch
  calculated insight. One IR run over 10M source profiles can burn ~1,000,000 credits.
  - Run IR **incrementally**, on a schedule aligned to real data change, never continuously.
  - Align downstream schedules — CIs, segments — to IR's actual incremental behaviour rather than
    recomputing everything on every trickle of new data.

Identity resolution and the cost model are the two things a Data 360 architect gets right before
anything else.

---

## 5. Querying — Choose the Right Method

There are three programmatic ways to read Data 360 data. Pick by where the logic lives.

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
org-specific — `UnifiedssotIndividualMain__dlm` above is one ruleset's output, not a platform
constant, and a plausible-looking `UnifiedIndividual__dlm` will not compile. Read the real name off
the ruleset in Setup, or list them with `GET /services/data/vXX.X/ssot/data-model-objects`.

Hard rules for any Data 360 query, SOQL or SQL:
- **Always a selective `WHERE` and a `LIMIT`.** An unfiltered scan of a 100M-row DMO can burn
  hundreds of credits in *one* query.
- **Project only the columns you need** — never `SELECT *`.
- **Querying DLOs requires the `DATASPACE` clause** at the end of the SOQL. Omit it and the query
  returns **zero records**.
- Preview on **sample data** before running exploratory queries at full scale.
- For the Query API, **paginate** with `getSqlQueryRows` (offset and rowLimit); re-reading cached
  results within 24h consumes nothing extra.

> Choosing between the four surfaces, with endpoints, auth and the `dne_cdpInstanceUrl` trap:
> `references/query-api.md`. Existing SOQL and Connect-in-Apex patterns:
> `references/query-access.md`.

---

## 6. Calculated Insights & Segments

- **Calculated Insights** (`__cio`) define metrics as dimensions plus measures over modeled data:
  lifetime value, engagement scores, RFM. **Run them in batch** unless sub-15-minute latency is
  essential, because a streaming CI can cost ~50× batch for identical daily-consumed output.
- **Segments** are filtered audiences for activation. Use aggregate and waterfall filtering
  thoughtfully: a data model that forces complex joins raises segmentation and activation cost by
  20–40%.
- Build and manage both programmatically through the **Connect API**. A CI created via the API must
  have a developer name ending in `__cio`.

---

## 7. Data Actions & Automation

Data 360 reacts to change. A **Data Action** fires when DMO records or calculated insights change,
emitting the `DataObjectDataChgEvent` **platform event**. Supported targets are a **Salesforce
Platform Event**, a **webhook** and **Marketing Cloud**.

The pattern: a subscriber — a Flow, or Apex on the platform event — does the work on the change,
updating a CRM record, calling an external webhook, launching a personalised offer. Use Data Actions
for **real-time responsiveness** such as a purchase or a threshold breach, and keep heavy analytical
recomputation in scheduled batch.

---

## 8. Cost & Governance — Credits Are a First-Class Concern

Unlike core CRM, **almost every Data 360 operation consumes credits.** Internalise the relative
costs:

| Operation | Relative cost (orientation) |
|---|---|
| Calculated Insight (batch) | cheapest |
| Query (per million rows scanned) | ~2 credits/M rows — but unfiltered scans multiply fast |
| External batch ingestion | ~2,000 credits/M rows |
| Streaming ingestion | ~5,000 credits/M rows (~2.5× batch) |
| Streaming Calculated Insight | up to ~50× batch CI |
| **Identity Resolution** | the single largest consumer — ~1,000,000 credits per 10M-profile run |

Governance rules:
- **Batch by default.** Use streaming only where business value degrades within 15 minutes.
- **Run identity resolution incrementally**, scheduled to real change.
- **Every query gets a `WHERE` and a `LIMIT`**, previewed on samples, with review established for
  exploratory queries on large DMOs.
- **Design the data model to avoid complex joins** at segmentation and activation time.
- **Cache and reuse** Query API results within the 24h window instead of re-running.

A Data 360 design review is, in large part, a credit-consumption review.

---

## 9. Grounding for Agentforce & RAG

Data 360 is what makes Agentforce answers accurate and explainable:

- **Structured grounding** — expose unified profiles and calculated insights so an agent reasons over
  real, permission-aware customer data. See `dya-agentforce` §6.
- **Unstructured + vector search** — ingest documents and images into **UDLOs**, vectorise them, and
  use **vector search** for RAG so agents can cite source content.
- **Custom retrievers** — build domain-specific retrievers for the grounding step.

Grounding keeps the agent's knowledge fresh, governed and auditable. Always prefer it to baking facts
into a model.

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
| Drive Data 360 from a coding agent | Data 360 MCP Server (`dya-headless360`) |

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
