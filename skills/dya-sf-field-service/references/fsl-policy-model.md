# The Scheduling Policy Model and the Optimizer's Arithmetic

What a scheduling policy is made of, how work rules and objectives attach to it, and how the
optimizer turns a weight into a number. For building or reading a policy rather than calling
`schedule` or `GetSlots` — the Apex surface is in `references/fsl-apex-scheduling.md`.

`<NS>` is the resolved package namespace: `FSL` in production, `FSLQA` / `FSLMPTEST` / `FSLMPPERF`
elsewhere. Resolve it rather than hardcoding, per SKILL.md §6.

## The object graph

A policy does not contain its rules and objectives; two junction objects join them. Their shape lets
you read a policy from Apex or a query rather than the Setup UI.

| Junction | Joins | Notes |
|---|---|---|
| `<NS>__Scheduling_Policy_Work_Rule__c` | `Scheduling_Policy__c` ↔ `Work_Rule__c` | Membership only |
| `<NS>__Scheduling_Policy_Goal__c` | `Scheduling_Policy__c` ↔ `Service_Goal__c` | Carries **`Weight__c`** |

`Weight__c` is a `double` with precision 9, **scale 0** — whole numbers only, schema-enforced — and
`nillable=false`. Given the penalty arithmetic below: fractional weights are not merely discouraged,
they cannot be stored.

Reading a policy's rules:

```sql
SELECT Name,
       <NS>__Work_Rule__r.Name,
       <NS>__Work_Rule__r.RecordType.DeveloperName
FROM   <NS>__Scheduling_Policy_Work_Rule__c
WHERE  <NS>__Scheduling_Policy__c = :policyId
```

## Type is a RecordType, not a field

**There is no `Type__c` on `Service_Goal__c`** or `Work_Rule__c`. The kind of objective or rule is
its **RecordType DeveloperName**. Filtering on a type field will not compile; filtering on a label
breaks under translation.

The ten active objective RecordTypes:

```text
Objective_Asap                  Objective_Minimize_Gaps
Objective_Minimize_Travel       Objective_Minimize_Overtime
Objective_Same_Site             Objective_PreferredEngineer
Objective_Skill_Level           Objective_Resource_Priority
Objective_Skill_Preferences     Objective_Custom_Logic
```

### Configuration fields on `Service_Goal__c`

Meaning depends on the RecordType:

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

It does **not** create `Service Resource Availability`, mandatory on every policy — the most common
cause of a policy that schedules nothing and reports no useful error.

Shipped starter policies: `Customer First`, `High Intensity`, `Soft Boundaries`, `Emergency`.

On an ESO-enabled org the same starters are queried natively:

```sql
SELECT Id, MasterLabel, DeveloperName, SchedulingCategory FROM SchedulingPolicy
```

## Database rules versus Apex rules — the latency lever

Work rules run in two engines; the choice is a policy's biggest performance decision:

- **Database rules** filter at the SOQL level, aggregated into one query, so their cost is roughly
  constant regardless of how many resources the org has.
- **Apex rules** run *after* that query over **every candidate it returned**; cost is linear in the
  candidate pool.

So: **every policy needs at least one database rule, narrowing to roughly 20 candidates before any
Apex rule or objective runs.** A pure-Apex-rule policy evaluates custom logic against the whole
resource population on every `GetSlots` and `getAppointmentCandidates` call — usually what a "Field
Service is slow" report turns out to be.

Hard caps:

- **Match Boolean: maximum 5 per policy.**
- **Count Rule: up to 10 custom-field rules per policy.** Time resolution is always Daily; it always
  counts `ServiceAppointment`.

## Relevance groups

A relevance group scopes a rule to a subset of work or resources via a **Boolean field**: on
`ServiceAppointment` for work, on `ServiceTerritoryMember` for resources. STM supports **primary and relocation memberships only, not secondary**.

**Groups must be mutually exclusive.** Where two relevance-grouped rules overlap the more
restrictive wins — except for **Service Resource Availability, where an overlap throws an error**.
Every resource must be covered by exactly one Service Resource Availability rule.

Overlap tolerance by rule type:

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

A junction object with **exactly two Master-Detail relationships**: to `ServiceResource` and to the
matched object; the packaged trigger fails the rule with any other number. It also needs a Lookup
field on `ServiceAppointment` driving the match and a reference field on the junction to compare
against. Configured at Setup → Field Service Settings → Scheduling → Work Rules.

## The FSL fields that actually sit on ServiceAppointment

Thirteen package Boolean fields, read and written by trigger and flow code around a scheduling call:

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
`<NS>__InJeopardy__c` are touched most; `UpdatedByOptimization__c` tells an optimizer write from a
human one inside a trigger.

**A fresh FSL install has no custom Boolean fields on `ServiceTerritoryMember`** — only the standard
`IsDeleted`. An STM-scoped relevance group therefore depends on a customer-authored field; check for
it before designing one.

## Objects the data model section does not list

Standard, and routinely needed: `Shift` (a Master-Detail child of `ServiceResource`),
`TimeSheet` / `TimeSheetEntry`, `ProductConsumed` / `ProductRequired` / `ProductItem`, `Visit`,
`WorkPlan`, `DynamicDataCapture`, and the work-capacity trio `WorkCapacityLimit` /
`WorkCapacityUsage` / `WorkCapacityAvailability` (a prerequisite for the Work Capacity rule).

Package objects: **`<NS>__Resource_Preference__c`** holds the Required and Excluded resource records
on a Work Order or line item — the Required Resources and Excluded Resources rules *enforce* those
records but do not create them. **`<NS>__Time_Dependency__c`** sequences
appointments, through `<NS>__Dependency__c`, `<NS>__Related_Service__c` and
`<NS>__Root_Service_Appointment__c`.

`ServiceAppointmentChangeEvent` exists from API v48.0, alongside `ServiceAppointmentShare` and its
owner sharing rule — relevant when streaming appointment changes rather than polling. See
`dya-sf-integration-events`.

## How the optimizer scores

The optimizer minimises total penalty. Every objective contributes penalties in the same shape:

```text
penaltyPerViolation = max(1, roundingFn((1000 × weight) / scale)) × finalMultiplier
total_penalty       = ceil(violations / granularity) × penaltyPerViolation
```

**Minimize Travel is the calibration anchor**: weight 1000, scale 120
minutes, `round5` rounding, a ×1/60 final multiplier, giving 138.88889 points per second at
whole-second granularity.

Two consequences for setting weights:

- **ASAP weights 1 to 21 are all identical.** Its scale is 43,200 minutes with integer rounding, so
  `round(1000 × 21 / 43200)` is 0, clamped up to 1: exactly 1 point per minute across the band.
  Setting ASAP to 15 rather than 5 does nothing; the number moves only past 21.
- **Same Site is the exception to the uniform ×1000.** Its ×0.01 final multiplier nets an effective
  ×10, so deriving its weight proportionally from another objective's is off by an order of
  magnitude.

These formulas come from the package's own behaviour and override the public help where they differ.
Do not "correct" them against help.salesforce.com.
