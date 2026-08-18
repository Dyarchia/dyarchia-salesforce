---
name: dya-aura
description: Salesforce Aura Components Summer '26 (API v67.0) modern development best practices — when (not) to use Aura, lightning-namespace base components, LDS data access without Apex, server-side controllers, component vs application events, aura:method, attributes and expressions, lifecycle, LWC interop, Lightning Message Service, security and downloads. Load only when the user explicitly invokes this skill by name (`dya-aura`); do NOT auto-trigger on generic Aura, Lightning, or Salesforce component questions.
---

# Salesforce Aura Components — Modern Development

You are an expert Salesforce Aura developer working on a platform where Aura is a **mature, maintenance-mode** framework. You **always** check first whether LWC is the right tool, you **always** use `lightning`-namespace base components (never the deprecated `ui` namespace), you **always** prefer Lightning Data Service over Apex, and you **always** save controllers under the modern Apex security model. Follow every rule below without exception.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/` and are loaded on demand:

- `references/events-and-communication.md` — full component-event and application-event register/fire/handle patterns, `aura:method`, and Lightning Message Service from Aura.
- `references/server-and-lds.md` — full `@AuraEnabled` controller, `$A.enqueueAction` + storable actions + Promise wrapper, `force:recordData`, and `lightning:recordForm` patterns.

Load a reference when you are about to write or refactor code that needs that exact implementation. Aura server-side controllers are Apex — for deep Apex best practices (Service/Selector/Domain layering, async, observability, testing) load `dya-apex`. For new UI, load `dya-lwc` first.

---

## Platform Context — Summer '26 / API v67.0

**Current API version: 67.0 (Summer '26).** All new Aura component bundles and their Apex controllers MUST be saved at `<apiVersion>67.0</apiVersion>`. The release brings no new Aura framework features, but several platform changes land directly on Aura:

- **`@AuraEnabled` controllers are Apex at API 67** — the versioned security defaults flip. An omitted sharing declaration on an **Aura controller / `@AuraEnabled` method** defaults to `with sharing` (was `without sharing` ≤66); SOQL/SOSL/DML default to `USER_MODE`. See §5 and `dya-apex`.
- **`WITH SECURITY_ENFORCED` is REMOVED in API 67+** — a controller that uses it does not compile. Use `WITH USER_MODE`.
- **Lightning Web Security blocks `data:` URIs** — client-side downloads must use a `blob:` URL on the anchor `href`. See §10.
- **Voice Toolkit API for Salesforce Voice** — new APIs/methods/events to build voice-enabled Aura (or LWC) components, now also supported on Agentforce Contact Center. Niche; relevant only for telephony components.
- **Aura is in maintenance mode.** Salesforce ships no new Aura framework capability and steers all new development to LWC. The `ui` namespace has been deprecated since support ended **May 1, 2021** — never use it. Treat Aura as appropriate only for the specific cases in §1.

---

## 1. The First Question — Should This Be Aura At All?

Before writing a single `.cmp`, walk this decision tree. Stop at the first row that fits.

| Requirement | Build it as | Aura? |
|---|---|---|
| Any net-new component | LWC (`dya-lwc`) | NO |
| LWC genuinely can't reach the surface/feature (rare today) | Aura | YES |
| Maintaining / extending an **existing** Aura component | Aura | YES |
| Need to **wrap an LWC** so it can sit in an Aura-only context | Aura wrapper around LWC | YES |

The historical reasons to choose Aura (quick actions, utility bar, certain Flow/Community contexts, dynamic component creation) have almost all been closed by LWC. Assume LWC unless you can name the specific gap. **Aura components can contain LWC; LWC cannot contain Aura** — so the migration path is always "wrap or replace Aura with LWC", never the reverse. When you do build Aura, add a comment stating why LWC was insufficient.

---

## 2. Base Components — `lightning` Namespace Only

Use `lightning`-namespace base components for everything. They implement SLDS, accessibility, and internationalisation out of the box.

```html
<!-- ✅ -->
<lightning:card title="Account">
    <lightning:button label="Save" variant="brand" onclick="{!c.handleSave}" />
    <lightning:input label="Name" value="{!v.accountName}" />
</lightning:card>

<!-- ❌ — ui namespace, deprecated since May 1, 2021 -->
<ui:button label="Save" press="{!c.handleSave}" />
<ui:inputText value="{!v.accountName}" />
```

`ui:button` → `lightning:button` / `lightning:buttonIcon`; `ui:inputText` → `lightning:input`; `ui:inputSelect` → `lightning:select` / `lightning:combobox`; `ui:inputRichText` → `lightning:inputRichText`; `ui:message` → `lightning:notificationsLibrary` / toast. Replace any `ui:` component you encounter during maintenance.

Styling: use SLDS utility classes and **styling hooks** (CSS custom properties) for customisation. Design tokens are legacy — Aura has supported styling hooks since Summer '24; prefer them.

---

## 3. Attributes and Expressions

### Typed attributes

```html
<aura:attribute name="contacts" type="Contact[]" />
<aura:attribute name="isLoading" type="Boolean" default="false" access="private" />
<aura:attribute name="recordId" type="Id" />
```

Always declare a `type`; set `access="private"` for internal state and `access="public"` (default) only for the component's API. Use `description` on public attributes.

### Bound vs unbound expressions

- `{!v.value}` — **bound**: two-way data binding between parent and child. Changes propagate both directions. Use only when you actually need the child to mutate the parent's value.
- `{#v.value}` — **unbound**: one-time, one-way. Cheaper, no change-propagation overhead. **Prefer `{#…}` for read-only display** to reduce the cost of Aura's change-tracking.

```html
<!-- ✅ — display only, no two-way binding needed -->
<lightning:formattedText value="{#v.account.Name}" />

<!-- ✅ — genuine two-way binding into an input -->
<lightning:input value="{!v.searchTerm}" />
```

### Value providers

`v` (view/attributes), `c` (controller actions), `m` (renderer-rarely). Reference handlers as `{!c.handleClick}`.

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

Use `aura:iteration` (not a server loop) for lists; key your rows by binding stable data. Use `aura:if` rather than CSS `display:none` when the subtree is expensive — `aura:if` actually removes it from the DOM.

---

## 4. Data Access — Lightning Data Service Before Apex

Before writing an `@AuraEnabled` method, evaluate this order. Stop at the first that fits.

1. **`lightning:recordForm`** — single-record create/view/edit with auto-generated fields and layout. No Apex, no client code.
2. **`lightning:recordViewForm` / `lightning:recordEditForm`** — record read/write with custom field arrangement.
3. **`force:recordData`** — Aura's LDS data provider: load, create, save, delete a single record declaratively, with shared client cache and automatic refresh. No Apex.
4. **Apex `@AuraEnabled`** — only for multi-object queries, aggregates, cross-object logic, callouts, async, or non-UI-API objects.

```html
<!-- ✅ — record edit with zero Apex -->
<lightning:recordForm
    recordId="{!v.recordId}"
    objectApiName="Account"
    fields="Name,Industry,AnnualRevenue"
    onsuccess="{!c.handleSuccess}" />
```

`force:recordData` and `lightning:recordForm` share the Lightning Data Service cache with LWC and the rest of LEX, so edits made through them refresh other components on the page automatically. Hand-rolled Apex CRUD does not — another reason to prefer LDS. Full `force:recordData` pattern in `references/server-and-lds.md`.

---

## 5. Server-Side Apex — The `@AuraEnabled` Contract

When LDS can't do it, call Apex via `$A.enqueueAction`. The controller is Apex at API 67 — declare `with sharing`, query `WITH USER_MODE`, and throw `AuraHandledException` on failure.

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

Client call — always handle the three action states (`SUCCESS`, `ERROR`, `INCOMPLETE`). Wrap any state mutation that must re-render in `$A.getCallback`:

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

`@AuraEnabled(cacheable=true)` + `action.setStorable()` serves reads from the client cache after the first call. For deep server-side rules (Selector/Service layering, async, observability), load `dya-apex`. Full `$A.enqueueAction` + Promise-wrapper pattern in `references/server-and-lds.md`.

---

## 6. Events — Component Events Before Application Events

Aura has two event types. Choosing wrong is the most common Aura architecture mistake.

- **Component event** — travels up the containment hierarchy (child → ancestor). Scoped, traceable, cheap. **This is the default.** Use for child-to-parent communication.
- **Application event** — broadcast to every handler in the app regardless of hierarchy. Expensive, hard to trace, easy to over-fire. Use only when truly unrelated components must react.

```
Prefer, in order:
1. aura:method            — parent calls a child's method synchronously (parent → child)
2. Component event        — child notifies its ancestors (child → parent)
3. Lightning Message Svc  — communication with LWC/Visualforce, or across separate trees
4. Application event      — last resort: app-wide broadcast between unrelated Aura cmps
```

For cross-technology or cross-tree communication on a Lightning page, use **Lightning Message Service**, not an application event — it also reaches LWC and Visualforce. Full register/fire/handle implementations for both event types, `aura:method`, and LMS-from-Aura: `references/events-and-communication.md`.

---

## 7. Lifecycle — the `init` Handler

Initialise in the `init` handler, not in markup. Avoid overriding `render`/`rerender`/`afterRender`/`unrender` unless you have a concrete DOM-timing need.

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

Keep controllers thin: event entry points only. Put reusable logic in the **helper**. Never put server calls or business logic directly in markup.

---

## 8. Interop — Composing With LWC

Aura can contain LWC. Pass data down via attributes and listen to the LWC's `CustomEvent`s with `on<Event>` handlers (lowercased event name).

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

Prefer building the child in LWC and the thin wrapper in Aura — that is the migration direction. Do not try to embed Aura inside LWC; it is not supported.

---

## 9. Security and Error Handling

- **Lightning Web Security (LWS)** is the enforced security architecture (it superseded Locker Service). Avoid non-standard browser API access; LWS distorts or blocks risky APIs. Test components under LWS.
- **`@AuraEnabled` security** — declare `with sharing`, enforce CRUD/FLS via `WITH USER_MODE` (`WITH SECURITY_ENFORCED` no longer compiles at API 67), and use `Security.stripInaccessible` for variable-FLS reads. See `dya-apex` §3.
- **Never return raw exceptions to the client** — throw `AuraHandledException` with a clean message; log the real cause via Platform Events (see `dya-apex` §11).
- **Handle the `INCOMPLETE` action state** (offline / lost connection) as well as `ERROR`.

```java
// ✅ — clean message to the client, real cause logged server-side
catch (Exception e) {
    Logger.error('AccountController.updateRating', e);
    throw new AuraHandledException('Could not update the account. Please retry.');
}
```

---

## 10. Client-Side File Downloads — `blob:`, not `data:`

In Summer '26, Lightning Web Security blocks `data:` URIs on anchor `href`. Generate a `blob:` URL instead.

```javascript
// ✅
const blob = new Blob([csv], { type: "text/csv" });
const link = document.createElement("a");
link.href = URL.createObjectURL(blob);
link.download = "export.csv";
link.click();
URL.revokeObjectURL(link.href);

// ❌ — blocked by LWS in Summer '26
link.href = "data:text/csv;charset=utf-8," + encodeURIComponent(csv);
```

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
| API version < 67.0 on new bundles | `<apiVersion>67.0</apiVersion>` in the `*-meta.xml` |

---

## Summary — The Five Commandments

1. **Ask "should this be Aura at all?" first** — new UI is LWC; reserve Aura for existing components and the rare LWC gap, and wrap LWC in Aura, never the reverse.
2. **`lightning` namespace only** — the `ui` namespace is deprecated; use SLDS styling hooks, not design tokens.
3. **Lightning Data Service before Apex** — `lightning:recordForm` / `force:recordData` for record work; `@AuraEnabled` only for genuine server logic, and then `with sharing` + `WITH USER_MODE` + `AuraHandledException`.
4. **Component events before application events** — `aura:method` for parent→child, component events for child→parent, Lightning Message Service for cross-tree/LWC/Visualforce, application events only as a last resort.
5. **Thin controllers, safe async, `blob:` downloads** — initialise in `init`, keep logic in the helper, handle all three action states, wrap re-rendering callbacks in `$A.getCallback`, and use `blob:` (not `data:`) for downloads.
