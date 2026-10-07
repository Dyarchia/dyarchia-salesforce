---
name: dya-sf-omni-channel
description: Salesforce Omni-Channel routing (Winter '27, API v68.0) — service channels, queues, routing configs, PendingServiceRouting, AgentWork, presence and capacity, skills-based routing, the routeWork Agentforce-to-human handoff. Applies to ServiceChannel, QueueRoutingConfig, PresenceUserConfig and ServicePresenceStatus metadata, PendingServiceRouting and AgentWork code, routeWork Flow actions. Load before creating or editing anything in this scope.
---

# Salesforce Omni-Channel

Omni-Channel decides **which agent gets which piece of work**. Its job starts when a conversation,
case or call needs a human and ends when that human accepts it. Designing the agent that handles
the conversation before then belongs to `dya-sf-agentforce`. Digital Engagement channel setup, ITSM
object models and the Service Console's UI are out of scope. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults routing Apex and Flow inherit.
- `references/shared/sharing-and-access.md` — the access model behind queue membership, `AgentWork` visibility and supervisor scope.
- `references/omni-data-model.md` — every object in the chain with its fields, the standard `ServiceChannel` DeveloperNames, capacity, skills-based routing and supervisor configuration.
- `references/omni-gotchas.md` — the read-path asymmetries and v66 element renames, where most deploys fail.
- `references/omni-flow-deploy.md` — the `routeWork` action's targets, flow process types and how each is invoked, and the deploy and invocation error taxonomy.

---

## Platform Context — Winter '27 / API v68.0

Omni-Channel's programmatic surface is metadata and Tooling API, not Apex. The only code lives in
the routing flow.

| Change | Status | Notes |
|---|---|---|
| `routeWork` targets an **Agentforce employee agent** (`agentforceEmployeeAgentId`) | GA | The declarative handoff from a human queue *to* an agent, not only the reverse |
| `routeWork` targets an Agentforce Orchestrator **digital worker** (`digitalWorkerId`) | GA | Same mechanism, for orchestrated multi-agent work |
| `capacityModel` on `ServiceChannel` replaces `capacityWeight` | GA since v66 | Per-agent totals moved to `PresenceUserConfig.Capacity` — see `references/omni-gotchas.md` |
| Attribute-based (skills) routing via `WorkSkillRouting` | GA | Requires `enableOmniSkillsRouting` |

The `AiAgentDefinition` / `AiAgentDefinitionVersion` metadata types that carry an agent at 68.0 are
`dya-sf-agentforce`'s territory; Omni-Channel only needs the agent's Id to route to it.

---

## 1. The Routing Chain

```text
a work item        a Case, Lead, Order, MessagingSession, VoiceCall, or custom object record
    ↓
ServiceChannel     declares that this sObject type is routable at all
    ↓
Group (Type='Queue')  +  QueueSobject       the queue, and which sObjects it accepts
    ↓
QueueRoutingConfig    how work leaves the queue: routing model, priority, capacity cost
    ↓
PendingServiceRouting  a transient record: this item is waiting to be assigned
    ↓
AgentWork             the assignment itself, and the audit trail of it
```

Two agent-side objects decide whether an agent can receive work:

```text
ServicePresenceStatus   the statuses an agent can select (Available - Chat, Busy, …)
PresenceUserConfig      which statuses this agent may use, and their capacity
```

**Diagnose along the chain.** Work not routing is one of, checked in this order: no `ServiceChannel`
for the sObject, the queue does not accept it (`QueueSobject`), no `QueueRoutingConfig` on the
queue, no agent in an available status, or every eligible agent at capacity.

---

## 2. Enable Omni-Channel First

`Settings:OmniChannel` carries five toggles:

| Setting | Enables |
|---|---|
| `enableOmniChannel` | Omni-Channel itself |
| `enableOmniSkillsRouting` | Skills-based (attribute) routing |
| `enableOmniSecondaryRoutingPriority` | A second priority dimension on routing configs |
| `enableOmniStatusCapModel` | Status-based rather than tab-based capacity |
| `enableOmniAutoLoginPrompt` | Prompting an agent to go online at login |

**Deploy `enableOmniChannel` first, in its own step, and confirm it.** With
`enableOmniChannel = false`, every downstream metadata type rejects with `INVALID_TYPE`, and the error
names the deployed type, not the setting.

Do not debug why the login prompt is absent: `enableOmniAutoLoginPrompt` deploys and round-trips
cleanly but **does not currently drive the UI radio**.

---

## 3. `routeWork` — the Agentforce Seam

Use the `routeWork` Flow action to push a record into routing from automation; it is the boundary
with `dya-sf-agentforce`. Call it when an agent cannot help, and route through it when a queue should
be handled by an agent rather than a person.

Pass exactly one target:

| Target | Routes to |
|---|---|
| `queueId` / `queueLabel` | A queue, for a human |
| `agentId` | One named user directly |
| `botId` | A classic bot |
| `copilotId` | A copilot |
| **`agentforceEmployeeAgentId`** | An Agentforce employee agent |
| **`digitalWorkerId`** | An Agentforce Orchestrator digital worker |
| `externalConversationBotId` | An external conversation bot |

**Model both directions; the agent is not a terminal node.** Escalation from an agent to a person
and delegation from a person to an agent use the same action.

> Full parameter list, the flow process types that carry it, and the error taxonomy:
> `references/omni-flow-deploy.md`.

---

## 4. Capacity

Capacity decides when an agent is full. **Read per-agent capacity totals from
`PresenceUserConfig.Capacity`,** not from the channel.

- **Tab-based** (`capacityModel: TAB_BASED`) — each open work item costs its channel's weight.
- **Status-based** (`STATUS_BASED`, needs `enableOmniStatusCapModel`) — capacity is per presence
  status, for an agent who can take three chats *or* one call but not both.

The channel declares the *cost* of one item; the user config declares the *budget*.
`capacityWeight` is gone from `ServiceChannel` — see `references/omni-gotchas.md`.

---

## 5. Skills-Based Routing

Use attribute-based routing where the wrong agent means a transfer rather than a slower answer:
language, product line, regulatory certification. It matches a work item's required skills against
agents' skills instead of taking whoever is next.

- `QueueRoutingConfig.IsAttributeBased = true` switches a queue to it.
- `WorkSkillRouting` declares which skills a work item needs.
- `SkillUser` grants a skill, at a level, to a user.

Do not use it as a quality mechanism: each required skill narrows the eligible pool, and an item
matching nobody available waits rather than routing to a competent generalist.

---

## 6. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| Make a custom object routable | A `ServiceChannel` for that `RelatedEntityType` |
| Route work from automation | The `routeWork` Flow action |
| Hand a conversation from an agent to a person | `routeWork` with `queueId` |
| Hand work from a queue to an Agentforce agent | `routeWork` with `agentforceEmployeeAgentId` |
| Change how work leaves a queue | `QueueRoutingConfig` — `RoutingModel`, priority, `CapacityWeight` |
| Match work to qualified agents | `WorkSkillRouting` + `SkillUser`, with `IsAttributeBased` |
| Cap how much one agent can hold | `PresenceUserConfig.Capacity` |
| See what an agent is working on | `AgentWork` |
| Give supervisors a console | `OmniSupervisorConfig` and the `ContactCenterSupervisor` permission set |
| Find out why an item is not routing | Walk the chain in §1, in order |

---

## 7. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct approach |
|---|---|
| Deploying routing metadata before `enableOmniChannel` | Deploy the setting first; otherwise every type fails with `INVALID_TYPE` |
| Reading `capacityWeight` from `ServiceChannel` | It was replaced by `capacityModel` at v66; per-agent totals are on `PresenceUserConfig` |
| Tooling-SOQL for `ServiceChannel.Metadata` | Not queryable there — retrieve the metadata. `WorkSkillRouting.Metadata` **is** queryable |
| Two `ServiceChannel` records for one `RelatedEntityType` | One per entity type; the platform enforces it |
| Creating a `ServiceChannel` for Incident and expecting a standard one | Incident ships none — you author it |
| Passing two targets to `routeWork` | Exactly one; the others must be null |
| Treating an Agentforce agent as a terminal node | Routing goes both ways — model the escalation back to a person |
| Adding required skills to improve quality | Each one shrinks the eligible pool; an unmatched item waits instead of routing |
| Invoking a Draft or Obsolete flow through the Actions API | 404. Activate it first |
| Debugging `enableOmniAutoLoginPrompt` | It deploys and round-trips but does not drive the UI |

---

## Summary — The Five Commandments

1. **Learn the chain and diagnose along it** — channel, queue, routing config, pending routing,
   agent work. Every "it is not routing" question is a position on that list.
2. **Deploy `enableOmniChannel` first.** Nothing else deploys until it is on, and the error does not
   say so.
3. **Use `routeWork` as the seam with Agentforce, in both directions.** Escalating to a human and
   delegating to an agent are the same action with a different target.
4. **Set the capacity budget on the user and the cost on the channel.** Do not look for the total on
   `ServiceChannel`.
5. **Configure it as metadata, in order.** The read paths are asymmetric and several element names
   changed at v66 — check `references/omni-gotchas.md` before assuming a field exists.
