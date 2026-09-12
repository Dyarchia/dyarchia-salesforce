---
name: dya-b2b-commerce
description: Salesforce B2B (and D2C) Commerce on Core developer surface (Winter '27 / API v68.0) — the programmatic side, built on the Salesforce platform with LWC + Apex. The CartExtension framework (CartCalculate orchestrator + Pricing/Promotions/Inventory/Shipping/Tax calculators), ConnectApi.BaseEndpointExtension endpoint extensions, the ConnectApi.CommerceCart Apex API, buyer groups/entitlements, and Storefront/LWR. Not CloudCraze, not B2C Commerce. Load only when the user explicitly invokes this skill by name (`dya-b2b-commerce`); do NOT auto-trigger on generic commerce or Salesforce questions.
---

# Salesforce B2B Commerce (on Core) — Developer Surface

B2B and D2C Commerce are one stack. **Critical distinctions:** this is the **on-core** product on
the Salesforce platform, built from **LWC, Apex, SOQL**, the **`CartExtension`** framework and the
**`ConnectApi` Commerce** classes, so it builds on `dya-apex` and `dya-lwc`. It is **not** legacy
CloudCraze, and **not** B2C Commerce (`dya-b2c-commerce`, a separate platform). This skill covers
the programmatic surface only. Follow every rule below.

References:
- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults your extension code inherits.
- `references/shared/sharing-and-access.md` — the buyer and guest identity your calculator now runs as.
- `references/shared/governor-limits.md` — the transaction budget a cart calculation shares.
- `references/cart-extensions.md` — the Cart Calculate API: `CartExtension.CartCalculate` orchestrator + the five calculators, real `calculate(...)` signatures, registration via `RegisteredExternalService`, and `ConnectApi.BaseEndpointExtension` endpoint extensions.
- `references/connectapi-commerce.md` — the `ConnectApi.CommerceCart` (and related) Apex APIs, the input/output types, buyer groups/entitlements, and Storefront LWC APIs.

---

## Platform Context — Winter '27 / API v68.0

Winter '27 enhances the storefront and order-management surface but **changes none of the
programmatic contracts below**: the CartExtension base classes, the endpoint-extension hooks and the
`ConnectApi.CommerceCart` API are unchanged. Check the Commerce release notes for merchandising and
admin features; this skill is the developer surface.

- B2B and D2C Commerce run **on core**: storefronts are **LWR Experience Cloud** sites, UI is
  **LWC**, logic is **Apex**, data is the standard **Commerce objects** — WebStore, WebCart,
  CartItem, ProductCatalog.
- **Two distinct extension surfaces**, never to be conflated:
  - **Cart Calculate API** — extend cart and checkout *calculations* (price, promotions, inventory,
    shipping, tax) with the **`CartExtension`** base classes.
  - **Commerce endpoint extensions** — before and after hooks on the Connect *endpoints* (products,
    cart item, search) via **`ConnectApi.BaseEndpointExtension`**.
- **From API 67.0 your extension and calculator code defaults to `with sharing` and `USER_MODE`**,
  and `WITH SECURITY_ENFORCED` no longer compiles — use `WITH USER_MODE`. This matters more here than
  almost anywhere, because the storefront runs as the **guest or authenticated buyer**, whose profile
  now governs what your calculator can read. Scope those profiles deliberately: see `dya-permissions`
  and `references/shared/sharing-and-access.md`.
- **Entitlements are king.** What a buyer may see and buy is governed by the **buyer group →
  entitlement policy** relationship, not by CRUD and FLS alone. A product the user "has access to"
  stays unviewable in commerce when no entitlement applies.
- Legacy **CloudCraze** B2B Commerce is a different managed-package product and out of scope. New
  work is Commerce on Core.

---

## 1. The Stack — What You Build With

| Layer | Technology |
|---|---|
| Storefront UI | **LWR Experience Cloud site** + **LWC** (commerce components, custom LWC, Storefront APIs) |
| Cart/checkout calculations | **`CartExtension`** orchestrator + calculators (Apex) |
| Endpoint customization | **`ConnectApi.BaseEndpointExtension`** before/after hooks (Apex) |
| Programmatic cart ops | **`ConnectApi.CommerceCart`** + related Connect classes (Apex) / Commerce Connect REST |
| Data | Standard Commerce objects; **buyer groups + entitlement policies** govern visibility |

LWC and Apex knowledge carries most of the way. What remains is the Commerce objects, the
`CartExtension` framework and entitlements.

---

## 2. Cart Calculate API — the Core Extension Point

Pricing-side cart and checkout logic is customised by extending **`CartExtension`** base classes. An
**orchestrator** (`CartExtension.CartCalculate`) decides which **calculators** run and when, and each
calculator is separately overridable.

| Concern | Base Apex class | Extension point | Status |
|---|---|---|---|
| Orchestrator | `CartExtension.CartCalculate` | `Commerce_Domain_Cart_Calculate` | GA |
| Pricing | `CartExtension.PricingCartCalculator` | `Commerce_Domain_Pricing_CartCalculator` | GA |
| Promotions | `CartExtension.PromotionsCartCalculator` | `Commerce_Domain_Promotions_CartCalculator` | GA |
| Inventory | `CartExtension.InventoryCartCalculator` | `Commerce_Domain_Inventory_CartCalculator` | (Pilot) |
| Shipping | `CartExtension.ShippingCartCalculator` | `Commerce_Domain_Shipping_CartCalculator` | GA |
| Tax | `CartExtension.TaxCartCalculator` | `Commerce_Domain_Tax_CartCalculator` | GA |
| Create order (checkout) | `CartExtension.CheckoutCreateOrder` | `Commerce_Domain_Checkout_CreateOrder` | GA |

The real calculator shape overrides `calculate(...)`, taking a `CartCalculateCalculatorRequest`:

```apex
public class CustomPriceCalculator extends CartExtension.PricingCartCalculator {
    public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request) {
        CartExtension.Cart cart = request.getCart();
        // read cart items, call an external pricing system (Named Credential, ONE aggregated callout),
        // then write unit prices back onto the cart line items.
    }
}
```

`CartCalculate` is scoped to these operations: **AddItemToCart, EditCartItem, DeleteCartItem,
AddCoupon, DeleteCoupon, StartCheckout, PatchCheckout** (address or set delivery method). Full
orchestrator pattern, change-event handling and registration: `references/cart-extensions.md`.

---

## 3. Endpoint Extensions — before/after Connect Hooks

Separately from calculations, the **Commerce endpoints** themselves — products, cart item, search,
addresses — take before and after hooks by extending **`ConnectApi.BaseEndpointExtension`**:

| Extension point | Endpoint | Since |
|---|---|---|
| `Commerce_Endpoint_Catalog_Products` / `_Product` | Products / Product | — |
| `Commerce_Endpoint_Cart_Item` / `_Cart_ItemCollection` | Cart item(s) | v62.0+ |
| `Commerce_Endpoint_Search_Products` | Search products | — |
| `Commerce_Endpoint_Account_Addresses` / `_Account_Address` | Account address(es) | — |

These run in the `connectapi` namespace and wrap the request and response. The endpoint-extension
request parameter does not support `StringList` values. Use these to shape API I/O, and **Cart
Calculate** for pricing-side math.

---

## 4. Programmatic Cart Operations — `ConnectApi.CommerceCart`

Cart and checkout operations in code go through the Commerce `ConnectApi` classes, which enforce
commerce rules, pricing and entitlements, never through raw DML against the cart objects.

```apex
ConnectApi.CartItemInput input = new ConnectApi.CartItemInput();
input.productId = productId;
input.quantity  = '2';                       // String
input.type      = ConnectApi.CartItemType.PRODUCT;

ConnectApi.CartItem item =
    ConnectApi.CommerceCart.addItemToCart(webStoreId, effectiveAccountId, 'active', input);
```

`ConnectApi.CommerceCart` covers get, create, update, calculate and delete for carts and cart items.
**The most common failure is entitlement-related rather than access-related.**
`"You can't view 'ProductId'"` despite record access usually means the buyer's **account is not in a
buyer group tied to an entitlement policy** granting the product. Full class and type list, and entitlements:
`references/connectapi-commerce.md`.

---

## 5. Storefront LWC

B2B and D2C LWR stores support **Storefront APIs** for building custom LWC — headers, footers, cart.
Custom LWC follow the usual rules (`dya-lwc`): wire and Storefront APIs for data, `@AuraEnabled` Apex
or `ConnectApi` for commerce operations, no secrets in the browser, and respect for the guest or
buyer context.

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
| Confusing this with B2C Commerce | B2C is a separate platform (`dya-b2c-commerce`) |
| Building new on legacy CloudCraze | Commerce on Core (this skill) |
| Conflating Cart Calculate with endpoint extensions | Calculations = `CartExtension`; endpoint I/O = `ConnectApi.BaseEndpointExtension` |
| Raw SOQL/DML on cart objects for cart ops | `ConnectApi.CommerceCart` |
| One callout per line item in a calculator | One aggregated callout for the whole cart, Named Credential |
| Debugging `"can't view ProductId"` as an FLS issue | Check buyer group → entitlement policy |
| Overriding orchestrator "callable" methods (e.g. `priceCart`) | They can't be overridden; override the *calculator*'s `calculate()` |
| `WITH SECURITY_ENFORCED` in commerce Apex | `WITH USER_MODE` (removed from API 67.0) |
| Secrets in storefront LWC JS | Server-side Apex/Named Credentials |
| Over-broad guest/buyer profiles | Least-privilege (`dya-permissions`) |

---

## Summary — The Five Commandments

1. **On-core: LWC + Apex + `ConnectApi` + `CartExtension`** — reuse `dya-apex`/`lwc`. Not CloudCraze, not B2C.
2. **Two extension surfaces** — Cart Calculate (`CartExtension` calculators + orchestrator) for pricing-side math; `ConnectApi.BaseEndpointExtension` for endpoint I/O. Keep them straight.
3. **Override the calculator's `calculate(CartCalculateCalculatorRequest)`** — orchestrator decides *which* run; calculators do the work; the orchestrator's `priceCart`/`taxCart`/etc. dispatch methods can't be overridden.
4. **Cart ops through `ConnectApi.CommerceCart`** — never raw DML; and "can't view product" is almost always an **entitlement** gap, not FLS.
5. **Calculators run in the buyer path** — bulk-safe, one aggregated callout via Named Credential, resilient, `with sharing` + `WITH USER_MODE`; register via `RegisteredExternalService`.
