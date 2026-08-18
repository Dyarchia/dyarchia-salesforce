---
name: dya-lwr
description: Salesforce Lightning Web Runtime (LWR) Summer '26 (API v67.0) — building and porting Lightning Web Components for the LWR runtime: where LWR runs, module and base-component availability vs Lightning Experience, client-side navigation (NavigationMixin / navigate / generateUrl), Lightning Web Security and CSP, guest context, performance. Load only when the user explicitly invokes this skill by name (`dya-lwr`); do NOT auto-trigger on generic LWC, Lightning, or component questions.
---

# Salesforce Lightning Web Runtime (LWR) — Component Development

You are a Salesforce front-end expert. LWR is a **runtime**, not a kind of site: the engine
that runs Lightning Web Components **without the Aura framework underneath**. A component
behaves differently depending on the runtime that hosts it, and this skill is about that
difference. For LWC authoring itself (templates, LDS, GraphQL, state), use `dya-lwc`;
for building Experience sites on LWR, use `dya-lwr-sites`; for embedding LWCs in
non-Salesforce apps, use `dya-lightning-out`.

This SKILL.md carries the load-bearing rules. Larger material lives in `references/`:

- `references/runtime-differences.md` — full Lightning Experience (Aura runtime) vs LWR
  comparison, the navigation APIs and PageReference shape, and a port-an-LWC-to-LWR checklist.

---

## Platform Context — Summer '26 / API v67.0

**Current API version: 67.0 (Summer '26).** Save bundles at `<apiVersion>67.0</apiVersion>`.
Footprint and v67 facts you must hold:

- **LWR is GA and runs in several places** — Experience Cloud LWR sites (authenticated and
  public), Lightning Out 2.0 (LWCs in non-Salesforce apps), and standalone LWR on Node/Heroku.
  It is the modern, lightweight, LWC-native runtime.
- **Lightning Experience desktop is NOT on LWR** — the internal CRM app runs on the **Aura
  runtime**, where an LWC executes *inside* Aura. Do not assume an LWC in Lightning Experience
  runs on LWR; it does not.
- **LWR uses Lightning Web Security (LWS)**, never Lightning Locker, and an LWR site has its
  **own LWS instance** independent of the org-wide LWS setting.
- **v67 cross-cutting:** LWS now **blocks `data:` URIs** — build client-side downloads with
  `blob:` URLs (see `dya-lwc`). `WITH SECURITY_ENFORCED` no longer compiles in Apex
  controllers — use `WITH USER_MODE`.
- **React / Salesforce Multi-Framework (UI Bundles) is open Beta in v67 — DO NOT use in
  production.** Scratch orgs and sandboxes only; beta apps cannot deploy to production. Build
  LWR UIs with LWC; revisit at GA.

Mental model: **`dya-lwc` teaches the component; this skill teaches the runtime it lands
on.** Write runtime-aware components and you avoid the "works in LEX, breaks on the site" bug.

---

## 1. Know Your Target Runtime Before You Write

The same `.js`/`.html` LWC can target Lightning Experience (Aura runtime), an LWR site, or
Lightning Out. **Decide the target first** — module availability, navigation, and security
differ. A component is portable only if it avoids runtime-specific APIs or guards them; if it
must run in both LEX and LWR, restrict it to the **intersection** of supported APIs. Never
assume the richer LEX runtime is underneath.

---

## 2. Module & API Availability

LWR has **no Aura framework underneath**, so part of what "just works" in Lightning Experience
is absent or different:

- Many `lightning/*` modules work, but **not all** — verify each against the LWR reference.
- `@salesforce/*` scoped modules are largely available; confirm per module.
- Aura-runtime services that LEX provides implicitly are not present.

When a module is unavailable, prefer a standard-web-platform alternative over an Aura-era API.

---

## 3. Navigation in LWR

`lightning/navigation` exists on LWR, but it is a **client-side router** with a **narrower** set
of supported `PageReference` types than Lightning Experience. A `PageReference` is
`{ type, attributes, state }` (set `attributes`/`state` to `null` when empty).

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

- `NavigationMixin` is the **cross-compatible** choice (works in LEX and LWR). LWR also exposes
  `navigate()` / `generateUrl()` from the navigation module with the same capability.
- `this[NavigationMixin.GenerateUrl](pageRef)` returns a `Promise<string>` — use it to build a
  real `href` rather than navigating programmatically where a link is more appropriate.
- Read the current location with the `CurrentPageReference` wire adapter; the LWR router
  (`lwr-router-container`) dispatches navigation as page references.
- **Verify every `PageReference` type against the LWR client-side-routing reference** — a type
  that resolves in LEX (e.g. some `standard__*Page` types) may do nothing on an LWR site.
- Never hardcode the base path — derive it from the document `<base href>` at runtime.

> Navigation API details and the supported-type checklist: see `references/runtime-differences.md`.

---

## 4. Security — Lightning Web Security and CSP

LWR enforces **Lightning Web Security (LWS)**, not Lightning Locker:

- An LWR site runs its **own LWS instance**, unaffected by the org's global LWS setting — test
  in the actual site, not just in Lightning Experience.
- LWS supports cross-namespace LWC communication that Locker blocked.
- Third-party JS, inline styles, and external endpoints face strict **Content Security Policy**:
  register external endpoints as **CSP Trusted Sites**, and load third-party scripts as
  **static resources**, never from arbitrary URLs.
- `data:` URIs are blocked in v67 — generate files as `blob:` object URLs.

---

## 5. Base Components — Not All Are Supported

LWR ships **fewer** base components and templates than the Aura framework; some simply do not
exist on LWR.

- **`lightning-file-upload` is not supported on LWR sites.** (Note the nuance: Summer '26 lets
  you *upload files up to 10 GB* to an Aura or LWR site — but that is platform file capacity,
  not this base component. Handle uploads with a supported mechanism, and remember the guest
  user cannot use authenticated-only workarounds.)
- Before using any base component on an LWR target, confirm it is supported (the "Standard
  Components for LWR Templates" list); otherwise build with supported primitives or a custom
  component.

---

## 6. Guest / Unauthenticated Context

LWR sites are frequently browsed by users who are **not logged in**:

- The guest user is **read-only at most**, **cannot own records**, and sees only what the guest
  profile + sharing explicitly grant.
- Never assume `@AuraEnabled` data is present — results may be empty or access-denied for
  guests. Render the empty/denied path as a first-class state.
- Keep secrets and privileged operations out of guest-reachable components entirely.

(Site-level guest hardening lives in `dya-lwr-sites`; this is the component-side
discipline.)

---

## 7. Performance Posture

LWR is lean by design:

- Mind bundle size; lazy-load heavy work; do not pull large libraries into a guest-facing page.
- Let LDS / GraphQL own data and caching rather than hand-rolling fetch-and-store.
- Public LWR pages are measured on real-world load and Core Web Vitals — treat performance as a
  requirement.

---

## 8. React / UI Bundles — Open Beta, Do NOT Use in Production

Salesforce Multi-Framework runs external frameworks (starting with React) as **UI Bundles** on
LWR. In v67 this is **open Beta**: scratch orgs and sandboxes only, **no production deploy**.
Build production LWR UIs with LWC; reassess when Multi-Framework reaches GA.

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
| Production LWR UI | LWC (React UI Bundles are open Beta in v67) |

---

## 10. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| Assuming an LWC in Lightning Experience runs on LWR | LEX is the Aura runtime; LWR is a separate target |
| Using a `PageReference` type without checking LWR support | Verify against the LWR CSR reference |
| Hardcoding the site base path | Derive from `<base href>` at runtime |
| `data:` URI for a download | `blob:` URL (LWS blocks `data:` in v67) |
| Reaching for `lightning-file-upload` on an LWR site | Supported upload mechanism; mind the guest user |
| Assuming data is present for a guest user | Handle empty / access-denied as a first-class state |
| Loading third-party JS from arbitrary URLs | Static resource + CSP Trusted Site |
| Building production LWR UI with React UI Bundles | LWC (React UI Bundles are open Beta in v67) |
| Pulling heavy libraries into a guest-facing page | Keep bundles lean; lazy-load |
| API version < 67.0 on new components | `<apiVersion>67.0</apiVersion>` in the `*-meta.xml` |

---

## Summary — The Five Commandments

1. **Runtime first** — decide LEX (Aura) vs LWR vs Lightning Out before you write; they are not
   interchangeable.
2. **No Aura underneath** — verify module and base-component availability against LWR; do not
   assume LEX services exist.
3. **Navigation and security differ** — `lightning/navigation` is a narrower client-side router
   on LWR; LWS (not Locker) with strict CSP, and `data:` URIs are blocked.
4. **Design for the guest** — read-only, no ownership, empty/denied is a normal state.
5. **LWC, not React, for production** — Multi-Framework / UI Bundles is open Beta in v67.
