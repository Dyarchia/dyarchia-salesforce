# `routeWork`, Flow Types, and What Each Error Means

The one place Omni-Channel has code: getting a record into routing from automation. It fails two
ways: the flow cannot be invoked the way you are invoking it, or it is not the version you think.

## The `routeWork` action

Pass **exactly one** target. The others must be null; passing two is a validation error rather than a
precedence rule.

| Parameter | Routes to |
|---|---|
| `queueId` / `queueLabel` | A queue — the human path |
| `agentId` | One named user, bypassing the queue |
| `botId` | A classic bot |
| `copilotId` | A copilot |
| `agentforceEmployeeAgentId` | An Agentforce employee agent |
| `digitalWorkerId` | An Agentforce Orchestrator digital worker |
| `externalConversationBotId` | An external conversation bot |

Besides the target, the action takes the routing attributes: the work item Id, the `ServiceChannel`,
and for attribute-based routing the required skills.

**Both directions matter.** `agentforceEmployeeAgentId` sends work *to* an agent; `queueId` from
inside an agent's escalation path sends it *to a person*. Modelling only the second leaves the agent
as a terminal node, rarely what anyone wants.

## Flow process types and how each is invoked

This table decides whether an invocation strategy can work at all; getting it wrong yields a 400 that
reads like a payload problem.

| `processType` | Invoked by |
|---|---|
| `AutoLaunchedFlow` | The Actions REST API, Apex, another flow, a record change |
| `RecordAfterSave` | Record DML only — **not** invocable through the API |
| `RoutingFlow` | The platform, when a work item enters a queue |
| Screen flow | A user in a UI — **none of the above** |

To trigger routing from an external system, the flow must be an `AutoLaunchedFlow`. A
`RecordAfterSave` flow cannot be called; have the external system write the record and let the flow
fire.

`RoutingFlow` is invoked *by Omni-Channel itself* when work reaches a queue: the hook for routing
logic a `QueueRoutingConfig` cannot express.

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

**404 misleads.** It reads as "the flow does not exist", but the flow exists and is not activated,
so the API cannot see it. Check activation before the name.

## Getting the active version

```sql
SELECT Id, DeveloperName, ActiveVersionId, LatestVersionId
FROM   FlowDefinition
WHERE  DeveloperName = '<name>'
```

Through the Tooling API. A null `ActiveVersionId` is the 404 above. `LatestVersionId` differing from
`ActiveVersionId` means an unactivated draft — the usual state of a flow someone edited and did not
activate.
