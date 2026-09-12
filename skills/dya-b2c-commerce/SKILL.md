---
name: dya-b2c-commerce
description: Salesforce B2C Commerce developer surface (2026) — the programmatic side of the Demandware-lineage platform, SEPARATE from Salesforce core (no Apex/LWC/SOQL). Server-side JavaScript Script API (dw.*), SFRA cartridges/controllers/ISML/hooks/jobs, the Composable Storefront (PWA Kit + Managed Runtime), SCAPI (mandatory SLAS auth, real endpoint structure) vs the now-deprecated OCAPI, custom APIs, and Shopper Context personalization. Load only when the user explicitly invokes this skill by name (`dya-b2c-commerce`); do NOT auto-trigger on generic commerce or Salesforce questions.
---

# Salesforce B2C Commerce — Developer Surface

You are an expert B2C Commerce (Commerce Cloud, Demandware lineage) developer. **Critical:** this
platform is **not** Salesforce core — there is **no Apex, no LWC, no SOQL**. Server-side code is
**JavaScript on the B2C Commerce Script API (`dw.*`)**, packaged in **cartridges**, with **ISML**
templates, and the APIs are **SCAPI** (REST). Never apply `dya-apex` or `dya-lwc` patterns here. This
skill covers the programmatic surface only. Follow every rule below.

References:
- `references/sfra-cartridges.md` — SFRA architecture, cartridge path, controllers (`server.append/prepend/replace`), Script API (`dw.*`), ISML, hooks (`dw.order.calculate`, OCAPI/SCAPI hooks via `HookMgr`/`hooks.json`), and the Jobs framework (`steptypes.json`, chunk modules).
- `references/scapi-headless.md` — SCAPI base-URL structure and real endpoints, SLAS auth (guest/registered, OAuth 2.1), Composable Storefront (PWA Kit + Managed Runtime), Custom APIs, Shopper Context, and the OCAPI deprecation.

---

## Platform Context — 2026

- **Two storefront architectures coexist:** **SFRA** (Storefront Reference Architecture — controller
  and cartridge MVC, successor to SiteGenesis) and the **Composable Storefront** (headless **PWA
  Kit** on **Managed Runtime**, React, talking to SCAPI).
- **OCAPI has been deprecated since April 2026.** Under the versioning and deprecation policy it
  stays available with security updates and no new features for two years from then, so roughly April
  2028. **All new implementations use SCAPI exclusively**, and existing OCAPI integrations need a
  migration plan.
- **SCAPI is the modern API and SLAS is its mandatory gatekeeper.** Shopper APIs require a **SLAS**
  token, and SLAS uses OAuth 2.1 grant types: guest is client credentials, login and federated are
  auth code plus PKCE.
- **SLAS refresh-token reuse is prohibited** for public clients under OAuth 2.1. Each `/token` call
  issues a new refresh token, and reusing an old one returns `400 invalid refresh token` — enforced
  since September 2025.
- **SLAS JWTs (since April 2026)** carry an `ssc` claim (short code) and a CRM claim on the access
  token, an improved `id_token` (email and name, tenant-key signed, `typ: JWT`), and a `/jwks`
  endpoint for signature verification. Verify signatures against `/jwks` rather than trusting a token
  because it parsed.
- **The server-side language is JavaScript** on the Rhino-based B2C Commerce Script API — not
  Node.js, not Apex.

---

## 1. Choose the Architecture

| Approach | What it is | Use |
|---|---|---|
| **SFRA** | MVC: cartridges + controllers + ISML + Script API, server-rendered | Traditional storefront, fastest path with the reference app |
| **Composable Storefront** | Headless React (PWA Kit) on Managed Runtime, via SCAPI | Modern headless, custom front-end |
| **Hybrid** | SFRA for some pages (e.g. checkout), PWA Kit for others (PDP/PLP); **Hybrid Auth** keeps the `dwsid` and SLAS JWT in sync (25.3+) | Incremental migration to headless |

Salesforce invests most in the **Composable Storefront**; SFRA remains fully supported. In hybrid,
**never** use `BasketMgr.getCurrentOrNewBasket()` — create baskets through the SCAPI
`POST .../baskets` call instead (§3).

---

## 2. SFRA / Cartridges (server-side, `dw.*`)

- **Cartridges** are the unit of code and deployment. The **cartridge path** is set per site and read
  left to right with the leftmost winning, layering your cartridge **before** `app_storefront_base`.
  **Never modify the base cartridge**; override on the path.
- **Controllers** are CommonJS modules exposing routes via `server.get/post(...)`. Extend base
  controllers with `server.append`, `server.prepend` or `server.replace`, never by copying a whole
  base controller.
- **Script API** (`dw.*`): `dw/catalog/ProductMgr`, `dw/order/BasketMgr`, `dw/customer/CustomerMgr`,
  `dw/system/{Transaction, Site, Logger, HookMgr, Status}`, `dw/web/{URLUtils, Resource}`. Wrap data
  changes in `dw.system.Transaction`.

```javascript
'use strict';
var server = require('server');
var ProductMgr = require('dw/catalog/ProductMgr');

server.get('Show', function (req, res, next) {
    var product = ProductMgr.getProduct(req.querystring.pid);
    if (product) {
        res.render('product/productDetails', { product: product });
    } else {
        res.render('error/notFound');
    }
    next();
});
module.exports = server.exports();
```

`server.append` augments an existing route's view data without re-executing the controller:

```javascript
'use strict';
var server = require('server');
server.extend(module.superModule);
server.append('Show', function (req, res, next) {
    var vd = res.getViewData();
    vd.customFlag = true;
    res.setViewData(vd);
    next();
});
module.exports = server.exports();
```

Full controller, Script API, hook and job patterns: `references/sfra-cartridges.md`.

---

## 3. Hooks — Extend Without Forking

Hooks are CommonJS modules registered in `hooks.json` or `package.json` that run at extension points,
so the logic applies to **both** controller and API paths:

```json
{ "hooks": [
  { "name": "dw.order.calculate", "script": "./cartridge/scripts/hooks/cart/calculate.js" },
  { "name": "dw.ocapi.shop.basket.beforePOST", "script": "./cartridge/scripts/hooks/basket.js" }
]}
```

- `dw.order.calculate` — custom basket and order calculation: tax, promotions.
- **OCAPI hooks** (`dw.ocapi.shop.*`) and **SCAPI hooks** customise API request and response; call
  custom hooks with `dw.system.HookMgr.callHook(...)`.
- **All** registered modules for an extension point run across the cartridge path. You **cannot
  control the order**, and **only the last hook returns a value**.

> **Hybrid note:** on Phased Launch sites (SFRA + PWA Kit), never use
> `BasketMgr.getCurrentOrNewBasket()` for basket creation. Create baskets via SCAPI
> `POST .../baskets` and retrieve with `GET baskets/{basketId}`.

---

## 4. Jobs Framework

Batch and scheduled work — imports, feeds, indexing — runs as **custom job steps**:

- Write a **task-oriented** or **chunk-oriented** CommonJS module, best placed in
  `cartridge/scripts/steps`.
- Register it in **`steptypes.json`** at the cartridge root, one per cartridge, describing the step,
  its parameters and its exit statuses. Upload on the cartridge path and create the job in Business
  Manager, or run it with the B2C CLI `job` commands.
- **Chunk modules** expose `read`, `process` and `write` plus optional `total-count-function`,
  `before-step`, `before-chunk`, `after-chunk` and `after-step`. They finish OK or ERROR and return a
  `dw.system.Status`.
- Constraints: **explicit transactions are limited to 1,000 modified business objects**, and loops
  must be designed so memory does not grow with result-set size.

Full job module shapes: `references/sfra-cartridges.md`.

---

## 5. SCAPI — Real Endpoint Structure (and SLAS)

Base URL pattern:

```
https://{shortCode}.api.commercecloud.salesforce.com/{apiFamily}/{apiName}/{version}/organizations/{organizationId}/{resource}?siteId={siteId}
```

The version is `v1` **except** Shopper Baskets, which is `v1` or `v2`. A product fetch:

```
GET https://kv7kzm78.api.commercecloud.salesforce.com/product/shopper-products/v1/organizations/f_ecom_zzte_053/products/25518823M?siteId=RefArchGlobal
Authorization: Bearer {slas_access_token}
```

Guest token from a SLAS private client — the secret stays server-side — then create a basket:

```bash
# 1) Guest token (client_credentials, Basic auth = base64(clientId:clientSecret))
TOKEN=$(curl "$BASE/shopper/auth/v1/organizations/$ORG/oauth2/token" \
  -su "$SLAS_CLIENT_ID:$SLAS_CLIENT_SECRET" \
  -d 'grant_type=client_credentials' | jq -r '.access_token')

# 2) Create a basket
curl "$BASE/checkout/shopper-baskets/v1/organizations/$ORG/baskets?siteId=$SITE" \
  -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{ "productItems": [{ "productId": "682875090845M", "quantity": 1 }] }'
```

- **SLAS is mandatory** for Shopper APIs, and a token works across any Shopper API endpoint.
- **Public client** means browser or PWA with PKCE; **private client** means a server or BFF holding
  the secret. Never ship the secret to the browser.
- A SLAS access token can bridge to legacy OCAPI hooks during migration.

Full endpoint families, Custom APIs, Shopper Context and Composable Storefront:
`references/scapi-headless.md`.

---

## 6. SCAPI vs OCAPI

| | SCAPI | OCAPI |
|---|---|---|
| Status | **Modern, strategic, mandatory for new work** | **Deprecated (Apr 2026)** — 2 yrs security-only, no new features |
| Caching | **Object-level** | Full-response (any change invalidates) |
| Auth | **SLAS** (OAuth 2.1 JWTs) | OAuth/JWT |
| Families | Shopper APIs + Admin APIs + **Custom APIs** | Shop + Data APIs |
| Personalized price | **Shopper Context API** (no custom code) | "Modify Response" hook (server script) |

Personalise price and promotions by member level or region with **Shopper Context** rather than
response-modifying hooks: it preserves object-level caching.

---

## 7. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| Server-rendered storefront | SFRA (cartridges + controllers + ISML) |
| Headless React storefront | Composable Storefront (PWA Kit + MRT) |
| Incremental headless migration | Hybrid + Hybrid Auth |
| Read product data (headless) | SCAPI `product/shopper-products` + SLAS |
| Cart/checkout (headless) | SCAPI `checkout/shopper-baskets` (v1/v2) |
| Your own backend endpoint | SCAPI **Custom API** (`/custom/{api}/v1/...`) |
| Customize order/pricing lifecycle | Hook (`dw.order.calculate`) |
| Customize API request/response | OCAPI/SCAPI hook via `HookMgr` |
| Batch import/feed/index | Jobs framework (`steptypes.json` + chunk module) |
| Shopper auth (headless) | SLAS (guest = client_credentials; login = code+PKCE) |
| Personalized price without breaking cache | Shopper Context API |
| Any new integration | SCAPI (never OCAPI) |

---

## 8. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Applying Apex/LWC/SOQL thinking | JS cartridges + `dw.*` Script API + SCAPI — different platform |
| New build on OCAPI | SCAPI (deprecated Apr 2026) |
| Modifying `app_storefront_base` | Override via cartridge path |
| Copying a base controller to tweak it | `server.append/prepend/replace` |
| `getCurrentOrNewBasket()` in a hybrid site | SCAPI `POST .../baskets` |
| Reusing a SLAS refresh token (public client) | One-time use; use the new token each `/token` call |
| SLAS private-client secret in the browser | Keep on a server-side BFF |
| Response-modifying hook for personalized price | Shopper Context API |
| Business logic in ISML templates | Logic in controllers/Script API; ISML renders |
| Row-by-row job over a huge feed | Chunk-oriented step; ≤1,000 objects per transaction |
| Relying on hook execution order | Order is not guaranteed; only the last hook returns a value |

---

## Summary — The Five Commandments

1. **Not Salesforce core** — server-side JavaScript, `dw.*` Script API, cartridges, ISML, SCAPI; no Apex/LWC/SOQL.
2. **SCAPI only for new work; OCAPI is deprecated (Apr 2026)** — SLAS is the mandatory gatekeeper, refresh tokens are one-time-use.
3. **Extend by layering, not forking** — cartridge-path overrides, `server.append`, and hooks; never touch the base cartridge.
4. **Know the real endpoint shape** — `{shortCode}.api.commercecloud.salesforce.com/{family}/{api}/{version}/organizations/{org}/{resource}?siteId=`; `v1` except Shopper Baskets (`v1/v2`).
5. **Secrets server-side, cache deliberately, personalize with Shopper Context** — private SLAS clients on a BFF; chunk jobs ≤1,000 objects/transaction.
