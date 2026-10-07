# Pub/Sub API — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-events`.

## Flow Control and Clients

- **Pull-based flow control**: the subscriber requests `num_requested` events (**max 100 per fetch**) and the server delivers up to that many, so the client is never flooded.
- Client libraries across ~11 languages; generate stubs from the published `.proto`.

## Core RPCs

| RPC | Purpose |
|---|---|
| `GetSchema` | Fetch the Avro schema for a topic (needed to decode/encode payloads) |
| `Subscribe` | Stream events from a topic, controlling flow with `num_requested` |
| `Publish` / `PublishStream` | Publish events to a Platform Event topic |
| `GetTopic` | Topic metadata (can publish/subscribe, schema id) |
| `ManagedSubscribe` | Stream from a `ManagedEventSubscription` — **the platform tracks the replay position**, not you |

## Subscribe Flow (conceptual)

1. Authenticate (OAuth) and open a gRPC channel to the Pub/Sub endpoint, passing the access token, instance URL, and tenant id in metadata.
2. `GetTopic` / `GetSchema` for the channel (e.g. `/event/Order_Placed__e` or `/data/AccountChangeEvent`).
3. Open a `Subscribe` stream; send a `FetchRequest` with `num_requested` (≤100) and a **replay preset**:
   - `LATEST` — only new events from now.
   - `EARLIEST` — from the start of the 72 h retention window.
   - `CUSTOM` — from a specific stored **replay id**.
4. For each received event, **decode the Avro payload** using the schema, process it **idempotently**, and **persist the replay id**.
5. Send another `FetchRequest` to pull more (flow control), keeping the stream topped up.

## Replay & Recovery

- On reconnect, resume with `CUSTOM` from the **last successfully processed replay id**.
- Beyond 72 h, or for a first-time backfill, run a **reconciliation** (Bulk API query or CDC gap-fill).

### Or let the platform hold the position

`ManagedSubscribe` consumes a **`ManagedEventSubscription`**, identified by DeveloperName or Id, and
the replay position lives on the platform. That removes the most common source of duplicate or
skipped events — a consumer crashing between processing an event and persisting its replay id.

Prefer it for a long-lived subscriber. Keep `Subscribe` with manual replay bookkeeping when the
consumer already has durable state and wants the position committed in the same transaction as the
work.

Operational facts, element inventory and `topicName` formats: `references/cdc-metadata.md`.

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

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Requesting more than 100 events per fetch | `num_requested` ≤ 100; pull in a loop |
| Ignoring Avro schema versioning | `GetSchema` by schema id; handle schema evolution |
