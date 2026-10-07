---
name: dya-sf-flow
description: Salesforce Flow (Winter '27, API v68.0) — flow types, bulkification, screen reactivity, run context, invocable Apex, HTTP callouts, fault paths, testing. Applies to *.flow-meta.xml, invocable Apex called from Flow, and Flow tests. Load before creating or editing anything in this scope.
---

# Salesforce Flow — Modern Automation

You **always** reach for Flow before Apex when the requirement can be expressed declaratively, you
**always** bulkify, and you **always** treat Flow as production code: metadata-deployed, tested,
with explicit error handling and a documented run context. Follow every rule below.

References:

- `references/shared/` — platform fundamentals: `governor-limits.md` (the transaction budget a flow
  shares, and why a Get Records inside a Loop is fatal), `sharing-and-access.md` (the model behind
  run context), `platform-deltas.md` (release-coupled facts).
- `references/invocable-apex-patterns.md` — full `@InvocableMethod` / `@InvocableVariable`
  patterns, bulk handling, partial success, custom DTOs, `callout=true`, `Flow.Interview` in the
  reverse direction, and how Flow and Agentforce callers differ.
- `references/http-callout-patterns.md` — Flow HTTP Callout end to end: Named Credential, External
  Service generation, status-code branching, pagination, error handling.

Neighbouring skills: server-side Apex → `dya-sf-apex`; components that embed or launch flows →
`dya-sf-lwc`; permission and sharing design → `dya-sf-permissions`; platform events as an integration
surface → `dya-sf-integration-events`; agent actions → `dya-sf-agentforce`; the `routeWork` action and
Omni-Channel routing flows → `dya-sf-omni-channel`.

---

## Platform Context — Winter '27 / API v68.0

Save new flows at `<apiVersion>68.0</apiVersion>` in the `.flow-meta.xml`.

**Flow Test Mode is Beta**, so it does not run in a production org. Design testing without it.

> Every feature the release adds, plus earlier changes now standard: `references/release-notes.md`.

---

## 1. Absolute Rule — When Flow Is the Right Tool

1. **Standard configuration** — Validation Rules, Formula Fields, Rollup Summaries, Dynamic Forms. If
   the requirement fits here, build no flow.
2. **Flow** — record-triggered, schedule-triggered, screen, autolaunched, platform-event,
   orchestration. Most business automation belongs here.
3. **Apex** — only when Flow cannot express it: complex cross-object recursive logic, objects the UI
   API does not support, performance-critical synchronous code, integrations needing custom
   marshalling.

Document the type, trigger and purpose in the flow's **description** field, visible in a list view
without opening the canvas.

## 2. Flow Types

| Type | When | Run mode |
|---|---|---|
| **Record-Triggered, Before-Save** | Update fields on the same record on insert/update | Fastest — no SOQL/DML overhead, modifies in place |
| **Record-Triggered, After-Save** | Cross-object updates, Apex calls, subflows | Standard |
| **Record-Triggered, Asynchronous Path** | Callouts, slow work, anything not needed immediately | Runs after the transaction commits |
| **Schedule-Triggered** | Recurring batch work | Batched; batch size is configurable |
| **Screen Flow** | User-facing wizards and forms | User context |
| **Autolaunched (subflow)** | Reusable logic called by flows or Apex | Follows the caller |
| **Platform Event-Triggered** | Reaction to a published platform event | System context by default |
| **Orchestration** | Multi-step, multi-stakeholder work with handoffs and approvals | Standard feature |

**Before-Save record-triggered flows** replace most `before insert` / `before update` Apex triggers.
For multi-stakeholder processes — sequential approvals, conditional handoffs, parallel assignments —
prefer **Orchestration** over chained autolaunched flows with hand-rolled state tracking.

## 3. Bulkification

A record-triggered flow processes a batch of up to 200 records in one transaction.

**Never put Get / Create / Update / Delete Records inside a Loop.** Flow Builder allows it, and it
issues one SOQL or DML operation per iteration against a transaction budget of 100 queries and 150
DML statements. Instead:

1. **Get Records** once, before the loop, into a collection.
2. **Loop** only to filter, transform, and build a target collection.
3. **Create / Update / Delete Records** once, after the loop, on that collection.

**Custom batch size** in a scheduled flow's "Select Object" settings lowers records-per-transaction
from the default 200. Use it only when you measurably hit CPU limits or `UNABLE_TO_LOCK_ROW`.

> On `UNABLE_TO_LOCK_ROW`, first reorder the data so a batch touches distinct parents. The error
> means another transaction held a lock on a record yours needed — usually many child records each
> locking the **same shared parent** (a batch of Opportunities rolling up to one Account). A batch
> size of 1 also removes the contention, at the cost of far more transactions and a longer run.

**Tight entry conditions.** A record-triggered flow fires on every DML against the object. Filter in
the entry condition (`Industry CHANGED to "Tech"`), not with a Decision inside the flow — a run that
exits immediately still consumes an interview from the org's daily allocation (Setup › Company
Information).

## 4. Run Context and Security

Set the context in Edit Version Properties, "How to Run the Flow".

| Context | Sharing | Object and field permissions | Default for |
|---|---|---|---|
| **User Context** | Enforced | Enforced | Screen Flows |
| **System Context with Sharing** | Enforced | Bypassed | Record-Triggered Flows |
| **System Context without Sharing** | Bypassed | Bypassed | Never a default |

Switch to **User Context** for a flow updating fields the running user should be able to edit; the
record-triggered default lets a user trigger writes they could not perform directly. **Never** ship
"System Context without Sharing" without a justification in the flow description — it is the
declarative `without sharing`, almost always wrong outside a deliberate integration.

> The underlying model — profiles, permission sets, OWD, sharing rules, field-level security:
> `references/shared/sharing-and-access.md`. Design questions belong to `dya-sf-permissions`.

## 5. Screen Flows — Reactivity First

Bind a component input to another's output with `{!ComponentName.output}`; the downstream component
re-renders when the upstream value changes, without a page reload.

- **Action Buttons** — on click, an autolaunched subflow runs without leaving the screen. It can do
  callouts, DML and Get Records, and return values the screen reacts to. Use for user-initiated work:
  *Submit*, *Fetch Quote*, *Validate Postcode*.
- **Reactive Screen Actions** — the same mechanism, fired automatically when an input changes. Use for
  as-you-type enrichment: auto-lookup, real-time validation, dynamic prefill.

Before writing an LWC, check the standard components: `lightning-record-form`,
`lightning-input-field`, Radio Button Group, the Time component and Data Table (with "Show record
name" and "Link to record" on lookup columns).

Use **AI-assisted editing** for prototyping only, and review every generated change before
activation. It accepts natural-language changes through the Agentforce panel ("add a phone field
below the email", "show address fields only when billing country is US").

Avoid wizards where every step is a screen with a Next button; check whether the journey collapses
into fewer reactive screens.

## 6. Calling Apex from Flow

Use `@InvocableMethod` for logic Flow cannot express, callouts with custom marshalling, or complex
error handling.

- Make the method `static`, taking exactly one `List<T>` parameter.
- Return `void` or a `List<U>`; match the input's length **and order** in the output.
- Mark mandatory inputs `@InvocableVariable(required=true)`.
- Set `callout=true` when the method makes HTTP callouts; it gates where the action can be used.
- Give a custom Apex type used as an action input a **public no-argument constructor**; the platform
  cannot instantiate it at run time otherwise.
- Write for the batch: **Flow always passes a `List`**, even from a single-record context.
- Decide which caller you serve, or serve both by returning a result the flow branches on. An
  Agentforce agent calling the same method does not batch, and wants a structured result rather than
  a thrown exception.
- On full-batch failure, throw; the message surfaces as `{!$Flow.FaultMessage}` for a Fault Path.
- On per-row failures, return a success flag and an error message in the output.

Use **`InvocableActionExtension`** on reusable or packaged actions, to prevent misconfigured flows.
It shapes how an admin configures the action in Flow Builder: a custom property editor on one input,
fixed picklist values for a `String` input instead of free text, and a custom header above the
property panel.

> Class shape, DTOs, partial success, `callout=true`, `Flow.Interview` for the reverse direction,
> testing, and the Flow-versus-agent caller table: `references/invocable-apex-patterns.md`.

## 7. HTTP Callouts from Flow

For REST integrations without custom marshalling, use **Flow HTTP Callout**, not Apex. Create a
Named Credential, then Flow Builder › New Action › Create HTTP Callout: choose the credential and
method, paste sample request and response JSON; the platform generates the External Service and the
Apex types.

- **Always a Named Credential.** Never a raw URL or an inline secret.
- Pass POST and PUT bodies as a Record variable of the generated type, populated by Assignments.
- **Always branch on `{!ActionName.statusCode}`** in a Decision afterwards. The action returns a
  non-2xx response without throwing.
- Always connect a **Fault Path** for platform-level failures: network, misconfigured credential.
- In a record-triggered flow, run the callout on the **Asynchronous Path**; the synchronous path
  forbids a callout after uncommitted DML.

> Full setup, status-code branching, pagination, anti-patterns: `references/http-callout-patterns.md`.
> Choosing between this and Apex, and the wider integration picture: `dya-sf-integration-outbound`.

## 8. Error Handling — Fault Paths Are Mandatory

Every element that can fail — Get/Create/Update/Delete Records, Apex Actions, HTTP Callouts,
Subflows — gets a Fault Path.

1. Connect the Fault edge to an Assignment capturing `{!$Flow.FaultMessage}`.
2. Route it to a screen (in a screen flow), to the org's own error-handling subflow where one
   exists, or — last resort — to a notification. Do not create a logging object to hold the fault.

Where one error-handling subflow serves every fault path, collapse them with the chevron on the Fault
edge. Check the **Element Error Rate** column in the Automation app list view: it shows the
percentage of elements that errored in the most recent run, without opening a debug log.

Verify any "Fix Issue" that **Ask Agentforce** (Beta) offers, and run the flow in Debug before
reactivating. Ask Agentforce diagnoses a failure in natural language and may offer the fix
automatically.

## 9. Subflows and Reuse

Extract a subflow when the same logic appears in two or more flows, when a screen flow needs business
logic without leaving the screen, or when a piece of logic has its own meaningful name. Do not extract
logic used once in a single flow, or an operation so small that the subflow overhead exceeds the
saving.

Prefix subflows by domain — `Account_RecalculateScore`, `Order_ValidateLineItems` — to group them in
the alphabetical Automation app list. Flow Tags give a second axis.

Define reusable **value mappings** — external status to internal picklist, country code to display
name — once as **Global Flow Resources** and consume them through the Transform element, not
scattered Decision elements with the same hardcoded pairs.

## 10. Testing and Deployment

Build **Flow Tests** in the Automation app for autolaunched and record-triggered flows: define the
triggering record state, assert on the post-run state — field values, records created, actions
invoked — and run them from the Automation app or during `sf project deploy validate`. **Flow Test
Mode** (Beta) brings the same loop into Flow Builder, where a debug run can be saved as a reusable
scenario with mocked action outputs.

**Flow Tests earn no Apex code coverage**: a passing one does not raise the 75% Apex figure, and an
untested flow does not block a production deployment. Test anyway; untested automation fails
silently against real data.

Use **Debug** in Flow Builder for record-triggered and autolaunched flows; screen flows debug inline.
The panel offers filtering, search and full per-element input/output.

Flows are metadata (`.flow-meta.xml`). Never edit a flow directly in production. Deploy from version
control through a pipeline: validate against a sandbox, then deploy.

## 11. Decision Matrix — Is This Even Apex?

| Need | Solution | Apex? |
|---|---|---|
| Update a field on the record being saved | Before-Save record-triggered flow | NO |
| Update related records on save | After-Save flow or autolaunched subflow | NO |
| Recurring scheduled work | Schedule-triggered flow, batch size tuned if needed | NO |
| User-facing wizard or form | Screen flow with reactive components | NO |
| Act on many selected records from a list view | Screen flow launched with an `ids` collection | NO |
| Reactive data fetch inside a screen | Reactive Screen Action into an autolaunched subflow | NO |
| Multi-stakeholder approval | Flow Orchestration | NO |
| REST call without custom marshalling | Flow HTTP Callout + Named Credential | NO |
| Reusable value mapping | Global Flow Resources + Transform | NO |
| Reaction to a platform event | Platform-event-triggered flow | NO |
| Cross-object logic Flow cannot express | `@InvocableMethod` called from the flow | YES |
| Performance-critical synchronous work | Apex | YES |
| Objects the UI API does not support | Apex | YES |
| Callout needing complex marshalling | Apex `Http` via `@InvocableMethod` | YES |

## 12. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct approach |
|---|---|
| Process Builder or Workflow Rules for new automation | Record-triggered flow |
| An Apex trigger for a simple same-record field update | Before-Save record-triggered flow |
| Get / Create / Update / Delete Records inside a Loop | Collections: query before, DML after |
| No entry condition, filtering inside with a Decision | Filter in the entry condition |
| Hardcoded URL or API key | Named Credential, always |
| A callout on a record-triggered flow's synchronous path | Asynchronous Path |
| Not branching on `statusCode` after an HTTP Callout | Decision on the status code — the action does not throw |
| An element with no connected Fault Path | Fault Path into the org's error-handling subflow |
| `System Context without Sharing` with no stated reason | User context, or system-with-sharing; justify in the description |
| A wizard where every step is a screen with a Next button | Reactive components on fewer screens |
| A custom LWC for what a standard component does | Check the component library first |
| Scattered Decisions mapping the same values | Global Flow Resources + Transform |
| Editing or activating a flow directly in production | Metadata deployment from version control |
| Assuming Flow Tests raise Apex coverage or gate a deploy | They do neither — test because production is unforgiving |
| Several record-triggered flows on one object for the same DML | Consolidate; order between flows is not guaranteed |
| A custom Apex input type with no no-arg constructor | Add a public no-argument constructor |
| A free-text action input whose values are a fixed set | Picklist values via `InvocableActionExtension` |
| Applying an AI "Fix Issue" without review | Verify in Debug before reactivating |

## Summary — The Five Commandments

1. **Flow first, Apex second** — build declaratively whenever Flow can express the requirement; it is equally bulkified when used correctly.
2. **Bulkify by structure** — no data element inside a Loop; collections in, collections out; tune batch size only when you measure a real limit.
3. **Fault Paths are mandatory** — every fallible element gets one, routed somewhere durable.
4. **Named Credentials always** — no raw URLs, no inline secrets.
5. **Test every flow, though no gate forces you** — Flow Tests earn no Apex coverage and block no deployment, and production is unforgiving.
