# Object & Field Access — Reference (Winter '27 / API v68.0)

Load from `dya-permissions` for the "what can the user do" axis: profiles, permission sets, groups, muting, CRUD, FLS, system permissions, record types.

## The Assignment Stack

| Source | Cardinality | Role |
|---|---|---|
| **Profile** | exactly one per user | Thin baseline; login hours/IP, default record types/apps, baseline CRUD |
| **Permission Set** | many per user | Additive capability grants |
| **Permission Set Group (PSG)** | many per user | Bundle of permission sets for a persona |
| **Muting Permission Set** | within a PSG | Subtract specific permissions from that group |

Permissions combine **additively** across all assigned sources. The *only* way to take a permission away (other than not granting it) is a **muting permission set** inside a PSG.

## Object Permissions (CRUD)

Per object: **Create, Read, Edit, Delete**, plus **View All** and **Modify All** (bypass sharing for that object). View All/Modify All are powerful — grant sparingly. "View All Data"/"Modify All Data" are *system* permissions that bypass sharing for *all* objects — reserve for admins/integration-of-last-resort.

## Field-Level Security (FLS)

Per field: **Read** and **Edit**. FLS is enforced **everywhere** — UI, API, reports, and user-mode Apex from API 67.0. A field a user can't read is invisible in query results. FLS is set on profiles/permission sets, not on the field definition itself (the field defines defaults).

## System & User Permissions

App-wide capabilities not tied to a single object, e.g. **API Enabled**, **Author Apex**, **Manage Users**, **Run Flows**, **Manage Sharing**, **Customize Application**, **Modify Metadata Through Metadata API**, **View Setup and Configuration**. Grant via permission sets; many are high-privilege.

## Other Access Delivered via Permission Sets

- **Apex class access** and **Visualforce page access** (also relevant for `@RestResource` exposure).
- **Custom permissions** — feature flags your Apex/Flow checks with `FeatureManagement`/`$Permission`.
- **App, tab, and record-type** visibility.
- **Connected/External Client App** access (relevant to integration auth).
- **Custom metadata / custom setting** access.

## Record Types

Control, per profile/permission set:
- Which **picklist values** are available.
- Which **page layout** is assigned.
- Which **business process** (Lead/Opportunity/Case/Solution) applies.

Record-type *access* shapes **data entry and presentation** — it is **not** record visibility (that's sharing). A user can have access to a record type yet not see a given record, and vice versa.

## The Metadata Behind It

A `PermissionSet` is one XML file, and everything the assignment stack grants appears in it as a
named element:

| Element | Grants |
|---|---|
| `<objectPermissions>` | `allowRead`, `allowCreate`, `allowEdit`, `allowDelete`, `viewAllRecords`, `modifyAllRecords` |
| `<fieldPermissions>` | Field-level read and edit |
| `<userPermissions>` | System and user permissions, by API name |
| `<classAccesses>` | Apex class execution |
| `<applicationVisibilities>` / `<tabSettings>` | Apps and tabs |
| `<recordTypeVisibilities>` | Record types |
| `<customPermissions>` | Custom permissions |
| `<hasActivationRequired>` | Whether the set is session-activated |
| `<dataspaceScopes>` | Data 360 dataspaces — see `references/dataspace-access.md` |

**A required field listed in `<fieldPermissions>` fails the deployment.** Required fields cannot
carry field-level security at all, so omit them entirely rather than granting them explicitly. This
is a schema fact, not a permission problem, and the error message does not make that obvious.

User permissions are referenced by API name and are worth knowing in that form when you are writing
a permission set rather than clicking one — `PermissionsManageDataMaskPolicies` and
`PermissionsAccessDataMaskAndSeed` gate Data Mask, for instance, and `PermissionsViewAllProfiles` is
what bypasses Winter '27 profile filtering.

## Assignment Order — Licence Before Set

When a permission set carries a `LicenseId`, the licence assignment must land **first**:

1. `POST` a `PermissionSetLicenseAssign` for the user.
2. Then `POST` the `PermissionSetAssignment`.

Reversed, the second call fails. This bites in scripted persona provisioning, where a loop that
assigns several sets in one pass will succeed for the licence-free ones and fail for the rest, which
reads like an intermittent problem rather than an ordering one.

While there: do not "normalise" permission set API names when scripting against a packaged persona
model. Vendors ship inconsistent names on purpose or by accident — a set called `IncidentFulfiller`
sitting beside `ProblemFulfillerPermSet` and `ChangeRequestFulfillerPermSet` is a real shape, and
correcting the odd one out produces a `NOT_FOUND`.

## Turning a Feature On At All

Some capabilities are gated by an org feature toggle before any permission matters, and Salesforce Go
exposes those through a Connect API rather than metadata:

```text
GET  /services/data/vXX.X/connect/setup/discovery/feature/{apiName}/status
POST /services/data/vXX.X/connect/setup/discovery/feature/{apiName}/enable
```

Worth knowing because the failure looks like a permission problem: the user has the permission set,
the profile is right, and the feature still is not there. Check the toggle before auditing access.

## Design Rules

- Start from **Minimum Access - Salesforce** profile; grant everything else via permission sets.
- Model **personas as PSGs**; compose from small, single-purpose permission sets.
- Use **muting** to tailor a PSG for a sub-persona instead of cloning permission sets.
- Keep **View All/Modify All** and **Modify All Data** out of standard personas.
- Check capability in code with **custom permissions**, not by hard-coding profile names.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Fat, bespoke profiles per team | Minimal profile + PSGs |
| Cloning permission sets to drop one permission | Muting permission set |
| "Modify All Data" to fix one object's access | Object View All/Modify All, or sharing |
| Hard-coding profile names in Apex/Flow | Custom permissions |
| Setting FLS expecting UI-only effect | FLS hides fields in API/reports/user-mode Apex too |
| Confusing record-type access with visibility | Record type = picklists/layouts; sharing = which records |
