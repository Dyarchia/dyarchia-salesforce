# Data Capture Forms and Mobile Configuration

The programmatic surface behind Field Service Mobile forms: how a Data Capture flow differs from an
ordinary flow, how it is deployed, and the two configuration sObjects controlling the app.

The offline matrix and Briefcase are in `references/rest-and-mobile.md`.

## A Data Capture flow is a distinct process type

```json
{
    "processType": "DataCaptureFlow",
    "environments": ["Offline"],
    "variables": [
        { "name": "parentObjectType", "dataType": "String", "isInput": true },
        { "name": "parentRecordId",   "dataType": "String", "isInput": true },
        { "name": "recordId",         "dataType": "String", "isInput": true }
    ]
}
```

`processType` and `environments` make it run on the device. **All three String input variables are
mandatory**; a flow missing any is rejected.

## Deployment is a Tooling JSON round-trip, not XML

Unlike ordinary flow deployment, there is **no `.flow-meta.xml`, no zip, and no SFDX project**.

Create:

```text
POST /services/data/vXX.X/tooling/sobjects/Flow
{ "FullName": "<DeveloperName>", "Metadata": { … } }
```

The flow is created as **Draft**.

Editing takes three steps, because you mutate the version, not the definition:

```text
1.  SELECT Id, ActiveVersionId, LatestVersionId
    FROM FlowDefinition WHERE DeveloperName = '<name>'          (Tooling)
2.  GET   /tooling/sobjects/Flow/{versionId}
3.  PATCH /tooling/sobjects/Flow/{versionId}   with the mutated Metadata
```

## The component namespace

Data Capture screens use `runtime_service_fieldservice:dc*` components, each mapped to a Flow
field-type strategy. The wrong strategy deploys, then renders nothing:

| Flow field type | Components |
|---|---|
| `ComponentInstance` | `dcTextInput`, `dcLongText`, `dcName`, `dcEmail`, `dcPhone`, `dcNumeric`, `dcCounter`, `dcDate`, `dcDateTime`, `dcCheckbox`, `dcToggle` |
| `ComponentChoice` | `dcPicklist`, `dcRbGroup` |
| `ComponentMultiChoice` | `dcCbGroup`, `dcMatrix` |
| (other) | `dcSignature`, `dcUpFile`, `dcUpImage`, `dcImages`, `dcAddress`, `dcLookup`, `dcFileView` |

Native `Repeater` and `DisplayText` are also available.

## Prohibited patterns

The platform rejects flow structures that ordinary flows tolerate; some generalise beyond data
capture:

| Pattern | What you get |
|---|---|
| A Decision between two Create/Update/Delete nodes | "Append multiple Create, Update, or Delete operations only at the end of the flow" |
| A Get Records after any CUD node | Flow structure rejected |
| `isRequired=true` behind a `visibilityRule` | Deploys, then blocks the user with no way forward — use a `validationRule` instead |
| Calling an AutoLaunched subflow | "This flow can't reference [FlowName] because the referenced flow type is Autolaunched Flow" |
| A loop `collectionReference` that is not `<Repeater_Name>.AllItems` | Rejected |
| `IsLlmTargetable` as a JSON boolean | Must be a **string** |

## `DynamicDataCapture` — the pending-form record

A form appears on a device only when a `DynamicDataCapture` row points at a record.

| Field | Value |
|---|---|
| `ActionDefinition` | The Flow API name — **case-sensitive** |
| `ActionType` | `"Flow"` |
| `ProcessType` | `"DataCaptureFlow"` |
| `StatusCategory` | `"New"` |
| `ParentRecordId` | Polymorphic — see below |
| `IsRequired` | A real boolean here |
| `ExecutionOrder` | Ordering on the device |

`ParentRecordId` is polymorphic over `ServiceAppointment`, `ServiceResource`, `TimeSheet`, `Visit`,
`WorkOrder` and `WorkOrderLineItem`. **For Field Service Mobile, attach to the appointment's parent
Work Order rather than the appointment itself.**

## The sharing trap that blanks the Forms tab

The most confusing failure here, because it is invisible to whoever diagnoses it.

The Forms tab reads through the UI API
(`/ui-api/related-list-records/<woId>/DynamicDataCaptures`), and **the UI API enforces sharing**. If
`DynamicDataCapture` or `WorkPlan` has an OWD of Private — the platform default — the API
returns `INSUFFICIENT_ACCESS` and the tab shows "No forms available".

**Admin desktop SOQL does not reproduce it**, because administrators bypass sharing. The records are
there; the technician cannot see them.

The fix is a chain; every link is required:

1. Set OWD to Public Read/Write on **both** `DynamicDataCapture` and `WorkPlan`.
2. Tooling-PATCH `FieldServiceSettings` with
   `{"doesShareSaParentWoWithAr": true, "doesShareSaWithAr": true}`.
3. Issue a no-op `PATCH /sobjects/AssignedResource/{id}` per row to re-fire sharing recalculation.
4. **Sign out of the mobile app and back in.** FSL Mobile caches the sharing snapshot at login;
   pull-to-refresh does not pick up new sharing.

Verify:

```sql
SELECT QualifiedApiName, InternalSharingModel
FROM   EntityDefinition
WHERE  QualifiedApiName IN ('DynamicDataCapture', 'WorkPlan')
```

Both should read `ReadWrite`.

## The two configuration sObjects

### `FieldServiceMobileSettings` — branding, an ordinary sObject

The org default row is `DeveloperName = 'Field_Service_Mobile_Settings' AND IsDefault = true`.
Update with a plain `PATCH /sobjects/FieldServiceMobileSettings/{id}`, which has merge semantics.

Fourteen hex colour fields: `NavbarBackgroundColor`, `NavbarInvertedColor`, `PrimaryBrandColor`,
`SecondaryBrandColor`, `BrandInvertedColor`, `ContrastPrimaryColor`, `ContrastSecondaryColor`,
`ContrastTertiaryColor`, `ContrastQuaternaryColor`, `ContrastQuinaryColor`, `ContrastInvertedColor`,
`FeedbackPrimaryColor`, `FeedbackSecondaryColor`, `FeedbackSelectedColor`.

**`IsDefault` is not updateable**, and the **device metadata cache is 7 days by default** — a branding
change that seems not to work is not yet fetched.
`IsShowEditFullRecord` gates the mobile Edit Work Order and Edit Service Appointment actions.

### `FieldServiceSettings` — a Tooling sObject with a JSON blob

A singleton, reached through the Tooling API, whose configuration lives in a `Metadata` JSON object.
Known keys include `doesShareSaParentWoWithAr`, `doesShareSaWithAr` and `enableLsdkMode`.

**A partial body nulls the keys you omit.** The PATCH sends the entire `Metadata` object: read it,
change the one key, send it all back. Sending `{"Metadata": {"enableLsdkMode": true}}`
silently clears every other org preference in that blob.

## Licensing

Repeated from SKILL.md §7 as the first check when the app will not open: **`FieldServiceMobilePsl` gates login**, `EinsteinFieldServicePsl` gates Voice to Record
Edit and Pre-Work Brief, and `AgentforceForFieldServicePsl` gates Voice to Form. The shipped
permission set is `EinsteinFieldServiceUser`; the system permissions are
`PermissionsFieldServiceVoiceToRecordEdit` and `PermissionsFieldServiceVoiceToForm`.

## Pre-Work Brief, and why Apex cannot activate it

The Pre-Work Brief prompt template ships as `einstein_gpt__fieldServicePreWorkBrief`, is deployed as
`Pre_Work_Brief`, and is surfaced through the **`WorkOrder.PreWorkBriefPromptTemplate`** field.

Activation is a Connect API call:

```text
PUT /services/data/vXX.X/einstein/prompt-templates/{devName}/versions/{versionId}/status
    ?action=activate&ignoreWarnings=false
    body: {}
```

Resolve `versionId` from `GET /einstein/prompt-templates/{devName}` →
`childRelationships.GenAiPromptTemplateVersions[].fields.Id.value` (prefix `3vN`). Available from
API v65.0.

**The endpoint is `@ConnectHidden(from=Apex)`, so Apex cannot call it at all.** That is why
`ConnectApi.EinsteinLLM` and Tooling or metadata approaches fail — a deliberately closed door, not a
permissions problem. Drive it from the CLI or an external caller.

Related: **`GenAiPromptTemplate` is not SOQL- or REST-queryable.** Resolve its `0hf` Id through a
Metadata API deep read on `type=GenAiPromptTemplate, fullName=Pre_Work_Brief`.
