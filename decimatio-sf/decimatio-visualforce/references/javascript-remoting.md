# Visualforce JavaScript Remoting — Reference Implementation (API v67.0)

Full implementations referenced from SKILL.md §5. Load this when building asynchronous, partial-page server interaction on a Visualforce page. JavaScript Remoting is the modern default: it is stateless (carries **no view state**), fast, and gives you direct control over the request and response in JavaScript.

## `@RemoteAction` Contract

- The method MUST be `static` and annotated `@RemoteAction`.
- Parameters and return types must be primitives, SObjects, collections, or `@RemoteAction`-serialisable Apex types (no `Blob`, no `Object`).
- It runs in its own transaction with its own governor limits — bulkify the same way you would a controller.
- It does NOT automatically enforce CRUD/FLS — use `WITH USER_MODE` / `Security.stripInaccessible` and declare `with sharing` on the class.

```java
public with sharing class ContactRemote {

    @RemoteAction
    public static List<Contact> search(String accountId, String namePrefix) {
        return [
            SELECT Id, Name, Email, Title FROM Contact
            WHERE AccountId = :accountId
              AND Name LIKE :(namePrefix + '%')
            WITH USER_MODE
            ORDER BY LastName
            LIMIT 50
        ];
    }

    @RemoteAction
    public static SaveResultDTO updateEmails(List<Contact> contacts) {
        // Bulk DML, partial success, FLS enforced.
        Database.SaveResult[] srs = Database.update(contacts, false, AccessLevel.USER_MODE);
        SaveResultDTO dto = new SaveResultDTO();
        for (Integer i = 0; i < srs.size(); i++) {
            if (!srs[i].isSuccess()) {
                dto.failedIds.add(contacts[i].Id);
                dto.messages.add(srs[i].getErrors()[0].getMessage());
            }
        }
        dto.successCount = srs.size() - dto.failedIds.size();
        return dto;
    }

    public class SaveResultDTO {
        public Integer successCount = 0;
        public List<Id> failedIds = new List<Id>();
        public List<String> messages = new List<String>();
    }
}
```

## Invoking From the Page

The callback receives `(result, event)`. Always check `event.status` before using `result`; remoting errors arrive on the `event`, not as a thrown JS exception.

```html
<apex:page controller="ContactRemote" lightningStylesheets="true">
    <apex:slds />
    <div class="slds-scope" id="app"></div>

    <script>
        function searchContacts(accountId, prefix) {
            Visualforce.remoting.Manager.invokeAction(
                '{!$RemoteAction.ContactRemote.search}',
                accountId,
                prefix,
                function (result, event) {
                    if (event.status) {
                        render(result);
                    } else if (event.type === 'exception') {
                        console.error(event.message, event.where);
                    } else {
                        console.error('Remoting error', event);
                    }
                },
                { escape: true, timeout: 30000 }
            );
        }

        function render(contacts) {
            // contacts is a plain JS array of the SObject shape returned above
            const app = document.getElementById('app');
            app.textContent = contacts.length + ' contacts';
        }
    </script>
</apex:page>
```

Options object: `escape: true` HTML-escapes string fields in the response (default true — keep it on unless you are deliberately rendering trusted HTML); `timeout` is in ms (max 120000); `buffer: false` disables request batching when calls must fire independently.

## Choosing the Interaction Technique

| Need | Use | View state? | Apex? |
|---|---|---|---|
| Async partial update, full JS control | **JavaScript Remoting** (`@RemoteAction`) | none | YES |
| Simple DML on the page record from a JS event | `<apex:actionFunction>` | full round-trip | YES |
| Basic record CRUD from JS without Apex | **Remote Objects** (`<apex:remoteObjects>`) | none | NO |
| Declarative rerender on a component event | `<apex:actionSupport>` + `rerender` | full round-trip | maybe |

Prefer Remoting for anything data-heavy. Reserve `<apex:actionFunction>`/`<apex:actionSupport>` for small, record-scoped interactions where the view-state round-trip is negligible and you want declarative rerender.

## Remote Objects — CRUD Without Apex

When the page only needs basic CRUD on accessible objects and you'd rather not write a controller:

```html
<apex:page>
    <apex:remoteObjects>
        <apex:remoteObjectModel name="Account" fields="Id,Name,Industry">
            <apex:remoteObjectField name="AnnualRevenue" />
        </apex:remoteObjectModel>
    </apex:remoteObjects>

    <script>
        function loadAccounts() {
            const acct = new SObjectModel.Account();
            acct.retrieve(
                { where: { Industry: { eq: 'Technology' } }, limit: 20 },
                function (err, records) {
                    if (err) { console.error(err); return; }
                    records.forEach(r => console.log(r.get('Name')));
                }
            );
        }
    </script>
</apex:page>
```

Remote Objects enforce the running user's CRUD/FLS automatically (they go through the same access layer as the UI). They cannot do complex server logic — for that, drop to `@RemoteAction`.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| `<apex:actionFunction>` for large data loads | JavaScript Remoting (`@RemoteAction`) |
| Using `result` before checking `event.status` | Branch on `event.status` first |
| `@RemoteAction` without `WITH USER_MODE` / sharing | Declare `with sharing`, query `WITH USER_MODE` |
| Non-bulk DML inside `@RemoteAction` | Bulk `Database.*` with `AccessLevel.USER_MODE` |
| `escape: false` on untrusted response strings | Keep `escape: true` |
| Returning raw exceptions to the browser | Catch, log via Platform Events, return a clean DTO |
