---
name: decimatio-b2b-commerce
description: Salesforce B2B (and D2C) Commerce on Core developer surface (Summer '26 / API v67.0) — the programmatic side, built on the Salesforce platform with LWC + Apex. The CartExtension framework (CartCalculate orchestrator + Pricing/Promotions/Inventory/Shipping/Tax calculators), ConnectApi.BaseEndpointExtension endpoint extensions, the ConnectApi.CommerceCart Apex API, buyer groups/entitlements, and Storefront/LWR. Not CloudCraze, not B2C Commerce. Load only when the user explicitly invokes this skill by name (`decimatio-b2b-commerce`); do NOT auto-trigger on generic commerce or Salesforce questions.
---

# Salesforce B2B Commerce (on Core) — Developer Surface

You are an expert B2B Commerce (and D2C Commerce — same stack) developer. **Critical distinctions:** this is the **on-core** product on the Salesforce platform — **LWC, Apex, SOQL**, the **`CartExtension`** framework, and the **`ConnectApi` Commerce** classes, so it *does* build on `decimatio-apex`/`lwc`. It is **not** legacy CloudCraze, and **not** B2C Commerce (`decimatio-b2c-commerce`, a separate platform). This skill covers the programmatic surface only. Follow every rule below.

References:
- `references/cart-extensions.md` — the Cart Calculate API: `CartExtension.CartCalculate` orchestrator + the five calculators, real `calculate(...)` signatures, registration via `RegisteredExternalService`, and `ConnectApi.BaseEndpointExtension` endpoint extensions.
- `references/connectapi-commerce.md` — the `ConnectApi.CommerceCart` (and related) Apex APIs, the input/output types, buyer groups/entitlements, and Storefront LWC APIs.

---

## Platform Context — Summer '26 / API v67.0

- B2B/D2C Commerce runs **on core**: storefronts are **LWR Experience Cloud** sites, UI is **LWC**, logic is **Apex**, data is standard **Commerce objects** (WebStore, WebCart, CartItem, ProductCatalog, etc.).
- **Two distinct extension surfaces** (don't conflate them):
  - **Cart Calculate API** — extend cart/checkout *calculations* (price, promotions, inventory, shipping, tax) with **`CartExtension`** base classes.
  - **Commerce endpoint extensions** — before/after hooks on the Connect *endpoints* (products, cart item, search…) via **`ConnectApi.BaseEndpointExtension`**.
- **Apex v67 defaults** apply to your extension/calculator code (`with sharing`, `USER_MODE`); `WITH SECURITY_ENFORCED` no longer compiles → `WITH USER_MODE`. The storefront runs as the **guest or authenticated buyer** — scope those profiles tightly (`decimatio-permissions`).
- **Entitlements are king:** what a buyer can see/buy is governed by the **buyer group → entitlement policy** relationship, not just CRUD/FLS. A product the user "has access to" can still be unviewable in commerce if no entitlement applies.
- Legacy **CloudCraze** B2B Commerce is a different managed-package product — out of scope; new work is Commerce on Core.

---

## 1. The Stack — What You Build With

| Layer | Technology |
|---|---|
| Storefront UI | **LWR Experience Cloud site** + **LWC** (commerce components, custom LWC, Storefront APIs) |
| Cart/checkout calculations | **`CartExtension`** orchestrator + calculators (Apex) |
| Endpoint customization | **`ConnectApi.BaseEndpointExtension`** before/after hooks (Apex) |
| Programmatic cart ops | **`ConnectApi.CommerceCart`** + related Connect classes (Apex) / Commerce Connect REST |
| Data | Standard Commerce objects; **buyer groups + entitlement policies** govern visibility |

If you know LWC + Apex, you're most of the way there; the rest is the Commerce objects, the `CartExtension` framework, and entitlements.

---

## 2. Cart Calculate API — the Core Extension Point

Cart/checkout pricing-side logic is customized by extending **`CartExtension`** base classes. An **orchestrator** (`CartExtension.CartCalculate`) decides which **calculators** run and when; each calculator is a separate, separately-overridable extension.

| Concern | Base Apex class | Extension point | Status |
|---|---|---|---|
| Orchestrator | `CartExtension.CartCalculate` | `Commerce_Domain_Cart_Calculate` | GA |
| Pricing | `CartExtension.PricingCartCalculator` | `Commerce_Domain_Pricing_CartCalculator` | GA |
| Promotions | `CartExtension.PromotionsCartCalculator` | `Commerce_Domain_Promotions_CartCalculator` | GA |
| Inventory | `CartExtension.InventoryCartCalculator` | `Commerce_Domain_Inventory_CartCalculator` | (Pilot) |
| Shipping | `CartExtension.ShippingCartCalculator` | `Commerce_Domain_Shipping_CartCalculator` | GA |
| Tax | `CartExtension.TaxCartCalculator` | `Commerce_Domain_Tax_CartCalculator` | GA |
| Create order (checkout) | `CartExtension.CheckoutCreateOrder` | `Commerce_Domain_Checkout_CreateOrder` | GA |

Real calculator shape — override `calculate(...)` taking a `CartCalculateCalculatorRequest`:

```apex
public class CustomPriceCalculator extends CartExtension.PricingCartCalculator {
    public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request) {
        CartExtension.Cart cart = request.getCart();
        // read cart items, call an external pricing system (Named Credential, ONE aggregated callout),
        // then write unit prices back onto the cart line items.
    }
}
```

`CartCalculate` is currently scoped to these operations: **AddItemToCart, EditCartItem, DeleteCartItem, AddCoupon, DeleteCoupon, StartCheckout, PatchCheckout** (address / set delivery method). Full orchestrator pattern, change-event handling, and registration: `references/cart-extensions.md`.

---

## 3. Endpoint Extensions — before/after Connect Hooks

Separately from calculations, you can customize the **Commerce endpoints** themselves (products, cart item, search, addresses…) with before/after hooks by extending **`ConnectApi.BaseEndpointExtension`**:

| Extension point | Endpoint | Since |
|---|---|---|
| `Commerce_Endpoint_Catalog_Products` / `_Product` | Products / Product | — |
| `Commerce_Endpoint_Cart_Item` / `_Cart_ItemCollection` | Cart item(s) | v62.0+ |
| `Commerce_Endpoint_Search_Products` | Search products | — |
| `Commerce_Endpoint_Account_Addresses` / `_Account_Address` | Account address(es) | — |

These run in the `connectapi` namespace and wrap the request/response. Note: the endpoint-extension request parameter doesn't support `StringList` values. Use these for shaping API I/O; use **Cart Calculate** for pricing-side math.

---

## 4. Programmatic Cart Operations — `ConnectApi.CommerceCart`

For cart/checkout operations in code, use the Commerce `ConnectApi` classes (they enforce commerce rules, pricing, and entitlements) rather than raw DML against the cart objects.

```apex
ConnectApi.CartItemInput input = new ConnectApi.CartItemInput();
input.productId = productId;
input.quantity  = '2';                       // String
input.type      = ConnectApi.CartItemType.PRODUCT;

ConnectApi.CartItem item =
    ConnectApi.CommerceCart.addItemToCart(webStoreId, effectiveAccountId, 'active', input);
```

`ConnectApi.CommerceCart` covers get/create/update/calculate/delete carts and cart items. **The most common failure is entitlement-related**, not access-related: `"You can't view 'ProductId'"` despite record access usually means the buyer's **account isn't in a buyer group tied to an entitlement policy** that grants the product. Full class/type list and entitlements: `references/connectapi-commerce.md`.

---

## 5. Storefront LWC

B2B/D2C LWR stores support **Storefront APIs** for building custom LWC (headers, footers, cart, etc.). Custom LWC follow the usual rules (`decimatio-lwc`): wire/Storefront APIs for data, `@AuraEnabled` Apex (or `ConnectApi`) for commerce operations, no secrets in the browser, and respect the guest/buyer context.

---

## 6. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| Custom pricing | `CartExtension.PricingCartCalculator` |
| Custom promotions | `CartExtension.PromotionsCartCalculator` |
| Real-time external stock | `CartExtension.InventoryCartCalculator` |
| Carrier shipping rates | `CartExtension.ShippingCartCalculator` |
| External tax engine | `CartExtension.TaxCartCalculator` |
| Control calculator order / skip some | Custom orchestrator extending `CartExtension.CartCalculate` |
| Custom order creation at checkout | `CartExtension.CheckoutCreateOrder` |
| Shape a Connect endpoint's I/O | `ConnectApi.BaseEndpointExtension` (before/after) |
| Cart/checkout ops in Apex | `ConnectApi.CommerceCart` (+ input/output types) |
| Headless / external front-end | Commerce Connect **REST** APIs |
| Custom storefront UI | LWC + Storefront APIs on LWR |
| Control product visibility | Buyer group + **entitlement policy** |

---

## 7. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Confusing this with B2C Commerce | B2C is a separate platform (`decimatio-b2c-commerce`) |
| Building new on legacy CloudCraze | Commerce on Core (this skill) |
| Conflating Cart Calculate with endpoint extensions | Calculations = `CartExtension`; endpoint I/O = `ConnectApi.BaseEndpointExtension` |
| Raw SOQL/DML on cart objects for cart ops | `ConnectApi.CommerceCart` |
| One callout per line item in a calculator | One aggregated callout for the whole cart, Named Credential |
| Debugging `"can't view ProductId"` as an FLS issue | Check buyer group → entitlement policy |
| Overriding orchestrator "callable" methods (e.g. `priceCart`) | They can't be overridden; override the *calculator*'s `calculate()` |
| `WITH SECURITY_ENFORCED` in commerce Apex | `WITH USER_MODE` (removed at v67) |
| Secrets in storefront LWC JS | Server-side Apex/Named Credentials |
| Over-broad guest/buyer profiles | Least-privilege (`decimatio-permissions`) |

---

## Summary — The Five Commandments

1. **On-core: LWC + Apex + `ConnectApi` + `CartExtension`** — reuse `decimatio-apex`/`lwc`. Not CloudCraze, not B2C.
2. **Two extension surfaces** — Cart Calculate (`CartExtension` calculators + orchestrator) for pricing-side math; `ConnectApi.BaseEndpointExtension` for endpoint I/O. Keep them straight.
3. **Override the calculator's `calculate(CartCalculateCalculatorRequest)`** — orchestrator decides *which* run; calculators do the work; the orchestrator's `priceCart`/`taxCart`/etc. dispatch methods can't be overridden.
4. **Cart ops through `ConnectApi.CommerceCart`** — never raw DML; and "can't view product" is almost always an **entitlement** gap, not FLS.
5. **Calculators run in the buyer path** — bulk-safe, one aggregated callout via Named Credential, resilient, `with sharing` + `WITH USER_MODE`; register via `RegisteredExternalService`.
