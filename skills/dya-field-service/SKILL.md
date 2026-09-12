---
name: dya-field-service
description: Salesforce Field Service (FSL) developer surface (Winter '27 / API v68.0) — the programmatic side only, with real signatures and compilable code. The FSL Apex namespace (ScheduleService, AppointmentBookingService, GradeSlotsService, OAAS), the scope-1 + DML-before-callout scheduling pattern, the Salesforce Scheduler REST candidates/slots resources and Appointment Bundling REST APIs, the standard + FSL__ data model and ServiceAppointment lifecycle, and Field Service Mobile (LWC Offline, Briefcase). Load only when the user explicitly invokes this skill by name (`dya-field-service`); do NOT auto-trigger on generic Field Service, scheduling, or Salesforce questions.
---

# Salesforce Field Service — Developer Surface

You are an expert Field Service (FSL) developer. This skill covers the **programmatic** surface only,
with **real signatures and compilable code**: the `FSL` Apex namespace, the scheduling and booking
call pattern, the Salesforce Scheduler REST resources, the data model, and mobile extensibility.
Admin and config — work rules and policies in Setup — are out of scope except where code references
them. It builds on `dya-apex` and `dya-lwc`. Follow every rule below.

`FSL.*` classes and `FSL__*__c` objects are **managed-package** artifacts and **version-dependent**:
signatures can change across package upgrades, so verify against the installed version (§8).

References:
- `references/shared/platform-deltas.md` — the release-coupled facts, including the raised heap limits a scheduling call runs inside.
- `references/shared/sharing-and-access.md` — the permission model behind the FSL permission sets and user-mode enforcement.
- `references/shared/governor-limits.md` — the transaction budget the scope-1 batch pattern exists to respect.
- `references/fsl-apex-scheduling.md` — full ScheduleService / AppointmentBookingService / GradeSlotsService / OAAS reference with signatures, result-object members, and the scope-1 batch pattern.
- `references/rest-and-mobile.md` — Salesforce Scheduler REST (candidates/slots), Appointment Bundling REST APIs, and Field Service Mobile (LWC Offline, Briefcase, what works offline).
- `references/fsl-policy-model.md` — what a scheduling policy is made of: the junction objects, RecordType-based typing, relevance groups, database-versus-Apex rule engines, and the optimizer's penalty arithmetic.
- `references/mobile-data-capture.md` — Data Capture flows and their Tooling deployment, the `dc*` component namespace, `DynamicDataCapture`, the sharing trap that blanks the Forms tab, and the two mobile configuration sObjects.

---

## Platform Context — Winter '27 / API v68.0

Winter '27 improves Field Service operationally and on mobile, with **no change to the FSL Apex
namespace, the scheduling service signatures, or the Scheduler and Bundling REST resources** below.
What changes is the budget your wrapper code runs in: Apex heap rises to 10 MB synchronous and 25 MB
asynchronous, which matters when a scheduling call holds a large candidate set. See
`references/shared/governor-limits.md`.

- The `FSL` namespace lives in the **Field Service managed package**. The running user needs an
  **FSL permission set** — Admin, Agent, Dispatcher or Resource — and Field Service enabled.
- **The API 67.0 security defaults hit FSL wrapper code hard.** Compiled at 67.0 or above, SOQL,
  SOSL, DML and `Database.*` default to **user mode**, an omitted sharing keyword becomes
  **`with sharing`**, and **`WITH SECURITY_ENFORCED` no longer compiles** — replace it with
  `WITH USER_MODE`. Code querying `FSL__Scheduling_Policy__c`, `OperatingHours` or
  `ServiceAppointment` is affected, and user-mode FLS can hide fields the algorithm needs. Triggers
  always run in system mode, so delegate to handlers. See `dya-apex`.
- **HTTPS and Named Credentials** for the Bundling REST callouts; a Remote Site Setting or Named
  Credential is required.
- **Mobile** extensibility centres on **LWC Offline** with the `lightning__FieldServiceMobile`
  target. Apex writes, callouts, triggers and validation rules do **not** run offline.

---

## 1. The Two Programmatic Layers

| Layer | What | Use |
|---|---|---|
| **`FSL` Apex namespace** (managed package) | `ScheduleService`, `AppointmentBookingService`, `GradeSlotsService`, `OAAS` | In-session scheduling, booking, grading, optimization |
| **Standard data model + REST** | `ServiceAppointment`/`WorkOrder`/… + Salesforce Scheduler REST + Bundling REST | Headless/external booking, bundling, integrations |

The FSL Apex classes run **in-session**, for logged-in users and Experience Cloud. Truly external
self-service uses the **Salesforce Scheduler REST** candidates and slots resources (§5).

---

## 2. The Non-Negotiable Call Pattern: scope-1 + DML-before-callout

The booking backend processes **a single Service Appointment per FSL scheduling call**, and no DML
may precede a callout in the same transaction. The canonical pattern is a **Batchable executed with
scope = 1**, with the booking/DML step and the scheduling/callout step in **separate methods**.

```apex
public with sharing class FsBookingScheduling {

    // STEP 1 — set the arrival window from booking slots (DML; no callout here)
    public static void setArrivalWindow(List<ServiceAppointment> sas) {
        Id policyId = [SELECT Id FROM FSL__Scheduling_Policy__c
                       WHERE Name = 'Customer First' LIMIT 1 WITH USER_MODE].Id;
        OperatingHours oh = [SELECT Id FROM OperatingHours
                             WHERE Name = 'Gold Appointments Calendar' LIMIT 1 WITH USER_MODE];
        TimeZone tz = UserInfo.getTimeZone();

        for (ServiceAppointment sa : sas) {
            List<FSL.AppointmentBookingSlot> slots =
                FSL.AppointmentBookingService.GetSlots(sa.Id, policyId, oh, tz, 'SORT_BY_GRADE', false);
            if (!slots.isEmpty()) {
                sa.ArrivalWindowStartTime = slots[0].Interval.Start;
                sa.ArrivalWindowEndTime   = slots[0].Interval.Finish;
            }
        }
        update as user sas;   // user-mode DML
    }

    // STEP 2 — commit scheduling (THIS is the callout; runs after Step 1's DML)
    public static void schedule(List<ServiceAppointment> sas) {
        Id policyId = [SELECT Id FROM FSL__Scheduling_Policy__c
                       WHERE Name = 'Customer First' LIMIT 1 WITH USER_MODE].Id;
        for (ServiceAppointment sa : sas) {
            FSL.ScheduleResult res = FSL.ScheduleService.schedule(policyId, sa.Id);  // policy FIRST
            if (res != null) {
                System.debug('Scheduled ' + sa.Id + ' at ' + res.Service.SchedStartTime);
            }
        }
    }
}
```

```apex
public class FsBookingSchedulingBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    private final List<ServiceAppointment> sas;
    public FsBookingSchedulingBatch(List<ServiceAppointment> sas) { this.sas = sas; }
    public List<ServiceAppointment> start(Database.BatchableContext bc) { return sas; }
    public void execute(Database.BatchableContext bc, List<ServiceAppointment> scope) {
        FsBookingScheduling.setArrivalWindow(scope);   // DML step
        FsBookingScheduling.schedule(scope);           // callout step
    }
    public void finish(Database.BatchableContext bc) {}
}
// MUST run with scope = 1:
// Database.executeBatch(new FsBookingSchedulingBatch(appointments), 1);
```

---

## 3. FSL Apex — The Signatures You'll Use

```apex
// Schedule one appointment under a policy. NOTE: policy first, appointment second.
FSL.ScheduleResult FSL.ScheduleService.schedule(Id schedulingPolicyId, Id serviceAppointmentId);
// → null if unschedulable; result.Service is a ServiceAppointment (SchedStartTime/SchedEndTime)

// Get bookable, graded slots for an appointment.
List<FSL.AppointmentBookingSlot> FSL.AppointmentBookingService.GetSlots(
    Id serviceAppointmentId, Id schedulingPolicyId,
    OperatingHours abOperatingHours, System.TimeZone tz,
    String sortBy,            // 'SORT_BY_GRADE' | 'SORT_BY_DATE'
    Boolean exactAppointments);
// slot.Grade (number), slot.Interval.Start / slot.Interval.Finish (Datetime)

// Trigger optimization — creates an FSL__Optimization_Request__c and returns its Id.
Id new FSL.OAAS().optimize(FSL.OAASRequest request);
```

Key behaviours:
- **`GetSlots` only returns slots between the SA's `EarliestStartTime` and `DueDate`.** Widen
  `DueDate` to get more windows.
- Slot times are relative to the supplied `TimeZone`; offset when persisting
  `ArrivalWindowStartTime/EndTime` if the operating-hours timezone differs.
- **Status changes schedule too.** Setting a SA's `Status` to a scheduled or none-mapped value
  schedules or unschedules it, per the FSL Settings life-cycle mapping.
- **Latency is decided by the policy, not the call.** Work rules run in two engines: database rules
  filter inside the SOQL query, while Apex rules run afterwards and iterate over **every candidate
  that query returned**. A policy therefore needs at least one database rule, narrowing to roughly
  **20 candidates** before any Apex rule or objective runs. A policy of pure Apex rules is what
  "Field Service is slow" usually turns out to be. See `references/fsl-policy-model.md`.

Full members, `GradeSlotsService.getGradedMatrix` and the `OAASRequest` fields:
`references/fsl-apex-scheduling.md`.

---

## 4. Optimization (`FSL.OAAS`)

```apex
FSL.OAASRequest req = new FSL.OAASRequest();
req.allTasksMode       = false;                          // All vs. Unscheduled only
req.filterFieldAPIName = 'Include_In_Optimization__c';   // Boolean field on ServiceAppointment
req.start              = System.today().addDays(1);
req.finish             = System.today().addDays(8);
req.locations          = new List<Id>{ territoryId };
req.schedulingPolicyID = policyId;

Id optimizationRequestId = new FSL.OAAS().optimize(req);  // run from async (AllowsCallouts)
```

- **Optimize 1–7 days ahead.** Schedules change frequently, so longer single passes waste compute.
- **In-Day is time-boxed; Global is not.** In-Day Optimization is capped at **5 minutes with ESO,
  10 minutes without**, and reshuffles today; a Global run works the full horizon and takes hours.
  Widening one request is a cost decision rather than a limit to discover — **chain** requests,
  starting the next when the prior finishes.
- **Commit Mode decides whether your DML survives.** `Always Commit` lets a dispatcher change, or
  your Apex `update` on a `ServiceAppointment`, land while an optimization runs; `Rollback` rejects
  it to protect the run. Writes silently disappearing during an optimization window are this.
- Run from a Queueable or Batch with `Database.AllowsCallouts`, never inline in a per-save trigger.

---

## 5. External / Headless Booking — Salesforce Scheduler REST

Customer self-service outside Salesforce uses the **Salesforce Scheduler** REST resources, a distinct
product surface sharing objects with FSL — confirm licensing:

- **Get Appointment Candidates** — resources available for a work-type-group/work-type + territories.
- **Get Appointment Slots** — available time slots for a resource.
- **Available Territory Slots** (Connect `available-territory-slots`, POST) — consolidated
  availability per resource in a territory.

```apex
// In-session Apex builder (no separate REST auth needed)
lxscheduler.GetAppointmentCandidatesInput input =
    new lxscheduler.GetAppointmentCandidatesInputBuilder()
        .setWorkTypeGroupId(workTypeGroupId)
        .setTerritoryIds(new List<String>{ territoryId })
        .setStartTime(startDt.format('yyyy-MM-dd\'T\'HH:mm:ssZ'))
        .setEndTime(startDt.addDays(3).format('yyyy-MM-dd\'T\'HH:mm:ssZ'))
        .setAccountId(accountId)
        .setSchedulingPolicyId(policyId)
        .setApiVersion(68.0)
        .build();
String response = lxscheduler.SchedulerResources.getAppointmentCandidates(input);
```

Headless flow: **get candidates/slots → create WorkOrder + ServiceAppointment only when the customer
picks a slot → commit**, through the Scheduler save or `FSL.ScheduleService`. Use
`resourceLimitApptDistribution` to cap evaluated resources when a territory exceeds ~20. Full
payloads and Appointment Bundling REST: `references/rest-and-mobile.md`.

---

## 6. Data Model — What You Build Against

**Standard objects:** `ServiceAppointment` (the schedulable unit; `ParentRecordId`,
`ServiceTerritoryId`, `SchedStartTime/EndTime`, `ArrivalWindowStartTime/EndTime`,
`EarliestStartTime`, `DueDate`, `Duration`, `Status`, `IsBundle`/`IsBundleMember`),
`WorkOrder`/`WorkOrderLineItem`, `ServiceResource` (+`Skill`/`Capacity`/`ResourceAbsence`/
`ServiceCrew`/`AssignedResource`), `ServiceTerritory`/`ServiceTerritoryMember`,
`OperatingHours`/`TimeSlot`, `WorkType`/`WorkTypeGroup`, `SkillRequirement`, `ApptBundlePolicy`.

**FSL managed-package custom objects:** `FSL__Scheduling_Policy__c`, `FSL__Work_Rule__c`,
`FSL__Service_Goal__c` (service objectives), `FSL__Optimization_Request__c`, `FSL__Polygon__c`.

Four `ServiceAppointment` facts constrain a booking design. **`ParentRecordId` is create-only** and
polymorphic over Account, Asset, Lead, Opportunity, WorkOrder and WorkOrderLineItem, so §5's headless
flow must know the parent before it commits. **`DurationType`** — Minutes or Hours — governs what
`Duration` means. **`StatusCategory`** is a restricted picklist and the concrete mechanism behind the
status mapping below, so a custom Status must declare its category. Bundling carries
`BundlePolicyId` and `RelatedBundleId`, not only `IsBundle` and `IsBundleMember`.

**ServiceAppointment lifecycle (default, customizable):**
`None → Scheduled → Dispatched → In Progress → Completed`, with `Cannot Complete` and `Canceled` as
exceptions. Scheduling keys off the status-category mapping in FSL Settings, not the literal label.

**`FSL__` is not a constant — resolve it.** The prefix is `FSL` in a production org but `FSLQA`,
`FSLMPTEST` or `FSLMPPERF` elsewhere, and an org on **Enhanced Scheduling and Optimization (ESO)**
exposes native objects instead: `SchedulingPolicy`, `SchedulingConstraint`, `SchedulingRule`,
`SchedulingObjective` and `SchedulingPolicyObjective`. Query
`SELECT SubscriberPackage.NamespacePrefix, SubscriberPackage.Name FROM InstalledSubscriberPackage` on
the Tooling API **with no `WHERE` clause** — it rejects filters on `NamespacePrefix` — and filter
client-side for the first prefix starting with `FSL`. An empty result means FSL is not installed.
Then try the managed object and fall back to the native one on `INVALID_TYPE`.

Policies and objectives are referenced **by Id**, queried by Name:
`[SELECT Id FROM FSL__Scheduling_Policy__c WHERE Name = 'Customer First']` — which throws
`INVALID_TYPE` on an ESO-native org, so resolve first.

There is **no supported "write a Work Rule in Apex" SPI**, but four declarative hooks come before any
Apex: **Extended Match** (a junction object with *exactly two* Master-Detail relationships, to
`ServiceResource` and the matched object — the packaged trigger fails the rule with any other
number), **Match Fields** (any appointment field against any resource field), **Match Boolean** (any
resource checkbox, max 5 per policy) and **Count Rule** with `countBy: Custom`. Reach for triggers,
flows (the "Skill Iron Rule" pattern) or custom Gantt actions only once those are exhausted.

---

## 7. Field Service Mobile

- **Licensing first.** Every mobile worker needs the **`FieldServiceMobilePsl`** permission set
  licence to log into the app at all. There is no separate mobile user-licence SKU, and this is the
  entitlement people miss. `EinsteinFieldServicePsl` adds Voice to Record Edit and Pre-Work Brief;
  `AgentforceForFieldServicePsl` adds Voice to Form. Confirm with
  `SELECT DeveloperName, TotalLicenses, UsedLicenses FROM PermissionSetLicense`. The **Lightning SDK
  for Field Service Mobile** permission is a separate thing: it gates custom LWC, not login.
- **Custom LWC** run with target `lightning__FieldServiceMobile`. **LWC Offline**, opt-in, reads and
  updates locally and syncs on reconnect.
- **Works offline:** LDS base components, `getRecord`/LDS, the GraphQL wire
  (`lightning/uiGraphQLApi`), related-list wires, and Apex *reads* of data cached while online.
- **Does NOT work offline:** Apex *writes*, server-hitting Apex calls, **record-triggered**
  automation — triggers, validation rules, workflow and record-triggered flows all fire at sync, not
  on the device — and Lightning Message Service. **Screen flows are the exception**: they run offline
  under an offline flow cache policy, and a Data Capture flow (`processType: DataCaptureFlow`,
  `environments: ["Offline"]`) is built to. Keep GraphQL queries small — over 32 KB hurts mobile.
  Apex errors arrive as an **array** of error objects.
- **Briefcase Builder** primes offline data sets by object and filter; Files and Custom Metadata are
  not primed automatically. Deep links can be **signed** with the Public Security Key to suppress the
  security dialog.
- **An empty Forms tab is usually a sharing problem, not a data one.** The tab reads through the UI
  API, which enforces sharing, so a Private OWD on `DynamicDataCapture` or `WorkPlan` — the platform
  default — returns `INSUFFICIENT_ACCESS` and the app shows "No forms available". Desktop SOQL as an
  admin will not reproduce it, and the app caches its sharing snapshot at login, so the technician
  must sign out and back in after the fix.
- **Pre-Work Brief activation cannot be driven from Apex.** The prompt-template activation endpoint
  is `@ConnectHidden(from=Apex)`, so `ConnectApi.EinsteinLLM` and metadata approaches both fail by
  design. Drive it from the CLI or an external caller.

Full offline matrix and Bundling REST: `references/rest-and-mobile.md`. Data Capture flows, the `dc*`
components and the mobile settings objects: `references/mobile-data-capture.md`.

---

## 8. Verify Before You Ship (managed-package versioning)

`FSL.*` is managed-package code, so **confirm signatures in a sandbox** before production: run
anonymous Apex calling `schedule`, `GetSlots`, `getGradedMatrix` and `OAAS.optimize` against seeded
data, and `System.debug` the result objects to lock down members for **your installed package
version**. Re-verify whenever the package version differs from where you tested.

---

## 9. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Looping `schedule()`/`GetSlots()` over many SAs in one sync transaction | scope-1 Batchable, async |
| DML before the scheduling callout in the same transaction | Separate DML step then callout step |
| `FSL.ScheduleService.schedule(appointmentId, policyId)` (wrong order) | `schedule(policyId, appointmentId)` — policy first |
| Inline scheduling/optimization in a per-save trigger | Queueable/Batch with `AllowsCallouts` |
| `WITH SECURITY_ENFORCED` in FSL wrapper code | `WITH USER_MODE` (removed from API 67.0) |
| An FSL wrapper class with no sharing keyword | Explicit `with sharing` + `WITH USER_MODE` |
| Hard-coded policy/territory Ids | Query by Name / Custom Metadata |
| Creating throwaway SAs per quote for external booking | Scheduler REST candidates/slots; persist SA on selection |
| Optimizing a 21-day window every run | Optimize 1–7 days; chain for longer |
| Assuming Apex writes/triggers run offline on mobile | Offline-first; reconcile on sync |
| Guessing `FSL` member names | Verify in a sandbox (§8) |

---

## Summary — The Five Commandments

1. **scope-1 + DML-before-callout** — batch with scope 1, set the arrival window (DML) then schedule (callout) in separate steps.
2. **Signatures are real and order matters** — `schedule(policyId, appointmentId)`, `GetSlots(saId, policyId, oh, tz, sortBy, exact)`; widen `DueDate` for more slots.
3. **Heavy work is async; optimize 1–7 days** — Queueable/Batch with `AllowsCallouts`; chain Optimization Requests for longer horizons.
4. **External booking via Salesforce Scheduler REST** — candidates/slots, persist the SA only on slot selection.
5. **User mode plus a managed package means verify** — explicit `with sharing` + `WITH USER_MODE`, confirm `FSL` members in a sandbox; mobile is offline-first.
