# Lightning Web Security — the Rules That Break Working Code

Lightning Web Security replaces the DOM and several built-in objects with distorted versions inside a
component's sandbox. These are the rules where ordinary JavaScript compiles and deploys, then behaves
differently.

Salesforce's analysis catalogue numbers these `lws-001` through `lws-023b`; the identifiers below let a
finding be looked up.

## `lws-008` — assigning to global objects

Blocked as **property assignment** on `globalThis`, `window`, `window.top`, `window.parent`,
`window.frames`, `document.defaultView` and `self`.

```javascript
window.myAppState = { user };        // ❌ blocked
const w = window.innerWidth;         // ✅ reads are fine
document.cookie = 'k=v';             // ✅ document is not on the list
```

**Reads are unaffected**, and it only applies to files importing from `lwc` — a plain utility module
does not trip it. Use a module-scoped variable or a service module instead of a global.

## `lws-016` — `Map` and `Set` misuse

LWS replaces the internal data structures:

```javascript
myMap[key];                          // ❌ bracket access — use myMap.get(key)
JSON.stringify(mySet);               // ❌ produces nothing useful
this.dispatchEvent(new CustomEvent('x', { detail: myMap }));   // ❌
```

**A `Map` or `Set` passed through `@wire`, `@track`, an event payload, or into a child component
does not survive.** Convert to a plain object or array at the
boundary and rebuild on the other side.

## `lws-017` — mutating objects the component does not own

```javascript
event.detail.value = 'x';            // ❌ the event's payload is not yours
this.apiRecord.Name = 'x';           // ❌ an @api-received object is not yours
this.wiredData[0].amount = 0;        // ❌ wire data is not yours
element.customProp = 123;            // ❌ use element.dataset instead
```

Spread into a local copy and mutate that. Under LWS, one-way data flow is a platform constraint.

## `lws-019` — `URL.createObjectURL` by MIME type

| MIME | Behaviour |
|---|---|
| `application/octet-stream`, `application/json`, `application/pdf`, `text/plain`, `text/markdown`, `image/*`, `video/*`, `audio/*`, `font/*`, `application/zip`, `application/x-bzip`, `application/x-rar-compressed`, `application/x-tar` | Allowed |
| `text/html`, `image/svg+xml`, `text/xml` | Sanitized; throws if sanitizing would change the content |
| Empty | Re-typed as `text/plain` |
| Anything else, including `text/csv`, `text/javascript` and any type with parameters (`;charset=...`) | **Blocked**: throws `Unsupported MIME type.` |

For the `blob:` download pattern in §8, **give the `Blob` an explicit type from the allowed set.** A
CSV is not on it: use `application/octet-stream` and let `download` carry the file name.

## `lws-020` — URL schemes

Only `http`, `https` and `about:blank` are permitted where a URL is *taken from input or
constructed dynamically* — in `href`, `src`, `action`, `window.location`, `window.open`,
`setAttribute`, `fetch` and XHR. The schemes that matter are `javascript:`, `vbscript:`, `file:`,
`ftp:` and `ws:`.

The rule targets **untrusted URLs**, not every scheme it lists. The catalogue flags `data:`,
`blob:`, `tel:` and `mailto:` for review, and `lws-019` sanctions `URL.createObjectURL` for allowed MIME
types, so a `blob:` URL your own code minted for an `<a download>` is not caught. When a URL comes
from a record field, a parameter or anything a user can influence, validate the scheme before
assigning it.

## `lws-023` — iframes

**All `srcdoc` is blocked**, with no MIME-type escape hatch. `iframe.src` accepts only `http` and
`https`. For a third-party custom element, use `lwc:external` instead.

## `lws-018` — trusted-type policy names

`trustedTypes.createPolicy()` refuses the names `'default'`, `''`, `'lwsInternal'` and `'trusted'`.
Name the policy with something namespaced to your component.

## `lws-014` — `document.execCommand`

Blocked only for `insertHTML` and `selectAll`. `copy`, `cut`, `paste`, `bold` and the rest are fine.

## Reviewing for these

`sf code-analyzer run` with the ESLint engine covers part of this surface; the LWS-specific rules are
a review checklist no linter fully enforces. When a component works locally but not in the org, walk
this list before debugging the logic: these rules change behaviour without raising an error.

Add one template sink to any review: **`lwc:inner-html`**, the LWC equivalent of assigning
`innerHTML`, with the same injection question.
