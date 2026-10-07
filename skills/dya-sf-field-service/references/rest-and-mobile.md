# Field Service — Scheduler REST, Bundling REST & Mobile (Winter '27 / API v68.0)

Load from `dya-sf-field-service` for external/headless booking, appointment bundling, and mobile extensibility.

## Salesforce Scheduler REST — Candidates & Slots

The operations and the in-session `lxscheduler` builder are in SKILL.md §5.

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

`resourceLimitApptDistribution` (on `getAppointmentCandidates` and `available-territory-slots`) caps how many resource calendars are evaluated; set it when a territory exceeds ~20 resources.

**Headless booking flow:** (1) call candidates/slots to show windows; (2) create `WorkOrder` + `ServiceAppointment` (Work Type, `EarliestStartTime`, `DueDate`) **only when the customer selects a slot**; (3) commit via the Scheduler save action or `FSL.ScheduleService.schedule`.

## Appointment Bundling REST APIs

Six operations: **Automatic Bundling, Create Bundle, Remove Bundle Members, Unbundle, Unbundle Multiple, Update Bundle** (available in API v54.0+; not supported in Gov Cloud). Create Bundle takes service-appointment Ids + a manual bundling policy Id (`ApptBundlePolicy` marked for manual bundling) and returns the **bundle service appointment Id**. Bundling callouts need a Remote Site Setting/Named Credential and the Field Service bundling permission sets (Admin, Bundle for Dispatcher, Integration). Confirm resource paths and HTTP methods against the six official sub-pages for your version.

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

Grant the **Lightning SDK for Field Service Mobile** permission via a permission set.

### What works offline vs. not

| Works offline | Does NOT work offline |
|---|---|
| LDS base components; `getRecord` / LDS | Apex **writes** (DML via Apex) |
| GraphQL wire (`lightning/uiGraphQLApi`) | Server-hitting Apex calls (`@wire`/imperative) |
| `getRelatedListRecords` / `getRelatedListCount`* | Triggers, validation rules, workflow, **record-triggered** flows (fire on **sync**) |
| Apex **reads** of data cached while online | `getListUi` / `getRecordUi` (limited/deprecated) |
| | Lightning Message Service |

\* Related-list wires won't reflect records created/deleted while offline.

- Lint GraphQL query size with `@salesforce/eslint-plugin-lwc-mobile`; many fields also hurt.
- **Design offline-first:** client-side validation in the component; expect server rules (validation/triggers/flows) to apply at sync, and reconcile conflicts.

### Briefcase Builder (offline data priming)

Offline data sets defined by **object + filter criteria** prime records and metadata to the device; Performance Priming and High-Volume Briefcase handle large schedules. Prime Files (ContentDocument/ContentVersion) and Custom Metadata Types with custom LWC/Apex-wire patterns.

### Actions, flows, deep links

Supported: quick/global actions, LWC quick actions, screen flows (with offline flow cache policies), App Extensions, and deep links. The Public Security Key for signed deep links is in Field Service Settings. The legacy "Field Service Mobile Extension" toolkit (HTML/JS bundles) does **not** support native Apex calls — expose Apex as Apex REST there; native LDS/Lightning elements weren't supported in that toolkit.
