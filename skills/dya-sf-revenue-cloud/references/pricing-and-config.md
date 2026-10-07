# Revenue Cloud Advanced — Pricing, Catalog & Configuration (Winter '27 / API v68.0)

Load from `dya-sf-revenue-cloud`. Source: Revenue Lifecycle Management Developer Guide v68.0. Confirm exact request bodies against the guide for the org's version.

## Salesforce Pricing — the model

- **Pricing Procedures** succeed Industries EPC **Calculation Procedures / Pricing Plan Steps / custom Pricing Plan Step Apex**.
- **Decision Tables** + **Lookup Tables** hold list prices, tiers and rule outputs (input rule variables → matched row → output rule variables).
- **Context Definitions** consist of nodes, attributes and context tags. Setup → **Context Service → Context Definitions**.
- **Expression Sets**: reusable decision/calculation logic invoked by procedures.

## Apex Hooks for Pricing Procedures (Summer '25)

Implement the pricing Apex hook interface and register it in the procedure, where it surfaces as a pricing-procedure element. Confirm the exact interface or class name in the current developer guide.

## Invoking Pricing programmatically

```
# Connect REST — Run Salesforce Pricing / Price Context
POST /services/data/v68.0/connect/pricing/...        # body: context, pricingProcedure, priceWaterfall details
POST /services/data/v68.0/connect/pricing/price-context   # Price Context resource
```

- **Standard Pricing Actions** ship for Quote, Order, Contract, Case, Opportunity; **Custom Pricing Actions** work on any object via the Lightning component.
- Invoke pricing from **Flow** (create pricing actions) or **Apex** (Pricing Connect API or invocable).

## Keeping rules fresh

Pricing Procedures also read the PCM search index:

```
# Rebuild the PCM index programmatically (Snapshot v62.0+, Deploy v63.0+)
POST /services/data/v68.0/connect/pcm/index/deploy        # { "snapshotId": "<ID>", "buildType": "INCREMENTAL" | "FULL" }
GET  /services/data/v68.0/connect/pcm/snapshots/<ID>/index # poll status
GET  /services/data/v68.0/connect/pcm/snapshots/<ID>/index/errors
```

- Call the **Decision Table Refresh Action** from a Record-Triggered Flow, Scheduled Flow or Apex whenever the rule object or custom metadata changes; it refreshes one or many active tables asynchronously.
- Use **INCREMENTAL** for day-to-day changes and **FULL** for large or structural changes. The existing index keeps serving during a rebuild.
- To sync from Setup by clicks: **Salesforce Pricing Setup → Sync Pricing Data → Sync**.

```apex
// Queueable outline to rebuild the PCM index (GET snapshot → POST deploy via Named Credential)
public class PcmIndexRebuild implements Queueable, Database.AllowsCallouts {
    private final String snapshotId;
    public PcmIndexRebuild(String snapshotId) { this.snapshotId = snapshotId; }
    public void execute(QueueableContext ctx) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Self_Org/services/data/v68.0/connect/pcm/index/deploy');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String,Object>{ 'snapshotId' => snapshotId, 'buildType' => 'INCREMENTAL' }));
        new Http().send(req);
    }
}
```

## Product Catalog Management (PCM)

- **Product Classifications** categorize products and let them inherit attributes; **Catalogs/Categories** group them.
- Products are **configurable**, **static** or **bundle**.
- Verify semantics against the RLM guide: they resemble Industries CPQ EPC but differ.

## Product Configurator Business APIs

Runtime configuration covers component selection, attributes, cardinality and rules. Exposed as **Connect REST business APIs** and **standard invocable actions** (Product Configurator).

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Legacy Pricing Plan Step Apex mindset | Pricing Procedure Builder (declarative) + Apex Hooks |
| FULL rebuild for every small change | INCREMENTAL for day-to-day |
| Assuming PCM == Industries EPC | Verify semantics in the RLM guide |
