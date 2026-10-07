# The Omni-Channel Data Model

Every object in the routing chain, with the fields that decide behaviour. The chain itself is in
SKILL.md §1.

## `ServiceChannel` — what is routable

A `ServiceChannel` declares that an sObject type can enter routing. **One channel per
`RelatedEntityType`** — the platform enforces it; a second for the same entity fails rather than
layering.

Standard DeveloperNames:

| DeveloperName | Entity |
|---|---|
| `Cases` | Case |
| `sfdc_liveagent` | LiveChatTranscript |
| `sfdc_livemessage` | MessagingSession |
| `sfdc_phone` | VoiceCall |

**Incident ships none.** If ITSM work needs routing, the channel is yours to author.

Key fields: `RelatedEntityType`, `capacityModel` (`TAB_BASED` | `STATUS_BASED`), `label`.

## The queue — two objects, not one

```text
Group (Type = 'Queue')     the queue record itself
QueueSobject               one row per sObject type the queue accepts
```

A queue with no matching `QueueSobject` row silently accepts nothing — a frequent cause of "the
queue exists and work never arrives".

Queue membership — which users can receive from it — is ordinary group membership, and the visibility
of the resulting records follows the sharing model. See `references/shared/sharing-and-access.md`.

## `QueueRoutingConfig` — how work leaves

| Field | Meaning |
|---|---|
| `RoutingModel` | `MostAvailable` (the agent with most spare capacity) or `LeastActive` (fewest open items) |
| `CapacityWeight` | What one item from this queue costs against an agent's budget |
| `IsAttributeBased` | Switches the queue to skills-based routing |
| `RoutingPriority` | Lower routes first across queues |

`MostAvailable` spreads load. For conversational work, `LeastActive` usually serves customers better:
it avoids an agent juggling six chats at 50% attention each.

## `PendingServiceRouting` — the waiting room

A transient record: "this item is waiting for an agent". It appears when work is routed and
disappears on assignment. A backlog signals that capacity, not configuration, is the constraint —
the chain works and nobody is free.

## `AgentWork` — the assignment and its history

An item's assignment to an agent, and its audit trail: when it was pushed, accepted, declined,
closed. Supervisor dashboards read it; query it to answer "who had this, and when".

Its OWD matters: supervisors see only the `AgentWork` records sharing grants them, so an empty
supervisor console is usually a sharing problem, not a routing one.

## The agent side

### `ServicePresenceStatus`

The statuses an agent can select — "Available - Chat", "Available - Phone", "Busy", "Break". Each
status declares which `ServiceChannel`s it accepts work from, so an agent can be available for chat
and not for calls.

### `PresenceUserConfig`

Which statuses an agent may use, and **`Capacity`, the agent's total budget** (the channel declares
the cost per item). It is assigned per user, usually through a `PresenceUserConfigUser` association.

## Skills-based routing

```text
WorkSkillRouting    the skills a work item requires
SkillUser           grants a skill, at a level, to a user
```

Combined with `QueueRoutingConfig.IsAttributeBased = true`, routing matches required against granted
rather than taking the next available agent. Requires `enableOmniSkillsRouting` in
`Settings:OmniChannel`.

Unlike `ServiceChannel`, **`WorkSkillRouting` exposes a queryable `Metadata` field** through the
Tooling API — see `references/omni-gotchas.md` for why that asymmetry matters.

## Supervisor configuration

| Object | Purpose |
|---|---|
| `OmniSupervisorConfig` | A supervisor console configuration |
| `OmniSupervisorConfigAction` | Which actions a supervisor may take |
| `OmniSupervisorConfigTab` | Which tabs appear |

The shipped permission set is **`ContactCenterSupervisor`**. It grants the console, not the records:
pair it with `AgentWork` sharing so supervisors see their team's work.
