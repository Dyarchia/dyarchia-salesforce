---
name: dya-flow
description: Salesforce Flow Winter '27 (API v68.0) modern automation best practices — flow types, bulkification, screen reactivity, run context and security, the Apex invocable bridge, HTTP callouts, fault paths, AI-assisted authoring, testing. Load only when the user explicitly invokes this skill by name (`dya-flow`); do NOT auto-trigger on generic Flow, automation, or Process-Builder-related questions.
---

# Salesforce Flow — Modern Automation

You **always** reach for Flow before Apex when the requirement can be expressed declaratively, you
**always** bulkify, and you **always** treat Flow as production code: metadata-deployed, tested,
with explicit error handling and a documented run context. Follow every rule below.

References:

- `references/shared/` — the platform fundamentals the rules below rest on: `governor-limits.md`
  (what a flow shares its transaction budget with), `sharing-and-access.md` (the model behind run
  context), `platform-deltas.md` (release-coupled facts). **Start with the first if you do not
  already know why putting a Get Records inside a Loop is fatal.**
- `references/invocable-apex-patterns.md` — the full `@InvocableMethod` / `@InvocableVariable`
  patterns, bulk handling, partial success, custom DTOs, the `callout=true` gotcha, `Flow.Interview`
  in the reverse direction, and how Flow and Agentforce callers differ.
- `references/http-callout-patterns.md` — Flow HTTP Callout end to end: Named Credential, External
  Service generation, status-code branching, pagination, error handling.

Neighbouring skills: server-side Apex → `dya-apex`; components that embed or launch flows →
`dya-lwc`; permission and sharing design → `dya-permissions`; platform events as an integration
surface → `dya-integration-events`; agent actions → `dya-agentforce`; the `routeWork` action and
Omni-Channel routing flows → `dya-omni-channel`.

---

## Platform Context — Winter '27 / API v68.0

Save new flows at `<apiVersion>68.0</apiVersion>` in the `.flow-meta.xml`.

Two facts decide what you can promise about a flow:

- **Flow Test Mode is Beta**, so it does not run in a production org. Design the testing story
  without assuming it.
- **Flow Tests earn no Apex code coverage.** A flow with no test does not block a production
  deployment, and a passing Flow Test does not raise the 75% Apex figure. Test flows because
  untested automation breaks silently in production, not because a gate forces you to — no gate
  exists.

> Everything the release adds feature by feature, plus the earlier changes that are now simply how
> the platform works: `references/release-notes.md`.

---

## 1. Absolute Rule — When Flow Is the Right Tool

1. **Standard configuration** — Validation Rules, Formula Fields, Rollup Summaries, Dynamic Forms. If
   the requirement fits here, no flow is needed.
2. **Flow** — record-triggered, schedule-triggered, screen, autolaunched, platform-event,
   orchestration. Where the large majority of business automation belongs.
3. **Apex** — only when Flow cannot express it: complex cross-object recursive logic, objects the UI
   API does not support, performance-critical synchronous code, integrations needing custom
   marshalling.

Document the type, trigger and purpose in the flow's **description** field. That is what a maintainer
sees in a list view without opening the canvas.

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

**Before-Save record-triggered flows** are the modern replacement for most `before insert` /
`before update` Apex triggers. For multi-stakeholder processes — sequential approvals, conditional
handoffs, parallel assignments — prefer **Orchestration** over chained autolaunched flows with
hand-rolled state tracking.

## 3. Bulkification

Flow bulkifies itself: a record-triggered flow processes a batch of up to 200 records in one
transaction. The risk is never Flow — it is **what you put inside a Loop**.

**Never put Get / Create / Update / Delete Records inside a Loop.** Flow Builder allows it, and it
generates one SOQL or DML operation per iteration against a budget of 100 queries and 150 DML
statements for the whole transaction. Instead:

1. **Get Records** once, before the loop, into a collection.
2. **Loop** only to filter, transform, and build a target collection.
3. **Create / Update / Delete Records** once, after the loop, on that collection.

**Custom batch size** on a scheduled flow's "Select Object" settings lowers records-per-transaction
from the default 200. Reach for it when you measurably hit CPU limits or `UNABLE_TO_LOCK_ROW`.

> `UNABLE_TO_LOCK_ROW` means another transaction held a lock on a record yours needed. The usual
> cause is many child records updating at once and each locking the **same shared parent** — a batch
> of Opportunities all rolling up to one Account. A batch size of 1 serialises the work and removes
> the contention, at the cost of far more transactions and a longer run. Reordering the data so a
> batch touches distinct parents fixes it more cheaply.

**Tight entry conditions.** A record-triggered flow fires on every DML against the object. Filter in
the entry condition (`Industry CHANGED to "Tech"`) rather than inside the flow with a Decision — a
run that starts and immediately exits still consumes an interview from the org's daily allocation
(visible under Setup › Company Information).

## 4. Run Context and Security

Every flow runs in one of three contexts. The setting lives on the flow's **version properties** —
open the flow, Edit Version Properties, "How to Run the Flow".

| Context | Sharing | Object and field permissions | Default for |
|---|---|---|---|
| **User Context** | Enforced | Enforced | Screen Flows |
| **System Context with Sharing** | Enforced | Bypassed | Record-Triggered Flows |
| **System Context without Sharing** | Bypassed | Bypassed | Never a default |

The record-triggered default silently lets a user trigger writes they could not perform directly. For
a flow that updates fields the running user is meant to be able to edit, switch to **User Context**
explicitly. **Never** ship "System Context without Sharing" without a justification in the flow
description — it is the declarative equivalent of `without sharing`, and almost always wrong outside
a deliberate integration.

> The model this rests on — profiles, permission sets, OWD, sharing rules, field-level security:
> `references/shared/sharing-and-access.md`. Design questions belong to `dya-permissions`.

## 5. Screen Flows — Reactivity First

Components on one screen react to each other's values without a page reload. Bind a component input
to another's output with `{!ComponentName.output}` and the downstream component re-renders when the
upstream value changes.

- **Action Buttons** — the user clicks, and an autolaunched subflow runs without leaving the screen.
  The subflow can do callouts, DML and Get Records, and return values the screen reacts to. Use for
  explicit user-initiated work: *Submit*, *Fetch Quote*, *Validate Postcode*.
- **Reactive Screen Actions** — the same mechanism fired automatically when an input changes. Use for
  as-you-type enrichment: auto-lookup, real-time validation, dynamic prefill.

The standard component library covers more than most people assume — check `lightning-record-form`,
`lightning-input-field`, Radio Button Group, the Time component and Data Table (with "Show record
name" and "Link to record" on lookup columns) before writing an LWC.

**AI-assisted editing** accepts natural-language changes through the Agentforce panel ("add a phone
field below the email", "show address fields only when billing country is US"). Useful for
prototyping; review every generated change before activation.

Avoid multi-step wizards where every step is a screen with a Next button. Ask whether the same
journey collapses into fewer reactive screens.

## 6. Calling Apex from Flow

Use `@InvocableMethod` when Flow needs logic it cannot express, callouts with custom marshalling, or
complex error handling.

- The method must be `static` and take exactly one `List<T>` parameter.
- Return `void` or a `List<U>`; output length **and order** must match the input.
- `@InvocableVariable(required=true)` on inputs that must be present.
- `callout=true` when the method makes HTTP callouts — it gates where the action can be used.
- A custom Apex type used as an action input needs a **public no-argument constructor**. Without one
  the platform cannot instantiate it at run time.
- **Flow always passes a `List`**, even from a single-record context — write for the batch. An
  Agentforce agent calling the same method does not batch, and wants a structured result rather than
  a thrown exception. Decide which caller you serve, or serve both by returning a result the flow
  branches on.
- On full-batch failure, throwing surfaces the message as `{!$Flow.FaultMessage}` for a Fault Path.
  For per-row failures, propagate through the output with a success flag and an error message.

**`InvocableActionExtension`** shapes how an admin configures the action in Flow Builder: a custom
property editor on one individual input, fixed picklist values for a `String` input instead of a
free-text box, and a custom header above the property panel. Worth it for reusable or packaged
actions — better design-time UX means fewer misconfigured flows.

> The class shape, DTOs, partial success, the `callout=true` gotcha, `Flow.Interview` for the reverse
> direction, testing, and the Flow-versus-agent caller table: `references/invocable-apex-patterns.md`.

## 7. HTTP Callouts from Flow

For REST integrations that do not need custom marshalling, use **Flow HTTP Callout** rather than
writing Apex. Create a Named Credential, then Flow Builder › New Action › Create HTTP Callout: choose
the credential and method, paste sample request and response JSON, and the platform generates the
External Service and the Apex types.

- **Always a Named Credential.** Never a raw URL, never an inline secret.
- POST and PUT bodies need a Record variable of the generated type, populated by Assignments.
- **Always branch on `{!ActionName.statusCode}`** in a Decision afterwards. The action does not throw
  on a non-2xx response — it returns one.
- Always connect a **Fault Path** for platform-level failures: network, misconfigured credential.
- In a record-triggered flow a callout must run on the **Asynchronous Path**. The synchronous path
  forbids a callout after committed DML.

> Full setup, status-code branching, pagination, anti-patterns: `references/http-callout-patterns.md`.
> Choosing between this and Apex, and the wider integration picture: `dya-integration-outbound`.

## 8. Error Handling — Fault Paths Are Mandatory

Every element that can fail — Get/Create/Update/Delete Records, Apex Actions, HTTP Callouts,
Subflows — gets a Fault Path. A flow without them is a production incident waiting to happen.

1. Connect the Fault edge to an Assignment capturing `{!$Flow.FaultMessage}`.
2. Route it to a screen (in a screen flow), or to a logging subflow that publishes a platform event
   into a log object (see `dya-apex`), or — last resort — to a notification.

Where one error-handling subflow serves every fault path, collapse them with the chevron on the Fault
edge to keep the canvas readable. The **Element Error Rate** column in the Automation app list view
shows the percentage of elements that errored in the most recent run, which flags a flow needing
attention without opening a debug log.

**Ask Agentforce** (Beta) diagnoses a failure in natural language and may offer an automatic
"Fix Issue". Treat it as a starting point: verify the change and run the flow in Debug before
reactivating.

## 9. Subflows and Reuse

Extract a subflow when the same logic appears in two or more flows, when a screen flow needs business
logic without leaving the screen, or when a piece of logic has its own meaningful name. Do not extract
one-time logic used in a single flow, or an operation so small that the subflow overhead exceeds the
saving.

Prefix subflows by domain — `Account_RecalculateScore`, `Order_ValidateLineItems`. The Automation app
sorts alphabetically, so consistent prefixes make the list scannable. Flow Tags give a second axis.

For reusable **value mappings** — external status to internal picklist, country code to display
name — define them once as **Global Flow Resources** and consume them through the Transform element,
rather than scattering Decision elements with the same hardcoded pairs.

## 10. Testing and Deployment

Build **Flow Tests** in the Automation app for autolaunched and record-triggered flows: define the
triggering record state, assert on the post-run state — field values, records created, actions
invoked — and run them from the Automation app or during `sf project deploy validate`. **Flow Test
Mode** (Beta) brings the same loop inside Flow Builder, where a debug run can be saved as a reusable
scenario with mocked action outputs.

Be clear about what this does and does not buy you: **Flow Tests earn no Apex code coverage and do
not gate a production deployment.** They exist because untested automation fails silently against
real data, which is a better reason than a threshold.

Use **Debug** in Flow Builder for record-triggered and autolaunched flows; screen flows debug inline.
The panel supports filtering, search and full per-element input/output.

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
| An element with no connected Fault Path | Fault Path into a logging subflow |
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

1. **Flow first, Apex second** — declarative is faster to build, easier to maintain, and equally bulkified when used correctly.
2. **Bulkify by structure** — never a data element inside a Loop; collections in, collections out; tune batch size only when you measure a real limit.
3. **Fault Paths are mandatory** — every fallible element gets one, routed somewhere durable.
4. **Named Credentials always** — no raw URLs, no inline secrets, ever.
5. **Test because production is unforgiving**, not because a gate makes you — Flow Tests earn no Apex coverage and block no deployment.
