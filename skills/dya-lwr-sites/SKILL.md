---
name: dya-lwr-sites
description: Salesforce Experience Cloud LWR sites Summer '26 (API v67.0) — building production sites on the Lightning Web Runtime: enhanced vs non-enhanced LWR sites, standard components and the Grid, CMS collections, guest-user hardening, SEO, CSP/LWS, partial deployment via DigitalExperienceBundle, and the v67 Experience Cloud additions. Load only when the user explicitly invokes this skill by name (`dya-lwr-sites`); do NOT auto-trigger on generic Experience Cloud, site, or portal questions.
---

# Salesforce Experience Cloud — LWR Sites

You are a Salesforce Experience Cloud expert. This skill covers building **public and
authenticated sites on the Lightning Web Runtime (LWR)** — the modern, LWC-native site type
(vs legacy Aura template sites). For how components behave on the LWR runtime, use
`dya-lwr`; for the components themselves, use `dya-lwc`.

This SKILL.md carries the load-bearing rules. Larger material lives in `references/`:

- `references/guest-and-seo.md` — full guest-user hardening procedure and the SEO setup
  (slugs, sitemaps, robots.txt) for a production LWR site.

---

## Platform Context — Summer '26 / API v67.0

**LWR sites are GA and the recommended site type for new builds.** Hold these:

- **LWR sites are LWC-native** — HTML/CSS/JS through Lightning Web Components, focused on
  performance and developer control. Legacy **Aura template sites** still exist and are not
  this skill; do not migrate one blindly (it is a rebuild).
- **Enhanced vs non-enhanced LWR sites matter.** Enhanced LWR sites (enhanced workspace,
  `DigitalExperienceBundle`) are the forward path and unlock **partial deployment**,
  **expression-based visibility and variations**, a **component-specific Style tab** for custom
  CSS, and **site content search**. CMS collections from enhanced workspaces display **only** in
  enhanced LWR sites; non-enhanced LWR sites can show only object list views in the Grid.
- **LWR sites run Lightning Web Security**, with their **own LWS instance** independent of the
  org setting, and strict CSP.
- **New in v67 for Experience Cloud:** malware scans for Salesforce Files are GA; you can
  upload files **up to 10 GB** to Aura or LWR sites; **AI-assisted Self-Service components** are
  available for Aura/LWR sites; users on public email services can send email from the site;
  Chatter can be turned on in new orgs for Aura/LWR sites.
- **React UI Bundles is open Beta in v67 — DO NOT use in production.** A React-hosted site is a
  thin `appContainer` over a UI Bundle and cannot deploy to production yet. Build with LWC.

Sites deploy as metadata (`DigitalExperienceBundle`, `Network`, `CustomSite`,
`DigitalExperienceConfig`); never hand-edit in production.

---

## 1. Choose the Right Site Type

```
Need                                          Site type
--------------------------------------------  -------------------------------------------
New, performance/SEO-sensitive public site    Enhanced LWR site (LWC)
Content-driven site using enhanced CMS        Enhanced LWR site (required for CMS collections)
Simple list-view-only data display            Non-enhanced LWR site (Grid, list views only)
Existing Aura template site                   Stays Aura — migration is a rebuild, not a flip
React SPA hosted on Salesforce                UI Bundle (open Beta v67 — NOT production yet)
```

Pick **enhanced LWR** for new builds unless there is a reason not to. Aura-to-LWR is a
**rebuild** (components, theme, navigation), not a setting.

---

## 2. Build with Standard Components + the Grid

Compose the page from the **Standard Components for LWR Templates** first; only drop to custom
LWC when the standard set cannot do it.

- **Grid** — shows collections / list views: pick a **data source, layout, and pagination**.
  In an **enhanced** site the data source can be an object list view **or** a CMS collection
  (from an enhanced workspace); in a **non-enhanced** site, **only** object list views.
- Custom LWCs on the site run on the **LWR runtime** — all of `dya-lwr` applies (module
  and base-component availability, LWR navigation, design for the guest). Do not assume a
  component tested only in Lightning Experience works here.

---

## 3. Use the Enhanced-Site Capabilities

On enhanced LWR sites, prefer the platform features over hand-rolled equivalents:

- **Expression-based visibility & variations** — show/hide and vary components by audience or
  data condition declaratively, instead of forking components.
- **Component-specific Style tab** — scope custom CSS to a component rather than dumping global
  CSS.
- **Site content search** — built-in; do not build a custom search where this fits.
- **Partial deployment** — deploy only what changed in the `DigitalExperienceBundle`.

---

## 4. Guest User — Harden It First

A public LWR site is browsed by the **guest user**: unauthenticated, **read-only**, **cannot
own records**. Misconfigured guest access is the #1 Experience Cloud security incident.

- Before activating, **audit the guest user profile**: grant the **minimum** object/field read
  access the site needs, nothing more.
- Expose specific records via **guest user sharing rules** — never relax org-wide defaults for
  the public.
- The guest cannot own records; route any "create" through an Apex service in a controlled
  context (record assigned to a real owner) or behind an authenticated step.
- Every guest-facing component must render a clean **empty / access-denied** state (enforced
  component-side in `dya-lwr`).

> Full guest-user hardening procedure: see `references/guest-and-seo.md`.

---

## 5. SEO — Mandatory for Public Sites

Unlike Lightning Experience, a public LWR site must be crawlable:

- **SEO-friendly URL slugs** (GA) — replace record Ids in URLs for Accounts, Contacts, and
  custom objects.
- **Do not hand-write a custom sitemap** — the platform generates `sitemap.xml`; the guest
  profile's read access scopes what it contains (least-privilege and SEO coverage are linked).
- Maintain `robots.txt` with the paths to all sitemaps for the domain.
- Keep pages lean (`dya-lwr` §7); Core Web Vitals affect ranking.

> Full SEO setup: see `references/guest-and-seo.md`.

---

## 6. Security — CSP and LWS

- The site runs its **own LWS instance**; verify behaviour in the site, not in LEX.
- Register every external endpoint as a **CSP Trusted Site**; load third-party scripts as
  **static resources**, not from arbitrary URLs.
- Lock down head markup, CSP directives, and trusted URLs before go-live — public sites are
  attack surface.

---

## 7. Deployment

LWR sites are metadata: `DigitalExperienceBundle` (enhanced), plus `Network`, `CustomSite`,
`DigitalExperienceConfig`. Source-track them and deploy through CI/CD; on enhanced sites use
**partial deployment** for incremental changes; validate against a sandbox. Activating or
editing a production site by hand is an incident waiting to happen.

---

## 8. Decision Matrix — Quick Reference

| Need | Solution |
|---|---|
| Display object list views | Grid component (any LWR site) |
| Display CMS collections | Grid in an **enhanced** LWR site |
| Show/hide a component by audience/condition | Expression-based visibility (enhanced) |
| Scope custom CSS to one component | Component-specific Style tab (enhanced) |
| Expose specific public records | Guest user sharing rules + least-privilege profile |
| Public "create" action | Apex service in controlled context / authenticated step |
| Readable public URLs | SEO-friendly URL slugs (GA) |
| Crawlable site | Platform `sitemap.xml` + `robots.txt`; no custom sitemap |
| Call an external endpoint | CSP Trusted Site; LWS own instance |
| Incremental release | Partial deployment of the `DigitalExperienceBundle` |
| Custom UI beyond standard components | Custom LWC (apply `dya-lwr`) |

---

## 9. Anti-Patterns — NEVER Do These

| Anti-Pattern | Modern Replacement |
|---|---|
| Broadening org-wide sharing to expose public data | Guest user sharing rules, minimum read access |
| Granting the guest profile broad object/field access | Least-privilege: only what the site renders |
| Record Ids in public URLs | SEO-friendly URL slugs (GA) |
| Hand-written custom sitemap | Platform-generated `sitemap.xml` + guest read scope |
| Forking a component per audience | Expression-based visibility / variations (enhanced) |
| Global CSS dumping ground | Component-specific Style tab (enhanced) |
| Third-party JS from arbitrary URLs | Static resource + CSP Trusted Site |
| Testing a guest site only while logged in | Test as the guest user, in the site's own LWS |
| `lightning-file-upload` for site uploads | Supported mechanism; mind the guest (`dya-lwr`) |
| Flipping an Aura site to LWR as a setting | Plan a rebuild |
| Building a production site as a React UI Bundle | LWC LWR site (UI Bundles are open Beta in v67) |
| Editing/activating a production site by hand | Metadata + CI/CD; partial deployment |

---

## Summary — The Five Commandments

1. **Enhanced LWR for new sites** — LWC-native, fast, SEO-capable; enhanced unlocks CMS
   collections, expression visibility, scoped CSS, content search, partial deploy.
2. **Standard components first, Grid for data** — custom LWC only when needed (then
   `dya-lwr`).
3. **Harden the guest first** — least-privilege profile, guest sharing rules, read-only, no
   ownership, clean empty state.
4. **SEO is mandatory** — slugs (GA), platform sitemaps, `robots.txt`, lean pages.
5. **Production means LWC + pipeline** — React UI Bundles are open Beta in v67; deploy sites as
   metadata, never by hand.
