# Creating and Publishing a Site Programmatically

Everything between "no site exists" and "a visitor can reach it". The skill body covers building
inside a site; this file covers bringing one into existence, which is a different set of APIs and has
a step people consistently miss.

## The short version

A freshly created site is **not reachable**. It comes up with `status: UnderConstruction`, only the
creating admin as a member, and unpublished Builder pages. Creation, activation and publication are
three different operations on three different surfaces, and only the first is a Connect API call.

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

Discover the template rather than hardcoding it, because the accepted strings vary by org edition and
version:

```text
GET /services/data/vXX.X/connect/communities/templates
→ { "templates": [ { "publisher": "...", "templateName": "..." } ], "total": n }
```

Names you will commonly see:

| Runtime | Templates |
|---|---|
| LWR | **`Build Your Own (LWR)`**, **`Microsite (LWR)`** |
| Aura | `Customer Service`, `Help Center`, `Customer Account Portal`, `Partner Central`, `Employee Portal`, `Agentforce Employee Center`, `Build Your Own` |

**Never create a `Salesforce Tabs + Visualforce` site.** It is legacy, has no Builder, and cannot be
migrated to one.

### Two purpose-built alternatives

**Self-service** — asynchronous, and it sets the URL path prefix itself from the site name, so it
takes no `templateName`:

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
only. Looking for the activation endpoint is a detour; there isn't one.

Activation goes through the Metadata API:

```bash
sf project retrieve start --metadata "Network:My Site" --target-org <alias>
# edit: <status>UnderConstruction</status>  →  <status>Live</status>
sf project deploy start --metadata "Network:My Site" --target-org <alias>
```

Publishing is separate again, and there is no Connect API for it either:

```bash
sf community publish --name "My Site" --target-org <alias>
```

## The login-path trap

An Aura employee or customer site serves at the `/s`-style path and logs in at
`…/<prefix>/login` or `…/<prefix>/s/login` — **not** at the bare `…/<prefix>`.

Hitting the bare prefix and getting nothing useful is the single commonest "the site is broken"
report, and the site is fine.

## The source layout

An LWR site is a set of related metadata types, and knowing the shape saves guessing at a retrieve:

```text
digitalExperienceConfigs/{siteName}1.digitalExperienceConfig-meta.xml
digitalExperiences/site/{siteName}1/{siteName}1.digitalExperience-meta.xml
networks/{siteName}.network-meta.xml
sites/{siteName}.site-meta.xml
```

**Note the `1` suffix** on the config and bundle names — it is a convention, not a typo, and it is
absent from the `Network` and `CustomSite` files.

Supported LWR template devName: `talon-template-byo` (Build Your Own).

Site content lives under `digitalExperiences/site/{siteName}1/sfdc_cms__*/{contentApiName}/`, and
**each component needs both a `_meta.json` and a `content.json`**. Nine content types:

```text
sfdc_cms__site          sfdc_cms__brandingSet          sfdc_cms__theme
sfdc_cms__appPage       sfdc_cms__languageSettings     sfdc_cms__themeLayout
sfdc_cms__route         sfdc_cms__mobilePublisherConfig
sfdc_cms__view
```

**Creating a page requires both a `route` and a `view`.** One without the other produces a page that
does not resolve.

Object pages follow a naming convention: a custom object `Car__c` gets `Car_Detail`, `Car_List` and
`Car_Related_list` views.

## Never reach for FlexiPage tooling

**A newer LWR site with a `DigitalExperienceBundle` abstracts FlexiPage away entirely.** Any
FlexiPage-shaped instinct — retrieving `FlexiPage`, generating one, editing one — is wrong here and
produces metadata the site ignores. This is worth stating because FlexiPage is the reflex for
"Lightning page" and it silently does nothing on an LWR site.

## Deploying

```bash
sf project deploy start --metadata DigitalExperienceBundle DigitalExperience \
    DigitalExperienceConfig Network CustomSite --target-org <alias>
```

Metadata types are **space-delimited after a single flag**. Never quote the group and never
comma-join it: `--metadata "DigitalExperienceBundle DigitalExperience"` is read as one nonexistent
type name.
