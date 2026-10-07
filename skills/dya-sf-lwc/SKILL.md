---
name: dya-sf-lwc
description: Salesforce Lightning Web Components (Winter '27, API v68.0) — templates, Lightning Data Service, GraphQL, @lwc/state, third-party web components, the @AuraEnabled contract, tooling, Jest. Applies to lwc/ bundles (JS, HTML, CSS, js-meta.xml, Jest tests) and the @AuraEnabled methods they call. Load before creating or editing anything in this scope.
---

# Salesforce LWC & Apex (UI Layer) — Modern Development

You **always** use the most modern syntax available and **never** call Apex when a client-side
alternative exists. Follow every rule below.

References:

- `references/shared/` — platform fundamentals: `platform-deltas.md` (what this release
  changes), `metadata-and-api-versions.md` (what a bundle's `apiVersion` decides),
  `org-model.md` (orgs, DX projects, deployment), `sharing-and-access.md` (what a controller is
  allowed to read).
- `references/lds-patterns.md` — **what LDS, the UI API and a wire adapter are**, every read and
  write pattern, and the `'$property'` reactive syntax. Start here if those terms are unfamiliar.
- `references/graphql-patterns.md` — query, paginated query, mutation and multi-object patterns.
- `references/state-management.md` — `@lwc/state` manager patterns and Lightning Message Service.
- `references/dev-tooling-and-config.md` — the bundle meta XML, SLDS styling hooks, local preview, TypeScript, Dynamic Lists.
- `references/apex-controller-contract.md` — the minimum viable `@AuraEnabled` controller with its DTO.
- `references/jest-testing.md` — Jest setup, the `createElement` + `flushPromises` pattern, wire and Apex mocking, accessibility tests with Sa11y.
- `references/lws-rules.md` — Lightning Web Security rules where ordinary JavaScript compiles but behaves differently. Read it when a component works locally but not in the org.

Server-side Apex — security design, SOQL and DML, triggers, async, observability, testing — is
`dya-sf-apex`. Who a controller's caller is allowed to see is `dya-sf-permissions`. Flow mechanics are
`dya-sf-flow`. Components running outside Lightning Experience are `dya-sf-lwr` and `dya-sf-lwr-sites`.

---

## Platform Context — Winter '27 / API v68.0

Save new bundles at `<apiVersion>68.0</apiVersion>`. The version is per bundle and decides its
semantics; see `references/shared/metadata-and-api-versions.md`.

- **Complex template expressions are GA, but need the bundle at `apiVersion` 66.0 or higher.** Below
  that they do not compile.
- **Dynamic Lists virtualization is Developer Preview**, unavailable in production, so a component
  built on it cannot be deployed.
- **Lightning Web Security blocks `data:` URIs** on `HTMLAnchorElement.href`. See §8 and
  `references/lws-rules.md`.
- **From API 67.0 an `@AuraEnabled` class defaults to `with sharing` and user mode**, and
  `WITH SECURITY_ENFORCED` no longer compiles. §7.

> What the release adds, and the GA behaviour each section builds on: `references/release-notes.md`.

---

## 1. Absolute Rule — Avoid Apex When Alternatives Exist

Evaluate in order; stop at the first option that satisfies the requirement:

1. **`lightning-record-form`** and its view/edit siblings — single-record CRUD on the standard layout.
2. **LDS wire adapters** — `lightning/uiRecordApi`, `lightning/uiRelatedListApi`,
   `lightning/uiObjectInfoApi` and **`lightning/uiListsApi`** for records, related lists, object
   metadata, picklist values and **list views** (`getListRecordsByName`).
3. **GraphQL wire adapter** (`lightning/graphql` v2) — multi-object queries, filtering, aggregation,
   pagination.
4. **LDS imperative functions** — `createRecord`, `updateRecord`, `deleteRecord`.
5. **GraphQL mutations** — `executeMutation` for multi-record DML, chaining a mutation onto an
   earlier one's Id with `@{alias}`.
6. **Apex** — only when none of the above can express it: complex cross-object logic, callouts,
   platform events, async work, or an object the **UI API does not support**.

Check that last exclusion against the supported-object list in the UI API Developer Guide: the UI
API covers most standard and custom objects but not all, and an unsupported object is unreachable by
*every* option above.

When falling back to Apex, add a class-level comment saying which client-side option failed and why.

## 2. Template Syntax

**Conditionals** are `lwc:if` / `lwc:elseif` / `lwc:else`. Legacy `if:true` / `if:false` is an
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

**Template expressions** replace a getter that only formats a value, at `apiVersion` 66.0 or higher.

```html
<p>{firstName + ' ' + lastName}</p>
<p>{user?.role === 'admin' ? 'Manager' : 'Member'}</p>
```

Keep a getter when the logic is more than an expression or worth naming, even if it fits on one line.

**Dynamic event listeners** use `lwc:on` with an object mapping event name to handler. Listeners
rebind when the object reference changes and are removed on disconnect, so no `removeEventListener`
is needed.

```html
<button lwc:on={buttonHandlers}>Click Me</button>
```

Keys are bare event names (`click`, not `onclick`). Combining `lwc:on` with an `onevent={...}`
attribute for the same event throws. With `lwc:component` and `lwc:is`, it also attaches listeners
to a dynamically loaded child.

**Third-party web components** use `lwc:external` on the tag. Older code hosting them in an iframe
is worth revisiting.

**Property spread** uses `lwc:spread={props}`. Reassign the object to trigger reactivity —
`this.childProps = { ...this.childProps, name: 'Updated' }`. In-place mutation does not re-render.

**Reactivity**: primitive fields are reactive without `@track`. Use `@track` only to deep-track
mutated nested properties of an object or array — and prefer creating a new object or array.

**Native accordions**: give sibling `<details>` elements the same `name`; opening one closes the
others, with no JavaScript and no `lightning-accordion`.

## 3. Lightning Data Service

LDS reads and writes records through the UI API and keeps a **shared browser cache**: two components
asking for the same record cost one request and both re-render when it changes. An Apex controller
bypasses that cache, which is why section 1 puts Apex last.

```javascript
@wire(getRecord, { recordId: '$recordId', fields: FIELDS })
account;
```

`'$recordId'` means "the current value of `this.recordId`; re-run when it changes".
`recordId: this.recordId` passes the value once, usually while still `undefined`, and the wire never
fires again, so the component renders empty.

Import fields from `@salesforce/schema/...`, not `'Account.Name'`: a renamed field then breaks the
build instead of failing silently in production.

**Refreshing after a write.** When Apex or a callout changed the record, call
`notifyRecordUpdateAvailable([{ recordId }])` so the LDS cache re-fetches; `getRecordNotifyChange` is
deprecated. When the component reads through a **wired Apex** method, that
notification does nothing — the wire is not LDS. Use `refreshApex(this.wiredResult)` from
`@salesforce/apex`, keeping the raw wire result (`@wire(m) wired(result) { this.wiredResult = result; }`)
instead of destructuring `{ data, error }`. *Imperative* Apex has no wire to refresh: call it again.
Record-form base components refresh themselves.

> Every read and write pattern, object metadata, picklists, and error normalisation: `references/lds-patterns.md`.

## 4. GraphQL — the Default for Queries and Mutations

Use `lightning/graphql` (v2), never the deprecated `lightning/uiGraphQLApi` (v1). The v2 adapter
returns `errors` — plural.

- Pass dynamic values through `variables` with a getter, never interpolated into the query string.
- Default page size is 10. Set `first` explicitly and paginate with `after` and `endCursor`.
- Several queries can share one operation, returning unrelated objects in one round trip.
- A query that depends on another's result needs its own `@wire`; GraphQL will not sequence them.

> Query, paginated query, multi-object query and batch mutation implementations: `references/graphql-patterns.md`.

## 5. Shared State Across Components

**`@lwc/state`** is for shared **reactive** state between components in one component tree. A state manager
moves the data and its logic into a reusable, testable module, so siblings coordinate without lifting
state to a common parent or drilling props. Built-in **Lightning State Managers** wrap LDS for
record-backed state, so most cases need no hand-written manager. A state manager needs a provider
ancestor; components placed separately in App Builder have none.

**Lightning Message Service** is pub/sub over a Lightning Message Channel, for relationships that
cross the DOM, pages, apps or technologies — LWC talking to Aura or Visualforce, or a utility-bar
component broadcasting application-wide. Subscribe in `connectedCallback` and **unsubscribe in
`disconnectedCallback`**; a subscription that outlives its component is a leak.

| Scenario | Solution |
|---|---|
| Local state — a counter, a toggle, a form field | A plain field; reactive by default |
| Parent to child | `@api` property |
| Child to parent | A `CustomEvent` |
| Siblings under one container LWC sharing reactive state | `@lwc/state`, provided by the container |
| Record-backed shared state | A built-in Lightning State Manager, or a GraphQL wire |
| Across the DOM: separate App Builder components, utility bar, pages or apps | Lightning Message Service |
| LWC talking to Aura or Visualforce | Lightning Message Service |

For directly related components, `@api` properties and events stay correct and simplest. Use a state
manager only when the relationship is lateral, not merely awkward.

> Manager patterns, channel definition, scope options, Aura and Visualforce interop: `references/state-management.md`.

## 6. Navigation and the Agentforce Panel

Launch a flow with the `standard__flow` PageReference. Keys in `state` map onto the flow's input
variables.

```javascript
this[NavigationMixin.Navigate]({
    type: 'standard__flow',
    attributes: { apiName: 'My_Onboarding_Flow' },
    state: { inputVar1: 'value1', recordId: this.recordId }
});
```

`lightning/accApi` is the headless Agentforce Conversation Client: `open()`, `close()` and
`execute(utterance, botId)` drive the Agentforce side panel from your own UI without embedding the
chat component. Confirm the import binding against the module docs for your release. Building the
agent is `dya-sf-agentforce`.

## 7. The `@AuraEnabled` Contract

The only server-side surface this skill owns.

- Declare `with sharing` and query `WITH USER_MODE` explicitly, although both are the default from
  API 67.0; stating them keeps the intent readable and stable.
- `cacheable=true` for reads — served from the LDS cache after the first call, cannot perform DML,
  must be `static`. No `cacheable` for writes.
- Parameters and return values are primitives or `@AuraEnabled` DTO wrappers, never raw `SObject`.
- The controller delegates to a service class; business logic stays out of the `@AuraEnabled` method.
- Throw `AuraHandledException` on failure, so the component gets a clean message, not a stack trace.

Use `@wire` for cacheable reads and imperative `await` only for DML or non-cacheable work. An
imperative call in `connectedCallback` for something `@wire` could serve bypasses the cache and loses
the reactive re-fetch.

> The minimum viable controller with its DTO, and the `@wire` versus imperative forms: `references/apex-controller-contract.md`.

## 8. JavaScript

`const` and `let`, never `var`. Arrow functions for callbacks. Template literals over concatenation.
Optional chaining and nullish coalescing. `async`/`await` over `.then()` chains, except inside `@wire`
handlers, which are not async functions. Destructuring. `Array.prototype` methods over manual loops.

**Downloads use `blob:` with an explicit MIME type, never `data:`.** A `data:` URI set as `href` and
clicked fails silently under Lightning Web Security. Take the type from the allowed set in
`references/lws-rules.md`: `text/csv` is not on it and throws `Unsupported MIME type.`, so a CSV goes
out as `application/octet-stream` and `download` supplies the name. No `;charset=` parameters.

```javascript
downloadCsv(csv) {
    const url = URL.createObjectURL(new Blob([csv], { type: 'application/octet-stream' })); // ✅ not text/csv
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
keep one `jest.config.js` at the root, and put each test in a `__tests__` folder in the bundle.

- **`createElement` → `appendChild` → assert.** Query through `element.shadowRoot`, never `document`.
- **Rendering is asynchronous.** After any property change, wire emit or resolved promise, `await`
  a flushed microtask before asserting.
- **Reset between tests.** In `afterEach`, remove every child of `document.body` and clear mocks;
  jsdom and mocks are shared within a file.
- **Mock wires with `.emit()` and `.error()`** on the imported adapter. The `registerTestWireAdapter`
  family is legacy.
- **Mock imperative Apex with `jest.mock`** on the `@salesforce/apex/...` module.
- **Test behaviour, not internals.** Assert rendered output and dispatched events; never reach into
  private methods or snapshot whole trees.

> Setup, config, the canonical test, wire and Apex mocking, anti-patterns: `references/jest-testing.md`.

## 11. Configuration and Tooling

The bundle's `js-meta.xml` decides where the component can be placed (`isExposed`, `targets`) and what
an admin can configure (`targetConfigs`), and carries the `apiVersion` that sets its semantics. Local
preview (`sf lightning dev component`) runs a component without deploying, inside a DX project.

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

1. **Avoid Apex.** LDS adapters, GraphQL and the standard component library cover most needs — and LDS shares a cache an Apex controller bypasses.
2. **Modern template syntax only** — `lwc:if`, `lwc:on`, `lwc:spread`, `lwc:external`, and template expressions (GA at `apiVersion` 66.0 and above).
3. **GraphQL v2 is the default for queries and mutations** — never the deprecated v1 adapter.
4. **`@lwc/state` for same-page shared reactive state.** Keep Lightning Message Service for crossing the DOM, pages, apps or technologies.
5. **Treat `@AuraEnabled` Apex as code, not glue** — explicit `with sharing` and `USER_MODE`, DTOs rather than raw SObjects, `AuraHandledException` on failure, and the real logic in a service class.
