# Integration Patterns & Version Retirement — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-overview` for the pattern detail behind a choice, or the API-version-retirement facts.

## The Six Patterns in Depth

### 1. Remote Process Invocation — Request and Reply
Salesforce calls a remote system, **waits** for the response, and continues in the same transaction. Use for real-time validation, address lookup, payment authorisation. Implement with a synchronous Apex HTTP callout or Flow HTTP Callout. Constraints: callout-after-DML rule, 120 s cumulative timeout, the user/transaction blocks. Keep the remote call fast and the failure path explicit.

### 2. Remote Process Invocation — Fire and Forget
Salesforce notifies a remote system and does **not** wait. Use for "order placed → tell the warehouse." Implement with a Platform Event (preferred — decoupled, durable) or an async Queueable callout. The remote system must be idempotent: delivery may retry.

### 3. Batch Data Synchronization
Scheduled bulk data movement. Use for nightly syncs, initial loads, data warehousing. Implement with Bulk API 2.0 (in/out), ETL tools, or MuleSoft. Design for restartability and dedupe by external id.

### 4. Remote Call-In
An external system creates/reads/updates/deletes Salesforce data. Use for "the ERP pushes invoices into SF." Implement with REST/SOAP/Bulk for standard ops, Apex REST for bespoke transactional contracts. Govern with External Client Apps + OAuth and least-privilege permission sets.

### 5. UI Update Based on Data Changes
A user's UI (or an external subscriber) updates when data changes, without polling. Use for live dashboards, "another user changed this record." Implement with Change Data Capture / Platform Events over the Pub/Sub API (or `lightning/empApi` in LWC for in-org UI).

### 6. Data Virtualization
Salesforce reads external data **in place**, on demand, without storing it. Use for large external datasets that must appear as records but not be copied. Implement with Salesforce Connect (External Objects) over OData or an Apex custom adapter.

## Choosing Sync vs Async — Checklist

Choose **synchronous** only if ALL hold:
- A human or the next transaction step needs the result now.
- The remote system is reliably fast (well under the timeout budget).
- You can tolerate the caller failing if the remote system is down.

Otherwise choose **asynchronous / event-driven** and design:
- Idempotent consumers (dedupe key).
- A retry/replay strategy (Platform Event 72h replay, dead-letter handling).
- Reconciliation (a periodic batch sync that heals missed events).

## API Version Retirement — Precise Facts

The version numbers and dates live only in **`references/shared/metadata-and-api-versions.md`**, the
library's single source of truth. Never restate them here or in a skill body. The fragment carries the floor, the deprecated range, and
the two separate retirement dates (the versions themselves, and SOAP `login()` a year earlier).

| Item | Status |
|---|---|
| "Any API Auth" user permission | Gates SOAP `login()`; enforced by default in new orgs |
| Apex classes, triggers, Visualforce pages | **Not retired** — they keep their saved version |

Version retirement targets the numeric version in *standard platform endpoint* URLs, plus the SOAP
*login* method. Raising a class to 67.0 or above changes its *behaviour* (user mode and default
sharing): a security change, not a retirement.

## Governor Limits That Shape Integration Design

- **6 MB / 12 MB** request+response (sync/async). (The separate "10" limit is concurrent synchronous requests running >5 s — not the per-transaction maximum.)
- **Bulk API 2.0**: ~15,000 batches / 24 h shared with Bulk 1.0; 150 MB per file; 10k-record chunks.
- **Composite**: 25 subrequests (governor limits cumulative across them); **Composite Graph**: 500 nodes, each graph its own transaction.
- **Pub/Sub / Platform Events**: 72 h event retention; subscribe fetch max 100 events per request.
- Daily API request allocation is per-org/24 h and now includes most Connect REST API calls.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| No reconciliation behind an event integration | Periodic batch sync to heal gaps |
