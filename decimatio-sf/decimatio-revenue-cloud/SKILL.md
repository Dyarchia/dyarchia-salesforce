---
name: decimatio-revenue-cloud
description: Salesforce Revenue Cloud Advanced / Revenue Lifecycle Management (RCA/RLM, "Salesforce/Agentforce Revenue Management") developer surface (Summer '26 / API v67.0) — the programmatic side of the modern, API-first successor to legacy CPQ, with real Connect endpoints, Apex classes, and invocable actions. Product Catalog Management, Salesforce Pricing (Pricing Procedures + Context Service + Decision Tables, with Apex Hooks), Transaction Management (Place Quote / Place Sales Transaction), Product Configurator Business APIs, Asset Lifecycle, and Billing. Load only when the user explicitly invokes this skill by name (`decimatio-revenue-cloud`); do NOT auto-trigger on generic CPQ, pricing, or Salesforce questions.
---

# Salesforce Revenue Cloud Advanced (RCA / RLM) — Developer Surface

You are an expert Revenue Cloud Advanced developer. **Scope:** the **modern, API-first successor to legacy Salesforce CPQ** — Revenue Lifecycle Management (RLM), branded Revenue Cloud Advanced and, since Dreamforce 2025, "Agentforce Revenue Management." **Legacy Salesforce CPQ (End-of-Sale; the managed-package Quote Calculator Plugin world) is out of scope** — this skill is RCA only. It builds on `decimatio-apex`/`lwc`. Source of truth: the **Revenue Cloud / Revenue Lifecycle Management Developer Guide, Version 67.0 (Summer '26)**. Follow every rule below.

References:
- `references/pricing-and-config.md` — Salesforce Pricing (Pricing Procedures, Context Service, Decision Tables/Lookup Tables, **Apex Hooks**), Product Catalog Management, Product Configurator Business APIs + invocable actions, and the PCM index/snapshot endpoints.
- `references/transaction-billing-apis.md` — Transaction Management (Place Quote / Place Sales Transaction, `PlaceQuoteRLMApexProcessor`), Asset Lifecycle, and Billing (ConnectApi namespace) — real endpoints, Apex, and invocable actions.

---

## Platform Context — Summer '26 / API v67.0

- RCA is **API-first and on-core**: every domain exposes **Connect REST business APIs + standard invocable actions + built-in Apex classes/namespaces + Metadata API types + platform events**. You extend with **Apex, Flow, and LWC** — **not** the legacy CPQ Quote Calculator Plugin.
- It's built on shared **Salesforce Industries** infrastructure: the **Business Rules Engine** (Pricing Procedures, **Decision Tables**, **Lookup Tables**, Expression Sets) and the **Context Service** (Context Definitions/Mappings) power pricing and configuration.
- **Apex Hooks for Pricing Procedures** (since Summer '25) let you inject Apex into a pricing procedure — the supported way to add custom pricing logic the declarative tools can't express.
- **Naming churn (for recognition):** RLM (Spring '24) → Revenue Cloud (DF '24) → Agentforce Revenue Management (DF '25). The dev guide is still titled *Revenue Lifecycle Management Developer Guide*.
- **Migration:** RCA is a **re-implementation, not an upgrade** from legacy CPQ — a new data model. Don't port Quote Calculator Plugin logic.
- **Apex v67 defaults** apply to your custom RCA Apex (`with sharing`, `USER_MODE`; `WITH SECURITY_ENFORCED` no longer compiles → `WITH USER_MODE`). Assign the **Revenue Cloud permission set licenses**.

---

## 1. The Domains (the map)

| Domain | Covers | Primary extension surface |
|---|---|---|
| **Product Catalog Management (PCM)** | Products, attributes, classifications, bundles, cardinality, selling models | Objects + metadata + PCM index endpoints |
| **Product Discovery** | What's sellable in a context (qualification) | Qualification Rules, discovery procedures |
| **Salesforce Pricing** | Net price: Pricing Procedures + Decision/Lookup Tables | Business Rules Engine + **Apex Hooks** + Pricing Connect API |
| **Product Configurator** | Runtime configuration of configurable bundles | **Product Configurator Business APIs** + invocable actions |
| **Transaction Management (Quote/Order Capture)** | Build/price quotes & orders | **Place Quote / Place Sales Transaction** APIs, `PlaceQuote*` Apex, invocable actions |
| **Asset Lifecycle** | Amend / renew / cancel assets | Business APIs + invocable actions + Apex |
| **Billing** | Invoices, credit memos, billing schedules, taxes | **ConnectApi** namespace + invocable actions + Apex + platform events |

---

## 2. The Extension Model — Same Shape Everywhere

Each domain offers the **same set of programmatic surfaces**; pick by where the logic runs:

| Surface | Use |
|---|---|
| **Connect REST business APIs** | External/headless: drive pricing, config, quote/order, billing from outside |
| **Standard invocable actions** | Declarative: from Flow and Agentforce agents |
| **Built-in Apex classes/namespaces** | On-platform: same capabilities, callable from Apex |
| **Metadata API types** | Source-control/deploy domain config (procedures, catalogs, settings) |
| **Platform events** | React to lifecycle changes (e.g. billing) |

The rule: **declarative orchestration → invocable actions; on-platform logic → Apex; external/headless → Connect REST business APIs; deploy → Metadata API.** Never hand-roll DML against RCA objects when a business API / invocable action exists — they enforce the engine's rules (pricing, configuration, qualification, tax).

---

## 3. Salesforce Pricing — Configure, Then Hook

Pricing is **configured** on the Business Rules Engine, not coded:

- **Pricing Procedures** (Pricing Procedure Builder) — the visual successor to Industries' Calculation Procedures / Pricing Plan Steps; ordered pricing elements computing the net price/price waterfall.
- **Decision Tables / Lookup Tables** — drive tiered/volume discounts and rule lookups; Pricing Procedures read from internal lookup tables.
- **Context Service** — **Context Definitions + Mappings** assemble the runtime data a procedure consumes (and write results back).
- **Apex Hooks for Pricing Procedures** (Summer '25) — inject Apex into a procedure for logic the declarative tools can't express, or to pass attribute values; this is the **supported** custom-pricing extension point (not a Quote Calculator Plugin).

Invoke pricing programmatically:

```
# Connect REST — run a pricing action with context + procedure + waterfall
POST /services/data/v67.0/connect/pricing/...        (Run Salesforce Pricing / Price Context)
```

You can also invoke pricing from **Flow or Apex** via the **Run Salesforce Pricing Action** (supply context instance Ids, pricing procedure name, discovery procedure). After changing rule data, refresh with the **Decision Table Refresh Action** (invocable; no callout) and rebuild the PCM index. Full detail: `references/pricing-and-config.md`.

---

## 4. Transaction Management — Place Quote / Place Sales Transaction

Build and price quotes/orders through the **Transaction Management Business APIs** — never by assembling line items with raw DML.

```
# Create/update a quote (with integrated pricing + configuration)
POST /services/data/v67.0/connect/quotes/place                 # Place Quote

# Create/update a quote OR order, with pricing + config + estimated tax
POST /services/data/v67.0/connect/commerce/sales-transactions/actions/place   # Place Sales Transaction
```

In Apex, the **`PlaceQuoteRLMApexProcessor`** class (and the PlaceQuote Apex surface) processes quote placement; standard **invocable actions** exist for Flow/Agentforce (e.g. an action that creates an order from an existing quote). Full Apex/endpoints/actions: `references/transaction-billing-apis.md`.

---

## 5. Product Configurator & PCM

- **Product Catalog Management** — Products + Attributes + Classifications + bundles; the **Structure** tab builds bundles; **cardinality** sets min/max components; **Product Selling Models** (one-time/term/evergreen) define how a product sells/bills.
- **Product Configurator Business APIs** + **standard invocable actions** — configure/validate a configurable product at runtime (guided selling, headless configuration). Surface in a custom LWC via the APIs / `@AuraEnabled` Apex.

---

## 6. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| Define products/bundles/attributes | PCM (objects + metadata), Structure tab, cardinality |
| Control what's sellable in a context | Qualification Rules (Product Discovery) |
| Calculate net price | Pricing Procedure + Decision/Lookup Tables |
| Custom pricing logic the engine can't express | **Apex Hook** for the Pricing Procedure |
| Invoke pricing from Flow/Apex | **Run Salesforce Pricing Action** |
| Refresh rules after data change | **Decision Table Refresh Action** (invocable) + PCM index deploy |
| Configure a bundle at runtime | Product Configurator Business APIs / invocable actions |
| Build/price a quote | **Place Quote** API / `PlaceQuoteRLMApexProcessor` / invocable action |
| Build/price a quote or order (+ tax) | **Place Sales Transaction** API |
| Amend/renew/cancel an asset | Asset Lifecycle APIs / actions |
| Invoice / credit / bill | Billing **ConnectApi** + invocable actions + platform events |
| Drive RCA from Flow/agents | Standard invocable actions |
| Drive RCA from external/headless | Connect REST business APIs |
| Deploy RCA config | Metadata API types |

---

## 7. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Porting legacy CPQ Quote Calculator Plugin logic | Redesign for RCA (Apex Hooks, pricing procedures) |
| Hard-coding pricing in Apex | Pricing Procedures + Decision/Lookup Tables; Apex Hook for the rest |
| Raw DML to assemble quotes/orders | Place Quote / Place Sales Transaction APIs |
| Treating RCA as a CPQ upgrade | New data model — greenfield design |
| Forgetting to refresh decision tables / rebuild the index after rule changes | Decision Table Refresh Action + PCM index deploy |
| Ignoring Context Service mappings | Map the context the procedure needs |
| Bypassing Qualification Rules in code | Configure eligibility in Product Discovery |
| `WITH SECURITY_ENFORCED` in RCA Apex | `WITH USER_MODE` |
| Hand-rolling invoice/credit math | Billing ConnectApi / invocable actions |

---

## Summary — The Five Commandments

1. **RCA is the API-first CPQ successor** — a re-implementation with a new data model; never port legacy CPQ logic.
2. **Same extension shape per domain** — Connect REST (external), invocable actions (Flow/Agentforce), Apex (on-platform), Metadata API (deploy), platform events (react).
3. **Configure pricing, then hook** — Pricing Procedures + Decision/Lookup Tables + Context Service; **Apex Hooks** for the inexpressible (not Quote Calculator Plugins).
4. **Transactions via Place Quote / Place Sales Transaction** — never raw DML; `PlaceQuoteRLMApexProcessor` in Apex.
5. **After rule changes, refresh** — Decision Table Refresh Action + PCM index deploy; build on core with `with sharing` + `WITH USER_MODE` and the Revenue Cloud PSLs.
