# Pub/Sub API — Reference (API v67.0)

Load from `dya-integration-events` when an external system must publish or subscribe to Salesforce events. The Pub/Sub API is the strategic gRPC interface for Platform Events, Change Data Capture, and Real-Time Event Monitoring.

## Why Pub/Sub API

- **gRPC / HTTP-2**, **Avro** binary payloads — compact and fast versus the legacy CometD Streaming API.
- **One interface** for Platform Events, CDC, and RTEM.
- **Bidirectional streaming** with **pull-based flow control**: the subscriber asks for a number of events (`num_requested`, **max 100 per fetch**) and the server delivers up to that many, so the client never gets flooded.
- Client libraries across ~11 languages; you generate stubs from the published `.proto`.

## Core RPCs

| RPC | Purpose |
|---|---|
| `GetSchema` | Fetch the Avro schema for a topic (needed to decode/encode payloads) |
| `Subscribe` | Stream events from a topic, controlling flow with `num_requested` |
| `Publish` / `PublishStream` | Publish events to a Platform Event topic |
| `GetTopic` | Topic metadata (can publish/subscribe, schema id) |

## Subscribe Flow (conceptual)

1. Authenticate (OAuth) and open a gRPC channel to the Pub/Sub endpoint, passing the access token, instance URL, and tenant id in metadata.
2. `GetTopic` / `GetSchema` for the channel (e.g. `/event/Order_Placed__e` or `/data/AccountChangeEvent`).
3. Open a `Subscribe` stream; send a `FetchRequest` with `num_requested` (≤100) and a **replay preset**:
   - `LATEST` — only new events from now.
   - `EARLIEST` — from the start of the 72 h retention window.
   - `CUSTOM` — from a specific stored **replay id**.
4. For each received event, **decode the Avro payload** using the schema, process it **idempotently**, and **persist the replay id**.
5. Send another `FetchRequest` to pull more (flow control) — keep the stream topped up.

## Replay & Recovery

- Events are retained **72 hours**. Store the **last successfully processed replay id**; on reconnect, resume with `CUSTOM` from that id to avoid gaps and duplicates-beyond-necessary.
- Beyond 72 h (or first-time backfill), you cannot replay from the bus — run a **reconciliation** (Bulk API query / CDC gap-fill) to resync.

## Publishing Platform Events via Pub/Sub

- Encode your payload with the topic's Avro schema and call `Publish`/`PublishStream`.
- Each publish returns a result with a replay id (and error per event on failure). Handle partial failures.

## External Subscriber Pattern (typical ETL/replication)

```
[Salesforce] --CDC/PE--> [Event Bus] <--gRPC Subscribe-- [Your service]
                                             |
                                             +-- decode Avro
                                             +-- idempotent upsert into target store
                                             +-- persist replay id
```

This is the standard way to keep an external database/warehouse in near-real-time sync without polling.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| CometD Streaming API for a new external subscriber | Pub/Sub API (gRPC) |
| Not persisting the replay id | Store last processed replay id; resume on reconnect |
| Requesting more than 100 events per fetch | `num_requested` ≤ 100; pull in a loop |
| Ignoring Avro schema versioning | `GetSchema` by schema id; handle schema evolution |
| Assuming no duplicates | Idempotent processing (at-least-once delivery) |
| Relying on the bus for >72 h history | Reconcile via Bulk query / gap-fill |
