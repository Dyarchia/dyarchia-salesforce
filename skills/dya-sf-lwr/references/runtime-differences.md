# LWR vs Lightning Experience — Runtime Differences & Porting Checklist

Load when porting an LWC from Lightning Experience to an LWR target (Experience site or Lightning
Out) or writing one for both.

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

In a `PageReference`, `type` is required. The rest of the model is in SKILL.md §3.

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

For simple intra-site links, an anchor whose `href` derives from `<base href>` is often simpler than
programmatic navigation:

```javascript
get homeHref() {
    const base = document.querySelector('base')?.getAttribute('href') ?? '/';
    return `${base.replace(/\/$/, '')}/home`;
}
```

## Porting checklist — LWC from Lightning Experience to LWR

1. List every `lightning/*` and `@salesforce/*` import; confirm each is supported on LWR.
2. List every `NavigationMixin` / `PageReference` usage; confirm the type is supported on LWR;
   replace LEX-only ones with site routing or anchors.
3. Replace any unsupported base component (e.g. `lightning-file-upload`) with a supported
   alternative or a custom component.
4. Assume a guest user: handle empty / access-denied data; remove anything privileged.
5. Externalise nothing to arbitrary URLs — static resources + CSP Trusted Sites.
6. Re-test under the site's own LWS instance and as the guest user, not only in LEX.
7. Check bundle weight and Core Web Vitals on the real page.
