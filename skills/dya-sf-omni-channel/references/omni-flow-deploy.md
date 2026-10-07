# `routeWork`, Flow Types, and What Each Error Means

## The `routeWork` action

Passing two targets is a validation error, not a precedence rule. `agentId` bypasses the queue.

Besides the target, the action takes the work item Id, the `ServiceChannel`, and for
attribute-based routing the required skills.

## Flow process types and how each is invoked

| `processType` | Invoked by |
|---|---|
| `AutoLaunchedFlow` | The Actions REST API, Apex, another flow, a record change |
| `RecordAfterSave` | Record DML only — **not** invocable through the API |
| `RoutingFlow` | The platform, when a work item enters a queue |
| Screen flow | A user in a UI — **none of the above** |

To trigger routing from an external system, use an `AutoLaunchedFlow`, or have the system write the
record and let a `RecordAfterSave` flow fire.

`RoutingFlow` carries routing logic a `QueueRoutingConfig` cannot express.

## Error taxonomy

### Deploy and activation

| Symptom | Cause |
|---|---|
| `INVALID_TYPE` on any routing metadata | `enableOmniChannel` is off — see `references/omni-gotchas.md` |
| "the version you're trying to activate isn't the latest" | Another save landed between your read and your activate. Re-read the `FlowDefinition` and retry |

### Invocation

| Status | Cause |
|---|---|
| **404** | The flow is Draft or Obsolete. The Actions API only sees the **active** version |
| **400 `INVALID_TYPE`** | The flow is not an `AutoLaunchedFlow` — check the table above |
| **403** | The calling user lacks the **Run Flows** permission |

## Getting the active version

```sql
SELECT Id, DeveloperName, ActiveVersionId, LatestVersionId
FROM   FlowDefinition
WHERE  DeveloperName = '<name>'
```

Through the Tooling API. A null `ActiveVersionId` is the 404 above. `LatestVersionId` differing from
`ActiveVersionId` means an unactivated draft.
