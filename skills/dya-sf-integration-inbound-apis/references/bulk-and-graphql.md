# Bulk API 2.0 & GraphQL — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-inbound-apis` for large loads/extracts (Bulk) or field-precise/graph access (GraphQL).

## Bulk API 2.0 — Ingest Job Lifecycle

```
# 1) Create an ingest job
POST /services/data/v68.0/jobs/ingest
{ "object": "Account", "operation": "upsert", "externalIdFieldName": "External_Id__c", "contentType": "CSV" }
# → returns job id and contentUrl

# 2) Upload CSV data (PUT the raw CSV to contentUrl)
PUT /services/data/v68.0/jobs/ingest/{jobId}/batches    (Content-Type: text/csv)
External_Id__c,Name
A-1001,Acme
A-1002,Globex

# 3) Mark the job ready to process
PATCH /services/data/v68.0/jobs/ingest/{jobId}   { "state": "UploadComplete" }

# 4) Poll until JobComplete / Failed
GET /services/data/v68.0/jobs/ingest/{jobId}

# 5) Retrieve outcomes
GET /services/data/v68.0/jobs/ingest/{jobId}/successfulResults
GET /services/data/v68.0/jobs/ingest/{jobId}/failedResults
GET /services/data/v68.0/jobs/ingest/{jobId}/unprocessedrecords
```

- **Prefer `upsert` with an external id** — idempotent and restartable.
- Split a load past the **150 MB** file limit into multiple jobs.
- Always process `failedResults` and reconcile; `JobComplete` does not mean every row succeeded.
- Use **Bulk query** (`/jobs/query`) for large extracts, not REST query paging over hundreds of thousands of rows.

## When NOT to use Bulk

- <10,000 records → REST (single, Composite or sObject Collections).
- Real-time, answer-now → synchronous REST.

## GraphQL API

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
