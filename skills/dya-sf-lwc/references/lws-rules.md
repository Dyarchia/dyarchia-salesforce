# Lightning Web Security — the Rules That Break Working Code

Lightning Web Security replaces the DOM and several built-in objects with distorted versions inside a
component's sandbox. Most of it is invisible. Below are the rules where ordinary JavaScript compiles,
deploys, then behaves differently — which is why they first read as platform bugs.

Salesforce's analysis catalogue numbers these `lws-001` through `lws-023b`. This file carries the ones
that bite real component code, with identifiers so a finding can be looked up.

## `lws-008` — assigning to global objects

Blocked as **property assignment** on `globalThis`, `window`, `window.top`, `window.parent`,
`window.frames`, `document.defaultView` and `self`.

```javascript
window.myAppState = { user };        // ❌ blocked
const w = window.innerWidth;         // ✅ reads are fine
document.cookie = 'k=v';             // ✅ document is not on the list
```

**Reads are unaffected**, and it only applies to files importing from `lwc` — a plain utility module
does not trip it. The fix is almost always a module-scoped variable or a service module, not a global.

## `lws-016` — `Map` and `Set` misuse

LWS replaces the internal data structures, breaking three ordinary-looking things:

```javascript
myMap[key];                          // ❌ bracket access — use myMap.get(key)
JSON.stringify(mySet);               // ❌ produces nothing useful
this.dispatchEvent(new CustomEvent('x', { detail: myMap }));   // ❌
```

The third costs the most time: **a `Map` or `Set` passed through `@wire`, `@track`, an event
payload, or into a child component does not survive.** Convert to a plain object or array at the
boundary and rebuild on the other side.

## `lws-017` — mutating objects the component does not own

```javascript
event.detail.value = 'x';            // ❌ the event's payload is not yours
this.apiRecord.Name = 'x';           // ❌ an @api-received object is not yours
this.wiredData[0].amount = 0;        // ❌ wire data is not yours
element.customProp = 123;            // ❌ use element.dataset instead
```

Spread into a local copy and mutate that. This overlaps the framework's one-way data flow rule, so
the simpler mental model is a hard platform constraint, not a style preference.

## `lws-019` — `URL.createObjectURL` by MIME type

| MIME | Behaviour |
|---|---|
| `image/*`, `video/*`, `audio/*`, `application/pdf` | Safe |
| `text/html`, `image/svg+xml`, `text/xml` | Warns — requires content scanning |
| `text/javascript`, empty or undefined | **Blocked** |

This both enables and bounds the `blob:` download pattern in §8: **always give the `Blob` an
explicit MIME type from the safe set.** An omitted type is blocked, and the failure is silent.

## `lws-020` — URL schemes

Only `http`, `https` and `about:blank` are permitted where a URL is *taken from input or
constructed dynamically* — in `href`, `src`, `action`, `window.location`, `window.open`,
`setAttribute`, `fetch` and XHR. The schemes that matter are `javascript:`, `vbscript:`, `file:`,
`ftp:` and `ws:`.

This is a rule about **untrusted URLs**, not a blanket ban on every scheme it lists. The same
catalogue flags `data:`, `blob:`, `tel:` and `mailto:` for review, and `lws-019` above sanctions
`URL.createObjectURL` for safe MIME types — so a `blob:` URL your own code minted for an
`<a download>` is not what this rule catches. When a URL comes from a record field, a parameter or
anything a user can influence, validate the scheme before assigning it.

## `lws-023` — iframes

**All `srcdoc` is blocked**, with no MIME-type escape hatch. `iframe.src` accepts only `http` and
`https`. An iframe is often the wrong tool anyway: `lwc:external` lets a third-party custom element be
used directly.

## `lws-018` — trusted-type policy names

`trustedTypes.createPolicy()` refuses the names `'default'`, `''`, `'lwsInternal'` and `'trusted'`.
Pick something namespaced to your component.

## `lws-014` — `document.execCommand`

Blocked only for `insertHTML` and `selectAll`. `copy`, `cut`, `paste`, `bold` and the rest are fine —
so do not rewrite a working clipboard helper.

## Reviewing for these

`sf code-analyzer run` with the ESLint engine covers part of this surface; the LWS-specific rules are
a review checklist no linter fully enforces. When a component "works locally but not in the org", walk
this list before debugging the logic — every rule here produces behaviour, not an error.

Add one template sink to any review: **`lwc:inner-html`**, the LWC equivalent of assigning
`innerHTML`, with the same injection question.
