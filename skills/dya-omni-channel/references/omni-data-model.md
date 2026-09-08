# The Omni-Channel Data Model

Every object in the routing chain, with the fields that decide behaviour. The chain itself is in
SKILL.md §1; this is the detail behind each link.

## `ServiceChannel` — what is routable

A `ServiceChannel` declares that an sObject type can enter routing at all. **One channel per
`RelatedEntityType`** — the platform enforces it, so a second one for the same entity fails rather
than layering.

Standard DeveloperNames that ship with the platform:

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

A queue with no matching `QueueSobject` row silently accepts nothing. This is a frequent cause of
"the queue exists and work never arrives".

Queue membership — which users can receive from it — is ordinary group membership, and the visibility
of the resulting records follows the sharing model. See `references/shared/sharing-and-access.md`.

## `QueueRoutingConfig` — how work leaves

| Field | Meaning |
|---|---|
| `RoutingModel` | `MostAvailable` (the agent with most spare capacity) or `LeastActive` (fewest open items) |
| `CapacityWeight` | What one item from this queue costs against an agent's budget |
| `IsAttributeBased` | Switches the queue to skills-based routing |
| `RoutingPriority` | Lower routes first across queues |

`MostAvailable` spreads load; `LeastActive` keeps agents on fewer concurrent items. For anything
conversational, `LeastActive` usually gives a better customer experience because it avoids an agent
juggling six chats at 50% attention each.

## `PendingServiceRouting` — the waiting room

A transient record meaning "this item is waiting for an agent". It appears when work is routed and
disappears when it is assigned. A backlog of these is the signal that capacity, not configuration, is
the constraint — the chain is working and nobody is free.

## `AgentWork` — the assignment and its history

The record of an item being assigned to an agent, and the audit trail afterwards: when it was pushed,
accepted, declined, closed. This is what a supervisor dashboard reads and what you query to answer
"who had this, and when".

Its OWD matters: supervisors see only the `AgentWork` records sharing lets them see, so a supervisor
console that looks empty is usually a sharing question rather than a routing one.

## The agent side

### `ServicePresenceStatus`

The statuses an agent can select — "Available - Chat", "Available - Phone", "Busy", "Break". Each
status declares which `ServiceChannel`s it accepts work from, which is how an agent can be available
for chat and not for calls.

### `PresenceUserConfig`

Which statuses a given agent may use, and — importantly — **`Capacity`, the agent's total budget**.
The channel declares the cost per item; this declares how much the agent can hold. Assigning it is
per user, usually through a `PresenceUserConfigUser` association.

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

The shipped permission set is **`ContactCenterSupervisor`**. Combine it with `AgentWork` sharing so
the supervisor can actually see the work their team holds; the permission set alone grants the
console, not the records.
