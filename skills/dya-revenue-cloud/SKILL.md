---
name: dya-revenue-cloud
description: Salesforce Revenue Cloud Advanced / Revenue Lifecycle Management (RCA/RLM, now branded **Agentforce Revenue Management**) developer surface (Winter '27 / API v68.0) — the programmatic side of the modern, API-first successor to legacy CPQ, with real Connect endpoints, Apex classes, and invocable actions. Product Catalog Management, Salesforce Pricing (Pricing Procedures + Context Service + Decision Tables, with Apex Hooks), Transaction Management (Place Quote / Place Sales Transaction), Product Configurator Business APIs, Asset Lifecycle, and Billing. Load only when the user explicitly invokes this skill by name (`dya-revenue-cloud`); do NOT auto-trigger on generic CPQ, pricing, or Salesforce questions.
---

# Salesforce Revenue Cloud Advanced (RCA / RLM) — Developer Surface

**Scope:** the **modern, API-first successor to legacy Salesforce CPQ** — Revenue Lifecycle
Management (RLM), branded Revenue Cloud Advanced and, since Dreamforce 2025, "Agentforce Revenue
Management". **Legacy Salesforce CPQ — End-of-Sale, the managed-package Quote Calculator Plugin
world — is out of scope.** This skill builds on `dya-apex` and `dya-lwc`. Source of truth: the
**Revenue Lifecycle Management Developer Guide, Version 68.0 (Winter '27)**. Follow every rule
below.

References:
- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults custom pricing Apex inherits.
- `references/shared/sharing-and-access.md` — the permission model, and why a missing permission set licence looks like a missing API.
- `references/shared/governor-limits.md` — the transaction budget a pricing procedure and its Apex hooks share.
- `references/pricing-and-config.md` — Salesforce Pricing (Pricing Procedures, Context Service, Decision Tables/Lookup Tables, **Apex Hooks**), Product Catalog Management, Product Configurator Business APIs + invocable actions, and the PCM index/snapshot endpoints.
- `references/transaction-billing-apis.md` — Transaction Management (Place Quote / Place Sales Transaction, `PlaceQuoteRLMApexProcessor`), Asset Lifecycle, and Billing (ConnectApi namespace) — real endpoints, Apex, and invocable actions.

---

## Platform Context — Winter '27 / API v68.0

**The product is now called Agentforce Revenue Management.** Winter '27 completes a rename running
across three releases, and features split across the Growth, Advanced and Billing tiers — check which
tier an org holds before promising a capability. The **programmatic surface is unchanged**: the
Connect business APIs, invocable actions, Apex hooks and metadata types below all still apply.

- RCA is **API-first and on-core**. Every domain exposes **Connect REST business APIs, standard
  invocable actions, built-in Apex classes and namespaces, Metadata API types and platform events**.
  Extend with **Apex, Flow and LWC** — **never** the legacy CPQ Quote Calculator Plugin.
- It is built on shared **Salesforce Industries** infrastructure: the **Business Rules Engine**
  (Pricing Procedures, **Decision Tables**, **Lookup Tables**, Expression Sets) and the **Context
  Service** (Context Definitions and Mappings) power pricing and configuration.
- **Apex Hooks for Pricing Procedures** (Summer '25) are the supported extension point for custom
  pricing logic. §3.
- **Naming churn, which you will meet in every document and org:** RLM (Spring '24) → Revenue Cloud
  (Dreamforce '24) → **Agentforce Revenue Management** (Dreamforce '25, the current name). The
  developer guide is still titled *Revenue Lifecycle Management Developer Guide*, and objects and
  namespaces still carry the older names. Recognise all of them as the same product, and use the
  current name in new work.
- **Migration:** RCA is a **re-implementation, not an upgrade** from legacy CPQ — a new data model.
  Never port Quote Calculator Plugin logic.
- **From API 67.0 your custom Apex defaults to `with sharing` and `USER_MODE`**, and
  `WITH SECURITY_ENFORCED` no longer compiles — use `WITH USER_MODE`. Assign the **Revenue Cloud
  permission set licences**: without them the APIs are absent rather than failing informatively. See
  `dya-permissions`.

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

Every domain offers the **same programmatic surfaces**. Pick by where the logic runs:

| Surface | Use |
|---|---|
| **Connect REST business APIs** | External/headless: drive pricing, config, quote/order, billing from outside |
| **Standard invocable actions** | Declarative: from Flow and Agentforce agents |
| **Built-in Apex classes/namespaces** | On-platform: same capabilities, callable from Apex |
| **Metadata API types** | Source-control/deploy domain config (procedures, catalogs, settings) |
| **Platform events** | React to lifecycle changes (e.g. billing) |

The rule: **declarative orchestration → invocable actions; on-platform logic → Apex;
external/headless → Connect REST business APIs; deploy → Metadata API.** Never hand-roll DML against
RCA objects where a business API or invocable action exists — those enforce the engine's rules for
pricing, configuration, qualification and tax.

---

## 3. Salesforce Pricing — Configure, Then Hook

Pricing is **configured** on the Business Rules Engine, not coded:

- **Pricing Procedures** (Pricing Procedure Builder) — the visual successor to Industries'
  Calculation Procedures and Pricing Plan Steps: ordered pricing elements computing the net price and
  price waterfall.
- **Decision Tables / Lookup Tables** — drive tiered and volume discounts and rule lookups; Pricing
  Procedures read from internal lookup tables.
- **Context Service** — **Context Definitions and Mappings** assemble the runtime data a procedure
  consumes, and write results back.
- **Apex Hooks for Pricing Procedures** (Summer '25) — inject Apex into a procedure for logic the
  declarative tools cannot express, or to pass attribute values. This is the **supported**
  custom-pricing extension point, not a Quote Calculator Plugin.

Invoke pricing programmatically:

```
# Connect REST — run a pricing action with context + procedure + waterfall
POST /services/data/v68.0/connect/pricing/...        (Run Salesforce Pricing / Price Context)
```

Pricing also runs from **Flow or Apex** through the **Run Salesforce Pricing Action**, supplying
context instance Ids, the pricing procedure name and the discovery procedure. After changing rule
data, refresh with the **Decision Table Refresh Action** — invocable, no callout — and rebuild the
PCM index. Full detail: `references/pricing-and-config.md`.

---

## 4. Transaction Management — Place Quote / Place Sales Transaction

Build and price quotes and orders through the **Transaction Management Business APIs**, never by
assembling line items with raw DML.

```
# Create/update a quote (with integrated pricing + configuration)
POST /services/data/v68.0/connect/quotes/place                 # Place Quote

# Create/update a quote OR order, with pricing + config + estimated tax
POST /services/data/v68.0/connect/commerce/sales-transactions/actions/place   # Place Sales Transaction
```

In Apex, the **`PlaceQuoteRLMApexProcessor`** class and the wider PlaceQuote Apex surface process
quote placement, and standard **invocable actions** serve Flow and Agentforce — for example creating
an order from an existing quote. Full Apex, endpoints and actions:
`references/transaction-billing-apis.md`.

---

## 5. Product Configurator & PCM

- **Product Catalog Management** — Products, Attributes, Classifications and bundles. The
  **Structure** tab builds bundles, **cardinality** sets min and max components, and **Product
  Selling Models** (one-time, term, evergreen) define how a product sells and bills.
- **Product Configurator Business APIs** and **standard invocable actions** configure and validate a
  configurable product at runtime, for guided selling or headless configuration. Surface them in a
  custom LWC through the APIs or `@AuraEnabled` Apex.

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
