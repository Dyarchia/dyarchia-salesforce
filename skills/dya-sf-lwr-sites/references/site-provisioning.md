# Creating and Publishing a Site Programmatically

Everything between "no site exists" and "a visitor can reach it": a different set of APIs from
building inside a site.

## The short version

A freshly created site is **not reachable**: `status: UnderConstruction`, only the creating admin as a
member, unpublished Builder pages. Creation, activation and publication are three operations on three
surfaces; only the first is a Connect API call.

```text
create    →  Connect API      POST /connect/communities
activate  →  Metadata API     Network.status: UnderConstruction → Live
publish   →  CLI             sf community publish --name "<Site>"
```

## Creating

```text
POST /services/data/vXX.X/connect/communities
{ "name": "...", "urlPathPrefix": "...", "description": "...", "templateName": "..." }
```

`urlPathPrefix` must be **alphanumeric only** — no hyphens, no spaces.

Discover the template rather than hardcoding it; accepted strings vary by org edition and version:

```text
GET /services/data/vXX.X/connect/communities/templates
→ { "templates": [ { "publisher": "...", "templateName": "..." } ], "total": n }
```

Common names:

| Runtime | Templates |
|---|---|
| LWR | **`Build Your Own (LWR)`**, **`Microsite (LWR)`** |
| Aura | `Customer Service`, `Help Center`, `Customer Account Portal`, `Partner Central`, `Employee Portal`, `Agentforce Employee Center`, `Build Your Own` |

**Never create a `Salesforce Tabs + Visualforce` site.** It is legacy, has no Builder, and cannot
migrate to one.

### Two purpose-built alternatives

**Self-service** — asynchronous; derives the URL path prefix from the site name and takes no
`templateName`:

```text
POST /services/data/vXX.X/connect/self-service/site
{ "siteName": "...", "siteType": "AURA" | "LWR",
  "guestEmbeddedServiceConfigId": "...",     ← required
  "embeddedServiceConfigId": "...",          ← optional
  "enableForGuest": true, "contentDocumentId": "...",
  "brandColors": { … } }

GET /services/data/vXX.X/connect/self-service/site/status/{jobId}
```

`brandColors` entries target `action`, `link`, `border`, `text` or `pageBackground` with RGBA values.

**Partner Relationship Management** — synchronous, returns `{ "networkId": "0DB…" }`, and needs the
`CommonPrmEnabled` feature:

```text
POST /services/data/vXX.X/connect/prm/setup/sites
{ "siteName": "...", "siteUrlPrefix": "...", "siteDesc": "...", "prmTemplate": "..." }
```

## Activating — and why there is no API for it

**`PATCH /connect/communities/<id>` returns 405 METHOD_NOT_ALLOWED.** The resource is GET and HEAD
only; there is no activation endpoint. Activate through the Metadata API:

```bash
sf project retrieve start --metadata "Network:My Site" --target-org <alias>
# edit: <status>UnderConstruction</status>  →  <status>Live</status>
sf project deploy start --metadata "Network:My Site" --target-org <alias>
```

Publishing is separate, with no Connect API either:

```bash
sf community publish --name "My Site" --target-org <alias>
```

## The login path

An Aura employee or customer site serves at the `/s`-style path and logs in at
`…/<prefix>/login` or `…/<prefix>/s/login` — **not** at the bare `…/<prefix>`. A bare prefix that
returns nothing useful does not mean the site is broken.

## The source layout

An LWR site is a set of related metadata types:

```text
digitalExperienceConfigs/{siteName}1.digitalExperienceConfig-meta.xml
digitalExperiences/site/{siteName}1/{siteName}1.digitalExperience-meta.xml
networks/{siteName}.network-meta.xml
sites/{siteName}.site-meta.xml
```

**The `1` suffix** on the config and bundle names is a convention, not a typo; the `Network` and
`CustomSite` files lack it.

Supported LWR template devName: `talon-template-byo` (Build Your Own).

Site content lives under `digitalExperiences/site/{siteName}1/sfdc_cms__*/{contentApiName}/`, and
**each component needs both a `_meta.json` and a `content.json`**. Nine content types:

```text
sfdc_cms__site          sfdc_cms__brandingSet          sfdc_cms__theme
sfdc_cms__appPage       sfdc_cms__languageSettings     sfdc_cms__themeLayout
sfdc_cms__route         sfdc_cms__mobilePublisherConfig
sfdc_cms__view
```

Object pages follow a naming convention: a custom object `Car__c` gets `Car_Detail`, `Car_List` and
`Car_Related_list` views.

## Never reach for FlexiPage tooling

Retrieving, generating or editing a `FlexiPage` on a `DigitalExperienceBundle` site produces
metadata the site ignores.

## Deploying

```bash
sf project deploy start --metadata DigitalExperienceBundle DigitalExperience \
    DigitalExperienceConfig Network CustomSite --target-org <alias>
```

Metadata types are **space-delimited after a single flag**. Never quote or comma-join the group:
`--metadata "DigitalExperienceBundle DigitalExperience"` is read as one nonexistent type name.
