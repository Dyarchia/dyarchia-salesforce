---
name: dya-lwr
description: Salesforce Lightning Web Runtime (LWR) Winter '27 (API v68.0) — building and porting Lightning Web Components for the LWR runtime: where LWR runs, module and base-component availability vs Lightning Experience, client-side navigation (NavigationMixin / navigate / generateUrl), Lightning Web Security and CSP, guest context, performance. Load only when the user explicitly invokes this skill by name (`dya-lwr`); do NOT auto-trigger on generic LWC, Lightning, or component questions.
---

# Salesforce Lightning Web Runtime (LWR) — Component Development

You are a Salesforce front-end expert. LWR is a **runtime**, not a kind of site: the engine that runs
Lightning Web Components **without the Aura framework underneath**. `dya-lwc` teaches the component;
this skill teaches the runtime it lands on, and writing runtime-aware components is what avoids the
"works in LEX, breaks on the site" bug. For Experience sites on LWR use `dya-lwr-sites`; for
embedding LWCs in non-Salesforce apps, `dya-lightning-out`.

This SKILL.md carries the load-bearing rules. Larger material lives in `references/`:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the security
  defaults an LWR-hosted controller inherits.
- `references/shared/metadata-and-api-versions.md` — what the `apiVersion` on a bundle decides.
- `references/runtime-differences.md` — the full Lightning Experience (Aura runtime) versus LWR
  comparison, the navigation APIs and PageReference shape, and a port-an-LWC-to-LWR checklist.

---

## Platform Context — Winter '27 / API v68.0

Save bundles at `<apiVersion>68.0</apiVersion>`. Winter '27 adds `lwc:external`, which uses a
third-party custom element directly instead of through an iframe — a bigger deal on LWR, where
third-party widgets most often need embedding. See `dya-lwc`.

The runtime facts you must hold:

- **LWR is GA and runs in several places** — Experience Cloud LWR sites, authenticated and public;
  Lightning Out 2.0; standalone LWR on Node/Heroku.
- **Lightning Experience desktop is NOT on LWR.** The internal CRM app runs on the **Aura runtime**,
  where an LWC executes *inside* Aura. Never assume an LWC in Lightning Experience runs on LWR.
- **LWR uses Lightning Web Security (LWS)**, never Lightning Locker, and an LWR site has its **own
  LWS instance** independent of the org-wide LWS setting.
- **Cross-cutting security:** LWS **blocks `data:` URIs**, so client-side downloads use `blob:` URLs
  (`dya-lwc`). From API 67.0 `WITH SECURITY_ENFORCED` no longer compiles in an Apex controller — use
  `WITH USER_MODE` — and an LWR site's guest user is often the one running it (`dya-permissions`).
- **Salesforce Multi-Framework (UI Bundles) now covers React *and* Angular, and packages as 2GP** —
  managed or unlocked, namespace supported, distributable on AppExchange. Hyperforce only. Confirm
  the availability status for the target org before planning production on it; LWC stays the
  lower-risk choice for a UI that only ever lives in one org. See §8.

---

## 1. Know Your Target Runtime Before You Write

The same `.js`/`.html` LWC can target Lightning Experience (Aura runtime), an LWR site, or Lightning
Out, and module availability, navigation and security differ across the three. **Decide the target
first.** A component is portable only if it avoids runtime-specific APIs or guards them: one that
must run in both LEX and LWR is restricted to the **intersection** of supported APIs.

---

## 2. Module & API Availability

With no Aura framework underneath, part of what "just works" in Lightning Experience is absent or
different on LWR:

- Many `lightning/*` modules work, but **not all** — verify each against the LWR reference.
- `@salesforce/*` scoped modules are largely available; confirm per module.
- Aura-runtime services that LEX provides implicitly are not present.

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

- `NavigationMixin` is the **cross-compatible** choice, working in LEX and LWR. LWR also exposes
  `navigate()` / `generateUrl()` from the navigation module with the same capability.
- `this[NavigationMixin.GenerateUrl](pageRef)` returns a `Promise<string>`. Use it to build a real
  `href` wherever a link is more appropriate than programmatic navigation.
- Read the current location with the `CurrentPageReference` wire adapter; the LWR router
  (`lwr-router-container`) dispatches navigation as page references.
- **Verify every `PageReference` type against the LWR client-side-routing reference.** A type that
  resolves in LEX — some `standard__*Page` types — may do nothing on an LWR site.
- Never hardcode the base path. Derive it from the document `<base href>` at runtime.

> Navigation API details and the supported-type checklist: see `references/runtime-differences.md`.

---

## 4. Security — Lightning Web Security and CSP

LWR enforces **Lightning Web Security**, not Lightning Locker:

- An LWR site runs its **own LWS instance**, unaffected by the org's global LWS setting. Test in the
  actual site, not in Lightning Experience.
- LWS supports the cross-namespace LWC communication Locker blocked.
- Third-party JS, inline styles and external endpoints face a strict **Content Security Policy**.
  Register external endpoints as **CSP Trusted Sites** and load third-party scripts as **static
  resources**, never from arbitrary URLs.

---

## 5. Base Components — Not All Are Supported

LWR ships **fewer** base components and templates than the Aura framework; some do not exist on it.

- **`lightning-file-upload` is not supported on LWR sites.** The platform separately allows *file
  uploads up to 10 GB* to an Aura or LWR site, but that is file capacity, not this base component.
  Handle uploads with a supported mechanism, and note that the guest user cannot use
  authenticated-only workarounds.
- Confirm any base component against the "Standard Components for LWR Templates" list before using
  it on an LWR target. Otherwise build from supported primitives or a custom component.

---

## 6. Guest / Unauthenticated Context

LWR sites are frequently browsed by users who are **not logged in**:

- The guest user is **read-only at most**, **cannot own records**, and sees only what the guest
  profile and sharing explicitly grant.
- Never assume `@AuraEnabled` data is present — results may be empty or access-denied. Render the
  empty and denied paths as first-class states.
- Keep secrets and privileged operations out of guest-reachable components entirely.

Site-level guest hardening lives in `dya-lwr-sites`; this is the component-side discipline.

---

## 7. Performance Posture

LWR is lean by design:

- Mind bundle size, lazy-load heavy work, and keep large libraries out of a guest-facing page.
- Let LDS and GraphQL own data and caching rather than hand-rolling fetch-and-store.
- Public LWR pages are measured on real-world load and Core Web Vitals. Treat performance as a
  requirement.

---

## 8. UI Bundles — a Real Distribution Path, With Real Constraints

Salesforce Multi-Framework runs external frameworks as **UI Bundles** on LWR, and it is no longer
React-only: `sf template generate project` ships `reactinternalapp`, `reactexternalapp`,
`angularinternalapp` and `angularexternalapp`, the internal templates for already-authenticated
employees and the external ones carrying a full login, registration and profile flow.

A bundle packages as **2GP** in three flavours — managed (registered namespace, source hidden, the
AppExchange path), unlocked namespaced, and unlocked org-dependent — so packaging and namespaces are
both supported, and IP protection is managed-only: `getSourceZip()` returns null to a subscriber for
a managed package and readable source for an unlocked one. Installed bundles render from
`*.salesforce.app`, isolated from core UI, which is why two same-named bundles from different
packages coexist.

Feasibility is decided elsewhere: **Hyperforce only**, English as the org's default language, and the
Dev Hub toggle *Enable Unlocked Packages and Second-Generation Managed Packages* — until that is on,
`sf package create` returns `NOT_FOUND`. Build `dist/` before packaging or deploying or the app
installs and renders blank. Setup › Security › **Multi-Framework Domains** disables a provisioned
domain as a kill switch: immediate 404, metadata untouched, reversible.

Salesforce publishes no GA label for this, so **confirm the availability status for the target org
before committing a production plan** rather than inferring it from the packaging support. LWC
remains the lower-risk choice for a UI that will only ever live in one org.

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

---

## Summary — The Five Commandments

1. **Runtime first** — decide LEX (Aura) vs LWR vs Lightning Out before you write; they are not
   interchangeable.
2. **No Aura underneath** — verify module and base-component availability against LWR; do not
   assume LEX services exist.
3. **Navigation and security differ** — `lightning/navigation` is a narrower client-side router
   on LWR; LWS (not Locker) with strict CSP, and `data:` URIs are blocked.
4. **Design for the guest** — read-only, no ownership, empty/denied is a normal state.
5. **LWC by default; a UI Bundle when the app ships to other orgs** — Multi-Framework packages as 2GP, but it is Hyperforce-only and adds a build step LWC does not have.
