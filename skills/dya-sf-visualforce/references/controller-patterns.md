# Visualforce Controller Patterns — Reference Implementation (Winter '27 / API v68.0)

Implementations for SKILL.md §2–§4, for writing or refactoring a controller, extension or list controller.

## Standard Controller + Extension Skeleton

Actions return a `PageReference`, or `null` to stay on the page.

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
        loadData();              // re-query instead of holding huge view state
        return null;             // stay on the page
    }

    public PageReference saveAndReturn() {
        // Real persistence goes to a Service class; StandardController.save()
        // saves the parent record with CRUD/FLS + sharing enforced.
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

Every non-`transient` member field is serialised on each postback.

| Field role | Declaration |
|---|---|
| Query results used only to render this response | `transient` |
| Large blobs, derived/aggregate data, wrapper lists for display | `transient` |
| Small scalar values needed across postbacks (filters, selected ids, flags) | non-transient |
| References to `StandardController`, services, selectors | `private final` (and consider `transient`) |

## Custom Controller — CRUD/FLS Is Your Job

```java
public with sharing class CaseConsoleController {

    public transient List<Case> cases { get; private set; }

    public CaseConsoleController() {
        // USER_MODE enforces the running user's object + field permissions.
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

If you cannot bind (e.g. a dynamic field/object name), validate against a `Schema.describe` allow-list and `String.escapeSingleQuotes` the literal.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| `StandardController.save()` reimplemented by hand | Reuse the standard action; it enforces security |
