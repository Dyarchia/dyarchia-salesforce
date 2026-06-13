# Visualforce Controller Patterns — Reference Implementation (API v67.0)

Full implementations referenced from SKILL.md §2–§4. Load this when writing or refactoring a Visualforce controller, extension, or list controller on Summer '26 (API v67.0). Visualforce controllers are Apex, so the deep Apex rules in `decimatio-apex` (Service/Selector/Domain layering, async, testing, observability) apply on top of everything here.

## Standard Controller + Extension Skeleton

The extension constructor receives an `ApexPages.StandardController`. Query once, cache in fields, expose actions that return `PageReference` (or `null` to stay on the page).

```java
public with sharing class AccountDashboardExt {

    private final ApexPages.StandardController stdCtrl;
    private final Id accountId;

    // Render-only data — excluded from view state.
    public transient List<Contact> contacts { get; private set; }
    public transient List<Opportunity> openOpps { get; private set; }

    // Small, postback-relevant state stays non-transient.
    public String selectedView { get; set; }

    public AccountDashboardExt(ApexPages.StandardController stdCtrl) {
        this.stdCtrl = stdCtrl;
        this.accountId = stdCtrl.getId();
        this.selectedView = 'open';
        loadData();
    }

    private void loadData() {
        this.contacts = [
            SELECT Id, Name, Email, Phone FROM Contact
            WHERE AccountId = :accountId WITH USER_MODE
            ORDER BY LastName LIMIT 200
        ];
        this.openOpps = [
            SELECT Id, Name, Amount, StageName FROM Opportunity
            WHERE AccountId = :accountId AND IsClosed = false
            WITH USER_MODE ORDER BY CloseDate LIMIT 200
        ];
    }

    public PageReference refresh() {
        loadData();              // re-query on demand instead of holding huge view state
        return null;             // stay on the same page
    }

    public PageReference saveAndReturn() {
        // Delegate real persistence to a Service class; StandardController.save()
        // handles the parent record with CRUD/FLS + sharing enforced.
        this.stdCtrl.save();
        return new PageReference('/' + accountId);
    }
}
```

Page wiring:

```html
<apex:page standardController="Account" extensions="AccountDashboardExt"
           lightningStylesheets="true">
    <apex:slds />
    <div class="slds-scope">
        <apex:repeat value="{!contacts}" var="c">
            <apex:outputField value="{!c.Name}" />
        </apex:repeat>
    </div>
</apex:page>
```

## View State Discipline

The view state hard limit is 135 KB. Every non-`transient` member field is serialised on each postback.

| Field role | Declaration |
|---|---|
| Query results used only to render this response | `transient` |
| Large blobs, derived/aggregate data, wrapper lists for display | `transient` |
| Small scalar values needed across postbacks (filters, selected ids, flags) | non-transient |
| References to `StandardController`, services, selectors | `private final` (and consider `transient`) |

Rules:

- Re-query in an action method (`refresh()` above) rather than carrying a big collection across postbacks.
- Bind `<apex:inputField>` directly to SObject fields; don't shadow every field into scalar properties.
- Use the View State Inspector (enable Development Mode) to verify size before shipping.

## Custom Controller — CRUD/FLS Is Your Job

A standard controller enforces CRUD/FLS/sharing automatically. A custom controller does not. Declare `with sharing` and enforce field access via `WITH USER_MODE` queries and `Security.stripInaccessible`.

```java
public with sharing class CaseConsoleController {

    public transient List<Case> cases { get; private set; }

    public CaseConsoleController() {
        // USER_MODE enforces object + field permissions for the running user.
        this.cases = [
            SELECT Id, CaseNumber, Subject, Status, Priority FROM Case
            WHERE IsClosed = false WITH USER_MODE
            ORDER BY CreatedDate DESC LIMIT 200
        ];
    }

    public PageReference closeSelected(Id caseId) {
        Case c = new Case(Id = caseId, Status = 'Closed');
        Database.update(c, AccessLevel.USER_MODE);   // FLS/CRUD enforced
        return null;
    }
}
```

## Injection-Safe Dynamic SOQL

Never concatenate user input into a query. Prefer bind variables; for fully dynamic queries use `Database.queryWithBinds` with `AccessLevel.USER_MODE`.

```java
public with sharing class SearchController {

    public String keyword { get; set; }
    public String industry { get; set; }
    public transient List<Account> results { get; private set; }

    public PageReference search() {
        Map<String, Object> binds = new Map<String, Object>{
            'kw'  => '%' + keyword + '%',
            'ind' => industry
        };
        this.results = Database.queryWithBinds(
            'SELECT Id, Name, Industry FROM Account ' +
            'WHERE Name LIKE :kw AND Industry = :ind ' +
            'WITH USER_MODE LIMIT 200',
            binds,
            AccessLevel.USER_MODE
        );
        return null;
    }
}
```

If you genuinely cannot bind (e.g. a dynamic field/object name), validate against a `Schema.describe` allow-list and `String.escapeSingleQuotes` the literal — never trust raw input.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| SOQL/DML in a getter | Query in constructor or action method; cache in a field |
| Big collection in a non-`transient` field | Mark `transient`; re-query on demand |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` (removed in API 67+) |
| Custom controller with no sharing keyword | `with sharing` + `WITH USER_MODE` |
| `'SELECT … ' + userInput` | `Database.queryWithBinds(q, binds, USER_MODE)` |
| `StandardController.save()` reimplemented by hand | Reuse the standard action; it enforces security |
| Shadowing every SObject field into scalar properties | Bind components straight to SObject fields |
