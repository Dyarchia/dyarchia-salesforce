# Ingestion API — Reference (Winter '27 / API v68.0)

Load from `dya-data360` when pushing data into Data 360 from an external system. Two modes on one
API, and the choice between them is a cost decision before it is a latency decision — see the credit
table in the skill body.

## Before any call

An **Ingestion API connector** must exist, with a **schema** describing the objects you will send.
Data 360 requires the schema up front; there is no inferring it from the payload. The connector's
`sourceName` (for example `ecomm_api`) and the object name appear in every streaming URL, so name
them for readability rather than convenience.

Authentication is OAuth 2.0 against the Data 360 instance. All URLs below are
`https://{instance_url}/api/v1/ingest/...`.

## Streaming ingestion — small, continuous, near-real-time

```http
POST /api/v1/ingest/sources/{sourceName}/{objectName}
```

```http
POST /api/v1/ingest/sources/ecomm/Order/
```

Send records in the body and they enter the pipeline continuously. There is a **test action** that
validates a payload against the schema without ingesting anything:

```http
POST /api/v1/ingest/sources/ecomm/Order/actions/test
```

Use it while building. A schema mismatch discovered in production looks like data silently not
arriving.

Deleting is a separate verb on the same source path, taking ids:

```http
DELETE /api/v1/ingest/sources/{sourceName}/{objectName}?ids=001xx000003DGb2AAG,003xx000004TmiQAAS
```

**Streaming costs roughly 2.5× batch for the same rows.** Use it when sub-15-minute latency changes a
business outcome, not because it feels more modern.

## Bulk ingestion — a job in four steps

Bulk is a job lifecycle, close in shape to Bulk API 2.0 on the core platform.

### 1. Create the job

```http
POST /api/v1/ingest/jobs
```

```json
{
  "object": "Contact",
  "sourceName": "ecomm_api",
  "operation": "upsert"
}
```

`upsert` is the operation you want in almost every case: ingestion is inherently retryable, and an
insert that runs twice duplicates data. The response carries the job `id` and `state: "Open"`.

### 2. Upload CSV batches

```http
PUT /api/v1/ingest/jobs/{jobId}/batches
```

The body is CSV, and its columns must match the schema registered on the connector.

### 3. Close the job for upload

```http
PATCH /api/v1/ingest/jobs/{jobId}
```

```json
{ "state": "UploadComplete" }
```

Nothing processes until this happens. A job left `Open` is the usual explanation for "I uploaded the
data and nothing arrived".

### 4. Poll to completion

```http
GET /api/v1/ingest/jobs/{jobId}
```

States you will see: **`Open`** → **`UploadComplete`** → **`JobComplete`**. The response also carries
`object`, `contentType` (`CSV`), `createdDate` and `systemModstamp`.

## Choosing between them

| | Streaming | Bulk |
|---|---|---|
| Shape | Records posted to a source URL | Job, CSV batches, close, poll |
| Latency | Near-real-time | Scheduled or on demand |
| Relative cost | ~2.5× batch per million rows | The cheaper baseline |
| Fits | Event-shaped data where minutes matter | Backfills, nightly loads, migrations |

If neither fits because the data already lives in a supported warehouse, **do not ingest at all** —
zero-copy federation queries it in place and skips ingestion cost entirely. See the skill body.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Streaming by default | Batch unless sub-15-minute latency changes the outcome — it costs ~2.5× |
| `insert` as the bulk operation | `upsert`; ingestion is retryable and an insert run twice duplicates |
| Discovering a schema mismatch in production | `POST .../actions/test` validates a payload without ingesting |
| Leaving a bulk job `Open` | `PATCH` it to `UploadComplete` or nothing processes |
| Ingesting data that already lives in a supported warehouse | Zero-copy federation — no ingestion cost at all |
| An opaque `sourceName` | It appears in every URL; name it for the reader |
