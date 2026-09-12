---
name: dya-lightning-out
description: Salesforce Lightning Out 2.0 Winter '27 (API v68.0) — embedding Lightning Web Components in external (non-Salesforce) web apps on the LWR runtime: the lightning-out-application element, app-id from the App Manager, the singleaccess frontdoor-url OAuth flow, lifecycle events, closed-shadow-DOM iframe isolation, CORS, and host/component messaging. Load only when the user explicitly invokes this skill by name (`dya-lightning-out`); do NOT auto-trigger on generic LWC, embedding, or integration questions.
---

# Salesforce Lightning Out 2.0 — Embedding LWCs Off-Platform

You are a Salesforce integration expert. Lightning Out 2.0 renders **Lightning Web Components inside
a non-Salesforce web page** — your own site, another app. It runs on the **LWR runtime**, so
everything in `dya-lwr` applies; for the components themselves, `dya-lwc`.

This SKILL.md carries the load-bearing rules. Larger material lives in `references/`:

- `references/shared/platform-deltas.md` — the release-coupled facts behind the rules here.
- `references/shared/sharing-and-access.md` — what the brokered session identity is actually allowed
  to see once the component renders.
- `references/embed-example.md` — a full host-page embed: app registration, the singleaccess token
  exchange, `lightning-out-application`, lifecycle events, and receiving component events.

---

## Platform Context — Winter '27 / API v68.0

**Lightning Out 2.0 is GA (since Winter '26)** and is the supported way to surface LWCs outside
Salesforce, replacing the decade-old Lightning Out 1.0 (Aura). Hold these:

- **Built on LWR, not Aura**, so **every `dya-lwr` caveat applies**: verify module and
  base-component availability, navigation follows the LWR model — a host-page embed usually has no
  Salesforce navigation context at all — and the session identity may be limited.
- **Each embedded component is an iframe that is the root of a CLOSED shadow DOM.** Host-page
  JavaScript cannot see into or manipulate it, and the LWC executes in the **Salesforce context**
  rather than the host page's. Neither side's CSS or JS bleeds into the other.
- **Auth is brokered through a `frontdoor-url`** obtained via OAuth 2.0 and the
  `/services/oauth2/singleaccess` endpoint. Secrets never go into host JavaScript.
- **Register a Lightning Out 2.0 app** in the **Lightning Out 2.0 App Manager** (Setup) to get the
  18-digit `app-id` and the host script.

Winter '27 changes nothing in Lightning Out. It remains production-usable, and the OAuth
username-password flow retirement (enforced 20 February 2027) does not touch the `singleaccess`
exchange used here — see `dya-integration-auth` if the host application authenticates any other way.

---

## 1. When to Use Lightning Out (and When Not)

Use it when a **specific Salesforce LWC must appear inside an app you do not host on Salesforce** and
rebuilding it natively is not worth it.

```
Situation                                          Right tool
-------------------------------------------------  ----------------------------------------
Embed one/few Salesforce LWCs in an external app   Lightning Out 2.0
Whole experience could live on Salesforce          LWR site (dya-lwr-sites)
You need data, not UI                              Salesforce API / integration (no embed)
Deep, chatty host<->component coupling             Cleaner API contract; the iframe is a wall
Embed in another Salesforce surface                Not Lightning Out — use a FlexiPage/site
```

---

## 2. Setup — Register the App First

1. **Lightning Out 2.0 App Manager** (Setup) — create the app. It declares which components may be
   embedded and yields the **18-digit `app-id`** and the **host script** URL for the external page.
2. **External Client App** — the modern connected app: OAuth 2.0 for the host, the correct scopes,
   and the host domain.
3. **CORS allowlist** — add the external app's origin under Setup → CORS. Without it, requests fail
   with opaque cross-origin errors.

---

## 3. The `lightning-out-application` Element

A non-visual element with three required attributes:

```html
<lightning-out-application
    app-id="0RBxx0000000001GAA"
    frontdoor-url={runtimeFrontdoorUrl}
    components="c-account-summary,c-case-list">
</lightning-out-application>
```

- **`app-id`** — the 18-digit id from the App Manager.
- **`frontdoor-url`** — set **dynamically at runtime**, never hardcoded; it carries the session (§4).
- **`components`** — comma-separated LWC names in `c-my-component` form, hyphens separating the
  namespace and the camelCase parts.

---

## 4. Authentication — the singleaccess frontdoor flow

The host page never holds a long-lived Salesforce secret:

1. The host obtains a valid Salesforce **access token** via OAuth 2.0, through your External Client
   App or the app's existing Salesforce auth.
2. The host **exchanges that token for a frontdoor URL** at `/services/oauth2/singleaccess`, the UI
   Bridge API.
3. The host sets the resulting URL on `frontdoor-url` **at runtime**.
4. The Lightning Out 2.0 script uses it to establish the Salesforce session for the iframe.

```javascript
const res = await fetch('https://MyDomain.my.salesforce.com/services/oauth2/singleaccess', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${accessToken}` }
});
const { frontdoor_uri } = await res.json();
document.querySelector('lightning-out-application').frontdoorUrl = frontdoor_uri;
```

Confirm the exact request and response shape against the current docs, since the mechanism is
auth-flow-specific. The principle is fixed: **token in, short-lived frontdoor URL out, set at
runtime.**

---

## 5. Lifecycle Events — Wire Them, Always

Lightning Out 2.0 fires events you MUST handle for a non-broken UX:

```javascript
const app = document.querySelector('lightning-out-application');
app.addEventListener('lo.application.ready', () => showEmbed());
app.addEventListener('lo.application.error', (e) => showFallback(e));
app.addEventListener('lo.component.ready',   () => hideSpinner());
app.addEventListener('lo.component.error',   (e) => logAndFallback(e));
```

- `lo.application.ready` / `lo.application.error` — session established or failed.
- `lo.component.ready` / `lo.component.error` — a component rendered or failed.

Never assume the embed succeeded. An auth or CORS misconfiguration surfaces here, not as an
exception.

---

## 6. Host ↔ Component Communication

- The boundary is a **closed shadow-DOM iframe**, so the host cannot reach in. Communication is
  `window.postMessage()` underneath, surfaced as standard `CustomEvent`s.
- Pass inputs **in** through attributes and properties on `lightning-out-application`; receive
  outputs **out** by listening for the component's events on that element.
- Keep the contract **small and serialisable** — primitives and plain objects, never DOM nodes or
  live references across the boundary.
- Treat each side as untrusted from the other and validate messages both ways.

---

## 7. Runtime Constraints Carry Over (it is LWR)

Design the embedded LWC for LWR, not for Lightning Experience: not all `lightning/*` modules and base
components exist, a host page usually has **no Salesforce navigation context** so LEX `PageReference`
types will not resolve, and the session may be a limited identity. `dya-lwr` carries the detail.

---

## 8. Decision Matrix — Quick Reference

| Need | Solution |
|---|---|
| 18-digit app id + allowed components | Register a Lightning Out 2.0 app in the App Manager |
| Establish the session in the iframe | `frontdoor-url` from `/services/oauth2/singleaccess`, set at runtime |
| Authorise the host | External Client App (OAuth 2.0) + CORS allowlist of host origin |
| Know when the embed is ready/failed | `lo.application.*` / `lo.component.*` events |
| Send data to the component | Attribute/property on `lightning-out-application` |
| React to the component | Listen for its `CustomEvent` on the element |
| Call an external endpoint from the LWC | CSP Trusted Site (it runs under LWS — see `dya-lwr`) |

---

## 9. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| Lightning Out 1.0 / Aura embedding for new work | Lightning Out 2.0 (LWR, GA) |
| Embedding a whole experience that could be a site | Build an LWR site (`dya-lwr-sites`) |
| Hardcoding tokens/secrets in host JS | Brokered `frontdoor-url` via `/services/oauth2/singleaccess` |
| Hardcoding the `frontdoor-url` | Set it dynamically at runtime per session |
| Skipping the CORS allowlist | Add the host origin in Setup -> CORS |
| Assuming the embed succeeded | Handle `lo.application.error` / `lo.component.error` |
| Passing DOM nodes / live refs across the iframe | Small, serialisable `CustomEvent` payloads |
| Using LEX `PageReference` types in the embed | No nav context off-platform; apply LWR rules |
| Assuming full LEX module/base-component availability | It is LWR — apply `dya-lwr` constraints |
| Using Lightning Out when you only need data | Call a Salesforce API; no embedded UI |

---

## Summary — The Five Commandments

1. **Lightning Out 2.0, not 1.0** — LWR-native, GA; closed-shadow-DOM iframe isolation.
2. **Register the app, then embed** — `app-id` + host script from the App Manager; three
   attributes on `lightning-out-application`.
3. **Brokered auth** — token -> `/services/oauth2/singleaccess` -> runtime `frontdoor-url`; no
   secrets in host JS; CORS-allowlist the host.
4. **Wire the lifecycle events** — `lo.application.*` / `lo.component.*`; never assume success.
5. **It is LWR underneath** — every `dya-lwr` constraint applies; small serialisable
   contract across the iframe, validated both ways.
