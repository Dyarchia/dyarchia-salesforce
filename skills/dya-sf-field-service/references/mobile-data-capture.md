# Data Capture Forms and Mobile Configuration

The programmatic surface behind forms on Field Service Mobile: how a Data Capture flow differs from
an ordinary flow, how it is deployed, and the two configuration sObjects that control the app itself.

The offline matrix and Briefcase are in `references/rest-and-mobile.md`; this file is about
authoring and deploying the forms.

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

`processType` and `environments` are what make it run on the device. **All three String input
variables are mandatory** — `parentObjectType`, `parentRecordId` and `recordId` — and a flow missing
any of them is rejected.

## Deployment is a Tooling JSON round-trip, not XML

This is the part that surprises anyone coming from ordinary flow deployment. There is **no
`.flow-meta.xml`, no zip, and no SFDX project** in this path.

Create:

```text
POST /services/data/vXX.X/tooling/sobjects/Flow
{ "FullName": "<DeveloperName>", "Metadata": { … } }
```

The flow is created as **Draft**.

Edit an existing one — three steps, because you must mutate the version rather than the definition:

```text
1.  SELECT Id, ActiveVersionId, LatestVersionId
    FROM FlowDefinition WHERE DeveloperName = '<name>'          (Tooling)
2.  GET   /tooling/sobjects/Flow/{versionId}
3.  PATCH /tooling/sobjects/Flow/{versionId}   with the mutated Metadata
```

## The component namespace

Data Capture screens use `runtime_service_fieldservice:dc*` components, and each maps to a Flow
field-type strategy. Getting the strategy wrong produces a flow that deploys and then renders
nothing:

| Flow field type | Components |
|---|---|
| `ComponentInstance` | `dcTextInput`, `dcLongText`, `dcName`, `dcEmail`, `dcPhone`, `dcNumeric`, `dcCounter`, `dcDate`, `dcDateTime`, `dcCheckbox`, `dcToggle` |
| `ComponentChoice` | `dcPicklist`, `dcRbGroup` |
| `ComponentMultiChoice` | `dcCbGroup`, `dcMatrix` |
| (other) | `dcSignature`, `dcUpFile`, `dcUpImage`, `dcImages`, `dcAddress`, `dcLookup`, `dcFileView` |

Native `Repeater` and `DisplayText` are also available.

## Prohibited patterns

The platform rejects flow structures that ordinary flows tolerate. The ones that generalise beyond
data capture are worth knowing regardless:

| Pattern | What you get |
|---|---|
| A Decision between two Create/Update/Delete nodes | "Append multiple Create, Update, or Delete operations only at the end of the flow" |
| A Get Records after any CUD node | Flow structure rejected |
| `isRequired=true` behind a `visibilityRule` | Deploys, then blocks the user with no way forward — use a `validationRule` instead |
| Calling an AutoLaunched subflow | "This flow can't reference [FlowName] because the referenced flow type is Autolaunched Flow" |
| A loop `collectionReference` that is not `<Repeater_Name>.AllItems` | Rejected |
| `IsLlmTargetable` as a JSON boolean | Must be a **string** |

## `DynamicDataCapture` — the pending-form record

A form does not appear on a device because it exists; it appears because a `DynamicDataCapture` row
points at a record.

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

The single most confusing failure in this area, because it is invisible to the person diagnosing it.

The Forms tab reads through the UI API
(`/ui-api/related-list-records/<woId>/DynamicDataCaptures`), and **the UI API enforces sharing**. If
`DynamicDataCapture` or `WorkPlan` has an OWD of Private — which is the platform default — the API
returns `INSUFFICIENT_ACCESS` and the tab shows "No forms available".

**Desktop SOQL as an administrator does not reproduce it**, because administrators bypass sharing.
The records are there; the technician cannot see them.

The fix is a chain, and every link is required:

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

Two operational facts: **`IsDefault` is not updateable**, and the **device metadata cache is 7 days
by default** — so a branding change is not "not working", it is not yet fetched.
`IsShowEditFullRecord` gates the mobile Edit Work Order and Edit Service Appointment actions.

### `FieldServiceSettings` — a Tooling sObject with a JSON blob

A singleton, reached through the Tooling API, whose configuration lives in a `Metadata` JSON object.
Known keys include `doesShareSaParentWoWithAr`, `doesShareSaWithAr` and `enableLsdkMode`.

**A partial body nulls the keys you omit.** The PATCH sends the entire `Metadata` object, so read it,
change the one key, and send the whole thing back. Sending `{"Metadata": {"enableLsdkMode": true}}`
silently clears every other org preference in that blob.

## Licensing

Covered in SKILL.md §7, and repeated here because it is the first thing to check when the app will
not open: **`FieldServiceMobilePsl` gates login**, `EinsteinFieldServicePsl` gates Voice to Record
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

**The endpoint is `@ConnectHidden(from=Apex)`, so it cannot be called from Apex at all.** That is why
`ConnectApi.EinsteinLLM` and Tooling or metadata approaches fail here — not a permissions problem, a
deliberately closed door. Drive it from the CLI or an external caller.

Related: **`GenAiPromptTemplate` is not SOQL- or REST-queryable.** Resolve its `0hf` Id through a
Metadata API deep read on `type=GenAiPromptTemplate, fullName=Pre_Work_Brief`.
