# B2B/D2C Commerce — Cart Calculate API & Endpoint Extensions (Winter '27 / API v68.0)

Load from `dya-sf-b2b-commerce`. The `CartExtension` framework (orchestrator + calculators) and `ConnectApi.BaseEndpointExtension` endpoint hooks, with real signatures. On-core Apex, so `dya-sf-apex` rules apply (bulk, `with sharing`, `WITH USER_MODE`, Named Credentials). Class availability depends on API version; confirm GA/Pilot status for yours.

## The Cart Calculate API

`CartExtension.CheckoutCreateOrder` (GA) and `CartExtension.SplitShipmentService` are checkout-time extensions.

## A Calculator — override `calculate(...)`

```apex
public class CustomPriceCalculator extends CartExtension.PricingCartCalculator {
    public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request) {
        CartExtension.Cart cart = request.getCart();

        // Optional: inspect what the buyer did
        // CartExtension.BuyerActionDetails details = request.getOptionalBuyerActionDetails();

        // 1) collect SKUs/quantities from the cart (bulk)
        // 2) ONE aggregated callout to the external pricing system (Named Credential)
        // 3) write unit prices back onto the cart line items
    }
}
```

Detecting why a recalculation fired (pattern from community samples):

```apex
public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request) {
    CartExtension.Cart cart = request.getCart();
    // derive the change type from the request, then branch:
    //   ADD         → price newly added item(s)
    //   QUANTITY    → re-price on quantity change
    //   RECALCULATE → full recalc trigger
}
```

## The Orchestrator — control which calculators run

A custom orchestrator extends `CartExtension.CartCalculate` and is registered for `Commerce_Domain_Cart_Calculate`. Once registered and available, **your** orchestrator runs on every cart calculation. Inside `calculate`, call the dispatch methods (`priceCart`, `promotionsCart`, `inventoryCart`, `shippingCart`, `taxCart`) — these **cannot be overridden**; each invokes your custom calculator if supplied, else the default.

```apex
public class CustomCartCalculate extends CartExtension.CartCalculate {
    public virtual override void calculate(CartExtension.CartCalculateOrchestratorRequest request) {
        CartExtension.Cart cart = request.getCart();

        Boolean runPricing  = /* true if item add/delete/update or start checkout */ true;
        Boolean runPromos   = true;
        Boolean runInventory = true;
        Boolean runShipping = /* true during checkout */ false;
        Boolean runTax      = false;

        if (runPricing)   priceCart(request);
        if (runPromos)    promotionsCart(request);
        if (runInventory) inventoryCart(request);
        if (runShipping)  shippingCart(request);
        if (runTax)       taxCart(request);
    }
}
```

This mirrors the `CartCalculateSample.cls` default logic. Your orchestrator can reorder or skip calculators.

> If the **Cart Calculate API is off** and store customizations change cart items via SObject/Apex DML/Delivery Group APIs, configure the **Apex Price** integration, or re-pricing won't occur at checkout.

## Registering an extension (`RegisteredExternalService`)

Wire a calculator/extension to a store by inserting a `RegisteredExternalService` row whose `ExternalServiceProviderId` is the Apex class Id (or the metadata equivalent), then linking it from the store's Administration menu (e.g. **Tax Calculation → Integration**). Each integration type (price/promotions/inventory/shipping/tax) is linked per store.

```apex
// Illustrative registration insert (confirm field names for your version)
RegisteredExternalService res = new RegisteredExternalService(
    DeveloperName    = 'Custom_Tax',
    MasterLabel      = 'Custom Tax',
    ExternalServiceProviderType = 'Tax',
    ExternalServiceProviderId   = taxApexClassId
);
insert res;
// Then link it to the WebStore via the store Administration UI (or StoreIntegratedService).
```

## Endpoint Extensions — before/after Connect hooks

- `Commerce_Endpoint_Catalog_Products` / `Commerce_Endpoint_Catalog_Product`
- `Commerce_Endpoint_Cart_Item` / `Commerce_Endpoint_Cart_ItemCollection` (v62.0+)
- `Commerce_Endpoint_Search_Products`
- `Commerce_Endpoint_Account_Addresses` / `Commerce_Endpoint_Account_Address`

```apex
public class CartItemEndpointExtension extends ConnectApi.BaseEndpointExtension {
    public override ConnectApi.BaseEndpointExtensionResponse beforeCall(
        ConnectApi.BaseEndpointExtensionRequest request) {
        // mutate the inbound request before the standard endpoint runs
        return super.beforeCall(request);
    }
    public override ConnectApi.BaseEndpointExtensionResponse afterCall(
        ConnectApi.BaseEndpointExtensionRequest request) {
        // mutate the response after the standard endpoint runs
        return super.afterCall(request);
    }
}
```

Confirm exact method signatures for your API version.

## Best Practices

- **Bulk + one callout**: a calculator runs in the buyer's request path — aggregate all line items into one external callout (Named Credential), never one per item.
- **Resilient**: handle external timeout/failure (fallback price/availability, clear error) without breaking the whole cart.
- **Register per store** and per integration type; verify with a SOQL query on `RegisteredExternalService` / store integration.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Per-line-item callout in a calculator | One aggregated bulk callout (Named Credential) |
| Overriding `priceCart`/`taxCart`/etc. | Override the calculator's `calculate()` |
| Forgetting to register the extension | Insert `RegisteredExternalService` + link to store |
| Cart Calculate off + DML cart changes, no Apex Price | Configure the Apex Price integration |
| Passing `StringList` to an endpoint extension param | Not supported — use another type |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` |
