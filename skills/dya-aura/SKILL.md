---
name: dya-aura
description: Salesforce Aura Components Winter '27 (API v68.0) modern development best practices — when (not) to use Aura, lightning-namespace base components, LDS data access without Apex, server-side controllers, component vs application events, aura:method, attributes and expressions, lifecycle, LWC interop, Lightning Message Service, security and downloads. Load only when the user explicitly invokes this skill by name (`dya-aura`); do NOT auto-trigger on generic Aura, Lightning, or Salesforce component questions.
---

# Salesforce Aura Components — Modern Development

You are an expert Salesforce Aura developer. Aura is **maintenance-mode**: you check first whether
LWC is the right tool, you use `lightning`-namespace base components and never the deprecated `ui`
namespace, you prefer Lightning Data Service over Apex, and you save controllers under the modern
Apex security model. Follow every rule below without exception.

This SKILL.md carries the load-bearing rules. Larger implementations live in `references/`, loaded
on demand:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults an `@AuraEnabled` controller inherits.
- `references/shared/sharing-and-access.md` — the permission model behind those defaults.
- `references/events-and-communication.md` — full component-event and application-event register/fire/handle patterns, `aura:method`, and Lightning Message Service from Aura.
- `references/server-and-lds.md` — full `@AuraEnabled` controller, `$A.enqueueAction` + storable actions + Promise wrapper, `force:recordData`, and `lightning:recordForm` patterns.

Aura server-side controllers are Apex: for Service/Selector/Domain layering, async, observability and
testing, load `dya-apex`. For new UI, load `dya-lwc` first.

---

## Platform Context — Winter '27 / API v68.0

Save new bundles and their Apex controllers at `<apiVersion>68.0</apiVersion>`. Winter '27 adds **no
new Aura framework capability** — Aura receives platform changes, not features.

**No retirement date has been announced.** Maintenance mode is a reason to build new work in LWC, not
a deadline. Do not imply an end date that does not exist.

Four platform changes reach Aura:

- **An `@AuraEnabled` controller is Apex**, so the API 67.0 defaults apply: an omitted sharing
  declaration becomes `with sharing`, and SOQL, SOSL and DML default to `USER_MODE`. §5, `dya-apex`,
  `dya-permissions`.
- **`WITH SECURITY_ENFORCED` no longer compiles.** Use `WITH USER_MODE`.
- **Lightning Web Security blocks `data:` URIs**, so client-side downloads use `blob:`. §10.
- **The `ui` namespace has been unsupported since 1 May 2021.** Never use it. §2.

The Voice Toolkit API adds voice-enabled component support, extended to Agentforce Contact Center —
relevant only if you are building telephony.

---

## 1. The First Question — Should This Be Aura At All?

Stop at the first row that fits.

| Requirement | Build it as | Aura? |
|---|---|---|
| Any net-new component | LWC (`dya-lwc`) | NO |
| LWC genuinely can't reach the surface/feature (rare today) | Aura | YES |
| Maintaining / extending an **existing** Aura component | Aura | YES |
| Need to **wrap an LWC** so it can sit in an Aura-only context | Aura wrapper around LWC | YES |

LWC has closed almost every historical reason to choose Aura — quick actions, utility bar, Flow and
Community contexts, dynamic component creation. Assume LWC unless you can name the specific gap, and
when you do build Aura, comment why LWC was insufficient.

**Aura can contain LWC; LWC cannot contain Aura.** The migration path is therefore always "wrap or
replace Aura with LWC", never the reverse.

---

## 2. Base Components — `lightning` Namespace Only

`lightning`-namespace components implement SLDS, accessibility and internationalisation for you.

```html
<!-- ✅ -->
<lightning:card title="Account">
    <lightning:button label="Save" variant="brand" onclick="{!c.handleSave}" />
    <lightning:input label="Name" value="{!v.accountName}" />
</lightning:card>

<!-- ❌ — ui namespace, unsupported since May 1, 2021 -->
<ui:button label="Save" press="{!c.handleSave}" />
<ui:inputText value="{!v.accountName}" />
```

Replace every `ui:` component you meet during maintenance:

```text
ui:button        →  lightning:button · lightning:buttonIcon
ui:inputText     →  lightning:input
ui:inputSelect   →  lightning:select · lightning:combobox
ui:inputRichText →  lightning:inputRichText
ui:message       →  lightning:notificationsLibrary · toast
```

Style with SLDS utility classes and **styling hooks** (CSS custom properties). Design tokens are
legacy; Aura has supported hooks since Summer '24.

---

## 3. Attributes and Expressions

### Typed attributes

```html
<aura:attribute name="contacts" type="Contact[]" />
<aura:attribute name="isLoading" type="Boolean" default="false" access="private" />
<aura:attribute name="recordId" type="Id" />
```

Always declare a `type`. Use `access="private"` for internal state, `access="public"` (the default)
only for the component's API, and `description` on every public attribute.

### Bound vs unbound expressions

- `{!v.value}` — **bound**, two-way. Changes propagate in both directions. Use only when the child
  must mutate the parent's value.
- `{#v.value}` — **unbound**, one-time and one-way. No change-tracking cost. **Use it for read-only
  display.**

```html
<!-- ✅ — display only -->
<lightning:formattedText value="{#v.account.Name}" />

<!-- ✅ — genuine two-way binding -->
<lightning:input value="{!v.searchTerm}" />
```

### Value providers

`v` attributes, `c` controller actions, `m` renderer (rare). Handlers are `{!c.handleClick}`.

### Conditional rendering and iteration

```html
<aura:if isTrue="{!v.isLoading}">
    <lightning:spinner alternative-text="Loading" />
    <aura:set attribute="else">
        <aura:iteration items="{!v.contacts}" var="contact">
            <p>{#contact.Name}</p>
        </aura:iteration>
    </aura:set>
</aura:if>
```

Use `aura:iteration` for lists, keyed on stable data. Use `aura:if` rather than `display:none` for
expensive subtrees — `aura:if` removes them from the DOM; CSS only hides them.

---

## 4. Data Access — Lightning Data Service Before Apex

Stop at the first that fits.

1. **`lightning:recordForm`** — single-record create/view/edit, auto-generated fields and layout.
2. **`lightning:recordViewForm` / `lightning:recordEditForm`** — record read/write, custom field
   arrangement.
3. **`force:recordData`** — declarative load, create, save and delete of one record.
4. **Apex `@AuraEnabled`** — only for multi-object queries, aggregates, cross-object logic, callouts,
   async, or objects the UI API does not support.

```html
<!-- ✅ — record edit with zero Apex -->
<lightning:recordForm
    recordId="{!v.recordId}"
    objectApiName="Account"
    fields="Name,Industry,AnnualRevenue"
    onsuccess="{!c.handleSuccess}" />
```

The first three share the Lightning Data Service cache with LWC and the rest of Lightning
Experience, so an edit through them refreshes every other component on the page. **Hand-rolled Apex
CRUD does not**, which is the strongest reason to exhaust LDS first. Full `force:recordData` pattern
in `references/server-and-lds.md`.

---

## 5. Server-Side Apex — The `@AuraEnabled` Contract

Declare `with sharing`, query `WITH USER_MODE`, throw `AuraHandledException` on failure.

```java
public with sharing class AccountController {
    @AuraEnabled(cacheable=true)        // reads → client-cacheable, no DML allowed
    public static List<Account> getTopAccounts(String industry) {
        return [
            SELECT Id, Name, AnnualRevenue FROM Account
            WHERE Industry = :industry WITH USER_MODE
            ORDER BY AnnualRevenue DESC LIMIT 10
        ];
    }

    @AuraEnabled                        // writes → no cacheable
    public static void updateRating(Id accountId, String rating) {
        try {
            Database.update(
                new Account(Id = accountId, Rating = rating),
                AccessLevel.USER_MODE
            );
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
```

Handle all three action states — `SUCCESS`, `ERROR`, `INCOMPLETE`. Wrap any state mutation that must
re-render in `$A.getCallback`.

```javascript
({
    loadAccounts: function (component) {
        const action = component.get("c.getTopAccounts");
        action.setParams({ industry: component.get("v.industry") });
        action.setStorable();                    // cacheable read → storable
        action.setCallback(this, function (response) {
            const state = response.getState();
            if (state === "SUCCESS") {
                component.set("v.accounts", response.getReturnValue());
            } else if (state === "ERROR") {
                this.showError(response.getError());
            }
        });
        $A.enqueueAction(action);
    }
})
```

`@AuraEnabled(cacheable=true)` plus `action.setStorable()` serves reads from the client cache after
the first call. Full `$A.enqueueAction` and Promise-wrapper patterns in
`references/server-and-lds.md`.

---

## 6. Events — Component Events Before Application Events

Choosing wrong here is the most common Aura architecture mistake. Prefer in this order:

```text
1. aura:method            parent calls a child's method synchronously (parent → child)
2. Component event        child notifies its ancestors. Scoped, traceable, cheap. THE DEFAULT
3. Lightning Message Svc  reaches LWC and Visualforce, and crosses component trees
4. Application event      last resort: broadcast to every handler in the app, regardless of
                          hierarchy. Expensive, hard to trace, easy to over-fire
```

For cross-technology or cross-tree communication, use **Lightning Message Service**, not an
application event. Full register/fire/handle implementations, `aura:method` and LMS-from-Aura:
`references/events-and-communication.md`.

---

## 7. Lifecycle — the `init` Handler

Initialise in `init`, never in markup. Do not override `render` / `rerender` / `afterRender` /
`unrender` without a concrete DOM-timing need.

```html
<aura:handler name="init" value="{!this}" action="{!c.doInit}" />
```

```javascript
({
    doInit: function (component, event, helper) {
        helper.loadAccounts(component);   // delegate real work to the helper
    }
})
```

Controllers are event entry points only. Reusable logic goes in the **helper**; server calls and
business logic never go in markup.

---

## 8. Interop — Composing With LWC

Pass data down through attributes; listen to the LWC's `CustomEvent`s with lowercased `on<Event>`
handlers.

```html
<!-- Aura parent embedding an LWC child named c:contactList -->
<c:contactList accountId="{!v.recordId}" oncontactselect="{!c.handleSelect}" />
```

```javascript
// the LWC dispatches: new CustomEvent('contactselect', { detail: { id } })
({
    handleSelect: function (component, event) {
        const contactId = event.getParam("arguments")
            ? event.getParam("arguments").id      // aura:method style
            : event.getParam("id");                // CustomEvent detail
        // ...
    }
})
```

Build the child in LWC and keep the Aura wrapper thin — that is the migration direction. Embedding
Aura inside LWC is not supported.

---

## 9. Security and Error Handling

- **Lightning Web Security** superseded Locker Service and is enforced. It distorts or blocks risky
  browser APIs, so avoid non-standard ones and test under LWS.
- **`@AuraEnabled`**: `with sharing`, CRUD/FLS through `WITH USER_MODE`, and
  `Security.stripInaccessible` for variable-FLS reads. See `dya-apex` §3.
- **Never return a raw exception to the client.** Throw `AuraHandledException` with a clean message
  and log the real cause through Platform Events (`dya-apex` §11).
- **Handle `INCOMPLETE`** — offline or lost connection — as well as `ERROR`.

```java
// ✅ — clean message to the client, real cause logged server-side
catch (Exception e) {
    Logger.error('AccountController.updateRating', e);
    throw new AuraHandledException('Could not update the account. Please retry.');
}
```

---

## 10. Client-Side File Downloads — `blob:`, not `data:`

```javascript
// ✅
const blob = new Blob([csv], { type: "text/csv" });
const link = document.createElement("a");
link.href = URL.createObjectURL(blob);
link.download = "export.csv";
link.click();
URL.revokeObjectURL(link.href);

// ❌ — blocked by Lightning Web Security
link.href = "data:text/csv;charset=utf-8," + encodeURIComponent(csv);
```

Give the `Blob` an explicit MIME type. An omitted type is the case LWS blocks.

---

## 11. Decision Matrix — Quick Reference

| Need | Solution | Apex? |
|---|---|---|
| New component | LWC (`dya-lwc`) | per skill |
| Single-record create/view/edit | `lightning:recordForm` | NO |
| Custom-arranged record CRUD | `lightning:recordEditForm` / `recordViewForm` | NO |
| Load/save one record declaratively | `force:recordData` | NO |
| Multi-object query / aggregate / callout | `@AuraEnabled` Apex | YES |
| Child notifies parent | Component event | NO |
| Parent calls child method | `aura:method` | NO |
| Talk to LWC / Visualforce / across trees | Lightning Message Service | NO |
| App-wide broadcast between unrelated cmps | Application event (last resort) | NO |
| Conditional subtree (expensive) | `aura:if` | NO |
| Render a list | `aura:iteration` | NO |
| Read-only display value | unbound `{#v.x}` | NO |
| Two-way input binding | bound `{!v.x}` | NO |
| Cacheable server read | `@AuraEnabled(cacheable=true)` + `setStorable()` | YES |
| Client-side file download | `blob:` URL | NO |
| Embed modern UI in an Aura context | LWC wrapped in Aura | per skill |

---

## 12. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| New component built in Aura | LWC (`dya-lwc`) |
| `ui:` namespace components | `lightning:` namespace base components |
| Apex for single-record CRUD | `lightning:recordForm` / `force:recordData` |
| Application event for child → parent | Component event |
| Application event for cross-tree / LWC comms | Lightning Message Service |
| `WITH SECURITY_ENFORCED` in a controller | `WITH USER_MODE` (removed in API 67+) |
| `@AuraEnabled` class with no sharing keyword | `with sharing` + `WITH USER_MODE` |
| Returning raw exceptions to the client | `AuraHandledException` + Platform Event log |
| Ignoring the `INCOMPLETE` / `ERROR` action state | Branch on all three states |
| Mutating state in an async callback without `$A.getCallback` | Wrap re-rendering callbacks in `$A.getCallback` |
| Business logic / server calls in markup | `init` handler → helper |
| Bound `{!v.x}` for read-only display | Unbound `{#v.x}` |
| `display:none` to hide expensive subtrees | `aura:if` |
| Design tokens for theming | SLDS styling hooks |
| `data:` URI anchor download | `blob:` URL via `URL.createObjectURL` |
| Trying to embed Aura inside LWC | Embed LWC inside Aura (the supported direction) |
| API version below 68.0 on new bundles | `<apiVersion>68.0</apiVersion>` in the `*-meta.xml` |

---

## Summary — The Five Commandments

1. **Ask "should this be Aura at all?" first** — new UI is LWC; reserve Aura for existing components
   and the rare LWC gap, and wrap LWC in Aura, never the reverse.
2. **`lightning` namespace only** — the `ui` namespace is unsupported; style with SLDS hooks, not
   design tokens.
3. **Lightning Data Service before Apex** — `lightning:recordForm` and `force:recordData` for record
   work; `@AuraEnabled` only for genuine server logic, and then `with sharing` + `WITH USER_MODE` +
   `AuraHandledException`.
4. **Component events before application events** — `aura:method` parent→child, component events
   child→parent, Lightning Message Service across trees and technologies, application events only as
   a last resort.
5. **Thin controllers, safe async, `blob:` downloads** — initialise in `init`, keep logic in the
   helper, branch on all three action states, wrap re-rendering callbacks in `$A.getCallback`.
