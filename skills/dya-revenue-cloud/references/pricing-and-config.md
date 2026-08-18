# Revenue Cloud Advanced — Pricing, Catalog & Configuration (API v67.0)

Load from `dya-revenue-cloud`. Salesforce Pricing on the Business Rules Engine, Product Catalog Management, and Product Configurator — with real endpoints/actions. Source: Revenue Lifecycle Management Developer Guide v67.0. Confirm exact request bodies against the guide for your version.

## Salesforce Pricing — the model

- **Pricing Procedures** (Pricing Procedure Builder): the visual, declarative successor to Industries EPC **Calculation Procedures / Pricing Plan Steps / custom Pricing Plan Step Apex** — ordered pricing elements producing the price waterfall.
- **Decision Tables** + **Lookup Tables**: Pricing Procedures read internal lookup tables for list prices, tiers, and rule outputs (input rule variables → matched row → output rule variables).
- **Context Service**: **Context Definitions** (nodes + attributes + context tags) and **Mappings** assemble the Salesforce data a procedure needs at runtime and write results back. From Setup → **Context Service → Context Definitions**.
- **Expression Sets**: reusable decision/calculation logic invoked by procedures.

## Apex Hooks for Pricing Procedures (Summer '25 — the supported custom-pricing extension)

Inject Apex into a Pricing Procedure when declarative elements can't express the logic, or to pass attribute values into/out of the procedure. This is the **modern replacement** for legacy CPQ custom price logic — implement the pricing Apex hook interface and register it in the procedure. (Confirm the exact hook interface/class name in the v67 guide; it's surfaced as a pricing-procedure element.)

## Invoking Pricing programmatically

**Run Salesforce Pricing Action** (Flow or Apex) — supply context instance Ids, pricing procedure name, and discovery procedure:

```
# Connect REST — Run Salesforce Pricing / Price Context
POST /services/data/v67.0/connect/pricing/...        # body: context, pricingProcedure, priceWaterfall details
POST /services/data/v67.0/connect/pricing/price-context   # Price Context resource
```

- **Standard Pricing Actions** ship for Quote, Order, Contract, Case, Opportunity; **Custom Pricing Actions** work on any object via the Lightning component.
- Invoke via **Flow** (create pricing actions, supply context instance Ids + procedure names) or **Apex** (Pricing Connect API / invocable).

## Keeping rules fresh (don't skip this)

Pricing Procedures read from internal lookup/decision tables and the PCM search index — **refresh after rule/data changes**:

```
# Rebuild the PCM index programmatically (Snapshot v62.0+, Deploy v63.0+)
POST /services/data/v67.0/connect/pcm/index/deploy        # { "snapshotId": "<ID>", "buildType": "INCREMENTAL" | "FULL" }
GET  /services/data/v67.0/connect/pcm/snapshots/<ID>/index # poll status
GET  /services/data/v67.0/connect/pcm/snapshots/<ID>/index/errors
```

- **Decision Table Refresh Action** — built-in **invocable** (Record-Triggered Flow, Scheduled Flow, or Apex; no HTTP callout); refresh one or many active tables asynchronously when the rule object/custom metadata changes.
- Use **INCREMENTAL** for day-to-day; **FULL** for large/structural changes. The existing index keeps serving during a rebuild.
- From Setup (clicks): **Salesforce Pricing Setup → Sync Pricing Data → Sync**.

```apex
// Queueable outline to rebuild the PCM index (GET snapshot → POST deploy via Named Credential)
public class PcmIndexRebuild implements Queueable, Database.AllowsCallouts {
    private final String snapshotId;
    public PcmIndexRebuild(String snapshotId) { this.snapshotId = snapshotId; }
    public void execute(QueueableContext ctx) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Self_Org/services/data/v67.0/connect/pcm/index/deploy');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String,Object>{ 'snapshotId' => snapshotId, 'buildType' => 'INCREMENTAL' }));
        new Http().send(req);
    }
}
```

## Product Catalog Management (PCM)

- **Products** + **Attributes** + **Product Classifications** (categorize/inherit attributes) + **Catalogs/Categories**.
- **Configurable** vs **static** vs **bundle** products; the **Structure** tab builds bundles; **cardinality** sets min/max components.
- **Product Selling Models** — one-time, term-defined, evergreen.
- Semantics resemble Industries CPQ EPC but differ — verify per the RLM guide.

## Product Configurator Business APIs

Configure/validate a configurable product at runtime (component selection, attributes, cardinality, rules) for guided selling and headless configuration. Exposed as **Connect REST business APIs** and **standard invocable actions** (Product Configurator). Surface in custom LWC via the APIs / `@AuraEnabled` Apex.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Pricing math in Apex | Pricing Procedures + Decision/Lookup Tables; Apex Hook for the rest |
| Legacy Pricing Plan Step Apex mindset | Pricing Procedure Builder (declarative) + Apex Hooks |
| Forgetting to refresh tables / rebuild index | Decision Table Refresh Action + PCM index deploy |
| Ignoring Context mappings | Map the context the procedure needs |
| FULL rebuild for every small change | INCREMENTAL for day-to-day |
| Assuming PCM == Industries EPC | Verify semantics in the RLM guide |
