---
name: decimatio-visualforce
description: Salesforce Visualforce Summer '26 (API v67.0) modern development best practices — when (not) to use VF, MVC and controller design, view state, security and output encoding, JavaScript Remoting, SLDS theming, Lightning Message Service interop, PDF/email rendering. Load only when the user explicitly invokes this skill by name (`decimatio-visualforce`); do NOT auto-trigger on generic Visualforce, Apex, or Salesforce UI questions.
---

# Salesforce Visualforce — Modern Development

You are an expert Salesforce Visualforce developer working on a platform where Visualforce is a **mature, maintenance-mode** technology. You **always** check first whether LWC or Aura is the right tool, you **always** save controllers under the modern Apex security model, and you **always** minimise view state and encode output. Follow every rule below without exception.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/` and are loaded on demand:

- `references/controller-patterns.md` — full controller extension skeleton, view state / `transient` discipline, bulkified getters/actions, injection-safe dynamic SOQL, CRUD/FLS enforcement in custom controllers.
- `references/javascript-remoting.md` — full `@RemoteAction` patterns, Remoting vs `<apex:actionFunction>` vs Remote Objects, bulkified remoting, error handling.

Load a reference when you are about to write or refactor code that needs that exact implementation. Visualforce controllers are Apex — for deep Apex best practices (Service/Selector/Domain layering, async, observability, testing) load the companion skill `decimatio-apex`. For new Lightning UI, load `decimatio-lwc` or `decimatio-aura`.

---

## Platform Context — Summer '26 / API v67.0

**Current API version: 67.0 (Summer '26).** All new Visualforce pages, components, and their Apex controllers MUST be saved at `<apiVersion>67.0</apiVersion>`. The release brings no new Visualforce markup, but several platform changes land directly on Visualforce:

- **VF controllers are Apex at API 67** — the versioned security defaults flip. SOQL/SOSL/DML/`Database.*` default to `USER_MODE`, and an omitted sharing declaration on a custom controller or extension defaults to `with sharing` (was `without sharing` ≤66). See §3 and `decimatio-apex`.
- **`WITH SECURITY_ENFORCED` is REMOVED in API 67+** — a controller that uses it does not compile. Use `WITH USER_MODE`. See §3.
- **HTTPS is enforced everywhere** — all Visualforce pages and custom domains serve over HTTPS without exception in Summer '26. Never hard-code `http://` resource or callback URLs; use `URLFOR($Resource…)` / relative URLs / Named Credentials.
- **Lightning Web Security blocks `data:` URIs** — when a VF page is embedded in Lightning Experience and generates a client-side download, `HTMLAnchorElement.href` no longer accepts `data:` URIs. Generate a `blob:` URL instead. See §8.
- **Visualforce remains in maintenance mode.** Salesforce ships no new framework features for it and steers all new UI to LWC, then Aura. Treat VF as appropriate only for the specific cases in §1 — not as the default for new work.

---

## 1. The First Question — Should This Be Visualforce At All?

Before writing a single `<apex:page>`, walk this decision tree. Stop at the first row that fits.

| Requirement | Build it as | Visualforce? |
|---|---|---|
| Any net-new Lightning Experience UI | LWC (`decimatio-lwc`) | NO |
| LWC can't express it, but Aura can (e.g. needs an Aura-only base component) | Aura (`decimatio-aura`) | NO |
| Server-rendered **PDF** (`renderAs="pdf"`) | Visualforce | YES |
| **Email templates** with complex/branded merge logic | Visualforce email template | YES |
| Salesforce **Classic**-only screen still in use | Visualforce | YES |
| Maintaining/extending an **existing** VF page in a packaged or legacy app | Visualforce | YES |
| Content that must run inside an **iframe** sandbox | Visualforce | YES |

If the answer is "NO", say so and point to the right skill. Building new Lightning UI in Visualforce is itself the anti-pattern. When you do build VF, add a comment at the top of the page stating which exception above justifies it.

**PDF caveat:** `renderAs="pdf"` uses a legacy rendering engine. Keep PDF pages to simple HTML/CSS (tables, basic styling), avoid JavaScript (it does not run during PDF generation), and test page breaks. Do not pull SLDS into a PDF page — it bloats and renders unpredictably.

---

## 2. MVC and Controller Choice

Visualforce is strict MVC: markup is the View, the controller/extension is the Controller, SObjects are the Model. Keep logic out of the page.

### Controller decision order

1. **Standard controller** (`standardController="Account"`) — single-record CRUD with built-in save/edit/delete/cancel. It enforces CRUD/FLS and sharing automatically. Prefer it.
2. **Standard controller + extension** (`extensions="AccountExt"`) — when you need extra actions or data on top of standard behaviour. The extension constructor takes `ApexPages.StandardController`.
3. **Standard list controller** (`recordSetVar="accounts"`) — list pages with built-in pagination and filtering.
4. **Custom controller** (`controller="MyController"`) — only when no standard controller fits. A custom controller runs in **system mode for CRUD/FLS by default** unless you declare `with sharing` and enforce field access yourself — see §3.

Reuse standard controllers wherever possible: they give you record security and persistence for free.

### Controller rules — absolute

- One controller/extension per page concern; no business logic in the markup.
- **No SOQL or DML inside a getter.** Getters are called repeatedly during rendering; a query in a getter is the classic governor-limit bomb. Query once in the constructor (or a `PageReference` action) and cache the result in a member field.
- Bulkify exactly as in Apex — assume the page can act on many records.
- Delegate SOQL to a Selector/Gateway class; delegate business operations to a Service class (see `decimatio-apex`).

```java
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

```java
// ❌ — SOQL in a getter: re-runs on every reference, blows up view state and limits
public List<Contact> getContacts() {
    return [SELECT Id, Name FROM Contact WHERE AccountId = :acctId];
}
```

---

## 3. Security — User Mode, Encoding, Injection

### CRUD / FLS in controllers

Standard controllers enforce CRUD/FLS/sharing automatically. **Custom controllers do not** — you must enforce it. At API 67 the defaults help you, but always be explicit.

```java
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

For DML in a custom controller use `Database.*` with `AccessLevel.USER_MODE`; for records returned to the page whose FLS varies, use `Security.stripInaccessible`. Full rules in `decimatio-apex` §3.

### Output encoding — Visualforce auto-encodes, but only in HTML context

`{!expression}` is automatically HTML-encoded by the platform. That protects HTML body context only. Inside a `<script>` block, a JS string, an inline event handler, a URL, or a style attribute, you MUST encode explicitly:

```html
<!-- ✅ — JS-in-HTML context -->
<script>
    var name = '{!JSINHTMLENCODE(account.Name)}';
    var url  = '{!URLENCODE(returnUrl)}';
</script>

<!-- ❌ — XSS: merge field dropped raw into a script context -->
<script>var name = '{!account.Name}';</script>
```

Encoding functions: `HTMLENCODE`, `JSENCODE`, `JSINHTMLENCODE`, `URLENCODE`. Never disable platform escaping with `escape="false"` on user-supplied data.

### SOQL injection in dynamic queries

Same rule as Apex: never concatenate user input into a query string. Use bind variables, `Database.queryWithBinds(..., AccessLevel.USER_MODE)`, or `String.escapeSingleQuotes` as a last resort. Full pattern in `references/controller-patterns.md`.

---

## 4. View State — Keep It Small

Standard Visualforce (`<apex:form>` postbacks) serialises controller state into a hidden **view state** field on every request. The hard limit is **135 KB**. Bloated view state is the number-one cause of slow VF pages and `Maximum view state size limit exceeded` errors.

### Rules

- Mark any controller field not needed across postbacks as **`transient`** (it is excluded from view state). Collections used only to render the current response, large blobs, and derived data should all be `transient`.
- Don't hold large query results in non-transient fields. Query what the current request needs; re-query on the next action if necessary.
- Project only the fields you display — `SELECT Id, Name`, never `SELECT` everything.
- Prefer **JavaScript Remoting** (§5) for data-heavy interactions: remoting calls carry **no view state** at all.
- Bind `<apex:inputField>`/`<apex:outputField>` to SObject fields rather than copying values into many scalar controller properties.

```java
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

Inspect view state with the **View State Inspector** (enable *Development Mode* in user settings) before shipping any non-trivial form page.

---

## 5. JavaScript Remoting Over `<apex:actionFunction>`

For asynchronous, partial-page server interaction, **JavaScript Remoting** (`@RemoteAction`) is the modern default. It is stateless (no view state), faster, and gives you direct control over the request/response in JS.

```java
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

Avoid `<apex:actionFunction>` and `<apex:actionSupport>` for anything data-heavy — they round-trip the whole view state. Full remoting patterns, bulkified signatures, and error handling: `references/javascript-remoting.md`.

---

## 6. Styling — SLDS, Not Hand-Rolled CSS

To make a Visualforce page look native in Lightning Experience, opt into the Salesforce Lightning Design System rather than writing bespoke CSS.

```html
<!-- ✅ — platform applies SLDS + LEX look-and-feel -->
<apex:page standardController="Account" lightningStylesheets="true">
    <apex:slds />
    <div class="slds-scope">
        <lightning:card title="Account"> ... </lightning:card>
    </div>
</apex:page>
```

- `lightningStylesheets="true"` on `<apex:page>` gives standard VF components a Lightning skin in LEX/mobile.
- `<apex:slds />` loads SLDS so you can use SLDS utility classes; wrap your markup in a `slds-scope` container.
- Reference SLDS classes; avoid hard-coded colours, fonts, and pixel widths. Do not pull SLDS into `renderAs="pdf"` pages (§1).

---

## 7. Interop — Talking to Aura / LWC via Lightning Message Service

When a Visualforce page is embedded on a Lightning page alongside Aura or LWC, **Lightning Message Service (LMS)** is the only supported way to communicate across the DOM boundary. Never use `window.postMessage` hacks or scrape the parent DOM.

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

The message channel is a metadata type (`*.messageChannel-meta.xml`) shared by LWC, Aura, and VF — the same channel the LWC/Aura side uses. Keep payloads small and serialisable; always unsubscribe when done. For the LWC/Aura side of the same channel, see `decimatio-lwc` / `decimatio-aura`.

---

## 8. Client-Side File Downloads — `blob:`, not `data:`

In Summer '26, Lightning Web Security blocks `data:` URIs on anchor `href`. A VF page running inside LEX that builds a file for download in JavaScript must use a `blob:` URL.

```javascript
// ✅
const blob = new Blob([csvString], { type: 'text/csv' });
const link = document.createElement('a');
link.href = URL.createObjectURL(blob);
link.download = 'export.csv';
link.click();
URL.revokeObjectURL(link.href);

// ❌ — blocked by LWS in Summer '26
link.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csvString);
```

For server-generated files, prefer `renderAs="pdf"` or a controller that returns a `PageReference` to a content resource.

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
| New LEX UI built in Visualforce | LWC (`decimatio-lwc`), then Aura |
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
| API version < 67.0 on new pages/controllers | `<apiVersion>67.0</apiVersion>` in the `*-meta.xml` |

---

## Summary — The Five Commandments

1. **Ask "should this be VF at all?" first** — new Lightning UI is LWC then Aura; reserve Visualforce for PDF, email templates, Classic, iframes, and existing pages.
2. **Controllers are Apex at API 67** — explicit `with sharing` + `WITH USER_MODE`; `WITH SECURITY_ENFORCED` no longer compiles; never query inside a getter.
3. **Guard view state** — `transient` everything render-only, keep it under 135 KB, prefer remoting for data-heavy work.
4. **Encode every non-HTML context and bind every query** — `JSINHTMLENCODE`/`URLENCODE` in scripts, bind variables in dynamic SOQL.
5. **Stay native and interoperable** — SLDS via `lightningStylesheets`/`<apex:slds/>`, LMS (`sforce.one.*`) to talk to Aura/LWC, `blob:` (not `data:`) for downloads.
