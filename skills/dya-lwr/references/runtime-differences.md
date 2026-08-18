# LWR vs Lightning Experience — Runtime Differences & Porting Checklist

Reference for SKILL.md §1–§5. Load when porting an LWC from Lightning Experience to an LWR
target (Experience site or Lightning Out) or writing one for both.

## The two runtimes at a glance

```
Concern              Lightning Experience (Aura runtime)   LWR (Lightning Web Runtime)
-------------------  -----------------------------------   ---------------------------------
Framework underneath Aura (LWC runs inside Aura)           None — pure LWC
Security             Lightning Locker (or org LWS)          Lightning Web Security, own instance
Navigation           lightning/navigation, Aura-backed,     Client-side routing, narrower set
                     broad PageReference support            of supported PageReference types
Base components       Full library                          Subset; some not supported
File upload           lightning-file-upload supported        Not supported on LWR sites
Audience             Authenticated internal users           Often guest / unauthenticated
Performance          Heavier; app shell already loaded      Lean; you own bundle weight + SEO
```

## Navigation

In Lightning Experience, `lightning/navigation` resolves a wide range of `PageReference`
types through the Aura-backed navigation service. On LWR, `lightning/navigation` is a
**client-side router** with a **narrower** set of supported `PageReference` types.

A `PageReference` is `{ type, attributes, state }` — `type` is required; set `attributes` and
`state` to `null` when empty. The router (`lwr-router-container`) dispatches navigation as page
references; read the current one with the `CurrentPageReference` wire adapter.

```javascript
import { NavigationMixin } from 'lightning/navigation';

export default class Nav extends NavigationMixin(LightningElement) {
    // programmatic navigation
    goExternal() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: 'https://www.example.com/' }
        });
    }

    // build a real href instead (Promise<string>)
    async connectedCallback() {
        this.homeUrl = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url: '/home' }
        });
    }
}
```

- `NavigationMixin` is the **cross-compatible** choice (LEX + LWR). LWR also exposes
  `navigate()` / `generateUrl()` from the navigation module with equivalent capability.
- **Verify each `PageReference` type against the LWR client-side-routing reference** — a type
  that resolves in LEX may do nothing on an LWR site.
- For simple intra-site links, an anchor whose `href` is derived from `<base href>` at runtime
  is often simpler than programmatic navigation. Never hardcode the base path:

```javascript
get homeHref() {
    const base = document.querySelector('base')?.getAttribute('href') ?? '/';
    return `${base.replace(/\/$/, '')}/home`;
}
```

## Module availability

- Most `lightning/*` and `@salesforce/*` modules are available, but treat availability as
  **opt-in per module**: confirm against the LWR reference, do not assume parity with LEX.
- Aura-runtime services that LEX provides implicitly are absent — there is no Aura to fall
  back on.
- When a module is missing, prefer a standard web-platform approach over an Aura-era API.

## Security & CSP

- LWR uses Lightning Web Security; an LWR site has its own LWS instance independent of the org
  setting. Test in the site, not only in LEX.
- Register external endpoints as **CSP Trusted Sites**; ship third-party JavaScript as a
  **static resource**, not from an arbitrary URL.

## Porting checklist — LWC from Lightning Experience to LWR

1. List every `lightning/*` and `@salesforce/*` import; confirm each is supported on LWR.
2. List every `NavigationMixin` / `PageReference` usage; confirm the type is supported on LWR;
   replace LEX-only ones with site routing or anchors.
3. Replace any unsupported base component (e.g. `lightning-file-upload`) with a supported
   alternative or a custom component.
4. Assume a guest user: handle empty / access-denied data; remove anything privileged.
5. Externalise nothing to arbitrary URLs — static resources + CSP Trusted Sites.
6. Re-test under the site's own LWS instance and as the guest user, not just in LEX.
7. Check bundle weight and Core Web Vitals on the real page.
