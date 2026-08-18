# Data 360 Ingestion, Modeling & Activation — Reference (Summer '26)

Full implementations referenced from SKILL.md §3, §4, §6, §7. Load this when bringing data into Data 360, modeling it, or wiring activation/automation. Every stage consumes credits; the cost guidance here is as load-bearing as the mechanics.

## Getting Data In

| Method | When | Cost note |
|---|---|---|
| **Connectors** (CRM, S3, marketing, 3rd-party) | Standard, supported sources | Batch by default |
| **Ingestion API** | Push from a custom external system | Streaming (~5,000 cr/M rows) vs bulk/batch (~2,000 cr/M rows) |
| **Zero-copy federation (EDLO)** | Source is a supported warehouse (Snowflake, Databricks, Redshift) and a physical copy isn't needed | No ingestion cost; query-in-place cost applies |
| **Data Custom Code (Python SDK)** | Custom transform inside Data 360 | New Summer '26; author locally, deploy to sandbox, monitor via code-extensions DLO |

Rules:
- **Define an explicit schema** per ingestion pipeline — required for structural/semantic integrity.
- **Batch by default.** Streaming is ~2.5× the cost; justify it only when sub-15-minute latency changes the outcome.
- **Prefer zero-copy** when you can query the warehouse in place — it skips ingestion credits entirely.

## Ingestion API — Shape

The Ingestion API pushes records into a DLO mapped to a connector. Conceptually:

1. Create an **Ingestion API** data stream + connector with a defined schema (object + fields + primary key).
2. POST records to the ingestion endpoint (bulk file job, or streaming events).
3. Records land in the **DLO**; mapping then projects them into the **DMO**.

Use the bulk pattern for large periodic loads; reserve the streaming pattern for genuinely real-time signals.

## Modeling — DLO → DMO

- Map raw DLO fields onto **standard DMOs** from the Customer 360 Data Model (300+ prebuilt types: Individual, Account, Order, Engagement, …). Extend only when necessary.
- Configure **key qualifier fields** on join keys. When unset, joins return null and cost/perf degrade.
- Standardising onto the shared model is what makes downstream joins, segments, and grounding work consistently.

## Identity Resolution — the Expensive Step

Identity resolution merges DLO/DMO records describing the same entity into a **Unified DMO** (unified profile) using match + reconciliation rules.

- It is the **single largest credit consumer** — roughly 50× external ingestion and thousands of times a batch calculated insight. ~1,000,000 credits per run over 10M source profiles.
- Run **incrementally**, scheduled to actual data change — never continuously.
- Align downstream recompute (CIs, segments) to IR's real incremental behaviour; don't recompute the world on every trickle of new data.

## Calculated Insights (`__cio`)

Metrics computed over modeled data (dimensions + measures): lifetime value, engagement scores, RFM.

- **Batch by default.** A streaming CI can cost ~50× a batch CI for output that's only consumed daily. Processing 1B records/yr ≈ 15,000 credits batch vs ~800,000 streaming.
- Create/manage via the Connect API; CIs created through the API need a developer name ending in `__cio`.
- Use as grounding inputs for Agentforce and as segment criteria.

## Segments

Filtered audiences for activation.

- Poor data-model design that forces complex joins raises segmentation/activation cost 20–40% — model well first.
- Use aggregate filters and waterfall/ranked segments where supported to target precisely.
- Manage via the Connect API for repeatable, deployable definitions.

## Data Actions & Activation

Data 360 reacts to change in near-real-time:

- A **Data Action** fires when DMO records or calculated insights change, emitting the `DataObjectDataChgEvent` **platform event**.
- Supported targets: **Salesforce Platform Event**, **webhook**, **Marketing Cloud**.
- A subscriber (Flow, or Apex on the platform event) acts on the change — update a CRM record, call an external webhook, launch a personalised offer.

Pattern: real-time signals → Data Action → platform event → automation. Keep heavy analytical recomputation in scheduled batch; reserve Data Actions for events whose value is immediate.

## DevOps for Data 360 (Summer '26)

Promote Data 360 logic (data transforms, code extensions) through CI/CD with **DevOps data kits**, the same way you promote Apex/LWC metadata — enabling headless, repeatable deployments across environments.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Streaming ingestion as the default | Batch; streaming only for <15-min business value |
| Continuous / full identity resolution | Incremental IR aligned to real change |
| Streaming calculated insights for daily output | Batch CI |
| Custom object shapes ignoring the C360 model | Map to standard DMOs |
| Joins without key qualifiers | Configure key qualifier fields |
| Ingesting a warehouse you could federate | Zero-copy (EDLO) |
| Heavy recompute inside a Data Action | Data Action for real-time only; batch the rest |
| No schema on an ingestion pipeline | Define schema explicitly |
| Click-built CIs/segments with no source control | Manage via Connect API + DevOps data kits |
