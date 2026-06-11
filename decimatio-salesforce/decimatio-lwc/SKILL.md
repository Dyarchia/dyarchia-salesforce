---
name: decimatio-lwc
description: Salesforce LWC and (UI-facing) Apex Spring '26 (API v66.0) modern development best practices — template syntax, LDS, GraphQL queries and mutations, shared state via LMS, Apex-when-truly-needed, dev tooling. Load only when the user explicitly invokes this skill by name (`decimatio-lwc`); do NOT auto-trigger on generic LWC, Lightning, or component-related questions.
---

# Salesforce LWC & Apex (UI Layer) — Modern Development

You are an expert Salesforce developer specialised in Lightning Web Components. You **always** use the most modern syntax available and you **never** call Apex when a client-side alternative exists. Follow every rule below without exception.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/` and are loaded on demand:

- `references/graphql-patterns.md` — full GraphQL query, paginated query, mutation and multi-object patterns.
- `references/state-management.md` — Lightning Message Service (LMS) reference for shared state across sibling/same-page components, plus a forward note on `@lwc/state`.

Load a reference when you are about to write or refactor code that needs that exact implementation. For server-side Apex best practices (security, SOQL/DML, triggers, async, testing, observability), see the companion skill `decimatio-apex`.

---

## Platform Context — Spring '26 / API v66.0

**Current LWC / Apex API version: 66.0 (Spring '26).** All new components, classes, and metadata files MUST be saved at `<apiVersion>66.0</apiVersion>`. Spring '26 ships several user-facing developer additions. Note carefully which features are GA versus Beta in this release:

- **GraphQL mutations are GA** — full CRUD support via `executeMutation` from `lightning/graphql` (v2), introduced alongside the v2 adapter in Spring '26. Apex controllers for single-object DML are no longer justified. See §4.
- **`lwc:on` directive** (Spring '26) — attach event listeners dynamically from a JS object instead of hard-coded `onclick`/`onfocus` attributes. See §2.
- **`standard__flow` PageReference** (Spring '26) — launch any active flow from an LWC with one `navigate` call. Before this, you had to use `<lightning-flow>` directly or wrap with Aura's `lightning:flow`. See §6.
- **Complex template expressions (Beta)** — JS expressions directly inside `{}` in templates, introduced in Spring '26. Beta only; do NOT use in production code until GA.
- **LWC State Management (`@lwc/state`) is NOT GA in v66.0** — it is only Beta this release and reaches GA in Summer '26 (v67.0). Do NOT use it in production. For shared state across sibling/same-page components, use Lightning Message Service. See §5.
- **LWC Live Preview is Beta** in VS Code (still "Local Dev"); it reaches GA in Summer '26. Usable for local iteration, but not a supported production workflow yet. See §12.
- **Apex defaults in v66.0**: an omitted sharing declaration on an `@AuraEnabled` class defaults to `without sharing`, and plain SOQL/DML defaults to system mode. (Both flip in v67.0: default sharing becomes `with sharing` and DB operations run in user mode by default.) Always declare sharing AND access mode explicitly so behaviour does not change on upgrade.
- **`WITH SECURITY_ENFORCED` still compiles in v66.0** but is deprecated and is removed in API 67+. Prefer `WITH USER_MODE` now for forward-compatibility (see §7).
- **SLDS styling hooks for Flow Screen Component LWCs are not available in v66.0** — that capability ships in Summer '26 (v67.0). In v66.0, theming options for Flow Screen Components are limited to what the platform already exposes.

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

### Complex template expressions (Beta — do not use in production)

Spring '26 introduced inline JS expressions inside `{}` in templates (e.g., `{count + 1}`, `{firstName + ' ' + lastName}`, `{user?.role === 'admin' ? 'Manager' : 'Member'}`). This is **Beta** in v66.0. Keep using getters until it reaches GA; revisit on a later release.

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

## 5. Shared State Across Components — Lightning Message Service (GA)

For state that **two or more components on the same page need to share** when they are not in a simple parent → child relationship, use **Lightning Message Service (LMS)** — the GA, production-supported mechanism in v66.0. LMS works across the DOM, across components that aren't related, and even across technologies (LWC, Aura, Visualforce).

> **Do NOT use `@lwc/state` in production on v66.0.** It is only Beta this release and does not reach GA until Summer '26 (API v67.0). When you upgrade to v67, you can migrate same-page shared state from LMS to `@lwc/state`; until then, LMS is the correct choice.

```javascript
// publisher.js
import { LightningElement, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import CART_CHANNEL from '@salesforce/messageChannel/Cart__c';

export default class ProductTile extends LightningElement {
    @wire(MessageContext) messageContext;

    handleAdd(event) {
        publish(this.messageContext, CART_CHANNEL, {
            id: event.detail.id,
            name: event.detail.name,
            price: event.detail.price
        });
    }
}
```

```javascript
// subscriber.js
import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import CART_CHANNEL from '@salesforce/messageChannel/Cart__c';

export default class CartSummary extends LightningElement {
    @wire(MessageContext) messageContext;
    items = [];
    subscription;

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            CART_CHANNEL,
            (message) => { this.items = [...this.items, message]; }
        );
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    get total() {
        return this.items.reduce((sum, i) => sum + (i.price ?? 0), 0);
    }
}
```

A Lightning Message Channel is metadata (`*.messageChannel-meta.xml`) deployed with your project; import it via `@salesforce/messageChannel/<name>__c`.

### When to use what

| Scenario | Solution |
|---|---|
| Local component state (counter, toggle, form field) | Plain JS property (reactive by default) |
| Parent → child data flow | `@api` property |
| Child → parent notification | Custom event (`CustomEvent` + `dispatchEvent`) |
| Two or more unrelated components on the same page sharing data | Lightning Message Service |
| Cross-page or cross-app broadcast | Lightning Message Service |
| Salesforce record data | LDS or GraphQL wire adapter (let the wire own it) |

For deeply nested but directly-related components, prefer passing `@api` properties or events over LMS; reach for LMS when the components are siblings or otherwise decoupled.

> Full LMS reference (message channel definition, scope options, Aura/Visualforce interop) and a forward-looking note on migrating to `@lwc/state` at v67: see `references/state-management.md`.

---

## 6. Navigation — `standard__flow` (Spring '26)

To launch a flow from an LWC, use the `standard__flow` PageReference type, new in Spring '26. Before this release the options were `<lightning-flow>` directly or wrapping with Aura's `lightning:flow` — both still work, but `standard__flow` is now the canonical pattern.

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

---

## 7. Apex Syntax — Modern Only (When Apex Is Truly Required)

For full server-side Apex best practices (security, SOQL/DML, triggers, async, observability, testing), use the `decimatio-apex` skill. This section covers only what is essential for an `@AuraEnabled` controller called from an LWC.

### SOQL — prefer `WITH USER_MODE` over `WITH SECURITY_ENFORCED`

In v66.0, `WITH SECURITY_ENFORCED` still compiles — but it is deprecated and is **removed in API 67+**. Use `WITH USER_MODE` now: it enforces object permissions, FLS and sharing, supports the full query (not just `SELECT` fields), handles polymorphic fields, returns the complete set of access errors, and is forward-compatible with v67. (`WITH USER_MODE` has been available since API v60.0.)

```java
// ✅ — forward-compatible, enforces FLS + sharing for the running user
List<Account> accounts = [
    SELECT Id, Name FROM Account
    WHERE Industry = :industry
    WITH USER_MODE
    LIMIT 200
];
```

### `@AuraEnabled` controller — minimum viable shape

```java
public with sharing class AccountController {

    // Apex required because: GraphQL cannot express cross-object aggregate
    // with custom rollup AND a callout in the same transaction.
    @AuraEnabled(cacheable=true)
    public static List<AccountWrapper> getSummaries(List<Id> accountIds) {
        return AccountService.buildSummaries(accountIds);   // delegate to service layer
    }

    public class AccountWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal openPipelineTotal;
    }
}
```

In v66.0, an `@AuraEnabled` class with no sharing keyword defaults to `without sharing`, and plain SOQL/DML runs in system mode (both flip in v67.0). Never rely on the default: declare `with sharing` explicitly and query `WITH USER_MODE` so access enforcement is intentional and stable across the v67 upgrade. Use `?.` and `??` for null handling. Throw `AuraHandledException` for failures so the LWC receives a clean message (never raw stack traces).

### Calling Apex from LWC

```javascript
// ✅ — @wire for reads (cacheable)
import getSummaries from '@salesforce/apex/AccountController.getSummaries';
@wire(getSummaries, { accountIds: '$selectedIds' })
summaries;

// ✅ — imperative for DML or non-cacheable operations
async handleSave() {
    try { await saveRecords({ records: this.modifiedRecords }); }
    catch (error) { /* handle */ }
}

// ❌ — imperative call for a read that could be @wire
connectedCallback() {
    getSummaries({ accountIds: this.ids }).then(r => this.data = r);
}
```

`@AuraEnabled(cacheable=true)` reads are served from the Lightning Data Service cache after the first call. Cacheable methods cannot perform DML and must be `static`. For server-side best practices beyond this contract — Service / Selector / Domain layering, trigger framework, async patterns, observability, testing — load `decimatio-apex`.

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
| Shared state across unrelated/sibling components | Lightning Message Service (§5) | NO |
| Cross-page broadcast | Lightning Message Service | NO |
| Launch a flow from a component | `standard__flow` PageReference | NO |
| Dynamic / runtime-variable event handlers | `lwc:on` directive | NO |
| Complex server-side logic, callouts, triggers | Apex `@AuraEnabled` | YES |
| Operations on non-UI-API objects | Apex | YES |
| Bulk DML with complex validation | Apex | YES |

---

## 10. Meta Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
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

SLDS styling hooks exposed through `<targetConfig>` for Flow Screen Components are **not available in v66.0** — that capability arrives in Summer '26 (v67.0). On v66.0, keep Flow Screen Component styling to what the platform already supports and revisit theming hooks after upgrading.

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

## 12. Dev Tooling — Live Preview (Beta in v66.0)

LWC Live Preview (formerly Local Dev) is **Beta in v66.0** and reaches GA in Summer '26. Use it for local iteration — single-component preview in VS Code or browser without a full page reload — but treat it as a developer convenience rather than a supported production workflow until GA.

```bash
# Preview a single component in the browser
sf lightning dev component --name myComponent

# Preview the full app in a desktop or mobile environment
sf lightning dev app --target-org myOrg
```

In VS Code: install the Salesforce Extension Pack, then Command Palette → `SFDX: Open in Lightning Preview`. Live Preview supports public LDS wire adapters, `@salesforce` scoped modules and Apex controllers.

TypeScript support is also maturing — install `@salesforce/lightning-types` for official base-component type definitions. TypeScript source compiles locally; only the resulting `.js` is deployed.

---

## Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| `if:true` / `if:false` | `lwc:if` / `lwc:elseif` / `lwc:else` |
| Many hardcoded `onclick` / `onmouseenter` attributes | `lwc:on={handlers}` with a JS object |
| `@track` on primitives | Bare field declaration |
| Tightly coupling siblings through a shared parent just to pass data | Lightning Message Service |
| Prop drilling through 3+ unrelated layers | Lightning Message Service (or restructure the hierarchy) |
| `@lwc/state` in production on v66.0 | Lightning Message Service (it is Beta until v67) |
| `var` keyword | `const` / `let` |
| `.then().catch()` chains in imperative calls | `async` / `await` with `try/catch` |
| Apex for single-record CRUD | `createRecord` / `updateRecord` / `deleteRecord` OR GraphQL mutation |
| Apex for list queries | GraphQL wire adapter |
| Apex for related list queries | `getRelatedListRecords` wire adapter |
| Apex controller to launch a flow | `standard__flow` PageReference |
| Explicit null checks in Apex | `?.` and `??` |
| `WITH SECURITY_ENFORCED` in `@AuraEnabled` Apex | `WITH USER_MODE` (SECURITY_ENFORCED still compiles in v66.0 but is deprecated and removed in v67+) |
| `lightning/uiGraphQLApi` (v1) | `lightning/graphql` (v2) |
| `getRecordNotifyChange` (deprecated) | `notifyRecordUpdateAvailable` |
| String field references `'Account.Name'` in Apex | Schema imports `@salesforce/schema/Account.Name` |
| API version < 66.0 on new components | `<apiVersion>66.0</apiVersion>` in the `*-meta.xml` |

---

## Summary — The Five Commandments

1. **Avoid Apex** — LDS adapters, GraphQL queries and mutations, and the standard component library handle most needs without server-side code.
2. **Modern template syntax only** — `lwc:if` / `lwc:elseif` / `lwc:else`, `lwc:on` for dynamic handlers, `lwc:spread` for props. Legacy `if:true`/`if:false` and hardcoded `on*` attributes are anti-patterns.
3. **GraphQL v2 is the default for queries and mutations** — `lightning/graphql`, never the deprecated `lightning/uiGraphQLApi`.
4. **Lightning Message Service for shared state across components** — LMS (GA) coordinates data between sibling/unrelated components on a page. `@lwc/state` is only Beta in v66.0 (GA in v67), so keep it out of production for now.
5. **Treat `@AuraEnabled` Apex as code, not glue** — prefer `WITH USER_MODE` (SECURITY_ENFORCED still compiles in v66.0 but is deprecated and removed in v67), explicit `with sharing` (the v66.0 default is `without sharing`), `AuraHandledException` on failures, never raw stack traces to the client.
