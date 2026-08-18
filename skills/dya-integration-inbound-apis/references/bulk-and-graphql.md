# Bulk API 2.0 & GraphQL — Reference (API v67.0)

Load from `dya-integration-inbound-apis` for large-volume loads/extracts (Bulk) or field-precise/graph access (GraphQL).

## Bulk API 2.0 — Ingest Job Lifecycle

Asynchronous, CSV-based, for **>10,000 records**. Salesforce chunks the data into 10k-record batches on a separate async limit pool.

```
# 1) Create an ingest job
POST /services/data/v67.0/jobs/ingest
{ "object": "Account", "operation": "upsert", "externalIdFieldName": "External_Id__c", "contentType": "CSV" }
# → returns job id and contentUrl

# 2) Upload CSV data (PUT the raw CSV to contentUrl)
PUT /services/data/v67.0/jobs/ingest/{jobId}/batches    (Content-Type: text/csv)
External_Id__c,Name
A-1001,Acme
A-1002,Globex

# 3) Mark the job ready to process
PATCH /services/data/v67.0/jobs/ingest/{jobId}   { "state": "UploadComplete" }

# 4) Poll until JobComplete / Failed
GET /services/data/v67.0/jobs/ingest/{jobId}

# 5) Retrieve outcomes
GET /services/data/v67.0/jobs/ingest/{jobId}/successfulResults
GET /services/data/v67.0/jobs/ingest/{jobId}/failedResults
GET /services/data/v67.0/jobs/ingest/{jobId}/unprocessedrecords
```

Rules:
- **Prefer `upsert` with an external id** — idempotent and restartable.
- Limits: ~**15,000 batches / 24 h** shared with Bulk 1.0; **150 MB** per file. Split larger loads into multiple jobs.
- Always process `failedResults` and reconcile; don't assume a `JobComplete` means every row succeeded.
- Use **Bulk query** (`/jobs/query`) for large extracts rather than paging REST query for hundreds of thousands of rows.
- Use Bulk 2.0 (not 1.0) for all new work — 2.0 manages batching for you.

## When NOT to use Bulk

- <10,000 records → REST (single, Composite, or sObject Collections). Bulk's job overhead and async polling aren't worth it for small sets.
- Real-time, answer-now → synchronous REST.

## GraphQL API

Graph-shaped queries and mutations over UI API (honours FLS and UI-API object support).

### Query — fetch exactly what you need

```graphql
query {
  uiapi {
    query {
      Account(where: { Industry: { eq: "Technology" } } first: 10) {
        edges { node { Id Name { value } AnnualRevenue { value } } }
      }
    }
  }
}
```

### Mutation (GA) — create/update/delete

```graphql
mutation {
  uiapi {
    AccountCreate(input: { Account: { Name: "Acme" } }) {
      Record { Id }
    }
  }
}
```

**Summer '26 enhancement:** a later mutation can reference any field returned by an earlier operation in the same request (e.g. the new Account's Id) to create and link records in one round trip — not just the record id as before.

Constraints:
- UI-API-supported objects only.
- Creating a child relationship inside a single mutation is not supported.
- Great for bandwidth-sensitive clients (mobile) and multi-object reads in one call.

## Choosing Bulk vs GraphQL vs REST

| Situation | Use |
|---|---|
| Millions of rows in/out | Bulk API 2.0 |
| Exact-fields / multi-object read in one call | GraphQL query |
| Create + link records, minimal round trips | GraphQL mutation (field refs) |
| General single/few-record CRUD | REST |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Bulk job for a handful of records | REST |
| Ignoring `failedResults` | Always reconcile failures |
| `insert` operation on a re-runnable load | `upsert` by external id |
| Paging REST query for 500k rows | Bulk query job |
| Over-fetching whole sObjects via REST | GraphQL field selection |
| Bulk API 1.0 for new builds | Bulk API 2.0 |
