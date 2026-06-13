# REST & the Composite Family — Reference (API v67.0)

Load from `decimatio-integration-inbound-apis` when building multi-operation REST integrations. Authentication is covered in `decimatio-integration-auth`; all examples assume a valid OAuth bearer token and a current API version.

## sObject Basics

```
# Create
POST /services/data/v67.0/sobjects/Account
{ "Name": "Acme", "External_Id__c": "A-1001" }

# Upsert by external id (idempotent — safe to retry)
PATCH /services/data/v67.0/sobjects/Account/External_Id__c/A-1001
{ "Name": "Acme (updated)" }

# Query + pagination
GET /services/data/v67.0/query/?q=SELECT+Id,Name+FROM+Account+ORDER+BY+CreatedDate+LIMIT+200
# → response has "done": false and "nextRecordsUrl"; GET that URL for the next page
```

**Always upsert by external id on inbound writes** so a re-sent message updates rather than duplicates.

## Composite — Dependent Operations, One Round Trip

Up to **25 subrequests**; later subrequests can reference earlier results via `@{refId.field}`; optional `allOrNone` for atomic rollback. Counts as one API call but governor limits accumulate across subrequests.

```
POST /services/data/v67.0/composite
{
  "allOrNone": true,
  "compositeRequest": [
    { "method": "POST", "url": "/services/data/v67.0/sobjects/Account",
      "referenceId": "newAcct", "body": { "Name": "Acme" } },
    { "method": "POST", "url": "/services/data/v67.0/sobjects/Contact",
      "referenceId": "newCon",
      "body": { "LastName": "Smith", "AccountId": "@{newAcct.id}" } }
  ]
}
```

## Composite Graph — Large Dependent Graphs

Up to **500 nodes**; each graph executes as its **own transaction** (one graph failing doesn't roll back another). Use for big, interdependent record sets that exceed Composite's 25-subrequest cap.

```
POST /services/data/v67.0/composite/graph
{ "graphs": [ { "graphId": "g1", "compositeRequest": [ /* up to 500 nodes */ ] } ] }
```

## Composite Batch — Independent Operations

Up to **25 independent subrequests**, no reference passing, no shared rollback. Use to collapse unrelated calls into one round trip.

## sObject Collections — Same-Shape Bulk CRUD

Up to **200 records** per call (create/update/delete/upsert), optional `allOrNone`. The sweet spot between single-record REST and Bulk API for moderate volumes in a synchronous context.

```
POST /services/data/v67.0/composite/sobjects
{ "allOrNone": false,
  "records": [
    { "attributes": {"type":"Account"}, "Name": "A" },
    { "attributes": {"type":"Account"}, "Name": "B" }
  ] }
```

## sObject Tree — Nested Insert

Up to **200 records** across nested parent-child structures up to **5 levels**, insert only, all-or-nothing. Use to create a parent and its children in one transactional call.

## Choosing Within the Family

| Shape of work | Resource |
|---|---|
| Steps depend on each other, want atomic | Composite (`allOrNone`) |
| Big dependent graph (>25 ops) | Composite Graph |
| Unrelated ops, just save round trips | Composite Batch |
| Many records of one shape | sObject Collections |
| Parent + nested children insert | sObject Tree |

## Limits & Hygiene

- Governor limits (SOQL/DML/CPU) are **cumulative** across a composite call — a 25-subrequest Composite can still hit per-transaction limits.
- Composite Graph isolates transactions per graph; use it when partial success across graphs is acceptable.
- Every subrequest counts toward CPU/DML; keep payloads lean and project only needed fields on reads.
- Prefer one composite/collection call over N single calls to conserve the daily API allocation.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| N single POSTs for related records | One Composite with reference ids |
| >25 dependent ops via repeated Composite calls | Composite Graph (≤500 nodes) |
| sObject Collections for 5,000 records | Bulk API 2.0 |
| Blind insert on retry | Upsert by external id |
| Ignoring cumulative governor limits in Composite | Size subrequests with limits in mind |
