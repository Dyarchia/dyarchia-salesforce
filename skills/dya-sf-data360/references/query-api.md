# Querying Data 360 — Reference (Winter '27 / API v68.0)

The four surfaces are not interchangeable; picking the wrong one forces a rewrite.

## Pick the surface

| You are… | Use | Why |
|---|---|---|
| Writing Apex in the org | **`sfsqlquery` namespace** | The documented **recommended** approach for Apex. Iterators and queueables, so large results need not fit in one transaction |
| Writing Apex and want the REST shape | **`ConnectApi.CdpQuery`** | Mirrors the Connect REST endpoints one-for-one |
| Integrating from outside, standard case | **Connect REST API** (`/services/data/vXX.X/ssot/query-sql`) | Comprehensive, and on the normal org URL |
| Moving large result sets, or need schema introspection | **Data 360 REST API (Direct API)**, `/api/v3/query` | Chunked retrieval, metadata without rows, Apache Arrow |
| Reading a handful of DMO records inside a trigger or action | **SOQL on `__dlm`** | Cheapest thing that works |

The `sfsqlquery` namespace provides `SqlStatement`, `SqlRowIterator`, `Row`, `QueryHandle` and
`SqlQueueable`.

## Connect REST API

Four endpoints on your normal org URL, all requiring `Authorization: Bearer <token>`.

```http
POST   /services/data/vXX.X/ssot/query-sql                 # submit, returns queryId
GET    /services/data/vXX.X/ssot/query-sql/{queryId}       # status and metadata
GET    /services/data/vXX.X/ssot/query-sql/{queryId}/rows  # paginated results
DELETE /services/data/vXX.X/ssot/query-sql/{queryId}       # cancel, frees resources
```

Set two query parameters every time:

- `dataspace=default` — the data space the query runs in.
- `workloadName=...` — a description of the task or application, so Salesforce Support can find your
  query when something goes wrong.

**Parameterise rather than concatenate.** Pass a `sqlParameters` array in the body and reference
placeholders in the SQL:

```http
POST https://{instance}/services/data/vXX.X/ssot/query-sql?dataspace=default&workloadName=engagement-records
```

with `:startDate` in the statement bound from `sqlParameters`. String-built SQL is injectable here too.

**`result_scan` reads a cached result.** Pass a submit's `queryId` to `result_scan` in a later SQL
statement to read the cached output instead of re-scanning.

## Data 360 REST API (Direct API), `/api/v3/query`

**This one is not on your org URL.** It uses `dne_cdpInstanceUrl`, a separate instance URL obtained
with the access token. Sent to the org URL, these calls fail with an error that does not point at the
cause.

```http
POST   /api/v3/query                              # submit, ASYNC or ADAPTIVE mode
GET    /api/v3/query/{queryId}                    # status, row count, chunk count, statistics
GET    /api/v3/query/{queryId}/rows               # offset-based pagination
GET    /api/v3/query/{queryId}/chunks/{chunkId}   # chunked retrieval - preferred when large
GET    /api/v3/query/{queryId}/metadata           # output schema, no rows
DELETE /api/v3/query/{queryId}                    # cancel
```

The submit returns the `queryId` in the **`x-hyperdb-status` response header**, not the body; a
client reading the body concludes the call failed.

**Chunks over offsets for large results.** Offset pagination re-walks the result each time; chunked
retrieval does not.

**`/metadata` returns the output schema without rows**, so learning column types scans no data.

**Apache Arrow** is supported on submit, rows, chunks and metadata. Set
`Accept: application/vnd.apache.arrow.stream` and the response is a binary Arrow IPC stream instead of
JSON: smaller payloads and less deserialisation overhead for large result sets. Read it with
PyArrow or the Arrow Java library.

## Apex

```apex
// ConnectApi.CdpQuery mirrors the REST endpoints:
//   querySql        - submit
//   querySqlStatus  - check status
//   querySqlRows    - paginated results
//   cancelQuerySql  - cancel
```

Apex methods run in the **current user's session and permissions automatically** — no token to
manage, and the user's access governs what comes back (user-mode enforcement).

Prefer `sfsqlquery` for new work; `ConnectApi.CdpQuery` fits when you want the REST semantics mirrored
exactly, for example when porting an existing integration inward.

## Authentication

| Surface | Auth |
|---|---|
| Connect REST API | OAuth 2.0 bearer token. Client credentials flow for server-to-server |
| Direct API (`/api/v3`) | OAuth 2.0 bearer token **plus** the separate `dne_cdpInstanceUrl` |
| Apex (`sfsqlquery`, `ConnectApi`) | The running user's session — nothing to configure |

See `dya-sf-integration-auth` for the client credentials flow. The OAuth username-password flow is
retired with enforcement on 20 February 2027.

## Schema Introspection — Finding Out What Exists

Four read-only SSOT endpoints list what the org has:

```text
GET /services/data/vXX.X/ssot/data-lake-objects
GET /services/data/vXX.X/ssot/data-lake-objects/{name}
GET /services/data/vXX.X/ssot/data-model-objects
GET /services/data/vXX.X/ssot/data-model-objects/{name}
```

List responses are enveloped as `{ "dataLakeObjects": [...], "totalSize": n }` and
`{ "dataModelObjects": [...], "totalSize": n }`. Each entry carries `name`, `label`, `category`,
`id`, `status`, `totalRecords` and `fields`. Id prefixes are **`1dl`** for a DLO and **`0dm`** for a
DMO.

Use them to resolve a **unified DMO's real, org-specific name** (SKILL.md §5).

Every DLO also carries auto-injected system fields you did not define:
`DataSource__c`, `InternalOrganization__c`, and the `cdp_sys_*` and `KQ_*` families. They are
platform bookkeeping, not ingestion mappings.

## Two SQL Constraints That Fail Confusingly

- **Table names must be double-quoted** in Data 360 SQL:
  `SELECT COUNT(*) FROM "ssot__Individual__dlm"`. Unquoted is a syntax error.
- **A hybrid-search `prefilter` only works on fields marked prefilter-capable when the index was
  created.** HNSW index parameters are read-only afterwards, so a prefilter that silently matches
  nothing means rebuilding the index, not fixing the query.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Materialising a large result set in one synchronous Apex transaction | `sfsqlquery` with an iterator and a queueable |
| Sending Direct API calls to the org URL | Use `dne_cdpInstanceUrl` — it is a different host |
| Looking for `queryId` in the submit response body on v3 | Read the `x-hyperdb-status` header |
| Offset pagination over a large result | Chunked retrieval |
| Fetching rows just to learn the column types | `GET /api/v3/query/{queryId}/metadata` |
| JSON for a very large result set | Apache Arrow via the `Accept` header |
| Re-running a query you already ran | Pass the `queryId` to `result_scan` and read the cache |
| String-concatenating SQL | `sqlParameters` with placeholders |
| Omitting `workloadName` | Set it — it is how Support finds your query |
| Reaching for the REST API from inside Apex | Apex has native surfaces that carry the user's permissions |
