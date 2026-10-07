# Lightning Data Service Patterns — Reference (Winter '27 / API v68.0)

Load from `dya-sf-lwc` when writing a component that reads or writes records without Apex.

## What LDS is

**Lightning Data Service** is a client-side layer over the **UI API** with a shared browser cache
(SKILL.md §3). An `@AuraEnabled` controller bypasses that cache, costing a round trip every time and
updating nothing else on the page.

**UI API** is the REST API behind it, returning record data *plus* the metadata and layout information
a UI needs, with field-level security applied. It does not support every object; see SKILL.md §1.

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

If a wire seems never to run, check the `$` prefix first (SKILL.md §3).

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

Use `getObjectInfo` and `getPicklistValues` from `lightning/uiObjectInfoApi` for object metadata and
record-type-aware picklist values. Never derive picklist values by hand or hardcode them in JavaScript;
they drift from the org.

## The full adapter directory

| Module | Adapters |
|---|---|
| `lightning/uiRecordApi` | `getRecord`, **`getRecords`**, `createRecord`, `updateRecord`, `deleteRecord`, `notifyRecordUpdateAvailable` |
| `lightning/uiRelatedListApi` | `getRelatedListRecords`, **`getRelatedListRecordsBatch`**, `getRelatedListInfo`, `getRelatedListInfoBatch`, `getRelatedListsInfo`, **`getRelatedListCount`** |
| `lightning/uiObjectInfoApi` | `getObjectInfo`, **`getObjectInfos`**, `getPicklistValues`, **`getPicklistValuesByRecordType`** |
| **`lightning/uiListsApi`** | `getListRecordsByName`, `getListInfoByName`, `getListInfosByName`, `getListInfosByObjectName`, `getListObjectInfo`, `createListInfo`, `updateListInfoByName`, `getListPreferences`, `updateListPreferences` |

### `optionalFields` versus `fields`

- A field the user cannot access, listed in **`fields`**, makes the whole wire **error**.
- The same field in **`optionalFields`** is silently omitted from the result.

Put any field the running user might lack FLS on into `optionalFields` and handle its absence.

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
rules) and `allowSaveOnDuplicate` — all default to `false`, so assignment rules do not fire from an
LWC unless requested.

## Telling the cache something changed

```javascript
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
```

Call it after Apex or a callout changes a record; every component bound to that record then
re-renders.

## Refreshing a wired Apex method — a different mechanism

A wired Apex method bypasses LDS, so `notifyRecordUpdateAvailable` does nothing and stale data stays
on screen with no error. `refreshApex` needs the **raw wire result**:

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

| The component reads via | Something changed the record through | Refresh with |
|---|---|---|
| LDS (`getRecord`, `getRelatedListRecords`, base components) | LDS imperative (`updateRecord`) | nothing — LDS updates itself |
| LDS | Apex or a callout | `notifyRecordUpdateAvailable([{ recordId }])` |
| **Wired** Apex | anything, including LDS | **`refreshApex(this.wiredResult)`** |
| **Imperative** Apex | anything | call the method again — there is no wire to refresh |
| `lightning-record-form` / `-edit-form` / `-view-form` | its own save | nothing — it refreshes itself |

## Normalising error shapes

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
Normalise all three with `reduceErrors` from the standard `ldsUtils` community utility. A hand-rolled
formatter usually handles only the shape you tested.

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
