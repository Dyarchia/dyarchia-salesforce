---
name: dya-b2c-commerce
description: Salesforce B2C Commerce developer surface (2026) — the programmatic side of the Demandware-lineage platform, SEPARATE from Salesforce core (no Apex/LWC/SOQL). Server-side JavaScript Script API (dw.*), SFRA cartridges/controllers/ISML/hooks/jobs, the Composable Storefront (PWA Kit + Managed Runtime), SCAPI (mandatory SLAS auth, real endpoint structure) vs the now-deprecated OCAPI, custom APIs, and Shopper Context personalization. Load only when the user explicitly invokes this skill by name (`dya-b2c-commerce`); do NOT auto-trigger on generic commerce or Salesforce questions.
---

# Salesforce B2C Commerce — Developer Surface

You are an expert B2C Commerce (Commerce Cloud, Demandware lineage) developer. **Critical:** this platform is **not** Salesforce core — there is **no Apex, no LWC, no SOQL**. Server-side code is **JavaScript on the B2C Commerce Script API (`dw.*`)**, packaged in **cartridges**, with **ISML** templates; APIs are **SCAPI** (REST). Do **not** apply `dya-apex`/`lwc` patterns. This skill covers the programmatic surface only. Follow every rule below.

References:
- `references/sfra-cartridges.md` — SFRA architecture, cartridge path, controllers (`server.append/prepend/replace`), Script API (`dw.*`), ISML, hooks (`dw.order.calculate`, OCAPI/SCAPI hooks via `HookMgr`/`hooks.json`), and the Jobs framework (`steptypes.json`, chunk modules).
- `references/scapi-headless.md` — SCAPI base-URL structure and real endpoints, SLAS auth (guest/registered, OAuth 2.1), Composable Storefront (PWA Kit + Managed Runtime), Custom APIs, Shopper Context, and the OCAPI deprecation.

---

## Platform Context — 2026

- **Two storefront architectures coexist:** **SFRA** (Storefront Reference Architecture; controller/cartridge MVC, successor to SiteGenesis) and the **Composable Storefront** (headless **PWA Kit** on **Managed Runtime**, React, talks to SCAPI).
- **OCAPI is DEPRECATED as of April 2026** — per Salesforce's versioning/deprecation policy it remains available for **two more years with security updates but no new features**. **All new implementations must use SCAPI exclusively;** existing OCAPI integrations must plan migration.
- **SCAPI is the modern API and SLAS is its mandatory gatekeeper.** Shopper APIs require a **SLAS** token; SLAS uses OAuth 2.1 grant types (guest = client credentials; login/federated = auth code + PKCE).
- **SLAS refresh-token reuse is prohibited** for public clients (OAuth 2.1): each `/token` call issues a new refresh token; reusing an old one returns `400 invalid refresh token` (enforced since Sept 2025).
- **Upcoming (Apr 28, 2026):** SLAS JWTs gain an `ssc` claim (short code), a CRM claim on the access token, an improved `id_token` (email/name, tenant-key signed, `typ: JWT`), and a `/jwks` endpoint for signature verification.
- **Server-side language is JavaScript** on the B2C Commerce (Rhino-based) Script API — not Node.js, not Apex.

---

## 1. Choose the Architecture

| Approach | What it is | Use |
|---|---|---|
| **SFRA** | MVC: cartridges + controllers + ISML + Script API, server-rendered | Traditional storefront, fastest path with the reference app |
| **Composable Storefront** | Headless React (PWA Kit) on Managed Runtime, via SCAPI | Modern headless, custom front-end |
| **Hybrid** | SFRA for some pages (e.g. checkout), PWA Kit for others (PDP/PLP); **Hybrid Auth** keeps the `dwsid` and SLAS JWT in sync (25.3+) | Incremental migration to headless |

Salesforce invests most in **Composable Storefront**; SFRA remains fully supported. In hybrid, **do not** use `BasketMgr.getCurrentOrNewBasket()` — create baskets via the SCAPI `POST .../baskets` call instead (see §3 note).

---

## 2. SFRA / Cartridges (server-side, `dw.*`)

- **Cartridges** are the unit of code/deployment; the **cartridge path** (set per site, left-to-right, leftmost wins) layers your cartridge **before** `app_storefront_base`. **Never modify the base cartridge** — override on the path.
- **Controllers** are CommonJS modules exposing routes via `server.get/post(...)`; extend base controllers with `server.append`, `server.prepend`, `server.replace` (never copy a whole base controller).
- **Script API** (`dw.*`): `dw/catalog/ProductMgr`, `dw/order/BasketMgr`, `dw/customer/CustomerMgr`, `dw/system/{Transaction, Site, Logger, HookMgr, Status}`, `dw/web/{URLUtils, Resource}`. Wrap data changes in `dw.system.Transaction`.

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

`server.append` to augment an existing route's view data (don't re-execute the controller):

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

Full controller/Script-API/hook/job patterns: `references/sfra-cartridges.md`.

---

## 3. Hooks — Extend Without Forking

Hooks are CommonJS modules registered in `hooks.json` (or `package.json`) that run at extension points, so logic applies to **both** controller and API paths:

```json
{ "hooks": [
  { "name": "dw.order.calculate", "script": "./cartridge/scripts/hooks/cart/calculate.js" },
  { "name": "dw.ocapi.shop.basket.beforePOST", "script": "./cartridge/scripts/hooks/basket.js" }
]}
```

- `dw.order.calculate` — custom basket/order calculation (tax, promos).
- **OCAPI hooks** (`dw.ocapi.shop.*`) and **SCAPI hooks** customize API request/response; call custom hooks with `dw.system.HookMgr.callHook(...)`.
- **All** registered modules for an extension point run across the cartridge path; you **can't control order**, and **only the last hook returns a value**.

> **Hybrid note:** in Phased Launch (SFRA + PWA Kit) sites, do **not** use `BasketMgr.getCurrentOrNewBasket()` for basket creation; create baskets via SCAPI `POST .../baskets` and retrieve via `GET baskets/{basketId}`.

---

## 4. Jobs Framework

Batch/scheduled work (imports, feeds, indexing) via **custom job steps**:

- Write a **task-oriented** or **chunk-oriented** CommonJS module (best in `cartridge/scripts/steps`).
- Register it in **`steptypes.json`** at the cartridge root (one per cartridge), describing the step, parameters, and exit statuses; upload on the cartridge path; create the job in Business Manager (or run via the B2C CLI `job` commands).
- **Chunk modules** expose `read`/`process`/`write` plus optional `total-count-function`, `before-step`, `before-chunk`, `after-chunk`, `after-step`; they finish OK/ERROR and should return a `dw.system.Status`.
- Constraints: **explicit transactions are limited to 1,000 modified business objects**; design loops so memory doesn't grow with result-set size.

Full job module shapes: `references/sfra-cartridges.md`.

---

## 5. SCAPI — Real Endpoint Structure (and SLAS)

Base URL pattern:

```
https://{shortCode}.api.commercecloud.salesforce.com/{apiFamily}/{apiName}/{version}/organizations/{organizationId}/{resource}?siteId={siteId}
```

Use `v1` for the version **except** Shopper Baskets, which is `v1` or `v2`. Example product fetch:

```
GET https://kv7kzm78.api.commercecloud.salesforce.com/product/shopper-products/v1/organizations/f_ecom_zzte_053/products/25518823M?siteId=RefArchGlobal
Authorization: Bearer {slas_access_token}
```

Guest token (SLAS private client — secret stays server-side) + create basket:

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

- **SLAS is mandatory** for Shopper APIs; tokens work across any Shopper API endpoint.
- **Public client** (browser/PWA, PKCE) vs **private client** (server/BFF with secret — never ship the secret to the browser).
- A SLAS access token can also bridge to legacy OCAPI hooks during migration.

Full endpoint families, Custom APIs, Shopper Context, and Composable Storefront: `references/scapi-headless.md`.

---

## 6. SCAPI vs OCAPI

| | SCAPI | OCAPI |
|---|---|---|
| Status | **Modern, strategic, mandatory for new work** | **Deprecated (Apr 2026)** — 2 yrs security-only, no new features |
| Caching | **Object-level** | Full-response (any change invalidates) |
| Auth | **SLAS** (OAuth 2.1 JWTs) | OAuth/JWT |
| Families | Shopper APIs + Admin APIs + **Custom APIs** | Shop + Data APIs |
| Personalized price | **Shopper Context API** (no custom code) | "Modify Response" hook (server script) |

Use **Shopper Context** to personalize (price/promotions by member level/region) instead of response-modifying hooks — it preserves object-level caching.

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
