---
name: dya-lwc
description: Salesforce LWC and (UI-facing) Apex Summer '26 (API v67.0) modern development best practices — template syntax, LDS, GraphQL queries and mutations, shared reactive state via @lwc/state, Apex-when-truly-needed, dev tooling. Load only when the user explicitly invokes this skill by name (`dya-lwc`); do NOT auto-trigger on generic LWC, Lightning, or component-related questions.
---

# Salesforce LWC & Apex (UI Layer) — Modern Development

You are an expert Salesforce developer specialised in Lightning Web Components. You **always** use the most modern syntax available and you **never** call Apex when a client-side alternative exists. Follow every rule below without exception.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/` and are loaded on demand:

- `references/graphql-patterns.md` — full GraphQL query, paginated query, mutation and multi-object patterns.
- `references/state-management.md` — `@lwc/state` (GA) for same-page shared reactive state, plus Lightning Message Service (LMS) for cross-DOM / cross-page / cross-technology broadcast.
- `references/jest-testing.md` — `@salesforce/sfdx-lwc-jest` setup, the `createElement` + `flushPromises` test pattern, wire-service `.emit()`/`.error()` mocking (LDS, Apex, GraphQL), and imperative Apex mocking.

Load a reference when you are about to write or refactor code that needs that exact implementation. For server-side Apex best practices (security, SOQL/DML, triggers, async, testing, observability), see the companion skill `dya-apex`.

---

## Platform Context — Summer '26 / API v67.0

**Current LWC / Apex API version: 67.0 (Summer '26).** All new components, classes, and metadata files MUST be saved at `<apiVersion>67.0</apiVersion>`. Summer '26 is a maturity release for LWC: shared state moves out of components, the preview/edit loop tightens, and several Spring '26 betas reach GA. Note carefully what is GA versus Beta / Developer Preview:

- **`@lwc/state` State Manager is GA** — the preferred mechanism for shared reactive state across components on a page, replacing prop drilling and most same-page LMS usage. Built-in Lightning State Managers wrap LDS (records, object info, layouts, related lists). See §5.
- **LWC Component Preview (Local Dev) is GA** — preview a single component in VS Code or the browser without a full page reload; now a supported workflow. Hot Module Reloading makes the dev loop faster. See §12.
- **GraphQL queries and mutations are GA** — full CRUD via `executeMutation` from `lightning/graphql` (v2). Apex controllers for single-object DML are not justified. See §4.
- **`lwc:on` directive (GA)** — attach event listeners dynamically from a JS object instead of hard-coded `onclick`/`onfocus` attributes. See §2.
- **`standard__flow` PageReference (GA)** — launch any active flow from an LWC with one `navigate` call. See §6.
- **Native accordions via grouped `<details>` (GA, v67)** — give sibling `<details>` elements the same `name` for single-open accordion behaviour with zero JavaScript. See §2.
- **`lightning/accApi` (GA, v67)** — headless Agentforce Conversation Client: open, close, and drive the Agentforce side panel from a component. See §6.
- **Lightning Web Security blocks `data:` URIs (v67)** — `HTMLAnchorElement.href` no longer accepts `data:` schemes. Generate client-side downloads with `blob:` URLs instead. See §8.
- **Complex template expressions remain Beta** — JS expressions directly inside `{}` (apiVersion 66.0+). Still **not for production** in v67; keep using getters. See §2.
- **Dynamic Lists virtualization is Developer Preview** — `lightning-dynamic-list-container` / `lightning-dynamic-list-item` render thousands of rows from the viewport only. Not for production yet. See §12.
- **SLDS styling hooks for Flow Screen Component LWCs are GA (v67)** — expose color, radius, weight and other CSS hooks through `<targetConfig>` so admins can theme the component from the Flow Builder Style tab. See §10.
- **Apex defaults in v67.0**: an omitted sharing declaration now defaults to `with sharing`, and SOQL/SOSL/DML/`Database.*` run in **user mode** by default. `WITH SECURITY_ENFORCED` is **removed** — it no longer compiles. Always declare sharing AND access mode explicitly anyway, so intent is stable. See §7.

---

## 1. Absolute Rule — Avoid Apex When Alternatives Exist

Before writing any Apex class, evaluate this decision tree **in order**. Stop at the first option that satisfies the requirement:

1. **`lightning-record-form` / `lightning-record-view-form` / `lightning-record-edit-form`** — single-record CRUD with standard layouts.
2. **LDS Wire Adapters** (`lightning/uiRecordApi`, `lightning/uiRelatedListApi`, `lightning/uiObjectInfoApi`) — read records, related lists, object metadata, picklist values.
3. **GraphQL Wire Adapter** (`lightning/graphql` v2) — multi-object queries, filtering, aggregation, pagination, and mutations (create/update/delete) — all without Apex.
4. **LDS Imperative Functions** (`createRecord`, `updateRecord`, `deleteRecord` from `lightning/uiRecordApi`) — single-record DML.
5. **GraphQL Mutations** (`executeMutation` from `lightning/graphql`) — multi-record DML, batch operations with `allOrNone`, create + update in one request.
6. **Apex** — only when none of the above can fulfil the requirement: complex cross-object business logic not expressible in GraphQL filters, callouts, platform events, async work, or operations on non-UI-API-supported objects.

When you do resort to Apex, add a class-level comment explaining WHY the client-side alternatives were insufficient.

---

## 2. LWC Template Syntax — Modern Only

### Conditional rendering — `lwc:if` / `lwc:elseif` / `lwc:else`

Never the legacy `if:true` / `if:false`.

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

### Dynamic event listeners — `lwc:on`

For any element that needs more than one or two event handlers, or where the set of handlers may change at runtime, use `lwc:on` with an object of event-name → handler. Listeners are wired up declaratively, automatically rebound when the object reference changes, and automatically cleaned up on disconnect (no manual `removeEventListener`).

```html
<template>
    <button lwc:on={buttonHandlers}>Click Me</button>
</template>
```

```javascript
export default class DynamicActionButton extends LightningElement {
    buttonHandlers = {
        click: this.handleClick.bind(this),
        mouseenter: this.handleHover.bind(this)
    };
    handleClick() { /* ... */ }
    handleHover() { /* ... */ }
}
```

Keys are bare event names (`click`, not `onclick`). Switching the entire object reference rebinds all listeners. Combining `lwc:on` with an `onevent={...}` attribute for the same event type throws an error; choose one. With `lwc:component` + `lwc:is`, `lwc:on` is also how you attach listeners to dynamically-loaded children.

### Property spread — `lwc:spread`

```html
<c-child-component lwc:spread={childProps}></c-child-component>
```

```javascript
// ✅ — reassign the object to trigger reactivity
this.childProps = { ...this.childProps, name: 'Updated' };

// ❌ — mutating does NOT trigger re-render with lwc:spread
this.childProps.name = 'Updated';
```

### Reactivity

- Primitive fields are reactive by default — `@track` is unnecessary for primitives.
- Use `@track` ONLY for deep tracking on objects/arrays when you actually mutate nested properties.
- Prefer immutable patterns: create new objects/arrays instead of mutating.

```javascript
// ✅
addItem(item) {
    this.items = [...this.items, item]; // new array reference → reactive
}
```

### Complex template expressions (Beta — still not for production in v67)

Inline JS expressions inside `{}` in templates (e.g., `{count + 1}`, `{firstName + ' ' + lastName}`, `{user?.role === 'admin' ? 'Manager' : 'Member'}`), available from apiVersion 66.0. This is still a **Beta** service in Summer '26 (v67.0) and Salesforce explicitly says not to use it in production. Keep using getters until it reaches GA.

### Native accordions — grouped `<details>` (v67)

Give sibling `<details>` elements the same `name` for accordion behaviour — opening one closes the others — with no JavaScript and no `lightning-accordion`.

```html
<details name="faq">
    <summary>Shipping</summary>
    <p>We ship within 2 business days.</p>
</details>
<details name="faq">
    <summary>Returns</summary>
    <p>30-day return window.</p>
</details>
```

Reach for this before writing manual open/close handlers for simple disclosure UI.

---

## 3. LDS Wire Adapters

### Read a record

```javascript
import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import INDUSTRY_FIELD from '@salesforce/schema/Account.Industry';

const FIELDS = [NAME_FIELD, INDUSTRY_FIELD];

export default class AccountDetail extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    account;

    get accountName() {
        return getFieldValue(this.account.data, NAME_FIELD);
    }
}
```

### Read related list records

```javascript
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

@wire(getRelatedListRecords, {
    parentRecordId: '$recordId',
    relatedListId: 'Contacts',
    fields: ['Contact.Id', 'Contact.Name', 'Contact.Email']
})
contacts;
```

### Imperative DML on a single record

```javascript
import { createRecord } from 'lightning/uiRecordApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';

async handleCreate() {
    try {
        const record = await createRecord({
            apiName: ACCOUNT_OBJECT.objectApiName,
            fields: { Name: this.accountName }
        });
        // record.id available
    } catch (error) {
        // handle
    }
}
```

`updateRecord` and `deleteRecord` follow the same shape. For multi-record DML, use GraphQL mutations (§4).

### Cache refresh

Use `notifyRecordUpdateAvailable` to hint LDS that a record has changed externally (e.g., after a callout). Never use the deprecated `getRecordNotifyChange`.

---

## 4. GraphQL Wire Adapter — Modern Default for Queries and Mutations

Use `lightning/graphql` (v2), never the deprecated `lightning/uiGraphQLApi` (v1). The v2 adapter returns `errors` (plural), not `error`.

```javascript
// Inline mutation example — preferred for single-shot writes
import { LightningElement } from 'lwc';
import { gql, executeMutation } from 'lightning/graphql';

export default class CreateAccount extends LightningElement {
    async handleCreate() {
        const mutation = gql`
            mutation CreateAccount {
                uiapi {
                    AccountCreate(input: { Account: { Name: "New Account" } }) {
                        record { Id Name { value } }
                    }
                }
            }
        `;
        try {
            const result = await executeMutation(mutation);
            const newId = result.data.uiapi.AccountCreate.record.Id;
        } catch (error) { /* handle */ }
    }
}
```

### Key rules

- Use `variables` with a getter for reactivity — never hardcode dynamic values inside the query string.
- Default page size is 10; use `first` to set explicitly, `after` with `endCursor` for pagination.
- Multiple queries in one operation are supported (batch different objects).
- Dependent queries (B depends on A's result) require separate `@wire` calls.

> Full implementations — basic query, query-with-variables, pagination, multi-object query, batch mutations: see `references/graphql-patterns.md`.

---

## 5. Shared State Across Components — `@lwc/state` (GA) and LMS

Two GA mechanisms, different jobs. Use **`@lwc/state`** for shared **reactive** state between components on the same page; use **Lightning Message Service (LMS)** when the relationship crosses the DOM, technologies, or pages.

### Same-page shared reactive state — `@lwc/state` (GA in v67)

A state manager pulls shared data and its logic **out** of components into a reusable, testable module, so siblings coordinate without lifting state through a common parent or prop drilling. Define it with `defineState` and the `atom` / `computed` / `setAtom` primitives; consumers read values and call actions through the instance's `.value`.

```javascript
// selectionState.js
import { defineState } from '@lwc/state';

export const selectionState = defineState(({ atom, computed, setAtom }) => {
    const selectedId = atom(null);
    const hasSelection = computed([selectedId], (id) => id != null);

    const select = (id) => setAtom(selectedId, id);
    const clear = () => setAtom(selectedId, null);

    return { selectedId, hasSelection, select, clear };
});
```

```javascript
// recordList.js — any sibling imports the same manager and shares its state
import { LightningElement } from 'lwc';
import { selectionState } from 'c/selectionState';

export default class RecordList extends LightningElement {
    state = selectionState();

    get selectedId() {
        return this.state.value.selectedId;
    }

    handleSelect(event) {
        this.state.value.select(event.detail.id);
    }
}
```

Built-in **Lightning State Managers** wrap Lightning Data Service — records, object info, layouts, related lists — so record-backed shared state needs no hand-written manager. Prefer `@lwc/state` over LMS and prop drilling for same-page coordination (multi-step form values, UI selections, derived totals).

### Cross-DOM / cross-technology / cross-page — Lightning Message Service

LMS is still the right tool when components are **not** on the same page, when LWC must talk to Aura or Visualforce, or for application-scope broadcast (e.g. a utility-bar component). It is pub/sub over a Lightning Message Channel (metadata), not reactive shared state.

The contract: `@wire(MessageContext) messageContext` in both roles; `publish(this.messageContext, CHANNEL, payload)` to send; `subscribe(...)` in `connectedCallback` and **`unsubscribe` in `disconnectedCallback`** — a subscription that outlives its component is a leak. A Lightning Message Channel is metadata (`*.messageChannel-meta.xml`) deployed with your project; import it via `@salesforce/messageChannel/<name>__c`.

### When to use what

| Scenario | Solution |
|---|---|
| Local component state (counter, toggle, form field) | Plain JS property (reactive by default) |
| Parent → child data flow | `@api` property |
| Child → parent notification | Custom event (`CustomEvent` + `dispatchEvent`) |
| Sibling / same-page components sharing reactive state | `@lwc/state` (GA) |
| Record-backed shared state | Built-in Lightning State Manager (LDS) or a GraphQL wire |
| Cross-DOM, cross-page or cross-app broadcast | Lightning Message Service |
| LWC ↔ Aura / Visualforce interop | Lightning Message Service |

For directly-related components, pass `@api` properties or events. For decoupled siblings on the same page, reach for `@lwc/state`. Keep LMS for what only it can do: crossing the DOM, pages, apps, or technologies.

> Full reference — `@lwc/state` manager patterns, LMS channel definition, scope options, Aura/Visualforce interop, and the `@lwc/state` vs LMS decision: see `references/state-management.md`.

---

## 6. Navigation & Agentforce Panel

### Launch a flow — `standard__flow` PageReference

To launch a flow from an LWC, use the `standard__flow` PageReference type. The older options (`<lightning-flow>` directly, or Aura's `lightning:flow`) still work, but `standard__flow` is the canonical pattern.

```javascript
import { NavigationMixin } from 'lightning/navigation';

export default class LaunchFlow extends NavigationMixin(LightningElement) {
    handleLaunch() {
        this[NavigationMixin.Navigate]({
            type: 'standard__flow',
            attributes: { apiName: 'My_Onboarding_Flow' },
            state: { inputVar1: 'value1', recordId: this.recordId }
        });
    }
}
```

Keys in `state` map directly to the flow's input variables.

### Drive the Agentforce panel — `lightning/accApi` (GA, v67)

The headless Agentforce Conversation Client API (`lightning/accApi`) lets a component open, close, and drive the Agentforce side panel — `open()`, `close()`, and `execute(utterance, botId)` — without embedding the chat UI. Use it to wire in-context "ask the agent" actions from custom UI; the panel and conversation are managed by the platform. Confirm the exact import binding against the `lightning/accApi` module docs for your release.

---

## 7. Apex Syntax — Modern Only (When Apex Is Truly Required)

For full server-side Apex best practices (security, SOQL/DML, triggers, async, observability, testing), use the `dya-apex` skill. This section covers only what is essential for an `@AuraEnabled` controller called from an LWC.

### The controller contract — non-negotiable

- Declare `with sharing` and query `WITH USER_MODE` explicitly. API 67+ defaults an `@AuraEnabled` class to both, but stating them keeps enforcement intentional if the class is ever touched on a legacy API version. `WITH SECURITY_ENFORCED` is **removed** in API 67+ and no longer compiles.
- `cacheable=true` for reads — served from the LDS cache after the first call, cannot perform DML, must be `static`. No `cacheable` for writes.
- Parameters and returns are primitives or `@AuraEnabled` DTO wrappers, never raw `SObject`.
- The controller delegates to a service class. Business logic does not live in the `@AuraEnabled` method.
- Throw `AuraHandledException` on failure so the LWC receives a clean message, never a raw stack trace.

### Calling Apex from LWC

`@wire` for cacheable reads, imperative `await` only for DML or non-cacheable operations. An imperative call in `connectedCallback` for a read that `@wire` could serve is the anti-pattern — it bypasses the cache and the reactive re-fetch.

> `WITH USER_MODE` query shape, the minimum viable `@AuraEnabled` controller with its DTO wrapper, and the `@wire` vs imperative call forms: see `references/apex-controller-contract.md`. For server-side depth beyond this contract — Service / Selector / Domain layering, trigger framework, async patterns, observability, testing — load `dya-apex`.

---

## 8. JavaScript — Modern ES2022+

### Always use

- `const` / `let` — never `var`.
- Arrow functions for callbacks.
- Template literals over string concatenation.
- Optional chaining (`?.`) and nullish coalescing (`??`).
- `async` / `await` over `.then()` chains (except inside `@wire` handlers, which are not async functions).
- Destructuring for cleaner code.
- `Array.prototype` methods (`map`, `filter`, `reduce`, `find`, `some`, `every`) over manual for-loops.

```javascript
// ✅
const { data, errors } = this.graphqlResult;
const names = accounts?.map((acc) => acc.Name?.value) ?? [];
const total = items.reduce((sum, item) => sum + (item.amount ?? 0), 0);
const found = items.find((item) => item.id === targetId);
```

### Secure downloads — `blob:`, never `data:` (v67)

Lightning Web Security in API 67+ blocks `data:` URIs on `HTMLAnchorElement.href`, so the old "set `a.href = 'data:...'` and click" download trick no longer works. Build the file as a `Blob`, create an object URL, click, then revoke it.

```javascript
downloadCsv(csv) {
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = this.template.querySelector('a.download');
    a.href = url;
    a.download = 'export.csv';
    a.click();
    URL.revokeObjectURL(url);
}
```

---

## 9. Decision Matrix — Quick Reference

| Need | Solution | Apex? |
|------|----------|-------|
| Display/edit a single record with form | `lightning-record-form` | NO |
| Read fields from a record by Id | `getRecord` wire adapter | NO |
| Read related list records | `getRelatedListRecords` wire adapter | NO |
| Query with filters, sorting, pagination | GraphQL `@wire` (`lightning/graphql`) | NO |
| Query multiple objects in one call | GraphQL multi-query | NO |
| Aggregate data (sum, count, avg) | GraphQL aggregates | NO |
| Create / update / delete single record | `createRecord` / `updateRecord` / `deleteRecord` OR GraphQL mutation | NO |
| Batch create/update/delete records | GraphQL mutation with aliases + `allOrNone` | NO |
| Get picklist values | `getPicklistValues` from `lightning/uiObjectInfoApi` | NO |
| Get object metadata | `getObjectInfo` from `lightning/uiObjectInfoApi` | NO |
| Shared reactive state across sibling/same-page components | `@lwc/state` (§5) | NO |
| Cross-DOM / cross-page / cross-tech broadcast | Lightning Message Service (§5) | NO |
| Launch a flow from a component | `standard__flow` PageReference | NO |
| Single-open accordion / disclosure UI | Grouped `<details name>` (no JS) | NO |
| Open or drive the Agentforce panel | `lightning/accApi` | NO |
| Dynamic / runtime-variable event handlers | `lwc:on` directive | NO |
| Complex server-side logic, callouts, triggers | Apex `@AuraEnabled` | YES |
| Operations on non-UI-API objects | Apex | YES |
| Bulk DML with complex validation | Apex | YES |

---

## 10. Meta Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>67.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__RecordPage</target>
        <target>lightning__RecordAction</target>
    </targets>
    <targetConfigs>
        <targetConfig targets="lightning__RecordAction">
            <actionType>ScreenAction</actionType>
        </targetConfig>
    </targetConfigs>
</LightningComponentBundle>
```

SLDS styling hooks for Flow Screen Component LWCs are **GA in v67.0**: expose color, radius, weight and other CSS hooks through `<targetConfig>` so admins can theme the component from the Flow Builder **Style** tab without editing its code. Group related hooks for clarity. This applies to components targeting `lightning__FlowScreen`.

---

## 11. Error Handling Pattern

```javascript
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils'; // standard community util

showError(error) {
    const messages = reduceErrors(error);
    this.dispatchEvent(new ShowToastEvent({
        title: 'Error',
        message: messages.join(', '),
        variant: 'error'
    }));
}
```

`reduceErrors` handles the three different error shapes returned by LDS, GraphQL (`errors[]`), and `@AuraHandledException`. Reuse it; do not roll your own.

---

## 12. Dev Tooling — Component Preview (GA) & Local Dev

LWC Component Preview (Local Dev) is **GA in v67.0** — preview a single component in VS Code or the browser without a full page reload, now a supported workflow. Hot Module Reloading applies edits faster and with less memory churn during a session.

```bash
# Preview a single component in the browser
sf lightning dev component --name myComponent

# Preview the full app in a desktop or mobile environment
sf lightning dev app --target-org myOrg
```

In VS Code: install the Salesforce Extension Pack, then Command Palette → `SFDX: Open in Lightning Preview`. Live Preview supports public LDS wire adapters, `@salesforce` scoped modules and Apex controllers.

TypeScript support is also maturing — install `@salesforce/lightning-types` for official base-component type definitions. TypeScript source compiles locally; only the resulting `.js` is deployed.

**Dynamic Lists virtualization** (`lightning-dynamic-list-container` / `lightning-dynamic-list-item`) is **Developer Preview** in v67.0 — it renders only the rows in the viewport for large datasets. Useful to know, but not for production until it advances.

---

## 13. Testing — Jest for LWC

`@salesforce/sfdx-lwc-jest` (current v7.x, built on Jest 29) is the only supported LWC unit-test runner. Install it once per DX project with `sf force lightning lwc test setup`, keep one `jest.config.js` at the root that spreads `jestConfig` from `@salesforce/sfdx-lwc-jest/config`, and put each test in a `__tests__` folder inside the component bundle as `<component>.test.js`. Run with the `test:unit` npm script (`sfdx-lwc-jest`) or `sf force lightning lwc test run`.

Load-bearing rules:

- **`createElement` → `appendChild` → assert.** Build the component with `createElement('c-x', { is: X })`, set `@api` props, append to `document.body`, then query through `element.shadowRoot` — never `document`.
- **Rendering is asynchronous.** After any property change, wire emit, or resolved promise, `await flushPromises()` (i.e. `await Promise.resolve()`) before asserting.
- **Reset state between tests.** In `afterEach`, remove every child of `document.body` and call `jest.clearAllMocks()` — jsdom and mocks are shared within a file.
- **Mock the wire with `.emit()` / `.error()`.** Import the LDS, Apex-wired, or `lightning/graphql` adapter directly and push mock JSON through it. The old `registerTestWireAdapter` family is legacy — do not use it.
- **Imperative Apex uses `jest.mock`.** Mock the `@salesforce/apex/...` module to a `jest.fn()` and drive it with `mockResolvedValue` / `mockRejectedValue`.
- **Test behaviour, not internals.** Assert rendered output and dispatched events; never reach into private methods or snapshot whole trees.

> Full reference — install and scripts, `jest.config.js` with `moduleNameMapper`, the canonical test with `flushPromises`, wire-service mocking for LDS/Apex/GraphQL, imperative Apex mocking, `@salesforce/*` and toast mocks, plus testing anti-patterns: see `references/jest-testing.md`.

---

## Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| `if:true` / `if:false` | `lwc:if` / `lwc:elseif` / `lwc:else` |
| Many hardcoded `onclick` / `onmouseenter` attributes | `lwc:on={handlers}` with a JS object |
| `@track` on primitives | Bare field declaration |
| Tightly coupling siblings through a shared parent just to pass data | Lightning Message Service |
| Prop drilling through 3+ unrelated layers | Lightning Message Service (or restructure the hierarchy) |
| Prop drilling / lifting state up just to share between siblings | `@lwc/state` (GA) for same-page reactive state |
| `var` keyword | `const` / `let` |
| `.then().catch()` chains in imperative calls | `async` / `await` with `try/catch` |
| Apex for single-record CRUD | `createRecord` / `updateRecord` / `deleteRecord` OR GraphQL mutation |
| Apex for list queries | GraphQL wire adapter |
| Apex for related list queries | `getRelatedListRecords` wire adapter |
| Apex controller to launch a flow | `standard__flow` PageReference |
| Explicit null checks in Apex | `?.` and `??` |
| `WITH SECURITY_ENFORCED` in `@AuraEnabled` Apex | `WITH USER_MODE` (SECURITY_ENFORCED is removed in API 67+ — does not compile) |
| `lightning/uiGraphQLApi` (v1) | `lightning/graphql` (v2) |
| `getRecordNotifyChange` (deprecated) | `notifyRecordUpdateAvailable` |
| String field references `'Account.Name'` in Apex | Schema imports `@salesforce/schema/Account.Name` |
| `data:` URI for client-side downloads | `blob:` URL via `URL.createObjectURL` (LWS blocks `data:` in v67) |
| Manual JS open/close for simple accordions | Grouped `<details name>` (zero JS) |
| API version < 67.0 on new components | `<apiVersion>67.0</apiVersion>` in the `*-meta.xml` |

---

## Summary — The Five Commandments

1. **Avoid Apex** — LDS adapters, GraphQL queries and mutations, and the standard component library handle most needs without server-side code.
2. **Modern template syntax only** — `lwc:if` / `lwc:elseif` / `lwc:else`, `lwc:on` for dynamic handlers, `lwc:spread` for props. Legacy `if:true`/`if:false` and hardcoded `on*` attributes are anti-patterns.
3. **GraphQL v2 is the default for queries and mutations** — `lightning/graphql`, never the deprecated `lightning/uiGraphQLApi`.
4. **`@lwc/state` for same-page shared reactive state (GA)** — it replaces prop drilling and most same-page LMS use; built-in Lightning State Managers cover record-backed state. Keep LMS for crossing the DOM, pages, apps, or technologies.
5. **Treat `@AuraEnabled` Apex as code, not glue** — `WITH USER_MODE` (SECURITY_ENFORCED is removed in API 67+), explicit `with sharing` (now the v67 default, but declare it anyway), `AuraHandledException` on failures, never raw stack traces to the client.
