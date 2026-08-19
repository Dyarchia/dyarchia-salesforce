# Object & Field Access — Reference (Summer '26)

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

Per field: **Read** and **Edit**. FLS is enforced **everywhere** — UI, API, reports, and (at v67) user-mode Apex. A field a user can't read is invisible in query results. FLS is set on profiles/permission sets, not on the field definition itself (the field defines defaults).

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
