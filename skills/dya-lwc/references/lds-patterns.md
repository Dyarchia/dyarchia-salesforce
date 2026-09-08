# Lightning Data Service Patterns — Reference (Winter '27 / API v68.0)

Load from `dya-lwc` when writing a component that reads or writes records without Apex.

## What LDS actually is

**Lightning Data Service** is a client-side layer that reads and writes Salesforce records through the
**UI API** and keeps a shared cache in the browser. Two components asking for the same record get one
network request and one cached copy, and both re-render when it changes. This is why the skill's first
rule is to avoid Apex: an `@AuraEnabled` controller bypasses that cache entirely, so it costs a round
trip every time and updates nothing else on the page.

**UI API** is the REST API behind it. It returns record data *plus* the metadata and layout
information a UI needs, with field-level security already applied. Its one significant limitation is
coverage: it supports most standard and custom objects but **not all of them**, and an object it does
not support cannot be reached by any LDS adapter, `lightning-record-form`, or GraphQL. Check the *UI
API Developer Guide* object list before designing around it — an unsupported object is the single most
common legitimate reason to fall back to Apex.

A **wire adapter** is a function you attach to a component property with `@wire`. The framework calls
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

**The `$` prefix is the single most common LWC mistake.** `'$recordId'` — a string, with a dollar
sign — means "the value of `this.recordId`, and re-run this wire whenever it changes". Writing
`recordId: this.recordId` passes the value *once*, at construction, when it is usually still
`undefined`; the wire then never re-fires and the component renders empty forever. If a wire looks
like it never runs, check this first.

Importing fields from `@salesforce/schema/...` rather than writing `'Account.Name'` as a string means
the reference breaks at compile time if the field is renamed or deleted, instead of silently at run
time in production.

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

`updateRecord` and `deleteRecord` take the same shape. For multi-record writes use GraphQL mutations —
see `references/graphql-patterns.md`.

## Object metadata and picklists

`getObjectInfo` and `getPicklistValues` from `lightning/uiObjectInfoApi` return object metadata and
record-type-aware picklist values. Deriving picklist values by hand, or hardcoding them in JavaScript,
guarantees they drift from the org.

## Telling the cache something changed

```javascript
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
```

Call it after something outside LDS has changed a record — an Apex callout, an imperative Apex write —
so the cache refreshes and every component bound to that record re-renders. `getRecordNotifyChange` is
the deprecated predecessor; do not use it.

## Refreshing a wired Apex method — a different mechanism

`notifyRecordUpdateAvailable` refreshes the **LDS** cache. A component reading through `@wire` on an
Apex method is not going through LDS, so that call does nothing for it and the stale data stays on
screen with no error anywhere. Use `refreshApex`, which needs the **raw wire result** — keep it
instead of destructuring:

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

LDS, GraphQL (`errors`, plural) and `AuraHandledException` each return errors in a different shape.
`reduceErrors` from the standard `ldsUtils` community utility normalises all three. Rolling your own
means handling only the shape you happened to test against.

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
