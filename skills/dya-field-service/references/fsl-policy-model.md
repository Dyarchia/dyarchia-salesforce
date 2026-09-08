# The Scheduling Policy Model and the Optimizer's Arithmetic

What a scheduling policy is actually made of, how work rules and objectives attach to it, and how the
optimizer converts a weight into a number. Consult this when you are building or reading a policy
rather than calling `schedule` or `GetSlots` — the Apex surface is in
`references/fsl-apex-scheduling.md`.

Throughout, `<NS>` stands for the resolved package namespace. It is `FSL` in production and
`FSLQA` / `FSLMPTEST` / `FSLMPPERF` elsewhere; resolve it rather than hardcoding, per SKILL.md §6.

## The object graph

A policy does not contain its rules and objectives. It is joined to them through two junction
objects, and knowing their shape is what lets you read a policy from Apex or a query rather than the
Setup UI.

| Junction | Joins | Notes |
|---|---|---|
| `<NS>__Scheduling_Policy_Work_Rule__c` | `Scheduling_Policy__c` ↔ `Work_Rule__c` | Membership only |
| `<NS>__Scheduling_Policy_Goal__c` | `Scheduling_Policy__c` ↔ `Service_Goal__c` | Carries **`Weight__c`** |

`Weight__c` is a `double` with precision 9 and **scale 0** — whole numbers only, enforced at the
schema level, and `nillable=false`. That constraint matters once you read the penalty arithmetic
below: fractional weights are not merely discouraged, they cannot be stored.

Reading a policy's rules:

```sql
SELECT Name,
       <NS>__Work_Rule__r.Name,
       <NS>__Work_Rule__r.RecordType.DeveloperName
FROM   <NS>__Scheduling_Policy_Work_Rule__c
WHERE  <NS>__Scheduling_Policy__c = :policyId
```

## Type is a RecordType, not a field

**There is no `Type__c` on `Service_Goal__c`,** and none on `Work_Rule__c` either. The kind of
objective or rule is its **RecordType DeveloperName**. Code that filters on a type field will not
compile; code that filters on a label will break under translation.

The ten active objective RecordTypes:

```text
Objective_Asap                  Objective_Minimize_Gaps
Objective_Minimize_Travel       Objective_Minimize_Overtime
Objective_Same_Site             Objective_PreferredEngineer
Objective_Skill_Level           Objective_Resource_Priority
Objective_Skill_Preferences     Objective_Custom_Logic
```

### Configuration fields on `Service_Goal__c`

Which of these is meaningful depends on the RecordType:

| Field | Type | Used by |
|---|---|---|
| `Custom_Type__c` | Picklist (14 values) | Custom Logic |
| `Prioritize_Resource__c` | Least Qualified / Most Qualified | Skill Level |
| `Gap_Duration__c` | Double, minutes | Minimize Gaps |
| `Ignore_Home_Base_Coordinates__c` | Boolean | Minimize Travel |
| `Skill_Type__c` | — | Skill Level / Skill Preferences |
| `Resource_Priority_Field__c` | String, default `fsl__priority__c` | Resource Priority |
| `Object_Group_Field__c` / `Resource_Group_Field__c` | — | Relevance-group scoping |
| `Custom_Logic_Data__c` | Long textarea | Custom Logic |

## Rules the package writes for you, and the one it does not

Creating a policy **auto-creates** the `Earliest Start Permitted` and `Due Date` Match Time rules.
Do not write them; a deploy that includes them collides with the package's own.

It does **not** create `Service Resource Availability`, which is mandatory on every policy. That
omission is the most common cause of a policy that schedules nothing and reports no error worth
reading.

Shipped starter policies: `Customer First`, `High Intensity`, `Soft Boundaries`, `Emergency`.

On an ESO-enabled org the same starters are queried natively:

```sql
SELECT Id, MasterLabel, DeveloperName, SchedulingCategory FROM SchedulingPolicy
```

## Database rules versus Apex rules — the latency lever

Work rules run in two engines, and the difference is the single biggest performance decision in a
policy:

- **Database rules** filter at the SOQL level. They are aggregated into one query, so their cost is
  roughly constant regardless of how many resources the org has.
- **Apex rules** run *after* that query, iterating over **every candidate it returned**. Their cost
  is linear in the candidate pool.

Therefore: **every policy needs at least one database rule, and the goal is to narrow to roughly 20
candidates before any Apex rule or objective runs.** A policy of pure Apex rules asks the engine to
evaluate custom logic against the whole resource population on every `GetSlots` and
`getAppointmentCandidates` call, and that is what a "Field Service is slow" report usually turns out
to be.

Hard caps worth knowing while composing:

- **Match Boolean: maximum 5 per policy.**
- **Count Rule: up to 10 custom-field rules per policy.** Its time resolution is always Daily and it
  always counts `ServiceAppointment`.

## Relevance groups

A relevance group scopes a rule to a subset of work or a subset of resources, using a **Boolean
field**: on `ServiceAppointment` for a work subset, on `ServiceTerritoryMember` for a resource
subset. STM supports **primary and relocation memberships only, not secondary**.

**Groups must be mutually exclusive.** Where two rules with relevance groups overlap the more
restrictive wins — except for **Service Resource Availability, where an overlap throws an error**.
Every resource must be covered by exactly one Service Resource Availability rule.

Which rule types tolerate overlap:

| Additive — may overlap | Single-coverage — must not |
|---|---|
| Count Rule | Match Skills |
| Extended Match | Match Territory |
| Match Boolean | Maximum Travel from Home |
| Match Fields | Required Resources |
| Match Time | Service Crew Resource Availability |
| | Service Resource Availability |
| | Working Territories |

Do not cover the same resource with both Match Territory and Working Territories.

**No relevance-group support at all:** TimeSlot Designated Work, Service Appointment Visiting Hours
and Work Capacity among rules; Group Nearby and Same Site among objectives.

## Extended Match

The supported no-Apex way to match one appointment field against many resource values — serviceable
postal codes, product lines, anything one-to-many.

It is a junction object with **exactly two Master-Detail relationships**: one to `ServiceResource`,
one to the matched object. The packaged trigger requires exactly two and the rule fails with any
other number. Alongside it you need a Lookup field on `ServiceAppointment` driving the match, and a
reference field on the junction to compare against. Configured at Setup → Field Service Settings →
Scheduling → Work Rules.

## The FSL fields that actually sit on ServiceAppointment

Thirteen package Boolean fields, and these are what trigger and flow code reads and writes around a
scheduling call:

```text
Auto_Schedule__c                Same_Day__c
Emergency__c                    Same_Resource__c
InJeopardy__c                   Schedule_over_lower_priority_appointment__c
IsFillInCandidate__c            UpdatedByOptimization__c
IsMultiDay__c                   Use_Async_Logic__c
Pinned__c                       Virtual_Service_For_Chatter_Action__c
Prevent_Geocoding_For_Chatter_Actions__c
```

Plus five standard Booleans: `IsBundle`, `IsBundleMember`, `IsDeleted`, `IsManuallyBundled`,
`IsOffsiteAppointment`.

`<NS>__Pinned__c`, `<NS>__Auto_Schedule__c`, `<NS>__UpdatedByOptimization__c` and
`<NS>__InJeopardy__c` are the four you will touch most; `UpdatedByOptimization__c` in particular is
how you tell an optimizer write from a human one inside a trigger.

**A fresh FSL install has no custom Boolean fields on `ServiceTerritoryMember` at all** — only the
standard `IsDeleted`. Any STM-scoped relevance group therefore depends on a customer-authored field,
which is a prerequisite to check before designing one.

## Objects the data model section does not list

Standard, and routinely needed: `Shift` (a Master-Detail child of `ServiceResource`),
`TimeSheet` / `TimeSheetEntry`, `ProductConsumed` / `ProductRequired` / `ProductItem`, `Visit`,
`WorkPlan`, `DynamicDataCapture`, and the work-capacity trio `WorkCapacityLimit` /
`WorkCapacityUsage` / `WorkCapacityAvailability` (a prerequisite for the Work Capacity rule).

Package objects: **`<NS>__Resource_Preference__c`** holds the Required and Excluded resource records
on a Work Order or line item — the Required Resources and Excluded Resources rules *enforce* those
records but do not create them, so something else has to. **`<NS>__Time_Dependency__c`** sequences
appointments, through `<NS>__Dependency__c`, `<NS>__Related_Service__c` and
`<NS>__Root_Service_Appointment__c`.

`ServiceAppointmentChangeEvent` exists from API v48.0, alongside `ServiceAppointmentShare` and its
owner sharing rule — relevant if you are streaming appointment changes rather than polling. See
`dya-integration-events`.

## How the optimizer scores

The optimizer minimises a total penalty. Every objective contributes penalties in the same shape:

```text
penaltyPerViolation = max(1, roundingFn((1000 × weight) / scale)) × finalMultiplier
total_penalty       = ceil(violations / granularity) × penaltyPerViolation
```

**Minimize Travel is the anchor** against which the others are calibrated: weight 1000, scale 120
minutes, `round5` rounding, a ×1/60 final multiplier, giving 138.88889 points per second at
whole-second granularity.

Two consequences that decide how you set weights:

- **ASAP weights 1 to 21 are all identical.** Its scale is 43,200 minutes with integer rounding, so
  `round(1000 × 21 / 43200)` is 0, clamped up to 1. Every weight in that band produces exactly
  1 point per minute. Setting ASAP to 15 rather than 5 does nothing at all; you have to cross 21
  before the number moves.
- **Same Site is the exception to the uniform ×1000.** Its final multiplier of ×0.01 nets an
  effective ×10, so deriving its weight by proportion from another objective's gives the wrong
  answer by an order of magnitude.

These formulas come from the package's own behaviour and override the public help documentation
where the two differ. Do not "correct" them against help.salesforce.com.
