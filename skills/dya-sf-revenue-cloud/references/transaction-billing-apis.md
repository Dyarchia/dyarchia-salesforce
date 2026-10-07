# Revenue Cloud Advanced — Transaction Management, Assets & Billing (Winter '27 / API v68.0)

Load from `dya-sf-revenue-cloud`. Source: Revenue Lifecycle Management Developer Guide v68.0. Confirm exact request and response bodies for each version.

## Transaction Management (Quote & Order Capture)

The **Transaction Management Business APIs** also fetch instant pricing on a quote or order.

```
# Place Quote — create/update a quote with integrated pricing & configuration
POST /services/data/v68.0/connect/quotes/place

# Place Sales Transaction — create/update a quote OR order with pricing + config + estimated tax;
# also insert/delete order or quote line items to recalc estimated tax
POST /services/data/v68.0/connect/commerce/sales-transactions/actions/place
```

Apex:
- **`PlaceQuoteRLMApexProcessor`** lives in the placequote namespace.
- Built-in Apex reference under **Transaction Management** (quote/order capture) classes.

Check the current invocable action list: it includes placing a quote, and new actions ship each release.

```apex
// Illustrative PlaceQuote via Apex (confirm request/response types in the current developer guide)
// placequote.PlaceQuoteRequest → placequote.PlaceQuoteResult, processed by PlaceQuoteRLMApexProcessor
```

> Place Quote and Place Sales Transaction apply pricing, configuration, qualification and tax atomically.

## Asset Lifecycle

Never mutate asset records directly. Manage the installed base — **amend** (change quantity or terms), **renew**, **cancel**, the RCA equivalent of CPQ contract amendment — through the business APIs, invocable actions and Apex, which produce correctly priced change transactions against existing assets.

## Billing (ConnectApi namespace)

The **`ConnectApi`** namespace (Connect in Apex) provides classes to manage **credit applications and billing scenarios**. Billing also covers invoices, **credit memos**, **billing schedules** and **taxes**.

Surfaces:
- **ConnectApi** Apex classes.
- **Standard invocable actions** from Flow (credit application, billing schedules, invoices).
- **Connect REST business APIs** for external billing integration.
- **Platform events** to react to billing changes.
- **Metadata API types** for billing settings/Flows.

```apex
// Confirm exact class/method names (e.g. credit application / invoice classes) in the current Billing Apex reference.
```

## Putting it together

| Lifecycle moment | Extend with |
|---|---|
| Custom validation on quote build | Apex around Place Quote, or an invocable action in Flow |
| Reprice on change | Pricing Procedure (config) invoked by capture |
| Create an order from a quote | Standard invocable action |
| Amend/renew a subscription | Asset Lifecycle action/API |
| Generate/adjust an invoice | Billing ConnectApi/action + platform event subscriber |
| Headless quote/checkout | Connect REST business APIs (+ OAuth, `dya-sf-integration-auth`) |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Mutating asset records to amend | Asset Lifecycle APIs / actions |
| Guessing API/action/class names | Verify against the RLM dev guide v68.0 |
