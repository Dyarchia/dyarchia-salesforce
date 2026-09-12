---
name: dya-lwr-sites
description: Salesforce Experience Cloud LWR sites Winter '27 (API v68.0) — building production sites on the Lightning Web Runtime: enhanced vs non-enhanced LWR sites, standard components and the Grid, CMS collections, guest-user hardening, SEO, CSP/LWS, partial deployment via DigitalExperienceBundle, embedded reports and dashboards, and the Experience Delivery discontinuation. Load only when the user explicitly invokes this skill by name (`dya-lwr-sites`); do NOT auto-trigger on generic Experience Cloud, site, or portal questions.
---

# Salesforce Experience Cloud — LWR Sites

This skill covers **public and authenticated sites on the Lightning Web Runtime**, the modern
LWC-native site type, as opposed to legacy Aura template sites. For how components behave on the LWR
runtime use `dya-lwr`; for the components themselves, `dya-lwc`. Follow every rule below.

References:

- `references/shared/sharing-and-access.md` — the guest user and the access model a public site
  runs under. **Read this before hardening anything.**
- `references/shared/platform-deltas.md` — the release-coupled facts behind the rules here.
- `references/site-provisioning.md` — creating a site through the Connect API, the source layout,
  and the activate-then-publish sequence a new site needs before anyone can reach it.
- `references/guest-and-seo.md` — the full guest-user hardening procedure and the SEO setup
  (slugs, sitemaps, robots.txt) for a production LWR site.

Designing the guest profile and its sharing rules is `dya-permissions`.

---

## Platform Context — Winter '27 / API v68.0

**LWR sites are GA and the recommended site type for new builds.** Hold these:

- **LWR sites are LWC-native** — HTML/CSS/JS through Lightning Web Components, built for
  performance and developer control. Legacy **Aura template sites** still exist and are not this
  skill. Never migrate one blindly: it is a rebuild.
- **Enhanced vs non-enhanced LWR sites matter.** Enhanced sites (enhanced workspace,
  `DigitalExperienceBundle`) are the forward path and unlock **partial deployment**,
  **expression-based visibility and variations**, a **component-specific Style tab** for custom CSS,
  and **site content search**. CMS collections from enhanced workspaces display **only** in enhanced
  LWR sites; a non-enhanced site shows only object list views in the Grid.
- **LWR sites run Lightning Web Security**, with their **own LWS instance** independent of the org
  setting, and strict CSP.

Winter '27 changes two things here:

- **Embedded reports and dashboards come to LWR sites (Beta)** — charts and tables with conditional
  formatting and inline record editing, previously Aura-template-only. That removes one of the last
  genuine reasons to stay on Aura, so raise it whenever someone justifies an Aura site by reporting.
  Beta: not production, and not a delivery you can plan around yet.
- **Experience Delivery (Beta) is discontinued**, with **auto-migration on republish through October
  2026**. Republishing is the migration, but confirm what the site looks like afterwards rather than
  assuming it was transparent.

Standing facts:

- Malware scanning for Salesforce Files is GA; files up to **10 GB** upload to Aura or LWR sites;
  AI-assisted Self-Service components are available; users on public email services can send email
  from a site; Chatter can be enabled in new orgs for Aura and LWR sites.
- **UI Bundles now cover React and Angular and package as 2GP** (managed or unlocked, namespace
  supported, AppExchange-distributable). A framework-hosted site is a thin `appContainer` over the
  bundle. It is Hyperforce-only and needs the Dev Hub packaging toggle; confirm the availability
  status for the target org before planning production on it. See `dya-lwr` §8.

Sites deploy as metadata — `DigitalExperienceBundle`, `Network`, `CustomSite`,
`DigitalExperienceConfig` — never hand-edited in production.

---

## 1. Choose the Right Site Type

```
Need                                          Site type
--------------------------------------------  -------------------------------------------
New, performance/SEO-sensitive public site    Enhanced LWR site (LWC)
Content-driven site using enhanced CMS        Enhanced LWR site (required for CMS collections)
Simple list-view-only data display            Non-enhanced LWR site (Grid, list views only)
Existing Aura template site                   Stays Aura — migration is a rebuild, not a flip
React or Angular SPA hosted on Salesforce     UI Bundle (Hyperforce only; packages as 2GP)
```

Pick **enhanced LWR** for new builds unless there is a reason not to. Aura-to-LWR is a **rebuild** of
components, theme and navigation, not a setting.

---

## 2. Build with Standard Components + the Grid

Compose the page from the **Standard Components for LWR Templates** first, and drop to custom LWC
only where the standard set cannot do it.

- **Grid** — displays collections and list views: pick a **data source, layout and pagination**. In
  an **enhanced** site the data source is an object list view **or** a CMS collection from an
  enhanced workspace; in a **non-enhanced** site, **only** object list views.
- Custom LWCs on the site run on the **LWR runtime**, so all of `dya-lwr` applies: module and
  base-component availability, LWR navigation, designing for the guest. A component tested only in
  Lightning Experience is not known to work here.

---

## 3. Use the Enhanced-Site Capabilities

On enhanced LWR sites, take the platform feature over the hand-rolled equivalent:

- **Expression-based visibility & variations** — show, hide and vary components by audience or data
  condition declaratively, instead of forking components.
- **Component-specific Style tab** — scope custom CSS to a component rather than dumping global CSS.
- **Site content search** — built in; do not build a custom search where this fits.
- **Partial deployment** — deploy only what changed in the `DigitalExperienceBundle`.

---

## 4. Guest User — Harden It First

A public LWR site is browsed by the **guest user**: unauthenticated, **read-only**, **cannot own
records**. Misconfigured guest access is the #1 Experience Cloud security incident.

- **Audit the guest user profile before activating**: the **minimum** object and field read access
  the site needs, nothing more.
- Expose specific records through **guest user sharing rules**. Never relax org-wide defaults for
  the public.
- The guest cannot own records, so route any "create" through an Apex service in a controlled
  context that assigns a real owner, or behind an authenticated step.
- Every guest-facing component renders a clean **empty / access-denied** state, enforced
  component-side in `dya-lwr`.

> Full guest-user hardening procedure: see `references/guest-and-seo.md`.

---

## 5. SEO — Mandatory for Public Sites

Unlike Lightning Experience, a public LWR site must be crawlable:

- **SEO-friendly URL slugs** (GA) replace record Ids in URLs for Accounts, Contacts and custom
  objects.
- **Never hand-write a custom sitemap.** The platform generates `sitemap.xml`, and the guest
  profile's read access scopes what it contains — least-privilege and SEO coverage are linked.
- Maintain `robots.txt` with the paths to every sitemap for the domain.
- Keep pages lean (`dya-lwr` §7); Core Web Vitals affect ranking.

> Full SEO setup: see `references/guest-and-seo.md`.

---

## 6. Security — CSP and LWS

- The site runs its **own LWS instance**. Verify behaviour in the site, not in LEX.
- Register every external endpoint as a **CSP Trusted Site**, and load third-party scripts as
  **static resources** rather than from arbitrary URLs.
- Lock down head markup, CSP directives and trusted URLs before go-live. A public site is attack
  surface.

---

## 7. Deployment

LWR sites are metadata: `DigitalExperienceBundle` (enhanced), plus `Network`, `CustomSite` and
`DigitalExperienceConfig`. Source-track them, deploy through CI/CD, use **partial deployment** for
incremental changes on enhanced sites, and validate against a sandbox. Activating or editing a
production site by hand is an incident waiting to happen.

Two things to internalise before the first deploy:

- **A newer LWR site abstracts FlexiPage away entirely.** Never reach for FlexiPage tooling —
  retrieving, generating or editing one — on a `DigitalExperienceBundle` site. It is the reflex for
  "Lightning page" and it silently does nothing here.
- **A page needs both a `route` and a `view`** under `digitalExperiences/site/<name>1/sfdc_cms__*/`,
  each with its own `_meta.json` and `content.json`. One without the other does not resolve.

> The full source layout, creating a site through the Connect API, and the activate-then-publish
> sequence: `references/site-provisioning.md`.

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
| Staying on an Aura template site because reporting needed it | Embedded reports and dashboards on LWR (Beta) close that gap |
| Leaving a site on Experience Delivery (Beta) | It is discontinued; republish to auto-migrate before October 2026 |
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
| Planning a UI Bundle site without checking Hyperforce and the packaging toggle | Verify both first; LWC LWR site otherwise |
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
5. **Production means a pipeline** — deploy sites as metadata, never by hand, whether the UI is
   LWC or a UI Bundle.
