---
name: dya-integration-inbound-apis
description: Salesforce standard inbound APIs (Summer '26 / API v67.0) — how external systems read/write Salesforce data. REST API and the composite family, SOAP (enterprise vs partner), Bulk API 2.0, GraphQL, and the Connect/UI/Metadata/Tooling APIs; choosing among them, batching, and limits. Load only when the user explicitly invokes this skill by name (`dya-integration-inbound-apis`); do NOT auto-trigger on generic API or integration questions.
---

# Salesforce Inbound Standard APIs

You are an expert on Salesforce's standard, platform-provided APIs that external systems call to read and write data. This skill covers the **out-of-the-box** APIs — for custom endpoints you author, see `dya-integration-inbound-apex`; for authentication, `dya-integration-auth`. Follow every rule below.

References:
- `references/rest-and-composite.md` — REST sObject ops and the full composite family (Composite, Composite Graph, Batch, sObject Collections, sObject Tree) with batching limits.
- `references/bulk-and-graphql.md` — Bulk API 2.0 ingest/query job lifecycle and the GraphQL API (queries + mutations).

---

## Platform Context — Summer '26 / API v67.0

- **Target API 41.0+ (ideally current 67.0).** Versions 21.0–30.0 are retired; 31.0–40.0 retire Summer '28. The version is the `vXX.X` in `/services/data/vXX.X/`.
- **SOAP `login()` retires Summer '27** (31.0–64.0). Authenticate with OAuth instead; SOAP API now also accepts a JWT OAuth access token in the session header. See `dya-integration-auth`.
- **GraphQL mutations are GA** and can now reference any field returned by an earlier operation in the same request (not just the record id) — enabling linked-record creation in one round trip.
- **Connect REST API** calls now draw from the per-org/24 h Platform API limit pool (except Chatter-touching requests).
- **HTTPS mandatory.** **My Domain login-URL enforcement** for API traffic is postponed to Winter '27, but build against My Domain URLs now.

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

Default to **REST** for general-purpose access, **Bulk 2.0** past 10k records, **Composite** to cut round trips, **GraphQL** when payload shape/efficiency matters.

---

## 2. REST API

The primary HTTP/JSON data API at `/services/data/vXX.X/`. Covers single-record CRUD, SOQL/SOSL query, search, describe, and limits.

```
GET    /services/data/v67.0/sobjects/Account/{id}
POST   /services/data/v67.0/sobjects/Account
PATCH  /services/data/v67.0/sobjects/Account/{id}
GET    /services/data/v67.0/query/?q=SELECT+Id,Name+FROM+Account+WHERE+...
```

- **Upsert by external id** for idempotency: `PATCH /sobjects/Account/External_Id__c/{value}`.
- Page query results via `nextRecordsUrl`.
- Each call counts against the daily API allocation — collapse chatty access with the composite family (§3) or Bulk (§4).

### The composite family — choose by shape

| Resource | Max | Atomic? | Reference passing | Use |
|---|---|---|---|---|
| **Composite** | 25 subrequests | `allOrNone` optional | yes (across subrequests) | mixed ops that depend on each other |
| **Composite Graph** | 500 nodes | each graph is its own transaction | yes | large dependent graphs of records |
| **Composite Batch** | 25 subrequests | no | no | independent ops, one round trip |
| **sObject Collections** | 200 records | optional | no | same-shape bulk-ish CRUD |
| **sObject Tree** | 200 records, 5 levels | all-or-nothing | n/a | nested parent-child insert |

Governor limits (SOQL, DML, CPU) apply **cumulatively** across all subrequests in a composite call. Full patterns in `references/rest-and-composite.md`.

---

## 3. SOAP API

XML/SOAP data API for strongly-typed or legacy consumers.

- **Enterprise WSDL** — strongly typed to *your* org's schema; regenerate after metadata changes. Best for a single-org tightly-integrated client.
- **Partner WSDL** — generic/loosely typed; for multi-org tools and ISVs.
- **Auth:** use OAuth (SOAP now accepts a JWT access token in the session header). **`login()` retires Summer '27** — never build new integrations on it.
- Prefer REST for new work unless a consumer specifically requires WSDL/SOAP.

---

## 4. Bulk API 2.0

Asynchronous, CSV-based, for large volumes. Job lifecycle: **create job → upload CSV → mark complete → poll status → get results**. Processes in 10k-record chunks on a separate async limit pool.

- Use past **10,000 records**; for initial loads, migrations, nightly extracts.
- ~**15,000 batches / 24 h** shared with Bulk 1.0; **150 MB** per uploaded file.
- Bulk query for large extracts. Prefer 2.0 over 1.0 for all new work.

Full lifecycle in `references/bulk-and-graphql.md`.

---

## 5. GraphQL API

Graph-shaped queries and mutations; runs over UI API, so respects FLS/layout rules and supports UI-API objects.

- **Queries GA**; **mutations GA** (create/update/delete) for UI-API-supported objects.
- **Summer '26:** mutations can reference any field from an earlier operation in the same request (`@{ref...}`), so you can create a parent and child and link them in one round trip.
- Use when the client wants exactly the fields it needs (mobile, bandwidth-sensitive) or multi-object reads in one call. Child-relationship creation in a single mutation is not supported.

---

## 6. Connect, UI, Metadata, Tooling

- **Connect REST API** — Chatter feeds, Experience Cloud, and many product APIs (Commerce, Revenue, etc.). Now on the per-org/24 h limit pool (except Chatter).
- **UI API** — returns records + metadata + layout together; powers Lightning Data Service. Use for custom UIs that must honour layouts/FLS without re-deriving metadata.
- **Metadata API** — deploy/retrieve metadata as zipped XML; the basis for SFDX/DevOps Center. Coarse-grained; use for releases.
- **Tooling API** — fine-grained, per-component metadata (compile a class, run anonymous Apex); used by IDEs/Workbench. Use for live, surgical edits.

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
| Building on API version <41.0 | Current API version (67.0) |
| Over-fetching whole sObjects when a few fields suffice | GraphQL field selection |

---

## Summary — The Five Commandments

1. **REST is the default; Bulk past 10k; Composite to cut round trips; GraphQL for field-precise/graph access.**
2. **Pick the composite resource by shape** — dependent (Composite/Graph), independent (Batch), same-shape (Collections), nested insert (Tree); governor limits are cumulative.
3. **SOAP only for WSDL/legacy consumers**, and never on `login()` — OAuth + ECA.
4. **Idempotency via upsert on external id** on every write path.
5. **Target a current API version (41.0+, ideally 67.0)** and authenticate with OAuth — see `dya-integration-auth`.
