# Aura Server-Side Apex & Lightning Data Service — Reference Implementation (API v67.0)

Full implementations referenced from SKILL.md §4–§5. Load this when accessing data from an Aura component on Summer '26 (API v67.0). Evaluate LDS first; reach for `@AuraEnabled` Apex only for genuine server-side logic. Aura controllers are Apex — deep server rules live in `dya-apex`.

## Lightning Data Service — `force:recordData`

Load, create, save, and delete a single record with no Apex and a shared client cache that keeps other LEX components in sync.

```html
<aura:component implements="flexipage:availableForRecordHome,force:hasRecordId">
    <aura:attribute name="recordId" type="Id" />
    <aura:attribute name="account" type="Object" />
    <aura:attribute name="fields" type="Object" />

    <force:recordData aura:id="recordLoader"
                      recordId="{!v.recordId}"
                      fields="Name,Industry,AnnualRevenue"
                      targetFields="{!v.account}"
                      targetError="{!v.error}"
                      mode="EDIT"
                      recordUpdated="{!c.onRecordUpdated}" />

    <lightning:input label="Name" value="{!v.account.Name}" />
    <lightning:button label="Save" onclick="{!c.save}" />
</aura:component>
```

```javascript
({
    save: function (component) {
        component.find("recordLoader").saveRecord(function (result) {
            if (result.state === "SUCCESS" || result.state === "DRAFT") {
                // saved; LDS cache + other components refresh automatically
            } else if (result.state === "ERROR") {
                console.error(result.error);
            }
        });
    },
    onRecordUpdated: function (component, event) {
        const changeType = event.getParams().changeType;   // LOADED | CHANGED | REMOVED | ERROR
        if (changeType === "ERROR") { /* handle */ }
    }
})
```

Prefer `lightning:recordForm` over `force:recordData` when you don't need custom field arrangement — it is even less code. Use `force:recordData` when you need programmatic control over load/save/delete.

## `@AuraEnabled` Controller — When LDS Can't Do It

Reach for Apex only for multi-object queries, aggregates, cross-object logic, callouts, async, or non-UI-API objects. Declare `with sharing`, query `WITH USER_MODE`, throw `AuraHandledException`.

```java
public with sharing class OpportunityController {

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getPipeline(Id accountId) {
        return [
            SELECT Id, Name, Amount, StageName, CloseDate
            FROM Opportunity
            WHERE AccountId = :accountId AND IsClosed = false
            WITH USER_MODE
            ORDER BY CloseDate
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static void closeWon(List<Id> opportunityIds) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Id oppId : opportunityIds) {
            opps.add(new Opportunity(Id = oppId, StageName = 'Closed Won'));
        }
        try {
            Database.update(opps, AccessLevel.USER_MODE);   // bulk, FLS enforced
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
```

## Calling Apex — `$A.enqueueAction` With All Three States

```javascript
({
    loadPipeline: function (component, helper) {
        const action = component.get("c.getPipeline");
        action.setParams({ accountId: component.get("v.recordId") });
        action.setStorable();                 // pairs with cacheable=true
        action.setCallback(this, function (response) {
            const state = response.getState();
            if (state === "SUCCESS") {
                component.set("v.opps", response.getReturnValue());
            } else if (state === "ERROR") {
                helper.showErrors(response.getError());
            } else if (state === "INCOMPLETE") {
                helper.showOffline();          // lost connection / offline
            }
        });
        $A.enqueueAction(action);
    }
})
```

- `cacheable=true` reads → call `action.setStorable()` to serve from the client cache after the first request. Cacheable methods cannot do DML and must be `static`.
- Writes → no `cacheable`, no `setStorable()`.
- Always branch on `SUCCESS` / `ERROR` / `INCOMPLETE`.

## Promise Wrapper — Cleaner Async

Wrapping `enqueueAction` in a Promise lets you use `async/await` in helpers. Resolve/reject inside the action callback so the framework still controls the boundary; wrap UI mutations after `await` in `$A.getCallback` if needed.

```javascript
({
    callApex: function (component, methodName, params, storable) {
        return new Promise(function (resolve, reject) {
            const action = component.get("c." + methodName);
            if (params) { action.setParams(params); }
            if (storable) { action.setStorable(); }
            action.setCallback(this, function (response) {
                const state = response.getState();
                if (state === "SUCCESS") {
                    resolve(response.getReturnValue());
                } else if (state === "ERROR") {
                    reject(response.getError());
                } else {
                    reject([{ message: "Request incomplete (offline?)" }]);
                }
            });
            $A.enqueueAction(action);
        });
    },

    loadPipeline: async function (component) {
        try {
            const opps = await this.callApex(component, "getPipeline",
                { accountId: component.get("v.recordId") }, true);
            $A.getCallback(function () { component.set("v.opps", opps); })();
        } catch (errors) {
            this.showErrors(errors);
        }
    }
})
```

## Error Reduction Helper

`response.getError()` returns an array of error shapes. Reduce to displayable strings before toasting.

```javascript
({
    reduceErrors: function (errors) {
        if (!Array.isArray(errors)) { errors = [errors]; }
        return errors
            .filter(Boolean)
            .map(function (e) {
                if (e.pageErrors && e.pageErrors.length) {
                    return e.pageErrors.map(p => p.message).join(", ");
                }
                if (e.fieldErrors) {
                    return Object.values(e.fieldErrors).flat().map(f => f.message).join(", ");
                }
                return e.message || JSON.stringify(e);
            })
            .filter(Boolean);
    }
})
```

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| `@AuraEnabled` Apex for single-record CRUD | `lightning:recordForm` / `force:recordData` |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` (removed in API 67+) |
| `@AuraEnabled` class with no sharing keyword | `with sharing` + `WITH USER_MODE` |
| `cacheable=true` method that does DML | Remove `cacheable`; cacheable is read-only |
| Cacheable read without `action.setStorable()` | Add `setStorable()` to hit the client cache |
| Handling only `SUCCESS` | Branch on `SUCCESS` / `ERROR` / `INCOMPLETE` |
| Setting attributes after `await` without `$A.getCallback` | Wrap the mutation in `$A.getCallback` |
| Non-bulk DML in `@AuraEnabled` | Bulk `Database.*` with `AccessLevel.USER_MODE` |
| Returning raw exceptions to the client | `AuraHandledException` + Platform Event log |
