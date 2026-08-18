# Revenue Cloud Advanced — Transaction Management, Assets & Billing (API v67.0)

Load from `dya-revenue-cloud`. The transactional and post-sale domains with real Connect endpoints, Apex, and invocable actions. Source: Revenue Lifecycle Management Developer Guide v67.0. Confirm exact request/response bodies per version.

## The consistent surface (recap)

Each domain exposes: **Connect REST business APIs** (external), **standard invocable actions** (Flow/Agentforce), **built-in Apex classes/namespaces** (on-platform), **Metadata API types** (deploy), and **platform events** (react). Never hand-roll DML when a business API/action exists.

## Transaction Management (Quote & Order Capture)

The **Transaction Management Business APIs** fetch instant pricing on a quote/order and create quotes/orders with integrated pricing + configuration.

```
# Place Quote — create/update a quote with integrated pricing & configuration
POST /services/data/v67.0/connect/quotes/place

# Place Sales Transaction — create/update a quote OR order with pricing + config + estimated tax;
# also insert/delete order or quote line items to recalc estimated tax
POST /services/data/v67.0/connect/commerce/sales-transactions/actions/place
```

Apex:
- **`PlaceQuoteRLMApexProcessor`** (placequote namespace) — processes quote placement on-platform; the PlaceQuote Apex surface lets you create/price quotes from Apex.
- Built-in Apex reference under **Transaction Management** (quote/order capture) classes.

Invocable actions: standard actions for Flow/Agentforce — e.g. **create an order from an existing quote**, place a quote, etc. New invocable actions ship each release; check the current list.

```apex
// Illustrative PlaceQuote via Apex (confirm request/response types in the v67 guide)
// placequote.PlaceQuoteRequest → placequote.PlaceQuoteResult, processed by PlaceQuoteRLMApexProcessor
```

> Don't build quotes/orders by inserting line items with raw DML — Place Quote / Place Sales Transaction apply pricing, configuration, qualification, and tax atomically.

## Asset Lifecycle

Manage the installed base: **amend** (change qty/terms), **renew**, **cancel** — the RCA equivalent of CPQ contract amendment. Exposed as **business APIs + invocable actions + Apex**; they produce correctly-priced change transactions against existing assets. Don't mutate asset records directly.

## Billing (ConnectApi namespace)

The **`ConnectApi`** namespace (Connect in Apex) provides classes to manage **credit applications and billing scenarios**. Billing covers invoices, **credit memos**, **billing schedules**, **taxes**, and credit application.

Surfaces:
- **ConnectApi** Apex classes for billing/credit scenarios.
- **Standard invocable actions** for billing operations (manage credit application, billing schedules, invoices) from Flow.
- **Connect REST business APIs** for external billing integration.
- **Platform events** to react to billing changes.
- **Metadata API types** for billing settings/Flows.

```apex
// Billing is driven through the ConnectApi namespace + invocable actions;
// confirm exact class/method names (e.g. credit application / invoice classes) in the v67 Billing Apex reference.
```

> Don't compute invoice/credit math by hand — use the Billing ConnectApi / invocable actions.

## Putting it together

| Lifecycle moment | Extend with |
|---|---|
| Custom validation on quote build | Apex around Place Quote, or an invocable action in Flow |
| Reprice on change | Pricing Procedure (config) invoked by capture |
| Create an order from a quote | Standard invocable action |
| Amend/renew a subscription | Asset Lifecycle action/API |
| Generate/adjust an invoice | Billing ConnectApi/action + platform event subscriber |
| Headless quote/checkout | Connect REST business APIs (+ OAuth, `dya-integration-auth`) |

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Raw DML to build quotes/orders | Place Quote / Place Sales Transaction |
| Mutating asset records to amend | Asset Lifecycle APIs / actions |
| Hand-coded invoice/credit math | Billing ConnectApi / invocable actions |
| Porting CPQ Quote Calculator Plugin logic | Redesign for RCA capture + pricing procedures |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` |
| Guessing API/action/class names | Verify against the RLM dev guide v67.0 |
