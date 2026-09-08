---
name: dya-omni-channel
description: Salesforce Omni-Channel and Service Cloud routing (Winter '27 / API v68.0) — the routing chain from work item to agent (ServiceChannel, queues, QueueRoutingConfig, PendingServiceRouting, AgentWork), presence and capacity, skills-based routing, the routeWork Flow action as the Agentforce-to-human handoff, supervisor configuration, and the metadata and Tooling API surfaces behind all of it. Load only when the user explicitly invokes this skill by name (`dya-omni-channel`); do NOT auto-trigger on generic Service Cloud, routing or queue questions.
---

# Salesforce Omni-Channel

You are an expert at Omni-Channel, the engine that decides **which agent gets which piece of work**.
Its job starts where a conversation, case or call needs a human and ends when that human accepts it.
Everything about designing the agent that handles the conversation before then is `dya-agentforce`;
this skill is the routing layer underneath. Digital Engagement channel setup, ITSM object models and
the Service Console's UI are out of scope. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults routing Apex and Flow inherit.
- `references/shared/sharing-and-access.md` — the access model behind queue membership, `AgentWork` visibility and supervisor scope.
- `references/omni-data-model.md` — every object in the chain with its fields, the standard `ServiceChannel` DeveloperNames, capacity, skills-based routing and supervisor configuration.
- `references/omni-gotchas.md` — the read-path asymmetries and the v66 element renames, which is where most deploys fail.
- `references/omni-flow-deploy.md` — the `routeWork` action's targets, flow process types and how each is invoked, and the deploy and invocation error taxonomy.

---

## Platform Context — Winter '27 / API v68.0

Omni-Channel's programmatic surface is metadata and Tooling API rather than Apex: you configure it,
you rarely code against it. The one place code lives is the routing flow.

| Change | Status | Notes |
|---|---|---|
| `routeWork` targets an **Agentforce employee agent** (`agentforceEmployeeAgentId`) | GA | The declarative handoff from a human queue *to* an agent, not only the reverse |
| `routeWork` targets an Agentforce Orchestrator **digital worker** (`digitalWorkerId`) | GA | Same mechanism, for orchestrated multi-agent work |
| `capacityModel` on `ServiceChannel` replaces `capacityWeight` | GA since v66 | Per-agent totals moved to `PresenceUserConfig.Capacity` — see `references/omni-gotchas.md` |
| Attribute-based (skills) routing via `WorkSkillRouting` | GA | Requires `enableOmniSkillsRouting` |

The `AiAgentDefinition` / `AiAgentDefinitionVersion` metadata types that carry an agent at 68.0 are
`dya-agentforce`'s territory; Omni-Channel only needs the agent's Id to route to it.

---

## 1. The Routing Chain — Learn It In Order

Every Omni-Channel question resolves to "where in this chain is it stuck". Nothing else in the skill
makes sense without it.

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

On the agent's side, two objects decide whether they can receive anything:

```text
ServicePresenceStatus   the statuses an agent can select (Available - Chat, Busy, …)
PresenceUserConfig      which statuses this agent may use, and their capacity
```

**Diagnosis follows the chain.** Work not routing is one of: no `ServiceChannel` for the sObject, the
queue does not accept it (`QueueSobject`), no `QueueRoutingConfig` on the queue, no agent in an
available status, or every eligible agent at capacity. Check in that order rather than guessing.

---

## 2. Turn It On First, Or Everything Below Fails

`Settings:OmniChannel` carries five toggles:

| Setting | Enables |
|---|---|
| `enableOmniChannel` | Omni-Channel itself |
| `enableOmniSkillsRouting` | Skills-based (attribute) routing |
| `enableOmniSecondaryRoutingPriority` | A second priority dimension on routing configs |
| `enableOmniStatusCapModel` | Status-based rather than tab-based capacity |
| `enableOmniAutoLoginPrompt` | Prompting an agent to go online at login |

**With `enableOmniChannel = false`, every downstream metadata type rejects with `INVALID_TYPE`.**
That error names the type you were deploying, not the setting, so it reads as a malformed deploy.
Deploy the setting first, in its own step, and confirm it before anything else.

`enableOmniAutoLoginPrompt` deploys and round-trips cleanly but **does not currently drive the UI
radio**. Do not spend time debugging why the prompt is absent.

---

## 3. `routeWork` — the Agentforce Seam

The `routeWork` Flow action is how a record is pushed into routing from automation, and it is the
concrete boundary between `dya-agentforce` and this skill. An agent that has decided it cannot help
calls this; a queue that should be handled by an agent rather than a person routes here too.

Its targets are mutually exclusive — pass exactly one:

| Target | Routes to |
|---|---|
| `queueId` / `queueLabel` | A queue, for a human |
| `agentId` | One named user directly |
| `botId` | A classic bot |
| `copilotId` | A copilot |
| **`agentforceEmployeeAgentId`** | An Agentforce employee agent |
| **`digitalWorkerId`** | An Agentforce Orchestrator digital worker |
| `externalConversationBotId` | An external conversation bot |

The last three are the ones that matter for a modern design: routing is no longer only
human-to-human, so **escalation from an agent to a person and delegation from a person to an agent
use the same action**. Model both directions deliberately rather than treating the agent as a
terminal node.

> Full parameter list, the flow process types that can carry it, and the error taxonomy:
> `references/omni-flow-deploy.md`.

---

## 4. Capacity — the Model Changed, and the Field Moved

Capacity is how Omni-Channel decides an agent is full. Two models:

- **Tab-based** (`capacityModel: TAB_BASED`) — each open work item costs its channel's weight.
- **Status-based** (`STATUS_BASED`, needs `enableOmniStatusCapModel`) — capacity is per presence
  status, which handles an agent who can take three chats *or* one call but not both.

**Per-agent capacity totals live on `PresenceUserConfig.Capacity`,** not on the channel. The channel
declares the *cost* of one item; the user config declares the *budget*. Looking for a per-agent
number on `ServiceChannel` is looking in the wrong place, and `capacityWeight` no longer exists there
at all — see `references/omni-gotchas.md`.

---

## 5. Skills-Based Routing

Attribute-based routing matches a work item's required skills against agents' skills instead of
routing to whoever is next in the queue.

- `QueueRoutingConfig.IsAttributeBased = true` switches a queue to it.
- `WorkSkillRouting` declares which skills a work item needs.
- `SkillUser` grants a skill, at a level, to a user.

Use it where the wrong agent means a transfer rather than a slower answer — language, product line,
regulatory certification. Do not use it as a general quality mechanism: every additional required
skill narrows the eligible pool, and an item whose skill set matches nobody currently available waits
rather than routing to a competent generalist.

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
2. **`enableOmniChannel` comes first.** Nothing else deploys until it is on, and the error will not
   tell you that.
3. **`routeWork` is the seam with Agentforce, and it runs both ways.** Escalating to a human and
   delegating to an agent are the same action with a different target.
4. **Capacity is a budget on the user and a cost on the channel.** Do not look for the total on
   `ServiceChannel`.
5. **Configure it as metadata, in order.** The read paths are asymmetric and several element names
   changed at v66 — check `references/omni-gotchas.md` before assuming a field exists.
