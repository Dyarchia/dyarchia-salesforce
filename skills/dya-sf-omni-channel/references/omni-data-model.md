# The Omni-Channel Data Model

## `ServiceChannel` — what is routable

**One channel per `RelatedEntityType`**: a second for the same entity fails rather than layering.
The standard channels:

| DeveloperName | Entity |
|---|---|
| `Cases` | Case |
| `sfdc_liveagent` | LiveChatTranscript |
| `sfdc_livemessage` | MessagingSession |
| `sfdc_phone` | VoiceCall |

**Incident ships none**; ITSM routing needs a channel you author.

Key fields: `RelatedEntityType`, `capacityModel` (`TAB_BASED` | `STATUS_BASED`), `label`.

## The queue — two objects, not one

```text
Group (Type = 'Queue')     the queue record itself
QueueSobject               one row per sObject type the queue accepts
```

Add a `QueueSobject` row for every routed sObject type; a queue with no matching row silently
accepts nothing, so work never arrives.

Queue membership — which users can receive from it — is ordinary group membership, and the visibility
of the resulting records follows the sharing model. See `references/shared/sharing-and-access.md`.

## `QueueRoutingConfig` — how work leaves

| Field | Meaning |
|---|---|
| `RoutingModel` | `MostAvailable` (the agent with most spare capacity) or `LeastActive` (fewest open items) |
| `CapacityWeight` | What one item from this queue costs against an agent's budget |
| `IsAttributeBased` | Switches the queue to skills-based routing |
| `RoutingPriority` | Lower routes first across queues |

For conversational work, prefer `LeastActive`, so no agent juggles many chats at once. `MostAvailable`
spreads load.

## `PendingServiceRouting` — the waiting room

It appears when work is routed and disappears on assignment. A backlog means capacity, not
configuration, is the constraint.

## `AgentWork` — the assignment and its history

Query it to answer "who had this, and when": it records when an item was pushed, accepted, declined
and closed. Supervisor dashboards read it.

Treat an empty supervisor console as a sharing problem first, not a routing one: supervisors see only
the `AgentWork` records sharing grants them.

## The agent side

### `ServicePresenceStatus`

The statuses an agent can select — "Available - Chat", "Available - Phone", "Busy", "Break". Each
status declares which `ServiceChannel`s it accepts work from, so an agent can be available for chat
and not for calls.

### `PresenceUserConfig`

Assigned per user, usually through a `PresenceUserConfigUser` association.

## Skills-based routing

Unlike `ServiceChannel`, **`WorkSkillRouting` exposes a queryable `Metadata` field** through the
Tooling API, so a helper written for one type and reused for the other silently returns empty.

## Supervisor configuration

| Object | Purpose |
|---|---|
| `OmniSupervisorConfig` | A supervisor console configuration |
| `OmniSupervisorConfigAction` | Which actions a supervisor may take |
| `OmniSupervisorConfigTab` | Which tabs appear |

Pair the shipped permission set, **`ContactCenterSupervisor`**, with `AgentWork` sharing so
supervisors see their team's work; it grants the console, not the records.
