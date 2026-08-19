# Field Service — Scheduler REST, Bundling REST & Mobile (Summer '26, API v67.0)

Load from `dya-field-service` for external/headless booking, appointment bundling, and mobile extensibility.

## Salesforce Scheduler REST — Candidates & Slots

For external customer self-service, use the **Salesforce Scheduler** REST resources (a distinct product surface sharing objects with FSL — confirm licensing). Three core operations:

| Operation | Returns |
|---|---|
| **Get Appointment Candidates** | Service resources available for a work-type-group/work-type + territories |
| **Get Appointment Slots** | Available time slots for a resource |
| **Available Territory Slots** (`available-territory-slots`, POST Connect) | Consolidated per-resource availability in a territory |

`getAppointmentCandidates` response shape (illustrative — values are shape, not current data):

```json
{
  "candidates": [
    {
      "startTime":   "2026-01-23T16:15:00.000+0000",
      "endTime":     "2026-01-23T19:15:00.000+0000",
      "resources":   ["0HnB0000000D2DsKAK"],
      "territoryId": "0HhB0000000TO9WKAW"
    }
  ]
}
```

In-session Apex builder (no separate REST auth):

```apex
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

Performance: `resourceLimitApptDistribution` (on `getAppointmentCandidates` and `available-territory-slots`) caps how many resources' calendars are evaluated — set it when a territory exceeds ~20 resources.

**Headless booking flow:** (1) call candidates/slots to show windows; (2) create `WorkOrder` + `ServiceAppointment` (Work Type, `EarliestStartTime`, `DueDate`) **only when the customer selects a slot**; (3) commit via the Scheduler save action or `FSL.ScheduleService.schedule`. Don't create throwaway SAs per quote.

## Appointment Bundling REST APIs

Six operations: **Automatic Bundling, Create Bundle, Remove Bundle Members, Unbundle, Unbundle Multiple, Update Bundle** (available in API v54.0+; not supported in Gov Cloud). Create Bundle takes service-appointment Ids + a manual bundling policy Id (`ApptBundlePolicy` marked for manual bundling) and returns the **bundle service appointment Id**. Bundling callouts need a Remote Site Setting/Named Credential and the Field Service bundling permission sets (Admin, Bundle for Dispatcher, Integration). Confirm the literal resource paths/HTTP methods against the six official sub-pages for your version.

Convenience wrapper (open-source `sfsAppointmentBundlingAPI`):

```apex
// Automatic bundling
sfsAppointmentBundlingAPI api =
    new sfsAppointmentBundlingAPI(sfsAppointmentBundlingAPI.BundlingAction.AUTOMATIC_BUNDLING);
sfsAppointmentBundlingAPI.automaticBundlingResponse res =
    (sfsAppointmentBundlingAPI.automaticBundlingResponse) api.run();

// Create a bundle from selected SAs
Id policyId = [SELECT Id FROM ApptBundlePolicy WHERE Name = 'Appointment Bundle Policy CDO'].Id;
sfsAppointmentBundlingAPI bApi = new sfsAppointmentBundlingAPI(
    sfsAppointmentBundlingAPI.BundlingAction.BUNDLE, policyId, new List<Id>{ /* SA Ids */ });
sfsAppointmentBundlingAPI.bundleResponse bRes = (sfsAppointmentBundlingAPI.bundleResponse) bApi.run();
```

On the SA, `IsBundle` marks the bundle header and `IsBundleMember` marks members.

## Field Service Mobile — Offline-First Extensibility

Custom LWC run with target **`lightning__FieldServiceMobile`**; developers/users need the **Lightning SDK for Field Service Mobile** permission (create a permission set granting it). **LWC Offline** is opt-in.

### What works offline vs. not

| Works offline | Does NOT work offline |
|---|---|
| LDS base components; `getRecord` / LDS | Apex **writes** (DML via Apex) |
| GraphQL wire (`lightning/uiGraphQLApi`) | Server-hitting Apex calls (`@wire`/imperative) |
| `getRelatedListRecords` / `getRelatedListCount`* | Triggers, validation rules, workflow, flows (run only on **sync**) |
| Apex **reads** of data cached while online | `getListUi` / `getRecordUi` (limited/deprecated) |
| | Lightning Message Service |

\* Related-list wires won't reflect records created/deleted while offline.

Constraints & gotchas:
- Keep **GraphQL queries small** — >32 KB or many fields hurts mobile; lint with `@salesforce/eslint-plugin-lwc-mobile`.
- Apex error responses on mobile are returned as an **array** of error objects, not a single object — handle accordingly.
- **Design offline-first:** client-side validation in the component; expect server rules (validation/triggers/flows) to apply at sync, and reconcile conflicts.

### Briefcase Builder (offline data priming)

Define offline data sets by **object + filter criteria** to prime records (and metadata) to the device; Performance Priming and High-Volume Briefcase handle large schedules. **Files (ContentDocument/ContentVersion) and Custom Metadata Types are not primed automatically** — prime them with custom LWC/Apex-wire patterns.

### Actions, flows, deep links

Supported: quick/global actions, LWC quick actions, screen flows (with offline flow cache policies), App Extensions, and deep links. **Deep links can be signed** with the Public Security Key (Field Service Settings) to suppress the security dialog. The legacy "Field Service Mobile Extension" toolkit (HTML/JS bundles) does **not** support native Apex calls — expose Apex as Apex REST there; native LDS/Lightning elements weren't supported in that toolkit.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Throwaway SAs per quote for external booking | Scheduler REST candidates/slots; persist SA on selection |
| Evaluating all resources in a big territory | `resourceLimitApptDistribution` |
| Bundling without the RSS/permission sets | Configure Named Credential + Field Service bundling permission sets |
| Assuming Apex writes/triggers run offline | Offline-first; reconcile at sync |
| Huge GraphQL queries on mobile | Keep <32 KB; lint with the mobile ESLint plugin |
| Expecting Files/CMDT in a Briefcase automatically | Prime them via custom wire/Apex |
| Native Apex calls from the legacy mobile extension toolkit | Expose as Apex REST |
