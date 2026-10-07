---
name: dya-sf-lwr
description: Salesforce Lightning Web Runtime (Winter '27, API v68.0) — building and porting LWC for LWR, module and base-component availability, client-side navigation, Lightning Web Security and CSP, guest context, performance. Applies to components targeting LWR, client-side navigation code, and components that run under LWS or guest context. Load before creating or editing anything in this scope.
---

# Salesforce Lightning Web Runtime (LWR) — Component Development

LWR is a **runtime**, not a kind of site: the engine that runs Lightning Web Components **without
the Aura framework underneath**. `dya-sf-lwc` teaches the component; this skill teaches the runtime it
lands on. For Experience sites on LWR use `dya-sf-lwr-sites`; for embedding LWCs in non-Salesforce
apps, `dya-sf-lightning-out`. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — release-coupled facts, including the security defaults an
  LWR-hosted controller inherits.
- `references/shared/metadata-and-api-versions.md` — what the `apiVersion` on a bundle decides.
- `references/runtime-differences.md` — full Lightning Experience (Aura runtime) versus LWR
  comparison, navigation APIs and PageReference shape, and a port-an-LWC-to-LWR checklist.

---

## Platform Context — Winter '27 / API v68.0

Save bundles at `<apiVersion>68.0</apiVersion>`. Winter '27 adds `lwc:external`, using a third-party
custom element directly instead of through an iframe — bigger on LWR, where third-party widgets most
often need embedding. See `dya-sf-lwc`.

- **LWR is GA and runs in several places** — Experience Cloud LWR sites, authenticated and public;
  Lightning Out 2.0; standalone LWR on Node/Heroku.
- **Lightning Experience desktop is NOT on LWR.** The internal CRM app runs on the **Aura runtime**,
  where an LWC executes *inside* Aura. Never assume an LWC in Lightning Experience runs on LWR.
- **LWR uses Lightning Web Security (LWS)**, never Lightning Locker.
- **Cross-cutting security:** LWS **blocks `data:` URIs**, so client-side downloads use `blob:` URLs
  (`dya-sf-lwc`). From API 67.0 `WITH SECURITY_ENFORCED` no longer compiles in an Apex controller — use
  `WITH USER_MODE` — and an LWR site's guest user is often the one running it (`dya-sf-permissions`).
- **Salesforce Multi-Framework (UI Bundles) now covers React *and* Angular, and packages as 2GP** —
  managed or unlocked, namespace supported, distributable on AppExchange. Hyperforce only. See §8.

## Summary — The Five Commandments

1. **Decide the runtime first** — decide LEX (Aura) vs LWR vs Lightning Out before writing; they are not
   interchangeable.
2. **Assume no Aura underneath** — verify module and base-component availability against LWR; do not
   assume LEX services exist.
3. **Treat navigation and security as different** — `lightning/navigation` is a narrower client-side router
   on LWR; LWS (not Locker) with strict CSP, and `data:` URIs are blocked.
4. **Design for the guest** — read-only, no ownership, empty/denied is a normal state.
5. **Default to LWC; use a UI Bundle when the app ships to other orgs** — Multi-Framework packages as 2GP, but it is Hyperforce-only and adds a build step LWC does not have.

---

## 1. Know Your Target Runtime

The same `.js`/`.html` LWC can target Lightning Experience (Aura runtime), an LWR site, or Lightning
Out; module availability, navigation and security differ across the three. **Decide the target
first.** A component is portable only if it avoids or guards runtime-specific APIs: one running in
both LEX and LWR is restricted to the **intersection** of supported APIs.

---

## 2. Module & API Availability

With no Aura underneath, some Lightning Experience behaviour is absent or different on LWR:

- Verify each `lightning/*` module against the LWR reference; many work, but **not all**.
- Confirm each `@salesforce/*` scoped module; most are available.
- Never rely on the Aura-runtime services that LEX provides implicitly; they are not present.

When a module is unavailable, prefer a standard-web-platform alternative over an Aura-era API.

---

## 3. Navigation in LWR

`lightning/navigation` exists on LWR as a **client-side router** with a **narrower** set of supported
`PageReference` types than Lightning Experience. A `PageReference` is `{ type, attributes, state }`;
set `attributes` and `state` to `null` when empty.

```javascript
import { NavigationMixin } from 'lightning/navigation';

export default class GoExternal extends NavigationMixin(LightningElement) {
    handleClick() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: 'https://www.example.com/' }
        });
    }
}
```

- Use `NavigationMixin`, the **cross-compatible** choice (LEX and LWR). LWR also exposes `navigate()` /
  `generateUrl()` from the navigation module with the same capability.
- `this[NavigationMixin.GenerateUrl](pageRef)` returns a `Promise<string>`; use it to build a real
  `href` wherever a link suits better than programmatic navigation.
- Read the current location with the `CurrentPageReference` wire adapter; the LWR router
  (`lwr-router-container`) dispatches navigation as page references.
- **Verify every `PageReference` type against the LWR client-side-routing reference.** A type that
  resolves in LEX — some `standard__*Page` types — may do nothing on an LWR site.
- Never hardcode the base path. Derive it from the document `<base href>` at runtime.

Navigation API details and the supported-type checklist: `references/runtime-differences.md`.

---

## 4. Security — Lightning Web Security and CSP

- An LWR site runs its **own LWS instance**, unaffected by the org's global LWS setting. Test in the
  site, not in Lightning Experience.
- LWS supports the cross-namespace LWC communication Locker blocked.
- Third-party JS, inline styles and external endpoints face a strict **Content Security Policy**.
  Register external endpoints as **CSP Trusted Sites** and load third-party scripts as **static
  resources**, never from arbitrary URLs.

---

## 5. Base Components

LWR ships **fewer** base components and templates than the Aura framework.

- **`lightning-file-upload` is not supported on LWR sites.** The platform separately allows *file
  uploads up to 10 GB* to an Aura or LWR site, but that is file capacity, not this base component.
  Use a supported upload mechanism; the guest user cannot use authenticated-only workarounds.
- Confirm any base component against the "Standard Components for LWR Templates" list before using
  it on an LWR target; otherwise build from supported primitives or a custom component.

---

## 6. Guest / Unauthenticated Context

- The guest user is **read-only at most**, **cannot own records**, and sees only what the guest
  profile and sharing explicitly grant.
- Never assume `@AuraEnabled` data is present — results may be empty or access-denied. Render both
  paths as first-class states.
- Keep secrets and privileged operations out of guest-reachable components.

Site-level guest hardening: `dya-sf-lwr-sites`.

---

## 7. Performance

- Mind bundle size, lazy-load heavy work, and keep large libraries out of a guest-facing page.
- Let LDS and GraphQL own data and caching rather than hand-rolling fetch-and-store.
- Treat performance as a requirement: public LWR pages are measured on real-world load and Core Web
  Vitals.

---

## 8. UI Bundles

Salesforce Multi-Framework runs external frameworks as **UI Bundles** on LWR, no longer React-only:
`sf template generate project` ships `reactinternalapp`, `reactexternalapp`, `angularinternalapp` and
`angularexternalapp` — internal templates for already-authenticated employees, external ones with a
full login, registration and profile flow.

A bundle packages as **2GP** in three flavours — managed (registered namespace, source hidden, the
AppExchange path), unlocked namespaced, and unlocked org-dependent. IP protection is managed-only:
`getSourceZip()` returns null to a subscriber for a managed package and readable source for an
unlocked one. Installed bundles render from `*.salesforce.app`, isolated from core UI, so two
same-named bundles from different packages coexist.

It requires **Hyperforce**, English as the org's default language, and the Dev Hub
toggle *Enable Unlocked Packages and Second-Generation Managed Packages* — until it is on,
`sf package create` returns `NOT_FOUND`. Build `dist/` before packaging or deploying, or the app
installs and renders blank. Setup › Security › **Multi-Framework Domains** disables a provisioned
domain as a kill switch: immediate 404, metadata untouched, reversible.

Salesforce publishes no GA label for this, so **confirm availability for the target org before
committing a production plan** rather than inferring it from packaging support. LWC remains the
lower-risk choice for a UI that will only ever live in one org.

---

## 9. Decision Matrix — Quick Reference

| Need | Solution |
|---|---|
| Navigate within an LWR site | `NavigationMixin.Navigate` with an LWR-supported `PageReference` |
| Open an external URL | `standard__webPage` PageReference |
| Build a real link / href | `NavigationMixin.GenerateUrl` (Promise) + `<base href>` base path |
| Read the current route | `CurrentPageReference` wire adapter |
| Confirm a base component works | Check "Standard Components for LWR Templates" |
| Call an external endpoint | CSP Trusted Site + (third-party JS as) static resource |
| Client-side file download | `blob:` URL via `URL.createObjectURL` (`data:` is blocked) |
| Component for both LEX and LWR | Intersection of supported APIs; `NavigationMixin` for nav |
| Single-org production LWR UI | LWC; UI Bundles earn their keep when the app ships to other orgs |

---

## 10. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| Assuming an LWC in Lightning Experience runs on LWR | LEX is the Aura runtime; LWR is a separate target |
| Using a `PageReference` type without checking LWR support | Verify against the LWR CSR reference |
| Hardcoding the site base path | Derive from `<base href>` at runtime |
| `data:` URI for a download | `blob:` URL (LWS blocks `data:`) |
| Reaching for `lightning-file-upload` on an LWR site | Supported upload mechanism; mind the guest user |
| Assuming data is present for a guest user | Handle empty / access-denied as a first-class state |
| Loading third-party JS from arbitrary URLs | Static resource + CSP Trusted Site |
| Reaching for a UI Bundle without checking Hyperforce and the Dev Hub packaging toggle | Verify both first — `sf package create` returns `NOT_FOUND` until the toggle is on |
| Pulling heavy libraries into a guest-facing page | Keep bundles lean; lazy-load |
| API version below 68.0 on new components | `<apiVersion>68.0</apiVersion>` in the `*-meta.xml` |
