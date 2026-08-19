# Integration Patterns & Version Retirement — Reference (Summer '26)

Load from `dya-integration-overview` when you need the pattern detail behind a choice, or the precise API-version-retirement facts.

## The Six Patterns in Depth

### 1. Remote Process Invocation — Request and Reply
Salesforce calls a remote system and **waits** for a response, then continues in the same transaction. Use for real-time validation, address lookup, payment authorisation. Implement with synchronous Apex HTTP callout or Flow HTTP Callout. Constraints: callout-after-DML rule, 120 s cumulative timeout, the user/transaction blocks. Keep the remote call fast and the failure path explicit.

### 2. Remote Process Invocation — Fire and Forget
Salesforce notifies a remote system and does **not** wait. Use for "order placed → tell the warehouse." Implement with a Platform Event (preferred — decoupled, durable) or an async Queueable callout. The remote system must be idempotent because delivery may retry.

### 3. Batch Data Synchronization
Bulk movement of data on a schedule. Use for nightly syncs, initial loads, data warehousing. Implement with Bulk API 2.0 (in/out), ETL tools, or MuleSoft. Design for restartability and dedupe by external id.

### 4. Remote Call-In
An external system creates/reads/updates/deletes Salesforce data. Use for "the ERP pushes invoices into SF." Implement with REST/SOAP/Bulk for standard ops, or Apex REST for bespoke transactional contracts. Govern with External Client Apps + OAuth and least-privilege permission sets.

### 5. UI Update Based on Data Changes
A user's UI (or an external subscriber) updates when data changes, without polling. Use for live dashboards, "another user changed this record." Implement with Change Data Capture / Platform Events over the Pub/Sub API (or `lightning/empApi` in LWC for in-org UI).

### 6. Data Virtualization
Salesforce reads external data **in place**, on demand, without storing it. Use for large external datasets that must appear as records but shouldn't be copied. Implement with Salesforce Connect (External Objects) over OData or an Apex custom adapter.

## Choosing Sync vs Async — Checklist

Choose **synchronous** only if ALL hold:
- A human or the next transaction step genuinely needs the result now.
- The remote system is reliably fast (well under the timeout budget).
- You can tolerate the caller failing if the remote system is down.

Otherwise choose **asynchronous / event-driven** and design:
- Idempotent consumers (dedupe key).
- A retry/replay strategy (Platform Event 72h replay, dead-letter handling).
- Reconciliation (a periodic batch sync that heals missed events).

## API Version Retirement — Precise Facts

| Item | Status (as of Summer '26) |
|---|---|
| Platform API 21.0–30.0 (REST `/services/data/`, SOAP, Bulk) | **Retired** |
| Platform API 31.0–40.0 | **Deprecate Summer '27, retire Summer '28** — move to 41.0+ |
| SOAP `login()` for API 31.0–64.0 | **Retires Summer '27**; already gone in 65.0+ |
| "Any API Auth" user permission | Gates SOAP `login()`; default-enforced in new orgs |
| Custom Apex REST (`@RestResource`) / Apex SOAP web services | **NOT retired** — explicitly excluded from version retirement |
| Apex classes, triggers, Visualforce pages | **NOT retired** — keep their saved version |
| Salesforce-to-Salesforce native feature | Support ends Summer '26; stops functioning Spring '27 |

**The critical distinction:** version retirement targets the numeric version of the *standard platform endpoints* and the SOAP *login* method. It does not deprecate the *ability to build* custom Apex services. A `@RestResource` class keeps working; only a class explicitly bumped to API 67.0 changes *behaviour* (user-mode/with-sharing), which is a security change, not a retirement.

## Governor Limits That Shape Integration Design

- **100 callouts** per Apex transaction; **120 s** cumulative callout timeout; **6 MB / 12 MB** request+response (sync/async). (The separate "10" limit is concurrent synchronous requests running >5 s — not the per-transaction maximum.)
- **Bulk API 2.0**: ~15,000 batches / 24 h shared with Bulk 1.0; 150 MB per file; 10k-record chunks.
- **Composite**: 25 subrequests (governor limits cumulative across them); **Composite Graph**: 500 nodes, each graph its own transaction.
- **Pub/Sub / Platform Events**: 72 h event retention; subscribe fetch max 100 events per request.
- Daily API request allocation is per-org/24 h and now includes most Connect REST API calls.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Sync callout for a notification | Fire-and-forget Platform Event |
| No reconciliation behind an event integration | Periodic batch sync to heal gaps |
| Treating version retirement as deprecating Apex REST | It targets endpoint versions + SOAP login(), not the feature |
| Per-record REST in a loop | Composite / Bulk |
| Ignoring idempotency on retried messages | Dedupe by external id / replay id |
