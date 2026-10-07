# Object & Field Access — Reference (Winter '27 / API v68.0)

The "what can the user do" axis of `dya-sf-permissions`.

## The Assignment Stack

| Source | Cardinality | Role |
|---|---|---|
| **Profile** | exactly one per user | Thin baseline; login hours/IP, default record types/apps, baseline CRUD |
| **Permission Set** | many per user | Additive capability grants |
| **Permission Set Group (PSG)** | many per user | Bundle of permission sets for a persona |
| **Muting Permission Set** | within a PSG | Subtract specific permissions from that group |

## Object Permissions (CRUD)

**View All** and **Modify All** bypass sharing for one object; grant them sparingly. The *system* permissions **View All Data** and **Modify All Data** bypass sharing for *all* objects; reserve them for admins and integrations of last resort.

## Field-Level Security (FLS)

Set FLS on profiles and permission sets, not on the field definition, which defines defaults.

## System & User Permissions

Capabilities not tied to one object, e.g. **API Enabled**, **Author Apex**, **Manage Users**, **Run Flows**, **Manage Sharing**, **Customize Application**, **Modify Metadata Through Metadata API**, **View Setup and Configuration**. Grant via permission sets; many are high-privilege.

## Other Access Delivered via Permission Sets

- **Apex class access** and **Visualforce page access** (also relevant for `@RestResource` exposure).
- **Custom permissions** — feature flags your Apex/Flow checks with `FeatureManagement`/`$Permission`.
- **Connected/External Client App** access (relevant to integration auth).
- **Custom metadata / custom setting** access.

## Record Types

Business processes exist for Lead, Opportunity, Case and Solution. Record-type access and record visibility are independent: a user can have either without the other.

## The Metadata Behind It

A `PermissionSet` is one XML file; everything it grants appears as a named element:

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

**Omit required fields from `<fieldPermissions>`.** Required fields cannot carry field-level
security, so listing one fails the deployment. The error message does not say so.

The XML references user permissions by API name: `PermissionsManageDataMaskPolicies` and
`PermissionsAccessDataMaskAndSeed` gate Data Mask, and `PermissionsViewAllProfiles` bypasses
Winter '27 profile filtering.

## Assignment Order — Licence Before Set

When a permission set carries a `LicenseId`, assign the licence **first**:

1. `POST` a `PermissionSetLicenseAssign` for the user.
2. Then `POST` the `PermissionSetAssignment`.

Reversed, the second call fails. A provisioning loop assigning several sets in one pass succeeds for
the licence-free ones and fails for the rest, which looks intermittent rather than ordered.

Do not normalise permission set API names when scripting against a packaged persona model. Vendors
ship inconsistent names — `IncidentFulfiller` beside `ProblemFulfillerPermSet` and
`ChangeRequestFulfillerPermSet` — and correcting the odd one out produces a `NOT_FOUND`.

## Turning a Feature On At All

Some capabilities are gated by an org feature toggle before any permission matters; Salesforce Go
exposes those through a Connect API rather than metadata:

```text
GET  /services/data/vXX.X/connect/setup/discovery/feature/{apiName}/status
POST /services/data/vXX.X/connect/setup/discovery/feature/{apiName}/enable
```

Check the toggle before auditing access. A disabled toggle looks like a permission problem: the
permission set and profile are right, and the feature is still absent.

## Design Rules

- Compose **persona PSGs** from small, single-purpose permission sets.
- Use **muting** to tailor a PSG for a sub-persona instead of cloning permission sets.
- Keep **View All/Modify All** and **Modify All Data** out of standard personas.
- Check capability in code with **custom permissions**, not by hard-coding profile names.
