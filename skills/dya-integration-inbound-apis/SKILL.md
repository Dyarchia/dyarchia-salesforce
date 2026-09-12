---
name: dya-integration-inbound-apis
description: Salesforce standard inbound APIs (Winter '27 / API v68.0) — how external systems read/write Salesforce data. REST API and the composite family, SOAP (enterprise vs partner), Bulk API 2.0, GraphQL, and the Connect/UI/Metadata/Tooling APIs; choosing among them, batching, and limits. Load only when the user explicitly invokes this skill by name (`dya-integration-inbound-apis`); do NOT auto-trigger on generic API or integration questions.
---

# Salesforce Inbound Standard APIs

These are the standard APIs external systems call to read and write Salesforce data. Custom
endpoints you author are `dya-integration-inbound-apex`; authentication is `dya-integration-auth`.
Follow every rule below.

References:

- `references/shared/metadata-and-api-versions.md` — the single source of truth for API version numbers and retirement dates.
- `references/shared/platform-deltas.md` — the release-coupled facts behind the rules here.
- `references/shared/governor-limits.md` — the transaction budget a composite call spends cumulatively.
- `references/rest-and-composite.md` — REST sObject operations and the full composite family (Composite, Composite Graph, Batch, sObject Collections, sObject Tree) with batching limits.
- `references/bulk-and-graphql.md` — the Bulk API 2.0 ingest and query job lifecycle, and the GraphQL API.

Who the calling integration user may be, and what their permissions let the call see, belongs to
`dya-permissions`.

---

## Platform Context — Winter '27 / API v68.0

| Change | Status | What it means |
|---|---|---|
| **`/latest` version alias** | GA | `/services/data/latest/sobjects/Account` resolves to the newest version. Convenient for exploration; **never pin production to it** — the contract then changes three times a year with no deploy on your side |
| **Bulk API 2.0 coverage extended** | GA | More standard objects, including additional marketing objects |
| **OAuth username-password flow retired** | Enforced **20 February 2027** | Any caller posting `grant_type=password` stops receiving a token. See `dya-integration-auth` |
| **Update Instanced URLs in API Traffic** | Postponed to Spring '27 | Callers must address the org's My Domain URL, not an instance URL. Test it now: Setup › My Domain › Redirections › *Block API traffic that uses an incorrect instanced URL* |

Standing facts:

- **Target 68.0 for new integrations; 41.0 is the hard floor.** The version is the `vXX.X` in
  `/services/data/vXX.X/`. Dates and status live in `references/shared/metadata-and-api-versions.md`
  and nowhere else — do not restate them.
- **SOAP `login()` retires 1 June 2027** for API 31.0–64.0, a year before the versions themselves.
  SOAP accepts a JWT OAuth access token in the session header, so nothing justifies keeping it.
- **GraphQL mutations are GA** and can reference any field an earlier operation returned, not just
  the record id, so a parent and child are created and linked in one round trip.
- **Connect REST API** draws on the per-org 24-hour Platform API pool, except Chatter-touching
  requests. HTTPS is mandatory.

---

## 1. Pick the API

| Requirement | API |
|---|---|
| CRUD / query / search on records, JSON | **REST API** |
| Strongly-typed contract, legacy Java/.NET tooling, XML | **SOAP API** |
| >10,000 records, ETL, loads/extracts | **Bulk API 2.0** |
| Multiple related operations in one round trip | **REST Composite family** |
| Graph-shaped query/mutation, fetch only needed fields | **GraphQL API** |
| Records + layout + metadata in one response | **UI API** |
| Feeds, communities, many product APIs | **Connect REST API** |
| Deploy/retrieve org configuration | **Metadata API** |
| Fine-grained metadata, IDE-style live edits | **Tooling API** |

Default to **REST**; **Bulk 2.0** past 10k records; **Composite** to cut round trips; **GraphQL**
when payload shape matters.

---

## 2. REST API

The primary HTTP/JSON data API at `/services/data/vXX.X/`: single-record CRUD, SOQL/SOSL query,
search, describe, limits.

```
GET    /services/data/v68.0/sobjects/Account/{id}
POST   /services/data/v68.0/sobjects/Account
PATCH  /services/data/v68.0/sobjects/Account/{id}
GET    /services/data/v68.0/query/?q=SELECT+Id,Name+FROM+Account+WHERE+...
```

- **Upsert by external id** for idempotency: `PATCH /sobjects/Account/External_Id__c/{value}`.
- Page query results via `nextRecordsUrl`.
- Every call spends daily API allocation. Collapse chatty access with the composite family below or
  Bulk (§4).

### The composite family — choose by shape

| Resource | Max | Atomic? | Reference passing | Use |
|---|---|---|---|---|
| **Composite** | 25 subrequests | `allOrNone` optional | yes (across subrequests) | mixed ops that depend on each other |
| **Composite Graph** | 500 nodes | each graph is its own transaction | yes | large dependent graphs of records |
| **Composite Batch** | 25 subrequests | no | no | independent ops, one round trip |
| **sObject Collections** | 200 records | optional | no | same-shape bulk-ish CRUD |
| **sObject Tree** | 200 records, 5 levels | all-or-nothing | n/a | nested parent-child insert |

Governor limits — SOQL, DML, CPU — apply **cumulatively** across every subrequest of a composite
call. Full patterns in `references/rest-and-composite.md`.

---

## 3. SOAP API

The XML/SOAP data API, for strongly-typed or legacy consumers.

- **Enterprise WSDL** — typed to *your* org's schema; regenerate after every metadata change. For a
  single-org, tightly-integrated client.
- **Partner WSDL** — generic and loosely typed, for multi-org tools and ISVs.
- **Authenticate with OAuth.** SOAP accepts a JWT access token in the session header, and
  **`login()` retires Summer '27** — never build a new integration on it.
- Prefer REST for new work unless a consumer requires WSDL/SOAP.

---

## 4. Bulk API 2.0

Asynchronous, CSV-based, for large volumes. Lifecycle: **create job → upload CSV → mark complete →
poll status → get results**, processed in 10k-record chunks on a separate async limit pool.

- Use it past **10,000 records**: initial loads, migrations, nightly extracts.
- ~**15,000 batches / 24 h** shared with Bulk 1.0; **150 MB** per uploaded file.
- Bulk query handles large extracts. Prefer 2.0 over 1.0 for all new work.

Full lifecycle in `references/bulk-and-graphql.md`.

---

## 5. GraphQL API

Graph-shaped queries and mutations. It runs over UI API, so it respects FLS and layout rules and
covers UI-API objects.

- **Queries GA; mutations GA** — create, update and delete on UI-API-supported objects.
- A mutation can reference any field from an earlier operation in the same request (`@{ref...}`), so
  a parent and child are created and linked in one round trip.
- Use it when the client wants exactly the fields it needs — mobile, bandwidth-sensitive — or reads
  several objects at once. Child-relationship creation in a single mutation is not supported.

---

## 6. Connect, UI, Metadata, Tooling

- **Connect REST API** — Chatter feeds, Experience Cloud and many product APIs (Commerce, Revenue).
  On the per-org 24 h pool, except Chatter.
- **UI API** — returns records, metadata and layout together, and powers Lightning Data Service. For
  custom UIs that must honour layouts and FLS without re-deriving metadata.
- **Metadata API** — deploys and retrieves metadata as zipped XML; the basis for SFDX and DevOps
  Center. Coarse-grained, for releases.
- **Tooling API** — fine-grained and per-component: compile a class, run anonymous Apex. Used by
  IDEs and Workbench for live, surgical edits.

---

## 7. Decision Matrix — Quick Reference

| Need | API | Atomic | Volume |
|---|---|---|---|
| Single record CRUD | REST sObject | n/a | 1 |
| Run a SOQL query | REST query | n/a | up to query limits |
| Dependent multi-op write | Composite | optional | ≤25 |
| Large dependent record graph | Composite Graph | per graph | ≤500 nodes |
| Same-shape bulk CRUD, 1 call | sObject Collections | optional | ≤200 |
| Nested parent-child insert | sObject Tree | yes | ≤200 |
| >10k records load/extract | Bulk API 2.0 | per job | millions |
| Field-precise/graph read | GraphQL | n/a | query limits |
| Records + layout in one call | UI API | n/a | — |
| Deploy config | Metadata API | per deploy | — |
| Live metadata edit | Tooling API | n/a | — |
| Legacy WSDL consumer | SOAP API | optional | — |

---

## 8. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Looping single REST calls for many records | Composite / sObject Collections / Bulk 2.0 |
| REST for a 50k-record load | Bulk API 2.0 |
| Bulk API for 5 records | REST (Bulk overhead isn't worth it) |
| SOAP `login()` for auth | OAuth (JWT bearer) + External Client App |
| Blind insert on re-sent data | Upsert by external id |
| New build on Bulk API 1.0 | Bulk API 2.0 |
| Separate REST calls that must be atomic | Composite with `allOrNone` / Composite Graph |
| Building on API version below 41.0 | The current version, 68.0 |
| Pinning a production integration to `/latest` | An explicit version you upgrade deliberately |
| Assuming an integration user sees everything | Its own object and field access governs the call — see `dya-permissions` |
| Over-fetching whole sObjects when a few fields suffice | GraphQL field selection |

---

## Summary — The Five Commandments

1. **REST is the default; Bulk past 10k; Composite to cut round trips; GraphQL for field-precise/graph access.**
2. **Pick the composite resource by shape** — dependent (Composite/Graph), independent (Batch), same-shape (Collections), nested insert (Tree); governor limits are cumulative.
3. **SOAP only for WSDL/legacy consumers**, and never on `login()` — OAuth + ECA.
4. **Idempotency via upsert on external id** on every write path.
5. **Target a current API version** — 68.0 for new work, 41.0 as the absolute floor — pinned explicitly, never `/latest`, and authenticated with OAuth. See `dya-integration-auth`.
