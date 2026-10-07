# B2C Commerce — SCAPI, SLAS, Custom APIs & Composable Storefront

Load from `dya-sf-b2c-commerce` for headless/API development.

## SCAPI Base URL Parameters

- `{shortCode}` — instance short code (e.g. `kv7kzm78`); the 3-char string after the 3rd underscore region of your config.
- `{organizationId}` — e.g. `f_ecom_zzte_053`.
- `{version}` — **`v1`** for everything **except Shopper Baskets**, which is `v1` or `v2` (use `v2` for newer features).
- `{siteId}` — e.g. `RefArchGlobal`.

Most-used API families/names: `product/shopper-products`, `product/shopper-search`, `checkout/shopper-baskets`, `checkout/shopper-orders`, `customer/shopper-customers`, `pricing/shopper-promotions`, `shopper/auth` (SLAS), `shopper/shopper-context`.

## SLAS — the Mandatory Gatekeeper

Public clients hold no secret. Full-stack apps and any BFF must be private clients.

The guest-token call returns `access_token`, `refresh_token`, `usid` and `customer_id`.

Login (public client) uses the **authorization code grant + PKCE**: the app generates `code_verifier`/`code_challenge`, the shopper authenticates (optionally via a third-party IDP / SSO), then the app exchanges the code at `/token` and validates the JWT against the key set.

- Refresh-token rotation has been enforced since Sept 9, 2025. Persist and rotate the latest token, typically on a BFF.
- The JWT changes landed on Apr 28, 2026; `/jwks` serves the public key.

## After Creating a Basket

The create call returns `{ "basketId": "...", ... }`. Then add items, set shipping and billing, and place the order via `shopper-baskets` and `shopper-orders`.

## SDKs

- **commerce-sdk** (Node) and **commerce-sdk-isomorphic** / **@salesforce/commerce-sdk-react** (browser/PWA): typed clients per API family.

```javascript
import { ShopperProducts } from "commerce-sdk-isomorphic";
const clientConfig = { parameters: { clientId, organizationId, shortCode, siteId } };
const products = new ShopperProducts({ ...clientConfig, headers: { authorization: `Bearer ${token}` } });
const product = await products.getProduct({ parameters: { id: "25518823M" } });
```

## Custom APIs (SCAPI) — your own endpoints

Your own REST endpoint under the `custom` family: a Script API script plus an OpenAPI schema in a cartridge.

```
GET https://{shortCode}.api.commercecloud.salesforce.com/custom/loyalty-info/v1/organizations/{org}/customers?c_customerId={id}&siteId={site}&locale={locale}
Authorization: Bearer {token}
```

- Define the contract in an **OpenAPI 3.0** document (paths, params, `securitySchemes: ShopperToken`); implement each `operationId` in a **Script API** script in the cartridge.
- Verify cartridge structure, activate the code version, and assign the cartridge to the site.

## Composable Storefront (PWA Kit + Managed Runtime)

- **PWA Kit** — React storefront; uses SCAPI for products, search, baskets, promotions, inventory, shipping, billing.
- **Managed Runtime (MRT)** — serverless host (autoscaling, eCDN, ~100 environments out of the box, UI/API deploys + rollback). PWA Kit runs as a serverless app on MRT; an SFRA storefront can run alongside (hybrid) talking to the same instance.
- Customize the front end in React + the commerce SDK; the backend via SCAPI hooks and Custom APIs.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Hand-rolling SCAPI calls | commerce-sdk / commerce-sdk-isomorphic |
| Treating SCAPI as a stateful session API | Stateless REST |
