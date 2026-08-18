# FSL Apex — Scheduling, Booking, Grading, Optimization (Summer '26, API v67.0)

Load from `dya-field-service`. Real signatures and members for the `FSL` namespace scheduling classes, plus the scope-1 batch pattern. All `FSL.*` is managed-package code — **verify members in a v67 sandbox** (see SKILL.md §8) as they're version-dependent. Prerequisites: Field Service enabled + an FSL permission set on the running user.

## FSL.ScheduleService

```apex
// Schedule a single appointment under a policy. Policy FIRST, appointment SECOND.
global static FSL.ScheduleResult schedule(Id schedulingPolicyId, Id serviceAppointmentId);

// Schedule chains of dependent appointments ("complex work") — synchronous, ES&O.
global static List<FSL.ScheduleResult> scheduleExtended(...);   // confirm params per version

// Why can't this be scheduled?
global static ... getAppointmentInsights(...);                 // confirm signature per version
```

`FSL.ScheduleResult` members (confirmed): `Service` (a `ServiceAppointment` — read `Service.SchedStartTime`, `Service.SchedEndTime`, `Service.Id`). `AssignedResources` and other members exist but confirm names in-sandbox. `schedule` returns `null` when the appointment can't be placed.

```apex
FSL.ScheduleResult res = FSL.ScheduleService.schedule(policyId, saId);
if (res == null) {
    // unschedulable under this policy/horizon
} else {
    System.debug(res.Service.SchedStartTime + ' → ' + res.Service.SchedEndTime);
}
```

## FSL.AppointmentBookingService

```apex
global static List<FSL.AppointmentBookingSlot> GetSlots(
    Id      serviceAppointmentId,
    Id      schedulingPolicyId,
    OperatingHours abOperatingHours,
    System.TimeZone tz,
    String  sortBy,             // 'SORT_BY_GRADE' | 'SORT_BY_DATE'
    Boolean exactAppointments);
```

`FSL.AppointmentBookingSlot` members:
- `Grade` — Double, overall grade of the slot.
- `Interval.Start` / `Interval.Finish` — Datetime arrival-window bounds.
- `BestSlotGrades` — per-objective grade breakdown (confirm member name in-sandbox).

There is an enum `FSL.AppointmentBookingService.SortResultsBy` (value `Grade` confirmed); the by-date option corresponds to the `'SORT_BY_DATE'` string.

```apex
OperatingHours oh = [SELECT Id FROM OperatingHours
                     WHERE Name = 'Gold Appointments Calendar' LIMIT 1 WITH USER_MODE];
Id policyId = [SELECT Id FROM FSL__Scheduling_Policy__c
               WHERE Name = 'Customer First' LIMIT 1 WITH USER_MODE].Id;
TimeZone tz = UserInfo.getTimeZone();

List<FSL.AppointmentBookingSlot> slots =
    FSL.AppointmentBookingService.GetSlots(saId, policyId, oh, tz, 'SORT_BY_DATE', false);

for (FSL.AppointmentBookingSlot s : slots) {
    System.debug(s.Interval.Start + ' .. ' + s.Interval.Finish + '  grade=' + s.Grade);
}
```

Behaviour notes:
- Returns slots **only between the SA's `EarliestStartTime` and `DueDate`** — widen `DueDate` for more windows.
- Returned/expected times are relative to the supplied `TimeZone`. When persisting to `ArrivalWindowStartTime/EndTime`, offset for the operating-hours timezone if it differs (`tz.getOffset(dt)`).

## FSL.GradeSlotsService

```apex
// Powers the "Candidates" global action — graded slots per resource.
global static FSL.AdvancedGapMatrix getGradedMatrix(...);   // confirm params in-sandbox
```

Caveat: `getGradedMatrix` returns **all** possible slots; for a resource free all day it often returns ~2 slots (start of day, and after the break), so some arrival windows can be missing. Prefer `AppointmentBookingService.GetSlots` for customer-facing slot lists.

## FSL.OAAS (optimization)

```apex
// Creates an FSL__Optimization_Request__c and returns its Id.
Id requestId = new FSL.OAAS().optimize(FSL.OAASRequest request);
```

`FSL.OAASRequest` fields (assembled from usage — confirm exact names/types in-sandbox):
- `allTasksMode` (Boolean) — All appointments vs. Unscheduled only.
- `filterFieldAPIName` (String) — Boolean field on ServiceAppointment to scope which SAs optimize.
- `start` / `finish` (Date/Datetime) — horizon.
- `locations` (List<Id>) — service territories.
- `schedulingPolicyID` (Id).

```apex
public class OptimizeTerritoryQueueable implements Queueable, Database.AllowsCallouts {
    private final Id territoryId, policyId;
    public OptimizeTerritoryQueueable(Id t, Id p) { territoryId = t; policyId = p; }
    public void execute(QueueableContext ctx) {
        FSL.OAASRequest req = new FSL.OAASRequest();
        req.allTasksMode       = false;
        req.filterFieldAPIName = 'Include_In_Optimization__c';
        req.start              = System.today().addDays(1);
        req.finish             = System.today().addDays(8);   // 1–7 day horizon best practice
        req.locations          = new List<Id>{ territoryId };
        req.schedulingPolicyID = policyId;
        Id reqId = new FSL.OAAS().optimize(req);
        System.debug('Optimization request ' + reqId);
    }
}
```

Horizon: optimize **1–7 days** ahead (schedules churn); a single request supports up to ~**21 days** out of the box — chain requests (kick the next when the prior `FSL__Optimization_Request__c` finishes) for longer ranges.

## The scope-1 Batch Pattern (full)

See SKILL.md §2 for the full `FsBookingScheduling` + `FsBookingSchedulingBatch` example. The rules it encodes:
- **One SA per call** — backend constraint; run the batch with `Database.executeBatch(batch, 1)`.
- **DML before callout is illegal in one transaction** — set the arrival window (DML) in one method, schedule (callout) in another; the batch `execute` calls them in order.
- **`Database.AllowsCallouts`** on the batch class.
- **User-mode** SOQL/DML (`WITH USER_MODE` / `as user`) at v67.

## Other FSL utilities (developer-relevant)

`FSL.PolygonUtils` (territory-by-geolocation, list polygons), `FSL.Logger`, `FSL.GanttServices`, `FSL.WorkRuleService`, `FSL.GeocodingService`. Treat signatures as version-dependent; confirm against the FSL Apex Namespace index for the installed version.

## Invocable wrappers (Flow / Agentforce)

Open-source libraries expose these as invocable actions for Flow and agent actions: `sfsGetSlotsInvocable`, `sfsGetCandidatesInvocable`, `sfsScheduleInvocable`, `sfsAppointmentInsightsInvocable` (SFS-Utils), and the community Flow Scheduler's Get Slots / Schedule actions (omit the policy Id to use the "Default for Flow Scheduler" policy; the SA needs a Service Territory).

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| `schedule(appointmentId, policyId)` | `schedule(policyId, appointmentId)` |
| Many SAs per sync transaction | scope-1 Batchable |
| DML then callout in one transaction | Split DML step / callout step |
| `getGradedMatrix` for a customer slot list | `AppointmentBookingService.GetSlots` |
| Optimizing 21 days every run | 1–7 day horizon; chain for longer |
| Inline optimization in a trigger | Queueable/Batch with `AllowsCallouts` |
| Trusting member names without checking | Verify in a v67 sandbox |
