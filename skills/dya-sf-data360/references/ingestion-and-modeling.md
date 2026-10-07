# Data 360 Ingestion, Modeling & Activation — Reference (Winter '27 / API v68.0)

Detail for SKILL.md §3, §4, §6, §7.

Credit multipliers are in SKILL.md §8. Verify the current source before quoting a number; both are
versioned and now tiered:

- Customer Data Cloud Rate Card (PDF): <https://www.salesforce.com/en-us/wp-content/uploads/sites/4/documents/platform/data-cloud-platform-services-rate-sheet.pdf>
- Data Services Billable Usage Types for Data 360: <https://help.salesforce.com/s/articleView?id=data.c360_a_data_usage_types.htm&language=en_US&type=5>

## Ingestion API

The full streaming and bulk lifecycle is in `references/ingestion-api.md`.

## Modeling — DLO → DMO

- The Customer 360 Data Model's 300+ prebuilt types include Individual, Account, Order and
  Engagement. Extend only when necessary.

## Identity Resolution

Identity resolution merges DLO/DMO records describing the same entity into a **Unified DMO** using
match and reconciliation rules. Cost and scheduling: SKILL.md §4 and §8.

## Calculated Insights (`__cio`)

- Use them as grounding inputs for Agentforce and as segment criteria.

## Segments

- Use aggregate filters and waterfall/ranked segments where supported.
- Manage them through the Connect API for repeatable, deployable definitions.

## DevOps for Data 360

Promote Data 360 logic (data transforms, code extensions) through CI/CD with **DevOps data kits**,
like Apex/LWC metadata, for headless, repeatable deployments across environments.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Ingesting a warehouse you could federate | Zero-copy (EDLO) |
| Heavy recompute inside a Data Action | Data Action for real-time only; batch the rest |
| No schema on an ingestion pipeline | Define schema explicitly |
| Click-built CIs/segments with no source control | Manage via Connect API + DevOps data kits |
