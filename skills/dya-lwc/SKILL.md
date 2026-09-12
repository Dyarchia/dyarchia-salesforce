---
name: dya-lwc
description: Salesforce LWC and (UI-facing) Apex Winter '27 (API v68.0) modern development best practices — template syntax and expressions, Lightning Data Service, GraphQL queries and mutations, shared reactive state via @lwc/state, third-party web components, the @AuraEnabled contract, dev tooling, Jest. Load only when the user explicitly invokes this skill by name (`dya-lwc`); do NOT auto-trigger on generic LWC, Lightning, or component-related questions.
---

# Salesforce LWC & Apex (UI Layer) — Modern Development

You **always** use the most modern syntax available and you **never** call Apex when a client-side
alternative exists. Follow every rule below.

References:

- `references/shared/` — the platform fundamentals underneath: `platform-deltas.md` (what this release
  changes), `metadata-and-api-versions.md` (what the `apiVersion` in a bundle actually decides),
  `org-model.md` (orgs, DX projects, deployment), `sharing-and-access.md` (what a controller is
  allowed to read).
- `references/lds-patterns.md` — **what LDS, the UI API and a wire adapter are**, plus every read and
  write pattern and the `'$property'` reactive syntax. Start here if any of those terms is unfamiliar.
- `references/graphql-patterns.md` — query, paginated query, mutation and multi-object patterns.
- `references/state-management.md` — `@lwc/state` manager patterns and Lightning Message Service.
- `references/dev-tooling-and-config.md` — the bundle meta XML, SLDS styling hooks, local preview, TypeScript, Dynamic Lists.
- `references/apex-controller-contract.md` — the minimum viable `@AuraEnabled` controller with its DTO.
- `references/jest-testing.md` — Jest setup, the `createElement` + `flushPromises` pattern, wire and Apex mocking, accessibility tests with Sa11y.
- `references/lws-rules.md` — the Lightning Web Security rules where ordinary JavaScript compiles and then behaves differently. Read it when a component works locally and not in the org.

Server-side Apex — security design, SOQL and DML, triggers, async, observability, testing — is
`dya-apex`. Who a controller's caller is allowed to see is `dya-permissions`. Flow mechanics are
`dya-flow`. Components running outside Lightning Experience are `dya-lwr` and `dya-lwr-sites`.

---

## Platform Context — Winter '27 / API v68.0

Save new bundles at `<apiVersion>68.0</apiVersion>`. The version is per bundle and decides that
component's semantics; see `references/shared/metadata-and-api-versions.md`.

Four facts gate what compiles and deploys:

- **Complex template expressions are GA, but need the bundle at `apiVersion` 66.0 or higher.** Below
  that they do not compile, which is the version-stamp trap this skill exists to prevent.
- **Dynamic Lists virtualization is Developer Preview**, so it is not available in production.
  Proposing one as the default produces a component that cannot be deployed.
- **Lightning Web Security blocks `data:` URIs** on `HTMLAnchorElement.href`. Client-side downloads
  use `blob:` with an explicit MIME type. §8 and `references/lws-rules.md`.
- **From API 67.0 an `@AuraEnabled` class defaults to `with sharing` and user mode**, and
  `WITH SECURITY_ENFORCED` no longer compiles. §7.

> What the release adds, and the standing GA behaviour each section builds on:
> `references/release-notes.md`.

---

## 1. Absolute Rule — Avoid Apex When Alternatives Exist

Evaluate in order, and stop at the first option that satisfies the requirement:

1. **`lightning-record-form`** and its view/edit siblings — single-record CRUD on the standard layout.
2. **LDS wire adapters** — `lightning/uiRecordApi`, `lightning/uiRelatedListApi`,
   `lightning/uiObjectInfoApi` and **`lightning/uiListsApi`** for records, related lists, object
   metadata, picklist values and **list views** (`getListRecordsByName`).
3. **GraphQL wire adapter** (`lightning/graphql` v2) — multi-object queries, filtering, aggregation,
   pagination.
4. **LDS imperative functions** — `createRecord`, `updateRecord`, `deleteRecord`.
5. **GraphQL mutations** — `executeMutation` for multi-record DML, chaining a later mutation onto an
   earlier one's Id with `@{alias}`.
6. **Apex** — only when none of the above can express it: complex cross-object logic, callouts,
   platform events, async work, or an object the **UI API does not support**.

That last exclusion is the one that decides real designs, and it needs checking rather than guessing:
the UI API covers most standard and custom objects but not all, and an object it does not support is
unreachable by *every* option above. The supported-object list is in the UI API Developer Guide.
`references/lds-patterns.md` explains what the UI API is and how LDS sits on it.

When you do fall back to Apex, put a class-level comment saying which client-side option failed and
why.

## 2. Template Syntax

**Conditionals** are `lwc:if` / `lwc:elseif` / `lwc:else`. The legacy `if:true` / `if:false` are an
anti-pattern.

```html
<template lwc:if={isLoading}>
    <lightning-spinner alternative-text="Loading"></lightning-spinner>
</template>
<template lwc:elseif={hasData}>
    <c-data-table data={records}></c-data-table>
</template>
<template lwc:else>
    <p>No records found.</p>
</template>
```

**Expressions in templates are now GA**, so a getter that exists only to format a value is no longer
necessary — provided the bundle is at `apiVersion` 66.0 or above.

```html
<p>{firstName + ' ' + lastName}</p>
<p>{user?.role === 'admin' ? 'Manager' : 'Member'}</p>
```

Keep a getter when the logic is genuinely more than an expression, or when it is worth naming.
"Because it fits on one line" is not on its own a reason to inline it.

**Dynamic event listeners** use `lwc:on` with an object of event name to handler. Listeners are rebound
when the object reference changes and cleaned up on disconnect, so there is no `removeEventListener`
to forget.

```html
<button lwc:on={buttonHandlers}>Click Me</button>
```

Keys are bare event names (`click`, not `onclick`). Combining `lwc:on` with an `onevent={...}`
attribute for the same event throws. With `lwc:component` and `lwc:is`, it is also how you attach
listeners to a dynamically loaded child.

**Third-party web components** use `lwc:external` on the tag. Before this existed the only option was
an iframe, so a third-party element in older code is usually worth revisiting.

**Property spread** uses `lwc:spread={props}`. Reassign the object to trigger reactivity —
`this.childProps = { ...this.childProps, name: 'Updated' }`. Mutating a property in place does not
re-render.

**Reactivity**: primitive fields are reactive without `@track`. Use `@track` only for deep tracking
when you actually mutate nested properties of an object or array, and prefer creating a new
object or array instead.

**Native accordions**: give sibling `<details>` elements the same `name` and opening one closes the
others, with no JavaScript and no `lightning-accordion`.

## 3. Lightning Data Service

LDS reads and writes records through the UI API and keeps a **shared browser cache**, so two
components asking for the same record cost one request and both re-render when it changes. An Apex
controller bypasses that cache entirely — which is the concrete reason section 1 puts Apex last, not
a stylistic preference.

```javascript
@wire(getRecord, { recordId: '$recordId', fields: FIELDS })
account;
```

The `'$recordId'` string — with the dollar sign — means "the current value of `this.recordId`, and
re-run when it changes". Writing `recordId: this.recordId` passes the value once, usually while it is
still `undefined`, and the wire never fires again. This is the most common reason a component renders
empty forever.

Import fields from `@salesforce/schema/...` rather than writing `'Account.Name'`: a renamed field then
breaks the build instead of failing silently in production.

**Refreshing after a write has two answers, and picking the wrong one fails silently.** When Apex or
a callout changed the record, call `notifyRecordUpdateAvailable([{ recordId }])` so the LDS cache
re-fetches; `getRecordNotifyChange` is deprecated. But when the component reads through a **wired
Apex** method, that notification does nothing — the wire is not LDS. Refresh it with
`refreshApex(this.wiredResult)` from `@salesforce/apex`, which means keeping the raw wire result
(`@wire(m) wired(result) { this.wiredResult = result; }`) instead of destructuring `{ data, error }`.
Apex called *imperatively* has no wire to refresh: call it again. Record-form base components
refresh themselves.

> Every read and write pattern, object metadata, picklists, and error normalisation: `references/lds-patterns.md`.

## 4. GraphQL — the Default for Queries and Mutations

Use `lightning/graphql` (v2), never the deprecated `lightning/uiGraphQLApi` (v1). The v2 adapter
returns `errors` — plural.

- Pass dynamic values through `variables` with a getter, never interpolated into the query string.
- Default page size is 10. Set `first` explicitly and paginate with `after` and `endCursor`.
- Several queries can share one operation, so unrelated objects come back in a single round trip.
- A query that depends on another's result needs its own `@wire`; GraphQL will not sequence them.

> Query, paginated query, multi-object query and batch mutation implementations: `references/graphql-patterns.md`.

## 5. Shared State Across Components

Two GA mechanisms with genuinely different jobs.

**`@lwc/state`** is for shared **reactive** state between components on the same page. A state manager
pulls the data and its logic out of the components into a reusable, testable module, so siblings
coordinate without lifting state into a common parent or drilling props through layers that do not
care. Built-in **Lightning State Managers** wrap LDS for record-backed state, so most cases need no
hand-written manager.

**Lightning Message Service** is pub/sub over a Lightning Message Channel, and is the right tool when
the relationship crosses the DOM, crosses pages, crosses apps, or crosses technologies — LWC talking
to Aura or Visualforce, or a utility-bar component broadcasting application-wide. Subscribe in
`connectedCallback` and **unsubscribe in `disconnectedCallback`**; a subscription that outlives its
component is a leak.

| Scenario | Solution |
|---|---|
| Local state — a counter, a toggle, a form field | A plain field; reactive by default |
| Parent to child | `@api` property |
| Child to parent | A `CustomEvent` |
| Siblings on the same page sharing reactive state | `@lwc/state` |
| Record-backed shared state | A built-in Lightning State Manager, or a GraphQL wire |
| Across the DOM, pages or apps | Lightning Message Service |
| LWC talking to Aura or Visualforce | Lightning Message Service |

For directly related components, `@api` properties and events remain correct and simplest — reach for
a state manager when the relationship is genuinely lateral, not merely awkward.

> Manager patterns, channel definition, scope options, Aura and Visualforce interop: `references/state-management.md`.

## 6. Navigation and the Agentforce Panel

Launch a flow with the `standard__flow` PageReference. Keys in `state` map directly onto the flow's
input variables.

```javascript
this[NavigationMixin.Navigate]({
    type: 'standard__flow',
    attributes: { apiName: 'My_Onboarding_Flow' },
    state: { inputVar1: 'value1', recordId: this.recordId }
});
```

`lightning/accApi` is the headless Agentforce Conversation Client: `open()`, `close()` and
`execute(utterance, botId)` drive the Agentforce side panel from your own UI without embedding the
chat component. Confirm the exact import binding against the module docs for your release. Building
the agent itself is `dya-agentforce`.

## 7. The `@AuraEnabled` Contract

This is the only server-side surface this skill owns. Everything else about Apex is `dya-apex`.

- Declare `with sharing` and query `WITH USER_MODE` explicitly. From API 67.0 both are the default,
  but stating them keeps the intent readable and stable. `WITH SECURITY_ENFORCED` no longer compiles.
- `cacheable=true` for reads — served from the LDS cache after the first call, cannot perform DML,
  must be `static`. No `cacheable` for writes.
- Parameters and return values are primitives or `@AuraEnabled` DTO wrappers, never raw `SObject`.
- The controller delegates to a service class. Business logic does not live in the `@AuraEnabled`
  method.
- Throw `AuraHandledException` on failure, so the component receives a clean message rather than a
  stack trace.

Use `@wire` for cacheable reads and an imperative `await` only for DML or non-cacheable work. An
imperative call in `connectedCallback` for something `@wire` could serve is the anti-pattern: it
bypasses the cache and loses the reactive re-fetch.

> The minimum viable controller with its DTO, and the `@wire` versus imperative forms: `references/apex-controller-contract.md`.

## 8. JavaScript

`const` and `let`, never `var`. Arrow functions for callbacks. Template literals over concatenation.
Optional chaining and nullish coalescing. `async`/`await` over `.then()` chains, except inside `@wire`
handlers, which are not async functions. Destructuring. `Array.prototype` methods over manual loops.

**Downloads use `blob:`, never `data:`.** Lightning Web Security blocks `data:` URIs on
`HTMLAnchorElement.href`, so the old "set `href` to a data URI and click" trick fails silently.

```javascript
downloadCsv(csv) {
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
    const a = this.template.querySelector('a.download');
    a.href = url;
    a.download = 'export.csv';
    a.click();
    URL.revokeObjectURL(url);
}
```

## 9. Decision Matrix — Is This Even Apex?

| Need | Solution | Apex? |
|---|---|---|
| Display or edit one record on the standard layout | `lightning-record-form` | NO |
| Read fields from a record by id | `getRecord` wire adapter | NO |
| Read a related list | `getRelatedListRecords` | NO |
| Query with filters, sorting, pagination | GraphQL `@wire` | NO |
| Query several objects in one call, or aggregate | GraphQL multi-query | NO |
| Create, update or delete one record | `createRecord` / `updateRecord` / `deleteRecord` | NO |
| Batch DML | GraphQL mutations chained with `@{alias}` | NO |
| Picklist values or object metadata | `lightning/uiObjectInfoApi` | NO |
| Shared reactive state between same-page components | `@lwc/state` | NO |
| Broadcast across DOM, page, app or technology | Lightning Message Service | NO |
| Launch a flow | `standard__flow` PageReference | NO |
| Single-open accordion | Grouped `<details name>` | NO |
| Use a third-party custom element | `lwc:external` | NO |
| Complex cross-object logic, callouts, async | Apex `@AuraEnabled` | YES |
| An object the UI API does not support | Apex | YES |

## 10. Testing — Jest

`@salesforce/sfdx-lwc-jest` is the only supported LWC unit-test runner. Install it once per DX project,
keep one `jest.config.js` at the root, and put each test in a `__tests__` folder inside the bundle.

- **`createElement` → `appendChild` → assert.** Query through `element.shadowRoot`, never `document`.
- **Rendering is asynchronous.** After any property change, wire emit or resolved promise, `await`
  a flushed microtask before asserting.
- **Reset between tests.** Remove every child of `document.body` and clear mocks in `afterEach`; jsdom
  and mocks are shared within a file.
- **Mock wires with `.emit()` and `.error()`** on the imported adapter. The `registerTestWireAdapter`
  family is legacy.
- **Imperative Apex is mocked with `jest.mock`** on the `@salesforce/apex/...` module.
- **Test behaviour, not internals.** Assert rendered output and dispatched events; never reach into
  private methods or snapshot whole trees.

> Setup, config, the canonical test, wire and Apex mocking, anti-patterns: `references/jest-testing.md`.

## 11. Configuration and Tooling

The bundle's `js-meta.xml` decides where the component can be placed (`isExposed`, `targets`) and what
an admin can configure (`targetConfigs`), and carries the `apiVersion` that sets its semantics. Local
preview (`sf lightning dev component`) runs a component without deploying, from inside a DX project.

> Meta XML, SLDS styling hooks for Flow screens, preview commands, TypeScript, Dynamic Lists: `references/dev-tooling-and-config.md`.

## 12. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct approach |
|---|---|
| `if:true` / `if:false` | `lwc:if` / `lwc:elseif` / `lwc:else` |
| A getter whose whole body is one formatting expression | A template expression — GA, needs `apiVersion` 66.0+ |
| Many hardcoded `onclick` / `onmouseenter` attributes | `lwc:on={handlers}` |
| An iframe to host a third-party custom element | `lwc:external` |
| `@track` on a primitive | A bare field — already reactive |
| Mutating an object passed via `lwc:spread` | Reassign a new object |
| `recordId: this.recordId` in a wire config | `recordId: '$recordId'` |
| Apex for single-record CRUD, list queries or related lists | LDS adapters and GraphQL |
| An Apex controller to launch a flow | `standard__flow` PageReference |
| An imperative Apex call where `@wire` would serve | `@wire` — it caches and re-fetches reactively |
| Prop drilling or lifting state to share between siblings | `@lwc/state` for same-page reactive state |
| LMS for two components on the same page | `@lwc/state`; keep LMS for crossing DOM, pages or technologies |
| Subscribing to LMS without unsubscribing | `unsubscribe` in `disconnectedCallback` |
| `lightning/uiGraphQLApi` (v1) | `lightning/graphql` (v2) |
| `getRecordNotifyChange` | `notifyRecordUpdateAvailable` |
| `var` | `const` / `let` |
| `.then().catch()` chains in imperative calls | `async` / `await` with `try`/`catch` |
| A `data:` URI for a client-side download | A `blob:` object URL |
| `WITH SECURITY_ENFORCED` in an `@AuraEnabled` class | `WITH USER_MODE` — the old form does not compile |
| Manual JavaScript open/close for a simple accordion | Grouped `<details name>` |
| A Developer Preview feature in production code | The GA path |

## Summary — The Five Commandments

1. **Avoid Apex.** LDS adapters, GraphQL, and the standard component library cover most needs — and LDS shares a cache that an Apex controller bypasses entirely.
2. **Modern template syntax only** — `lwc:if`, `lwc:on`, `lwc:spread`, `lwc:external`, and template expressions now that they are GA at `apiVersion` 66.0 and above.
3. **GraphQL v2 is the default for queries and mutations** — never the deprecated v1 adapter.
4. **`@lwc/state` for same-page shared reactive state.** Keep Lightning Message Service for what only it can do: crossing the DOM, pages, apps, or technologies.
5. **Treat `@AuraEnabled` Apex as code, not glue** — explicit `with sharing` and `USER_MODE`, DTOs rather than raw SObjects, `AuraHandledException` on failure, and the real logic in a service class.
