# B2C Commerce — SCAPI, SLAS, Custom APIs & Composable Storefront

Load from `decimatio-b2c-commerce` for headless/API development. **OCAPI is deprecated as of April 2026** (2 years security-only, no new features); all new work uses SCAPI.

## SCAPI Base URL & Request Formation

```
https://{shortCode}.api.commercecloud.salesforce.com/{apiFamily}/{apiName}/{version}/organizations/{organizationId}/{resource}?siteId={siteId}
```

- `{shortCode}` — instance short code (e.g. `kv7kzm78`); it's the 3-char string after the 3rd underscore region of your config.
- `{organizationId}` — e.g. `f_ecom_zzte_053`.
- `{version}` — **`v1`** for everything **except Shopper Baskets**, which is `v1` or `v2` (use `v2` for newer features).
- `{siteId}` — e.g. `RefArchGlobal`.

Real product fetch:

```
GET https://kv7kzm78.api.commercecloud.salesforce.com/product/shopper-products/v1/organizations/f_ecom_zzte_053/products/25518823M?siteId=RefArchGlobal
Authorization: Bearer {slas_access_token}
```

API families/names you'll use most: `product/shopper-products`, `product/shopper-search`, `checkout/shopper-baskets`, `checkout/shopper-orders`, `customer/shopper-customers`, `pricing/shopper-promotions`, `shopper/auth` (SLAS), `shopper/shopper-context`.

## SLAS — the Mandatory Gatekeeper

Shopper APIs require a SLAS token. SLAS uses OAuth 2.1 grant types. **Public client** = browser/PWA (PKCE, no secret). **Private client** = server/BFF that can store a secret (full-stack apps and any BFF must be private clients).

Guest token (private client, `client_credentials`, Basic auth header = `base64(clientId:clientSecret)`):

```bash
curl "$BASE/shopper/auth/v1/organizations/$ORG/oauth2/token" \
  -su "$SLAS_CLIENT_ID:$SLAS_CLIENT_SECRET" \
  -d 'grant_type=client_credentials'
# → { "access_token": "...", "refresh_token": "...", "usid": "...", "customer_id": "..." }
```

Login (public client) uses the **authorization code grant + PKCE**: the app generates `code_verifier`/`code_challenge`, the shopper authenticates (optionally via a third-party IDP / SSO), and the app exchanges the code at `/token` and validates the JWT via the key set.

Rules:
- **Refresh-token reuse is prohibited for public clients** (OAuth 2.1): each `/token` call returns a new refresh token; reusing an old one → `400 invalid refresh token` (enforced since Sept 9, 2025). Persist and rotate the latest token (typically on a BFF).
- A SLAS access token works on **any** Shopper API endpoint and can bridge to legacy OCAPI hooks during migration.
- **Apr 28, 2026 JWT changes:** `ssc` claim (short code), CRM claim on the access token, richer `id_token` (email/name, tenant-key signed, `typ: JWT`), `/jwks` endpoint to fetch the public key.

## Create a Basket (full headless flow start)

```bash
# 1) guest token (above) → $TOKEN
# 2) create basket
curl "$BASE/checkout/shopper-baskets/v1/organizations/$ORG/baskets?siteId=$SITE" \
  -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{ "productItems": [{ "productId": "682875090845M", "quantity": 1 }] }'
# → { "basketId": "...", ... }
# subsequent: add items, set shipping/billing, place order via shopper-baskets / shopper-orders
```

## SDKs

- **commerce-sdk** (Node) and **commerce-sdk-isomorphic** / **@salesforce/commerce-sdk-react** (browser/PWA): typed clients per API family.

```javascript
import { ShopperProducts } from "commerce-sdk-isomorphic";
const clientConfig = { parameters: { clientId, organizationId, shortCode, siteId } };
const products = new ShopperProducts({ ...clientConfig, headers: { authorization: `Bearer ${token}` } });
const product = await products.getProduct({ parameters: { id: "25518823M" } });
```

## Custom APIs (SCAPI) — your own endpoints

Expose your own RESTful endpoint under the `custom` family, implemented by a Script API script + an OpenAPI schema in a cartridge.

```
GET https://{shortCode}.api.commercecloud.salesforce.com/custom/loyalty-info/v1/organizations/{org}/customers?c_customerId={id}&siteId={site}&locale={locale}
Authorization: Bearer {token}
```

- Define the contract in an **OpenAPI 3.0** document (paths, params, `securitySchemes: ShopperToken`), and implement each `operationId` in a **Script API** script file in the cartridge. Verify cartridge structure, activate the code version, and assign the cartridge to the site.

## Shopper Context (personalization without custom code)

Instead of an OCAPI "Modify Response" hook to personalize price/promotions, send shopper attributes (e.g. Member Level, Region) to the **Shopper Context API**; SCAPI returns context-appropriate prices/promotions natively while preserving **object-level caching**.

## Composable Storefront (PWA Kit + Managed Runtime)

- **PWA Kit** — React storefront; uses SCAPI for products, search, baskets, promotions, inventory, shipping, billing.
- **Managed Runtime (MRT)** — serverless host (autoscaling, eCDN, ~100 environments out of the box, UI/API deploys + rollback). PWA Kit runs as a serverless app on MRT; an SFRA storefront can run alongside (hybrid) talking to the same instance.
- Customize in React + the commerce SDK; backend customization via SCAPI hooks and Custom APIs.

## SCAPI vs OCAPI

| | SCAPI | OCAPI |
|---|---|---|
| Status | Modern, mandatory for new work | Deprecated Apr 2026 (2 yrs security-only) |
| Caching | Object-level | Full-response |
| Auth | SLAS (OAuth 2.1) | OAuth/JWT |
| Personalized price | Shopper Context API | Modify Response hook |
| Custom endpoints | Custom APIs | — |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| New build on OCAPI | SCAPI |
| Reusing a SLAS refresh token (public client) | One-time use; rotate to the new token |
| Private-client secret in the browser | Server-side BFF |
| Response-modifying hook for personalized price | Shopper Context API |
| Wrong version on Shopper Baskets | `v1` or `v2` (v1 for everything else) |
| Hand-rolling SCAPI calls | commerce-sdk / commerce-sdk-isomorphic |
| Treating SCAPI as a stateful session API | Stateless REST |
