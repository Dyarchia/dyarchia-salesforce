---
name: dya-field-service
description: Salesforce Field Service (FSL) developer surface (Summer '26 / API v67.0) — the programmatic side only, with real signatures and compilable code. The FSL Apex namespace (ScheduleService, AppointmentBookingService, GradeSlotsService, OAAS), the scope-1 + DML-before-callout scheduling pattern, the Salesforce Scheduler REST candidates/slots resources and Appointment Bundling REST APIs, the standard + FSL__ data model and ServiceAppointment lifecycle, and Field Service Mobile (LWC Offline, Briefcase). Load only when the user explicitly invokes this skill by name (`dya-field-service`); do NOT auto-trigger on generic Field Service, scheduling, or Salesforce questions.
---

# Salesforce Field Service — Developer Surface

You are an expert Field Service (FSL) developer. This skill covers the **programmatic** surface only, with **real signatures and compilable code** — the `FSL` Apex namespace, the scheduling/booking call pattern, the Salesforce Scheduler REST resources, the data model, and mobile extensibility. Admin/config (work rules, policies in Setup) is out of scope except where code references it. It builds on `dya-apex` and `dya-lwc`. Follow every rule below.

`FSL.*` classes and `FSL__*__c` objects are **managed-package** artifacts and are **version-dependent** — signatures can change across package upgrades; verify against the installed package version (see §8).

References:
- `references/fsl-apex-scheduling.md` — full ScheduleService / AppointmentBookingService / GradeSlotsService / OAAS reference with signatures, result-object members, and the scope-1 batch pattern.
- `references/rest-and-mobile.md` — Salesforce Scheduler REST (candidates/slots), Appointment Bundling REST APIs, and Field Service Mobile (LWC Offline, Briefcase, what works offline).

---

## Platform Context — Summer '26 / API v67.0

- The `FSL` namespace lives in the **Field Service managed package**; the running user needs an **FSL permission set** (FSL Admin/Agent/Dispatcher/Resource as appropriate) and Field Service enabled.
- **Apex v67 hits FSL wrapper code hard.** Once a class is compiled at v67: SOQL/SOSL/DML/`Database.*` default to **user mode**, an omitted sharing keyword defaults to **`with sharing`** (was `without sharing`), and **`WITH SECURITY_ENFORCED` no longer compiles** — replace with `WITH USER_MODE`. Your code querying `FSL__Scheduling_Policy__c`, `OperatingHours`, `ServiceAppointment` is affected; user-mode FLS can hide fields the algorithm needs. Triggers always run in system mode — delegate to handlers. See `dya-apex`.
- **HTTPS / Named Credentials** for the Bundling REST callouts (a Remote Site Setting / Named Credential is required).
- **Mobile** extensibility centers on **LWC Offline** with the `lightning__FieldServiceMobile` target; Apex writes, callouts, triggers, and validation rules do **not** run offline.

---

## 1. The Two Programmatic Layers

| Layer | What | Use |
|---|---|---|
| **`FSL` Apex namespace** (managed package) | `ScheduleService`, `AppointmentBookingService`, `GradeSlotsService`, `OAAS` | In-session scheduling, booking, grading, optimization |
| **Standard data model + REST** | `ServiceAppointment`/`WorkOrder`/… + Salesforce Scheduler REST + Bundling REST | Headless/external booking, bundling, integrations |

The FSL Apex classes run **in-session** (logged-in users, Experience Cloud). For truly external self-service, use the **Salesforce Scheduler REST** candidates/slots resources (§5).

---

## 2. The Non-Negotiable Call Pattern: scope-1 + DML-before-callout

Because of the booking/scheduling backend, **each FSL scheduling call processes a single Service Appointment**, and you **cannot do DML before a callout in the same transaction**. The canonical pattern is a **Batchable executed with scope = 1**, with the booking/DML step and the scheduling/callout step in **separate methods**.

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
- **`GetSlots` only returns slots between the SA's `EarliestStartTime` and `DueDate`** — widen `DueDate` to get more windows.
- Slot times are relative to the supplied `TimeZone`; offset when persisting `ArrivalWindowStartTime/EndTime` if the operating-hours timezone differs.
- **Schedule by changing Status too** — setting a SA's `Status` to a scheduled/none-mapped value schedules/unschedules it, per the FSL Settings life-cycle mapping.

Full members, `GradeSlotsService.getGradedMatrix`, and the `OAASRequest` fields: `references/fsl-apex-scheduling.md`.

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

- **Best-practice horizon: optimize 1–7 days ahead** — schedules change frequently, so longer single passes waste compute.
- A single Optimization Request supports up to ~**21 days** out of the box; **chain** requests (start the next when the prior finishes) for longer horizons.
- Run from a Queueable/Batch with `Database.AllowsCallouts`; never inline in a per-save trigger.

---

## 5. External / Headless Booking — Salesforce Scheduler REST

For customer self-service outside Salesforce, use the **Salesforce Scheduler** REST resources (a distinct product surface that shares objects with FSL — confirm licensing):

- **Get Appointment Candidates** — resources available for a work-type-group/work-type + territories.
- **Get Appointment Slots** — available time slots for a resource.
- **Available Territory Slots** (Connect `available-territory-slots`, POST) — consolidated availability per resource in a territory.

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
        .setApiVersion(67.0)
        .build();
String response = lxscheduler.SchedulerResources.getAppointmentCandidates(input);
```

Headless flow: **get candidates/slots → create WorkOrder + ServiceAppointment only when the customer picks a slot → commit** (Scheduler save / `FSL.ScheduleService`). Use `resourceLimitApptDistribution` to cap evaluated resources when a territory exceeds ~20. Full payloads + Appointment Bundling REST: `references/rest-and-mobile.md`.

---

## 6. Data Model — What You Build Against

**Standard objects:** `ServiceAppointment` (the schedulable unit; `ParentRecordId`, `ServiceTerritoryId`, `SchedStartTime/EndTime`, `ArrivalWindowStartTime/EndTime`, `EarliestStartTime`, `DueDate`, `Duration`, `Status`, `IsBundle`/`IsBundleMember`), `WorkOrder`/`WorkOrderLineItem`, `ServiceResource` (+`Skill`/`Capacity`/`ResourceAbsence`/`ServiceCrew`/`AssignedResource`), `ServiceTerritory`/`ServiceTerritoryMember`, `OperatingHours`/`TimeSlot`, `WorkType`/`WorkTypeGroup`, `SkillRequirement`, `ApptBundlePolicy`.

**FSL managed-package custom objects:** `FSL__Scheduling_Policy__c`, `FSL__Work_Rule__c`, `FSL__Service_Goal__c` (service objectives), `FSL__Optimization_Request__c`, `FSL__Polygon__c`.

**ServiceAppointment lifecycle (default, customizable):** `None → Scheduled → Dispatched → In Progress → Completed`, with `Cannot Complete` / `Canceled` as exceptions. Scheduling keys off the status-category mapping in FSL Settings, not the literal label.

Policies/objectives are referenced **by Id** (query by Name): `[SELECT Id FROM FSL__Scheduling_Policy__c WHERE Name = 'Customer First']`. There is **no supported "write a Work Rule in Apex" SPI** — custom matching is done with triggers/flows (e.g. the "Skill Iron Rule" pattern) or custom Gantt actions (LWC/VF) in the Dispatcher Console.

---

## 7. Field Service Mobile

- **Custom LWC** run with target `lightning__FieldServiceMobile`; developers/users need the **Lightning SDK for Field Service Mobile** permission. **LWC Offline** (opt-in) reads/updates locally and syncs on reconnect.
- **Works offline:** LDS base components, `getRecord`/LDS, the GraphQL wire (`lightning/uiGraphQLApi`), related-list wires, and Apex *reads* of data cached while online.
- **Does NOT work offline:** Apex *writes*, server-hitting Apex calls, triggers/validation/flows (run only on sync), and Lightning Message Service. Keep GraphQL queries small (>32 KB hurts mobile). Apex errors arrive as an **array** of error objects.
- **Briefcase Builder** primes offline data sets (object + filter); Files and Custom Metadata aren't primed automatically. Deep links can be **signed** with the Public Security Key to suppress the security dialog.

Full offline matrix and Bundling REST: `references/rest-and-mobile.md`.

---

## 8. Verify Before You Ship (managed-package versioning)

Because `FSL.*` is managed-package code, **confirm signatures in a v67 sandbox** before production: run anonymous Apex calling `schedule`, `GetSlots`, `getGradedMatrix`, and `OAAS.optimize` against seeded data and `System.debug` the result objects to lock down members for **your installed package version**. Re-verify if the package version differs from where you tested.

---

## 9. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Looping `schedule()`/`GetSlots()` over many SAs in one sync transaction | scope-1 Batchable, async |
| DML before the scheduling callout in the same transaction | Separate DML step then callout step |
| `FSL.ScheduleService.schedule(appointmentId, policyId)` (wrong order) | `schedule(policyId, appointmentId)` — policy first |
| Inline scheduling/optimization in a per-save trigger | Queueable/Batch with `AllowsCallouts` |
| `WITH SECURITY_ENFORCED` in FSL wrapper code | `WITH USER_MODE` (removed at v67) |
| FSL wrapper class with no sharing keyword at v67 | Explicit `with sharing` + `WITH USER_MODE` |
| Hard-coded policy/territory Ids | Query by Name / Custom Metadata |
| Creating throwaway SAs per quote for external booking | Scheduler REST candidates/slots; persist SA on selection |
| Optimizing a 21-day window every run | Optimize 1–7 days; chain for longer |
| Assuming Apex writes/triggers run offline on mobile | Offline-first; reconcile on sync |
| Guessing `FSL` member names | Verify in a v67 sandbox (§8) |

---

## Summary — The Five Commandments

1. **scope-1 + DML-before-callout** — batch with scope 1, set the arrival window (DML) then schedule (callout) in separate steps.
2. **Signatures are real and order matters** — `schedule(policyId, appointmentId)`, `GetSlots(saId, policyId, oh, tz, sortBy, exact)`; widen `DueDate` for more slots.
3. **Heavy work is async; optimize 1–7 days** — Queueable/Batch with `AllowsCallouts`; chain Optimization Requests past ~21 days.
4. **External booking via Salesforce Scheduler REST** — candidates/slots, persist the SA only on slot selection.
5. **v67 + managed package = verify** — explicit `with sharing` + `WITH USER_MODE`, confirm `FSL` members in a sandbox; mobile is offline-first.
