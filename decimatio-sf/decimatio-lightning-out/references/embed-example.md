# Lightning Out 2.0 — Host-Page Embed Example

Reference for SKILL.md §2–§6. Load when wiring an LWC into a non-Salesforce page. Confirm exact
endpoint payloads and the script URL against the current Lightning Out 2.0 docs; the shape and
flow below are correct.

## Salesforce-side setup

1. **Lightning Out 2.0 App Manager** (Setup) — create a Lightning Out 2.0 app; declare the
   components allowed to embed. It yields the **18-digit `app-id`** and the **host script** URL.
2. **External Client App** — OAuth 2.0 for the host, correct scopes, host domain configured.
3. **CORS allowlist** (Setup → CORS) — add the external app origin. Without it, requests fail
   with opaque cross-origin errors.

## Host page

```html
<!doctype html>
<html>
<head>
    <meta charset="utf-8" />
    <script src="https://MyDomain.my.salesforce.com/lightning/lightningout2/app.js"></script>
</head>
<body>
    <lightning-out-application
        id="sf-app"
        app-id="0RBxx0000000001GAA"
        components="c-account-summary">
    </lightning-out-application>

    <script type="module">
        const app = document.getElementById('sf-app');

        // 1. Lifecycle — never assume success
        app.addEventListener('lo.application.ready', () => console.log('session ready'));
        app.addEventListener('lo.application.error', (e) => console.error('session failed', e));
        app.addEventListener('lo.component.ready', () => console.log('component rendered'));
        app.addEventListener('lo.component.error', (e) => console.error('component failed', e));

        // 2. Component events come out as standard CustomEvents
        app.addEventListener('accountselected', (e) => handleSelection(e.detail.recordId));

        // 3. Brokered auth: access token -> frontdoor URL, set at runtime
        const accessToken = await getSalesforceAccessToken(); // your OAuth 2.0 flow
        const res = await fetch(
            'https://MyDomain.my.salesforce.com/services/oauth2/singleaccess',
            { method: 'POST', headers: { Authorization: `Bearer ${accessToken}` } }
        );
        const { frontdoor_uri } = await res.json();
        app.frontdoorUrl = frontdoor_uri;
    </script>
</body>
</html>
```

The embedded component is an **iframe that is the root of a closed shadow DOM**; host CSS/JS
cannot reach into it, and the LWC runs in the **Salesforce context**. Cross-boundary messaging
is `window.postMessage()` under the hood, surfaced as `CustomEvent`s on the
`lightning-out-application` element.

## Passing inputs in

Set inputs as attributes/properties on the element (per the documented input mechanism). Keep
them primitive and serialisable.

```javascript
app.setAttribute('record-id', '001XXXXXXXXXXXXXXX');
```

## Component side — ordinary CustomEvent

```javascript
this.dispatchEvent(new CustomEvent('accountselected', {
    detail: { recordId: this.recordId }
}));
```

## Rules

- `frontdoor-url` is short-lived and per-session — generate it at runtime, never hardcode it;
  no long-lived secrets in host JS.
- Wire `lo.application.*` and `lo.component.*` — auth/CORS misconfig surfaces there, not as an
  exception.
- Small, serialisable payloads only — never DOM nodes or live references across the iframe;
  validate messages both ways.
- The component runs on **LWR** — apply every `decimatio-lwr` constraint (module/base-component
  availability, no off-platform navigation context, possibly limited session).
