# LWR Sites — Guest-User Hardening & SEO Setup

Reference for SKILL.md §2–§3. Load when configuring a production public LWR site.

## Guest-user hardening — order of operations

The guest user is an unauthenticated, read-only identity that cannot own records. Configure it
with least privilege **before** activating the site.

1. **Guest user profile** — grant read access only to the objects and fields the site actually
   renders. Remove everything else. No create/edit/delete; the guest cannot own records anyway.
2. **Org-wide defaults** — leave them as restrictive as the rest of the org needs. Never relax
   an org-wide default to expose data to the public.
3. **Guest user sharing rules** — expose the specific records the public should see through
   guest sharing rules scoped to criteria, not through broad access. This is the only safe way
   to widen guest visibility.
4. **"Let Guest Users See Other Members"** — keep off unless the site genuinely requires it.
5. **Create flows** — the guest cannot own records. Route any public "submit"/"create" through
   an Apex service that runs in a controlled context (with the record assigned to a real owner),
   or behind an authenticated step. Validate and rate-limit such entry points.
6. **Verify before activation** — review the guest profile's object read access; it directly
   determines what `sitemap.xml` can contain and what the public can reach.

## Component-side expectations

Guest-facing components must treat empty / access-denied results as a normal state and render
cleanly — never assume data is present (see `decimatio-lwr` §6).

## SEO setup

- **URL slugs (GA)** — enable SEO-friendly slugs to replace record Ids in URLs for Accounts,
  Contacts, and custom objects. Readable URLs index better and drive organic traffic.
- **Sitemaps** — the platform generates `sitemap.xml`; do **not** author a custom sitemap for
  an LWR (or Aura) site. The guest user profile's read access scopes what the sitemap includes,
  so least-privilege and SEO coverage are linked: only what the guest can read gets indexed.
- **robots.txt** — include the paths to all sitemaps for the domain.
- **Performance** — keep pages lean (see `decimatio-lwr` §7); Core Web Vitals influence ranking
  for public sites.

## Pre-go-live checklist

1. Guest profile: least-privilege read access reviewed and trimmed.
2. Guest sharing rules: only the intended records exposed; org-wide defaults untouched.
3. Slugs enabled; record Ids gone from public URLs.
4. `robots.txt` references the generated sitemaps; no custom sitemap.
5. CSP Trusted Sites registered; third-party JS shipped as static resources.
6. Tested as the guest user, in the site's own LWS instance — not only while logged in.
