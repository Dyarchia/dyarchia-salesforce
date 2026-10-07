---
name: dya-sf-visualforce
description: Salesforce Visualforce Winter '27 (API v68.0) modern development best practices — when (not) to use VF, MVC and controller design, view state, security and output encoding, JavaScript Remoting, SLDS theming, Lightning Message Service interop, PDF/email rendering. Applies to *.page and Visualforce *.component files, their controllers and extensions, Visualforce PDF and email templates. Load before creating or editing anything in this scope, or when the user invokes this skill by name (`dya-sf-visualforce`).
---

# Salesforce Visualforce — Modern Development

Visualforce is **maintenance-mode**: you check first whether LWC or Aura fits, save controllers
under the modern Apex security model, minimise view state and encode output. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — release-coupled facts, including the security defaults a Visualforce controller inherits.
- `references/shared/sharing-and-access.md` — the permission model those defaults enforce.
- `references/controller-patterns.md` — controller extension skeleton, view state and `transient` discipline, bulkified getters and actions, injection-safe dynamic SOQL, CRUD and FLS in custom controllers.
- `references/javascript-remoting.md` — `@RemoteAction` patterns, Remoting vs `<apex:actionFunction>` vs Remote Objects, bulkified remoting, error handling.

Controllers are Apex: for Service/Selector/Domain layering, async, observability and testing, load
`dya-sf-apex`. For new Lightning UI, load `dya-sf-lwc` or `dya-sf-aura`.

---

## Platform Context — Winter '27 / API v68.0

Save new pages, components and their controllers at `<apiVersion>68.0</apiVersion>`. Winter '27
brings **no new Visualforce markup**: Visualforce receives platform changes, not features.

**No retirement date has been announced.** Maintenance mode is a reason to build new work in LWC, not
a deadline; never imply an end date.

- **SLDS 2.0** — in an org that adopts it, Visualforce adapts to the new styling. Raise it when
  someone asks why an old page looks wrong.
- **A Visualforce controller is Apex**, so the API 67.0 security defaults apply: SOQL, SOSL, DML and
  `Database.*` default to `USER_MODE`, and an omitted sharing declaration on a custom controller or
  extension defaults to `with sharing`. §3, `dya-sf-apex`, `dya-sf-permissions`.
- **`WITH SECURITY_ENFORCED` no longer compiles.** Use `WITH USER_MODE`. §3.
- **HTTPS is enforced everywhere** — every Visualforce page and custom domain. Never hard-code an
  `http://` resource or callback URL; use `URLFOR($Resource…)`, a relative URL, or a Named Credential.
- **Lightning Web Security blocks `data:` URIs** on `HTMLAnchorElement.href` in a VF page embedded in
  Lightning Experience. §8.

---

## 1. The First Question — Should This Be Visualforce At All?

Stop at the first row that fits.

| Requirement | Build it as | Visualforce? |
|---|---|---|
| Any net-new Lightning Experience UI | LWC (`dya-sf-lwc`) | NO |
| LWC can't express it, but Aura can (e.g. needs an Aura-only base component) | Aura (`dya-sf-aura`) | NO |
| Server-rendered **PDF** (`renderAs="pdf"`) | Visualforce | YES |
| **Email templates** with complex/branded merge logic | Visualforce email template | YES |
| Salesforce **Classic**-only screen still in use | Visualforce | YES |
| Maintaining/extending an **existing** VF page in a packaged or legacy app | Visualforce | YES |
| Content that must run inside an **iframe** sandbox | Visualforce | YES |

Where the answer is NO, say so and point to the right skill. When you do build VF, comment at the top
of the page which exception justifies it.

**PDF caveat:** `renderAs="pdf"` uses a legacy rendering engine. Keep PDF pages to simple HTML and
CSS (tables, basic styling), avoid JavaScript (it does not run during PDF generation), and test page
breaks. Never pull SLDS into a PDF page: it bloats and renders unpredictably.

---

## 2. MVC and Controller Choice

Markup is the View, the controller or extension the Controller, SObjects the Model. Keep logic out
of the page.

### Controller decision order

1. **Standard controller** (`standardController="Account"`) — single-record CRUD with built-in
   save, edit, delete and cancel; enforces CRUD, FLS and sharing automatically. Prefer it.
2. **Standard controller + extension** (`extensions="AccountExt"`) — extra actions or data on top of
   standard behaviour. The extension constructor takes `ApexPages.StandardController`.
3. **Standard list controller** (`recordSetVar="accounts"`) — list pages with built-in pagination and
   filtering.
4. **Custom controller** (`controller="MyController"`) — only when no standard controller fits. It
   runs in **system mode for CRUD and FLS by default** unless you declare `with sharing` and enforce
   field access yourself. §3.

### Controller rules — absolute

- One controller or extension per page concern, and no business logic in the markup.
- **No SOQL or DML inside a getter.** Getters run repeatedly during rendering. Query once in the
  constructor or a `PageReference` action and cache the result in a member field.
- Bulkify as in Apex: assume the page can act on many records.
- Delegate SOQL to a Selector or Gateway class and business operations to a Service class
  (`dya-sf-apex`).

```apex
// ✅ — query once in the constructor, expose via a cached field
public with sharing class AccountExt {
    public List<Contact> contacts { get; private set; }

    public AccountExt(ApexPages.StandardController stdCtrl) {
        Id accountId = stdCtrl.getId();
        this.contacts = [
            SELECT Id, Name, Email FROM Contact
            WHERE AccountId = :accountId WITH USER_MODE
        ];
    }
}
```

```apex
// ❌ — SOQL in a getter: re-runs on every reference, blows up view state and limits
public List<Contact> getContacts() {
    return [SELECT Id, Name FROM Contact WHERE AccountId = :acctId];
}
```

---

## 3. Security — User Mode, Encoding, Injection

### CRUD / FLS in controllers

**Custom controllers do not enforce CRUD, FLS and sharing**; you do. The API 67.0 defaults help;
state them explicitly anyway.

```apex
// ✅ — explicit sharing + USER_MODE; CRUD/FLS enforced by the query
public with sharing class InvoiceController {
    public List<Invoice__c> invoices { get; private set; }

    public InvoiceController() {
        this.invoices = [
            SELECT Id, Name, Amount__c FROM Invoice__c
            WHERE Status__c = 'Open' WITH USER_MODE
            LIMIT 200
        ];
    }
}

// ❌ — removed in API 67+, does NOT compile
[SELECT Id FROM Invoice__c WITH SECURITY_ENFORCED];
```

For DML in a custom controller use `Database.*` with `AccessLevel.USER_MODE`; for returned records
whose FLS varies, `Security.stripInaccessible`. Full rules in `dya-sf-apex` §3.

### Output encoding — Visualforce auto-encodes, but only in HTML context

`{!expression}` is auto-HTML-encoded, which protects the HTML body context and nothing else. Inside a
`<script>` block, a JS string, an inline event handler, a URL or a style attribute, encode
explicitly:

```html
<!-- ✅ — JS-in-HTML context -->
<script>
    var name = '{!JSINHTMLENCODE(account.Name)}';
    var url  = '{!URLENCODE(returnUrl)}';
</script>

<!-- ❌ — XSS: merge field dropped raw into a script context -->
<script>var name = '{!account.Name}';</script>
```

The encoding functions are `HTMLENCODE`, `JSENCODE`, `JSINHTMLENCODE` and `URLENCODE`. Never disable
platform escaping with `escape="false"` on user-supplied data.

### SOQL injection in dynamic queries

Never concatenate user input into a query string. Use bind variables,
`Database.queryWithBinds(..., AccessLevel.USER_MODE)`, or `String.escapeSingleQuotes` as a last
resort. Full pattern in `references/controller-patterns.md`.

---

## 4. View State — Keep It Small

`<apex:form>` postbacks serialise controller state into a hidden **view state** field on every
request, against a hard limit of **135 KB**. Bloated view state causes slow VF pages and
`Maximum view state size limit exceeded` errors.

### Rules

- Mark fields not needed across postbacks **`transient`**: render-only collections, large blobs,
  derived data.
- Never hold large query results in non-transient fields. Query what the current request needs;
  re-query on the next action.
- Project only the fields you display — `SELECT Id, Name`, never everything.
- Prefer **JavaScript Remoting** (§5) for data-heavy interactions: it carries no view state.
- Bind `<apex:inputField>` and `<apex:outputField>` to SObject fields rather than copying values into
  scalar controller properties.

```apex
// ✅ — render-only data excluded from view state
public with sharing class ReportController {
    public transient List<AggregateResult> summary { get; private set; }
    public ReportController() {
        this.summary = [
            SELECT Industry, COUNT(Id) total FROM Account
            WITH USER_MODE GROUP BY Industry
        ];
    }
}
```

Inspect view state with the **View State Inspector** (enable *Development Mode* in user settings)
before shipping any non-trivial form page.

---

## 5. JavaScript Remoting Over `<apex:actionFunction>`

**JavaScript Remoting** (`@RemoteAction`) is the default for async, partial-page server interaction:
stateless, no view state, faster, with direct control over request and response in JS.

```apex
public with sharing class AccountRemote {
    @RemoteAction
    public static List<Account> findByName(String namePrefix) {
        return [
            SELECT Id, Name, Industry FROM Account
            WHERE Name LIKE :(namePrefix + '%') WITH USER_MODE
            LIMIT 50
        ];
    }
}
```

```html
<script>
    Visualforce.remoting.Manager.invokeAction(
        '{!$RemoteAction.AccountRemote.findByName}',
        prefix,
        function (result, event) {
            if (event.status) { render(result); }
            else { console.error(event.message); }
        },
        { escape: true }
    );
</script>
```

### Interaction technique — decision

| Need | Use |
|---|---|
| Async partial update, full control in JS, no view state | **JavaScript Remoting** (`@RemoteAction`) |
| Simple DML on the page record from a JS event, view state OK | `<apex:actionFunction>` (legacy, view-state-bound) |
| Basic record CRUD from JS without writing Apex | **Remote Objects** (`<apex:remoteObjects>`) |
| Declarative rerender on a standard component event | `<apex:actionSupport>` / `rerender` |

Avoid `<apex:actionFunction>` and `<apex:actionSupport>` for anything data-heavy: they round-trip the
whole view state. Bulkified signatures and error handling: `references/javascript-remoting.md`.

---

## 6. Styling — SLDS, Not Hand-Rolled CSS

Opt into the Salesforce Lightning Design System to look native in Lightning Experience.

```html
<!-- ✅ — platform applies SLDS + LEX look-and-feel -->
<apex:page standardController="Account" lightningStylesheets="true">
    <apex:slds />
    <div class="slds-scope">
        <lightning:card title="Account"> ... </lightning:card>
    </div>
</apex:page>
```

- `lightningStylesheets="true"` on `<apex:page>` gives standard VF components a Lightning skin in LEX
  and mobile.
- `<apex:slds />` loads SLDS utility classes; wrap your markup in a `slds-scope` container.
- Use SLDS classes, not hard-coded colours, fonts and pixel widths.

---

## 7. Interop — Talking to Aura / LWC via Lightning Message Service

A VF page embedded on a Lightning page alongside Aura or LWC communicates across the DOM boundary
only through **Lightning Message Service**. Never use `window.postMessage` hacks or scrape the parent
DOM.

```html
<apex:page lightningStylesheets="true">
    <script>
        // Get the channel token from the $MessageChannel global
        var CHANNEL = "{!$MessageChannel.OrderEvents__c}";
        var subscription;

        function publishOrder(payload) {
            sforce.one.publish(CHANNEL, payload);
        }
        function subscribeOrders() {
            if (subscription) { return; }
            subscription = sforce.one.subscribe(
                CHANNEL,
                function (msg) { handleMessage(msg); },
                { scope: "APPLICATION" }
            );
        }
        function unsubscribeOrders() {
            sforce.one.unsubscribe(subscription);
            subscription = null;
        }
    </script>
</apex:page>
```

The message channel (`*.messageChannel-meta.xml`) is one metadata record shared by LWC, Aura and VF.
Keep payloads small and serialisable, and always unsubscribe when done. For the other side, see
`dya-sf-lwc` and `dya-sf-aura`.

---

## 8. Client-Side File Downloads — `blob:`, not `data:`

A VF page in LEX that builds a download in JavaScript uses a `blob:` URL.

```javascript
// ✅
const blob = new Blob([csvString], { type: 'text/csv' });
const link = document.createElement('a');
link.href = URL.createObjectURL(blob);
link.download = 'export.csv';
link.click();
URL.revokeObjectURL(link.href);

// ❌ — blocked by LWS
link.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csvString);
```

For server-generated files, prefer `renderAs="pdf"` or a controller returning a `PageReference` to a
content resource.

---

## 9. Decision Matrix — Quick Reference

| Need | Solution | Custom Apex? |
|---|---|---|
| New Lightning UI | LWC, then Aura | per skill |
| Single-record CRUD page | Standard controller | NO |
| List page with pagination | Standard list controller (`recordSetVar`) | NO |
| Extra data/actions on a record page | Standard controller + extension | YES (extension) |
| Server-rendered PDF | `renderAs="pdf"` VF page | maybe |
| Branded email with merge logic | VF email template | maybe |
| Async partial-page data load | JavaScript Remoting (`@RemoteAction`) | YES |
| Basic CRUD from JS, no Apex | Remote Objects | NO |
| Native LEX styling | `lightningStylesheets="true"` + `<apex:slds/>` | NO |
| Talk to LWC/Aura on the same page | Lightning Message Service (`sforce.one.*`) | NO |
| Keep a value out of view state | `transient` field | YES |
| Client-side file download in LEX | `blob:` URL | NO |
| Dynamic SOQL with user input | `Database.queryWithBinds` + `USER_MODE` | YES |

---

## 10. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| New LEX UI built in Visualforce | LWC (`dya-sf-lwc`), then Aura |
| `WITH SECURITY_ENFORCED` in a controller | `WITH USER_MODE` (removed in API 67+ — does NOT compile) |
| `public class FooController` (no sharing keyword) | `public with sharing class FooController` |
| SOQL/DML inside a getter | Query once in the constructor, cache in a field |
| Large/derived data in non-`transient` fields | Mark render-only state `transient` |
| `{!userInput}` inside a `<script>` block | `{!JSINHTMLENCODE(userInput)}` |
| `escape="false"` on user-supplied data | Leave platform escaping on; encode explicitly |
| String-concatenated dynamic SOQL | `Database.queryWithBinds(q, binds, USER_MODE)` |
| `<apex:actionFunction>` for data-heavy calls | JavaScript Remoting (`@RemoteAction`) |
| `SELECT` every field for display | Project only the fields the page renders |
| Hand-rolled CSS to mimic Lightning | `lightningStylesheets="true"` + `<apex:slds/>` |
| `window.postMessage` to reach Aura/LWC | Lightning Message Service (`sforce.one.publish/subscribe`) |
| `data:` URI anchor download in LEX | `blob:` URL via `URL.createObjectURL` |
| `http://` hard-coded URLs | `URLFOR($Resource…)` / relative URL / Named Credential |
| SLDS pulled into a `renderAs="pdf"` page | Plain HTML/CSS in PDF pages |
| Business logic in the page markup | Controller/extension + Service class |
| API version below 68.0 on new pages and controllers | `<apiVersion>68.0</apiVersion>` in the `*-meta.xml` |

---

## Summary — The Five Commandments

1. **Ask "should this be VF at all?" first** — new Lightning UI is LWC then Aura; reserve Visualforce for PDF, email templates, Classic, iframes, and existing pages.
2. **Controllers are Apex at API 67** — explicit `with sharing` + `WITH USER_MODE`; `WITH SECURITY_ENFORCED` no longer compiles; never query inside a getter.
3. **Guard view state** — `transient` everything render-only, keep it under 135 KB, prefer remoting for data-heavy work.
4. **Encode every non-HTML context and bind every query** — `JSINHTMLENCODE`/`URLENCODE` in scripts, bind variables in dynamic SOQL.
5. **Stay native and interoperable** — SLDS via `lightningStylesheets`/`<apex:slds/>`, LMS (`sforce.one.*`) to talk to Aura/LWC, `blob:` (not `data:`) for downloads.
