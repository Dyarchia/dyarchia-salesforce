# B2B/D2C Commerce — ConnectApi Commerce, Entitlements & Storefront LWC (Winter '27 / API v68.0)

Load from `dya-sf-b2b-commerce`. The `ConnectApi.CommerceCart` Apex API, the buyer-group/entitlement model that governs visibility, and Storefront LWC. Confirm exact method overloads against the Apex Reference for your API version.

## ConnectApi.CommerceCart

`ConnectApi.CommerceCart` (static methods) covers get/create/update/calculate/delete cart, get cart items, and add/update/delete cart item.

```apex
// Add an item to the active cart
ConnectApi.CartItemInput input = new ConnectApi.CartItemInput();
input.productId = '01t...';
input.quantity  = '2';                       // quantity is a String
input.type      = ConnectApi.CartItemType.PRODUCT;

ConnectApi.CartItem item =
    ConnectApi.CommerceCart.addItemToCart(webStoreId, effectiveAccountId, 'active', input);
```

Parameters (overloads vary by version — verify):
- `webStoreId` — the WebStore Id.
- `effectiveAccountId` — the buyer **account** context (must be a buyer account entitled to the product).
- `activeCartOrId` — `'active'` or a specific cart Id.

Other operations: `getCartSummary`, `getCartItems`, `updateCartItem`, `deleteCartItem`, `createCart`, `deleteCart`, `calculateCart` — names per the `CommerceCart` reference. Related Connect classes cover checkout, orders, products, promotions, wishlists and search.

## Entitlements — why a buyer can/can't see a product

> `ConnectApi.ConnectApiException: Could not add cart item because: You can't view 'ProductId'` — even though the user has access to the product record.

Product visibility is governed by:
1. The buyer **account** is assigned to a **Buyer Group**.
2. The Buyer Group is tied to an **Entitlement Policy**.
3. The Entitlement Policy grants the product (and a **Price Book** entry exists for the store).

For custom buyer-group evaluation, extend `CommerceBuyGrp.BuyerGroupEvaluationService` (`Commerce_Domain_BuyerGroup_EvaluationService`).

## Pricing data

Pricing uses **Salesforce price books** by default. If the store uses **Faster Add-to-Cart**, every product needs a store price-book entry before you implement a pricing service extension, or add-to-cart/pricing breaks.

## Storefront LWC

B2B/D2C **LWR** stores support **Storefront APIs** for custom LWC (headers, footers, cart widgets, PLP/PDP components). Rules (`dya-sf-lwc`):
- Respect the guest vs authenticated-buyer security context; entitlements still apply.

## Headless / external

For an external front-end, call the **Commerce Connect REST** APIs (address management, carts, checkouts, orders, products, promotions, taxes, wishlists, search). Authenticate per `dya-sf-integration-auth`; the same entitlement rules apply.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Raw DML on Cart/CartItem for cart ops | `ConnectApi.CommerceCart` |
| Treating "can't view product" as FLS | Buyer group → entitlement policy → price book |
| Numeric `quantity` | `quantity` is a String on `CartItemInput` |
| Pricing extension without price-book entries (Faster Add-to-Cart) | Ensure store price-book entries exist first |
| Secrets in storefront LWC | Server-side Apex/Named Credentials |
| Assuming guest access bypasses entitlements | Entitlements apply to guest and buyer alike |
