# Lightning Data Service Patterns — Reference (Winter '27 / API v68.0)

Load from `dya-sf-lwc` when writing a component that reads or writes records without Apex.

## What LDS actually is

**Lightning Data Service** is a client-side layer that reads and writes Salesforce records through the
**UI API** and keeps a shared browser cache. Two components asking for the same record get one network
request and one cached copy, and both re-render when it changes. Hence the skill's first rule, avoid
Apex: an `@AuraEnabled` controller bypasses that cache, costing a round trip every time and updating
nothing else on the page.

**UI API** is the REST API behind it, returning record data *plus* the metadata and layout information
a UI needs, with field-level security applied. Its one significant limitation is coverage: it supports
most standard and custom objects but **not all**, and an unsupported object is unreachable by any LDS
adapter, `lightning-record-form` or GraphQL. Check the *UI API Developer Guide* object list before
designing around it — an unsupported object is the most common legitimate reason to fall back to Apex.

A **wire adapter** is a function attached to a component property with `@wire`. The framework calls
it, hands back `{ data, error }`, and calls it again whenever a reactive input changes. You never
invoke it yourself.

## Reading a record

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

**The `$` prefix is the most common LWC mistake.** `'$recordId'` — a string, with a dollar sign —
means "the value of `this.recordId`; re-run this wire whenever it changes". `recordId: this.recordId`
passes the value *once*, at construction, usually while still `undefined`; the wire never re-fires and
the component renders empty forever. If a wire seems never to run, check this first.

Importing fields from `@salesforce/schema/...` instead of the string `'Account.Name'` makes the
reference break at compile time if the field is renamed or deleted, not silently at run time in
production.

## Reading a related list

```javascript
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

@wire(getRelatedListRecords, {
    parentRecordId: '$recordId',
    relatedListId: 'Contacts',
    fields: ['Contact.Id', 'Contact.Name', 'Contact.Email']
})
contacts;
```

## Writing a single record

```javascript
import { createRecord } from 'lightning/uiRecordApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';

async handleCreate() {
    try {
        const record = await createRecord({
            apiName: ACCOUNT_OBJECT.objectApiName,
            fields: { Name: this.accountName }
        });
        // record.id is available here
    } catch (error) {
        this.showError(error);
    }
}
```

`updateRecord` and `deleteRecord` take the same shape. For multi-record writes use GraphQL mutations
(`references/graphql-patterns.md`).

## Object metadata and picklists

`getObjectInfo` and `getPicklistValues` from `lightning/uiObjectInfoApi` return object metadata and
record-type-aware picklist values. Picklist values derived by hand or hardcoded in JavaScript are
guaranteed to drift from the org.

## The full adapter directory

Four modules. Reaching for Apex or GraphQL without knowing an adapter existed is the most common way
a component ends up heavier than needed.

| Module | Adapters |
|---|---|
| `lightning/uiRecordApi` | `getRecord`, **`getRecords`**, `createRecord`, `updateRecord`, `deleteRecord`, `notifyRecordUpdateAvailable` |
| `lightning/uiRelatedListApi` | `getRelatedListRecords`, **`getRelatedListRecordsBatch`**, `getRelatedListInfo`, `getRelatedListInfoBatch`, `getRelatedListsInfo`, **`getRelatedListCount`** |
| `lightning/uiObjectInfoApi` | `getObjectInfo`, **`getObjectInfos`**, `getPicklistValues`, **`getPicklistValuesByRecordType`** |
| **`lightning/uiListsApi`** | `getListRecordsByName`, `getListInfoByName`, `getListInfosByName`, `getListInfosByObjectName`, `getListObjectInfo`, `createListInfo`, `updateListInfoByName`, `getListPreferences`, `updateListPreferences` |

### `optionalFields` versus `fields`

The most common cause of a `getRecord` wire erroring in a multi-profile org:

- A field the user cannot access, listed in **`fields`**, makes the whole wire **error**.
- The same field in **`optionalFields`** is silently omitted from the result.

Put any field the running user might lack FLS on into `optionalFields` and handle its absence, or
the component breaks for one profile while working for yours.

### List views

```javascript
import { getListRecordsByName } from 'lightning/uiListsApi';

@wire(getListRecordsByName, {
    objectApiName: 'Account',
    listViewApiName: 'AllAccounts',
    fields: ['Account.Name'],
    pageSize: 50,              // default 50, valid 1-2000
    sortBy: ['-Account.Name'], // leading '-' is descending
    where: '...'               // GraphQL filter syntax
})
listView;
```

Also accepts `optionalFields`, `searchTerm` (wildcards supported) and `pageToken`.

### `updateRecord`'s second argument

```javascript
await updateRecord(
    { fields: { Id: recordId, Name: 'New' } },
    { ifUnmodifiedSince: this.lastModifiedDate }   // optimistic concurrency
);
```

`ifUnmodifiedSince` turns a silent last-write-wins into a detectable conflict. The `recordInput`
also accepts `triggerOtherEmail`, `triggerUserEmail`, `useDefaultRule` (case and lead assignment
rules) and `allowSaveOnDuplicate` — all defaulting to `false`, which is why assignment rules seem not
to fire from an LWC until requested.

## Telling the cache something changed

```javascript
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
```

Call it after something outside LDS changed a record — an Apex callout, an imperative Apex write —
so the cache refreshes and every component bound to that record re-renders. Do not use the deprecated
predecessor, `getRecordNotifyChange`.

## Refreshing a wired Apex method — a different mechanism

`notifyRecordUpdateAvailable` refreshes the **LDS** cache. A component reading through `@wire` on an
Apex method bypasses LDS, so that call does nothing and stale data stays on screen with no error. Use
`refreshApex`, which needs the **raw wire result** — keep it instead of destructuring:

```javascript
import { refreshApex } from '@salesforce/apex';
import getContacts from '@salesforce/apex/ContactController.getContacts';

export default class ContactList extends LightningElement {
    wiredContacts;                                   // ✅ the whole result, not { data, error }

    @wire(getContacts, { accountId: '$recordId' })
    wired(result) {
        this.wiredContacts = result;
        if (result.data) { this.contacts = result.data; }
    }

    async handleSaved() {
        await refreshApex(this.wiredContacts);       // ✅ re-runs the wire
    }
}
```

Which one to reach for:

| The component reads via | Something changed the record through | Refresh with |
|---|---|---|
| LDS (`getRecord`, `getRelatedListRecords`, base components) | LDS imperative (`updateRecord`) | nothing — LDS updates itself |
| LDS | Apex or a callout | `notifyRecordUpdateAvailable([{ recordId }])` |
| **Wired** Apex | anything, including LDS | **`refreshApex(this.wiredResult)`** |
| **Imperative** Apex | anything | call the method again — there is no wire to refresh |
| `lightning-record-form` / `-edit-form` / `-view-form` | its own save | nothing — it refreshes itself |

## Handling errors from three different shapes

```javascript
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils';

showError(error) {
    this.dispatchEvent(new ShowToastEvent({
        title: 'Error',
        message: reduceErrors(error).join(', '),
        variant: 'error'
    }));
}
```

LDS, GraphQL (`errors`, plural) and `AuraHandledException` each return a different error shape.
`reduceErrors` from the standard `ldsUtils` community utility normalises all three. A hand-rolled one
handles only the shape you happened to test.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| `recordId: this.recordId` in a wire config | `recordId: '$recordId'` — the `$` makes it reactive |
| An Apex controller for single-record CRUD | `createRecord` / `updateRecord` / `deleteRecord` |
| An Apex controller for a related list | `getRelatedListRecords` |
| `'Account.Name'` as a string | `import NAME_FIELD from '@salesforce/schema/Account.Name'` |
| Hardcoded picklist values in JavaScript | `getPicklistValues` |
| `getRecordNotifyChange` | `notifyRecordUpdateAvailable` |
| A hand-rolled error formatter | `reduceErrors` from `ldsUtils` |
| Designing around LDS for an object the UI API does not support | Check the supported-object list first; Apex is the legitimate fallback |
