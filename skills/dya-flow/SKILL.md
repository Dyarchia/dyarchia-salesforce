---
name: dya-flow
description: Salesforce Flow Summer '26 (API v67.0) modern automation best practices — flow types, bulkification, screen reactivity, security, Apex integration, HTTP callouts, AI-assisted authoring, testing. Load only when the user explicitly invokes this skill by name (`dya-flow`); do NOT auto-trigger on generic Flow, automation, or Process-Builder-related questions.
---

# Salesforce Flow — Modern Automation

You are an expert Salesforce automation architect. You **always** reach for Flow before Apex when the requirement can be expressed declaratively, you **always** bulkify, and you **always** treat Flow as production code: metadata-deployed, tested, with explicit error handling and a documented security context.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/` and are loaded on demand:

- `references/invocable-apex-patterns.md` — full `@InvocableMethod` and `@InvocableVariable` patterns for the Flow → Apex bridge, with bulk handling, partial-success, custom DTOs, and the `callout=true` gotcha.
- `references/http-callout-patterns.md` — full Flow HTTP Callout setup: Named Credential, External Service generation, status-code branching, pagination, error handling.

For server-side Apex called from Flow, see the companion skill `dya-apex`. For Lightning Web Components that embed or launch Flows, see `dya-lwc`.

---

## Platform Context — Summer '26 / API v67.0

**Current API version: 67.0 (Summer '26).** All new Flows MUST be saved at `<apiVersion>67.0</apiVersion>` in the `.flow-meta.xml`. Summer '26 ships a significant batch of Flow improvements:

- **Custom batch size for Scheduled Flows** — under "Select Object", set the records-per-transaction down to 1 to mitigate record-locking errors and CPU limits at scale.
- **Flow Orchestration is now a Standard Feature** — orchestration runs are included in available editions with no usage-based limits.
- **20 new Date operators** in Decision elements — `Is Today`, `Is Tomorrow`, `Is Yesterday`, `Is This Month`, `Is Anniversary of Today`, `Last Number of Days`, `Next Number of Months`, and more. Useful for renewal reminders (`Renewal_Date__c Is This Month`), birthday automations (`Birth_Date__c Is Anniversary of Today`), and SLA cohorts (`Created_Date__c Last Number of Days = 7`). Date type only, not DateTime.
- **Email Template persistent references** in Send Email Action — templates are stored as a reference that survives deployments across orgs. The template-ID-drift problem is gone.
- **Collapsible Fault Paths** — joins collapsible Decisions and Loops (Spring '26) for a cleaner canvas.
- **Element Error Rate column** in the Automation app — shows the percentage of flow elements that errored in the most recent run, without opening the debug log.
- **Global Flow Resources / reusable mappings** — define value mappings once in the Automation app and use them in any flow's Transform element.
- **Radio Button Group screen component** — replaces the legacy radio styling; toggle to convert to Checkbox Group for multi-select.
- **Data Table lookup display name** — show the related record's Name (as a link) instead of the raw Id.
- **AI-assisted Screen Flow editing** — describe changes in natural language via the Agentforce panel.
- **"Ask Agentforce" for Flow errors (Beta)** — diagnose design-time and runtime errors; offers an automatic "Fix Issue" option. Treat suggestions as starting points, verify before applying.
- **AI Agent actions auto-migrate to Create Agent element** when opening existing flows; original configuration is preserved.
- **Configurable Apex Action property editors** — via the new `InvocableActionExtension` metadata, an invocable action can attach a custom property editor to an individual input, define **picklist values** for an input, and show a **custom header** atop its config panel in Flow Builder. Better, less error-prone admin UX for reusable and packaged actions. See §6.

Summer '26 pushes two directions: **harder bulkification controls** (custom batch sizes) and **AI-assisted authoring**. Use the former liberally; treat the latter as a helper, never a substitute for understanding what your flow does.

---

## 1. Absolute Rule — When Flow Is the Right Tool

Flow is the default declarative automation tool on the platform. The decision tree, in order:

1. **Standard configuration** — Validation Rules, Formula Fields, Rollup Summaries, Page Layouts, Dynamic Forms. If the requirement is expressible here, no Flow needed.
2. **Flow** — Record-triggered, schedule-triggered, screen, autolaunched, platform event, orchestration. Where ~80% of business automation belongs in 2026.
3. **Apex** — Only when Flow cannot express the requirement: complex cross-object recursive logic, operations on non-UI-API objects, performance-critical synchronous code, integrations needing custom marshalling.

When you do reach for Flow, document the type, trigger, and purpose in the Flow's description field — this is what future maintainers see in list views without opening the canvas.

---

## 2. Flow Types — Pick the Right One

| Type | When | Mode |
|---|---|---|
| **Record-Triggered Flow (RTF), Before-Save** | Update fields on the same record on insert/update | Fast, no transaction overhead |
| **Record-Triggered Flow, After-Save** | Cross-object updates, calls to Apex, subflows | Standard |
| **Record-Triggered Flow, Asynchronous Path** | Callouts, slow operations, anything not needed immediately | Runs after the transaction commits |
| **Schedule-Triggered Flow** | Recurring batch operations (nightly cleanup, weekly summaries) | Batched, custom batch size in Summer '26 |
| **Screen Flow** | User-facing wizards, multi-step forms, interactive UIs | User context |
| **Autolaunched Flow (subflow)** | Reusable logic invoked by other Flows or by Apex | Caller-dependent |
| **Platform Event-Triggered Flow** | Reactions to published platform events | System context by default |
| **Flow Orchestration** | Multi-step, multi-stakeholder workflows with handoffs and approvals | Standard since Summer '26 |

**Before-Save Record-Triggered Flows** are the modern replacement for most `before insert` / `before update` Apex triggers — no SOQL/DML overhead, modify the record in place, measurably faster.

For complex multi-stakeholder processes (sequential approvals, conditional handoffs, parallel work assignments), **Flow Orchestration** is now Standard in Summer '26 and should be preferred over chained autolaunched flows with manual state tracking.

---

## 3. Bulkification — Flow Is Bulkified, Treat It That Way

Flow is bulkified internally. Record-triggered flows process batches of 200 records by default. The risk is not Flow itself — it is **the elements you put inside it**.

### Never put Get / Create / Update / Delete Records inside a Loop

Flow Builder will let you do this; it generates SOQL/DML per iteration and you will hit governor limits. Always:

1. **Get Records** ONCE, outside the loop, into a Collection.
2. **Loop** to filter / transform / build a target Collection.
3. **Create / Update / Delete Records** ONCE, after the loop, on the target Collection.

### Custom Batch Size for Scheduled Flows (Summer '26)

When a scheduled flow hits record-locking errors, `UNABLE_TO_LOCK_ROW`, or CPU limits, lower the batch size in the "Select Object" settings of the scheduled path. Default is 200; you can set it to any value from 1 up.

A batch size of 1 serialises updates and eliminates locking contention at the cost of more transactions and longer total runtime. Reach for it only when you measurably hit locking or CPU errors at the default.

### Tight entry conditions

Record-triggered flows fire for every DML on the object. Filter early via entry conditions (`Industry CHANGED to "Tech"`) instead of evaluating inside the flow with Decision elements. Untriggered flow runs still consume the org's daily Flow run allocation.

---

## 4. Security — User Context vs System Context

Every flow runs in one of three contexts:

| Context | Sharing | CRUD/FLS | Default for |
|---|---|---|---|
| **User Context** | Enforced | Enforced | Screen Flows |
| **System Context with Sharing** | Enforced | Bypassed | Record-Triggered Flows |
| **System Context without Sharing** | Bypassed | Bypassed | Never the default |

Override only with a documented reason. **Never use "System Context without Sharing" without an explanation in the Flow description field** — it is the platform equivalent of `without sharing` in Apex, and like the Apex version, almost always wrong outside specific integration scenarios.

For record-triggered flows that update fields the running user can edit, switch to **User Context** explicitly to enforce FLS. The default is convenient, but it silently lets users trigger writes they would not be allowed to perform directly.

---

## 5. Modern Screen Flows — Reactivity First

Modern Screen Flows are **reactive** — components on the same screen react to each other's values without page reloads.

### Reactive components (default since Winter '24)

Bind one component's input to another component's output via `{!ComponentName.output}` references. The downstream component re-renders automatically when the upstream value changes.

### Action Buttons (Summer '24) and Reactive Screen Actions (Spring '25)

- **Action Buttons** — user clicks; invokes an autolaunched subflow without leaving the screen. The subflow can do callouts, DML, Get Records — and return values that the screen reacts to.
- **Reactive Screen Actions** — same mechanism, but triggered automatically when an input value changes. No button click.

Use Action Buttons for explicit user-initiated work (`Submit`, `Fetch Quote`, `Validate Postcode`). Use Reactive Screen Actions for "as you type" / "as you select" enrichment (auto-lookup, real-time validation, dynamic prefill).

### New in Summer '26

- **Radio Button Group** — horizontal-box selector. Toggle "Let Users Select Multiple Options" to convert to Checkbox Group.
- **Data Table lookup display** — enable "Show record name" and "Link to record" on lookup columns to render clickable names instead of raw Ids.
- **AI-assisted editing** — Agentforce panel accepts natural-language edits ("add a phone number field below the email", "show the address fields only if billing country is US"). Useful for rapid prototyping; review every change before activation.

### Avoid

- Multi-step wizards where every step is a Screen with a Next button. Consider whether the same UX collapses to fewer reactive screens.
- Custom LWCs for things the standard component library does. Check `lightning-record-form`, `lightning-input-field`, Radio Button Group, and Data Table first.

---

## 6. Calling Apex from Flow — `@InvocableMethod`

When Flow needs Apex (logic Flow cannot express, callouts with custom marshalling, complex error handling), invoke a method annotated with `@InvocableMethod`.

```java
public with sharing class AccountScorer {

    @InvocableMethod(
        label='Recalculate Account Score'
        description='Recomputes the rollup score for a set of Accounts'
        category='Account'
        callout=false
    )
    public static List<Output> recalculate(List<Input> inputs) {
        // Always bulk: Flow ALWAYS passes a List, even from a single-record context.
        Set<Id> accountIds = new Set<Id>();
        for (Input i : inputs) { accountIds.add(i.accountId); }
        // ... do work ...
        return buildOutputs(inputs);
    }

    public class Input {
        @InvocableVariable(required=true) public Id accountId;
    }
    public class Output {
        @InvocableVariable public Id accountId;
        @InvocableVariable public Decimal score;
    }
}
```

### Rules

- The method MUST be `static` and accept exactly one `List<T>` parameter.
- Return `void` or a `List<U>`; output length and order MUST match the input.
- `@InvocableVariable(required=true)` for inputs that must be present.
- `callout=true` when the method makes HTTP callouts (gates the action's availability on synchronous paths of record-triggered flows).
- Any **custom Apex type used as an action input must expose a public no-argument constructor** (enforced in v67) — otherwise the platform cannot instantiate it when the flow runs.
- Throw a clear exception on full-batch failure — the message surfaces as `{!$Flow.FaultMessage}`. For per-row failures, propagate via the output (a `success` boolean + `errorMessage` field).

### Make actions configurable — `InvocableActionExtension` (v67)

Beyond the bare action, Summer '26 lets you shape how admins configure it in Flow Builder through the `InvocableActionExtension` metadata type — GA, in Enterprise / Performance / Unlimited / Developer editions, in both Lightning Experience and Classic. Three capabilities:

- **Per-input custom property editor** — attach a custom LWC editor to a single input (not just the whole action), so one tricky parameter gets a guided UI while the rest use the standard editor.
- **Picklist values for an input** — present a fixed dropdown for a `String` input instead of a free-text box, removing typo and invalid-value errors at design time.
- **Custom header** — render a custom component at the top of the action's property panel, before the inputs (instructions, links, a summary).

Reach for these when you ship a **reusable or packaged** invocable action that admins configure repeatedly: the better the design-time UX, the fewer misconfigured flows. For the exact metadata shape, consult the `InvocableActionExtension` Metadata API reference.

> Full patterns — bulk processing, partial success, custom DTOs, error propagation, testing: see `references/invocable-apex-patterns.md`.

---

## 7. Calling Flow from Apex / LWC

### From Apex — `Flow.Interview`

```java
Map<String, Object> inputs = new Map<String, Object>{
    'accountId' => acc.Id,
    'newRating' => 'Hot'
};
Flow.Interview interview = Flow.Interview.createInterview('My_Autolaunched_Flow', inputs);
interview.start();
Object output = interview.getVariableValue('outputVariableName');
```

Use when Apex is the orchestrator and Flow is a step. Reverse (`@InvocableMethod`) when Flow is the orchestrator and Apex is a step.

### From LWC

Use `lightning/flowSupport` to embed a flow inside an LWC, or `standard__flow` PageReference to navigate to a screen flow (Summer '26 — see `dya-lwc` §6).

---

## 8. HTTP Callouts in Flow (GA Summer '23)

For REST integrations that do not need custom marshalling, use **Flow HTTP Callout** instead of writing Apex.

### High-level workflow

1. Create a **Named Credential** (Setup → Named Credentials) for the external service.
2. In Flow Builder → New Action → "Create HTTP Callout" — choose the Named Credential, method, and paste sample request/response JSON. The platform generates an External Service and reusable Apex types automatically.
3. The action appears in the Action picker for any flow type.

### Rules

- **Always Named Credential.** Never raw URLs or inline credentials.
- POST and PUT bodies require a Record variable of the generated type, populated with Assignment elements.
- After the action, **always** branch on `{!ActionName.statusCode}` in a Decision element — the action does NOT throw on non-2xx.
- Always connect a **Fault Path** for platform-level failures (network, misconfigured Named Credential).
- HTTP Callouts in record-triggered flows MUST run on an **Asynchronous Path**. The synchronous path forbids callouts after committed DML.

> Full HTTP Callout setup — Named Credential config, External Service generation, status-code branching, pagination, anti-patterns: see `references/http-callout-patterns.md`.

---

## 9. Error Handling — Fault Paths Are Mandatory

Every element that can fail — Get/Create/Update/Delete Records, Apex Actions, HTTP Callouts, Subflows — MUST have a Fault Path. A flow without Fault Paths is a production incident waiting to happen.

### Pattern

1. Connect the element's Fault edge to an Assignment that captures `{!$Flow.FaultMessage}` into a variable.
2. Route the variable to:
   - A Screen (for screen flows), or
   - A logging subflow that creates an `Application_Log__c` record via Platform Event (cross-stack logging pattern — see `dya-apex` §11), or
   - A notification mechanism (email to automation owner, Slack via Slack Workflow Builder) as the last resort.

### Collapsible Fault Paths (Summer '26)

When a single error-handling subflow handles all Fault Paths in a flow (the common pattern), collapse them via the chevron on the Fault edge. The canvas stays readable.

### Element Error Rate column (Summer '26)

In the Automation app's flow list view, add the "Element Error Rate" column. It shows the percentage of elements that errored in the most recent run — an at-a-glance signal for "this flow needs attention" without digging into debug logs.

### Ask Agentforce for Errors (Beta — Summer '26)

When a flow fails, click "Ask Agentforce" on the error to get a natural-language diagnosis. For common patterns (locking, governor limits, null references) it suggests an automatic "Fix Issue" change. **Verify manually before applying** — AI fixes are starting points, not authoritative changes. Run the fixed flow in Debug mode before reactivating.

---

## 10. Subflows & Reusability

### Use a subflow when

- The same logic appears in two or more flows.
- A screen flow needs to invoke business logic without leaving the screen (Action Button / Reactive Screen Action).
- A piece of logic has its own meaningful name and would benefit from being maintained independently.

### Don't use a subflow when

- The logic is one-time, in one flow — inline it.
- The operation is tiny (a single assignment) — subflow overhead exceeds the saving.

### Naming convention

Prefix subflows with their domain: `Account_RecalculateScore`, `Order_ValidateLineItems`, `Contact_DispatchWelcomeEmail`. The Automation app list view sorts alphabetically; consistent prefixes make the list scannable.

### Global Flow Resources (Summer '26)

For reusable **value mappings** — external statuses to internal picklist values, country codes to display names, error codes to human messages — define them once in the Automation app → Global Flow Resources, and reuse via the Transform element in any flow type. Replaces scattered Decision elements with hardcoded mappings.

---

## 11. Testing — Flow Tests Are Real Tests

### Flow Test framework

For autolaunched and record-triggered flows, create Flow Tests in the Automation app:

1. Define the trigger context (the record state that triggers the flow).
2. Define assertions on the post-flow state — record fields, related records created, Apex actions invoked.
3. Run from the Automation app or via `sf project deploy validate`.

Flow Tests count toward Apex code coverage in deployments — a flow without a passing test will block production deployment under standard test-level settings.

### Email Template persistent references (Summer '26)

The Send Email action now stores the email template as a persistent reference that survives metadata deployments. Existing flows: open the Send Email action → expand "Show advanced options" → confirm the template binding is the new reference-based format.

### Debug mode

Use **Debug** in Flow Builder for record-triggered and autolaunched flows. The modern debug panel (Summer '25+) supports filtering, search, and full input/output visibility per element. For screen flows, Debug now runs inline (Winter '26+) without a separate window.

### Deployment

Flows deploy as metadata (`.flow-meta.xml`). Never edit flows directly in production. Use a CI/CD pipeline: change set or `sf project deploy start` from a feature branch → validate against sandbox → deploy.

---

## 12. Decision Matrix — Quick Reference

| Need | Solution | Apex? |
|---|---|---|
| Update a field on the current record | Validation Rule / Formula / Before-Save RTF | NO |
| Update related records on save | After-Save RTF or autolaunched subflow | NO |
| Recurring scheduled cleanup | Schedule-Triggered Flow (custom batch size if needed) | NO |
| User-facing wizard or form | Screen Flow with reactive components | NO |
| Reactive data fetch in a screen | Reactive Screen Action → autolaunched subflow | NO |
| Multi-step, multi-stakeholder approval | Flow Orchestration (Standard since Summer '26) | NO |
| REST integration without custom marshalling | Flow HTTP Callout + Named Credential | NO |
| Reusable value mapping (status, country, etc.) | Global Flow Resources + Transform element | NO |
| Reaction to a platform event | Platform Event-Triggered Flow | NO |
| Complex cross-object logic Flow cannot express | `@InvocableMethod` invoked from Flow | YES |
| Performance-critical synchronous code | Apex (optionally invoked from Flow) | YES |
| Operations on non-UI-API objects | Apex | YES |
| Callout with complex marshalling | Apex `Http`/`HttpRequest` via `@InvocableMethod` | YES |

---

## 13. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| Process Builder for new automation | Record-Triggered Flow |
| Workflow Rules for new automation | Record-Triggered Flow |
| Apex trigger for simple same-record field update | Before-Save Record-Triggered Flow |
| Get / Create / Update / Delete Records inside a Loop | Move outside the loop, work with Collections |
| Hardcoded URLs or API keys | Named Credential always |
| HTTP Callout on a record-triggered flow's synchronous path | Move to Asynchronous Path |
| Element without a connected Fault Path | Connect Fault Path to a logging subflow |
| `System Context without Sharing` without justification | User or System with Sharing; document if without |
| Multi-screen wizards with Next buttons everywhere | Reactive components on fewer screens |
| Custom LWC for what `lightning-record-form` does | Use the standard component |
| `Send Email` with template Id only | Persistent template reference (Summer '26 default) |
| Scattered Decision elements mapping the same values | Global Flow Resources + Transform element |
| Activating flows directly in production | CI/CD pipeline with metadata deployment + Flow Tests |
| No Flow Test for autolaunched / record-triggered logic | Add Flow Tests; they count toward coverage |
| API version < 67.0 on new flows | `<apiVersion>67.0</apiVersion>` in the `.flow-meta.xml` |
| Custom Apex input type with no no-argument constructor | Add a public no-arg constructor (required for invocable action inputs in v67) |
| Free-text action input where values are a fixed set | Define picklist values on the input via `InvocableActionExtension` |
| Multiple record-triggered flows on the same object firing for the same DML | Consolidate, or use entry conditions; order between flows is not guaranteed |
| Trust AI "Fix Issue" suggestions without review | Verify in Debug mode before activation |

---

## Summary — The Five Commandments

1. **Flow first, Apex second** — declarative is faster to build, easier to maintain, and equally bulkified when used correctly.
2. **Bulkify by structure** — never SOQL/DML inside a Loop; use Collections; use custom batch size when scale demands.
3. **Fault Paths are mandatory** — every fallible element gets one, routed to a logging subflow.
4. **Named Credentials always** — no raw URLs, no inline credentials, ever.
5. **Test like Apex** — Flow Tests count for coverage and protect production deployments; treat flows as production code.
