---
name: dya-sf-permissions
description: Salesforce permissions and sharing (Winter '27, API v68.0) — profiles, permission sets and groups, OWD, role hierarchy, sharing rules, manual and Apex sharing, restriction and scoping rules, field-level security, record types, guest access, user mode. Applies to permission sets and groups, profiles, sharing rules and settings, field-level security, record types, Apex sharing and user-mode code. Load before creating or editing anything in this scope.
---

# Salesforce Permissions & Sharing Model

This skill is **conceptual**: the model of "who can do what" and "who can see what". Other skills
route here — `dya-sf-apex`, `dya-sf-flow`, `dya-sf-lwc`, `dya-sf-integration-inbound-apex` and
`dya-sf-agentforce` enforce this model without owning it. Authentication belongs to
`dya-sf-integration-auth`. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — release-coupled facts, including the API 67.0 security defaults that now enforce this model.
- `references/object-and-field-access.md` — profiles vs permission sets vs groups vs muting; object (CRUD) and field (FLS) permissions; system and user permissions; record types.
- `references/record-sharing.md` — the full sharing model: OWD, role hierarchy, sharing rules, manual and Apex sharing, teams, implicit sharing, restriction and scoping rules.
- `references/data-privacy-and-encryption.md` — regulated data: Shield `encryptionScheme` and the deterministic-versus-probabilistic trade-off, key models, `DsarPolicy` for subject requests, and Data Mask for sandboxes.
- `references/dataspace-access.md` — how Data 360 objects are granted: a permission set element, not part of the sharing model.

---

## Platform Context — Winter '27 / API v68.0

**Minimum access is the default.** Build on a thin base profile plus additive permission sets;
Salesforce lands new capability in permission sets.

**The model is enforced in code.** From API 67.0, Apex SOQL, SOSL and DML default to `USER_MODE`, so
the running user's object, field and sharing access governs what controller and integration code can
read and write — not just the UI. See `references/shared/platform-deltas.md` and `dya-sf-apex`.

| Change | Status | Effect |
|---|---|---|
| **Enable Profile Filtering** | Enforced | Users without a bypass permission cannot see other users' profile names. Queries return **empty, not an error**, so code reading profile names silently degrades |
| **"Use Any API Auth" required for SOAP `login()`** | Enforced in new orgs | Username/password SOAP authentication needs the permission. Treat SOAP `login()` as end-of-life. See `dya-sf-integration-auth` |
| **View Setup Audit Trail becomes a standalone permission** | GA | Auditors get the trail without the broader permission that used to carry it |
| **Keep Manual Shares When Transferring Records** | GA, off by default | An org-wide setting that preserves the manual shares an ownership change previously deleted |

**Do not grant View All Profiles to undo profile filtering.** When something breaks, find what
needed the profile name; broad visibility is the fallback. Profile filtering's bypass permissions are
View All Profiles, Customize Application, Manage Users and five others.

## Summary — The Five Commandments

1. **Keep the two questions separate** — what they can *do* (CRUD, FLS, permissions) versus which records they can *see* (sharing).
2. **Build access additively** — minimal profile, capability through permission sets and groups, removal only through muting.
3. **Widen sharing from a restrictive OWD** — hierarchy, rules, manual and Apex sharing, teams, implicit grants; only restriction rules narrow.
4. **Enforce the model in code** — `with sharing` plus `WITH USER_MODE`; triggers are the system-mode exception.
5. **Apply least privilege: fix the model, never the symptom.** Widening access to clear an error exposes the same data in reports and the API.

---

## 1. Two Independent Questions

Always reason about the two axes separately.

```text
WHAT can the user DO?         →  Object (CRUD) + Field (FLS) + system/user permissions
                                 Source: Profile (baseline) + Permission Sets (+ Groups)

WHICH RECORDS can they SEE?   →  Sharing model
                                 Source: OWD → Role Hierarchy → Sharing Rules →
                                         Manual/Apex sharing → Teams → (Restriction/Scoping)
```

Acting on a record needs **both**; almost every access bug is one axis satisfied without the other:

- *"It's shared with them but they can't edit it"* → missing object or field permission.
- *"They have Edit on the object but the list is empty"* → missing sharing.

## 2. What Can They Do — Permissions

### Sources, in additive order

1. **Profile** — exactly one per user, the baseline. Keep it minimal ("Minimum Access – Salesforce").
2. **Permission Sets** — additive grants on top; a user can have many.
3. **Permission Set Groups** — bundles of permission sets for a persona; assign the group, not the parts.
4. **Muting Permission Sets** — *subtract* specific permissions inside a group.

Permissions are **additive**: if any assigned source grants something, the user has it. There is no
deny; muting is the only exception, and works only within its group.

### What they grant

- **Object permissions (CRUD)** — Create, Read, Edit, Delete, plus View All and Modify All per
  object.
- **Field-Level Security** — Read and Edit per field. A field hidden by FLS is invisible
  *everywhere*: UI, API, reports and user-mode SOQL.
- **System and user permissions** — org-wide capabilities: Manage Users, API Enabled, Author
  Apex, Run Flows, View Setup Audit Trail.
- **Everything else in a permission set** — app and tab visibility, Apex class and Visualforce page
  access, custom permissions, connected and external app access, record type access.

### Record types

A **record type** selects the picklist values, page layout and business process that apply to a
record. Access to one is granted through the profile or permission set, separately from field
permissions. It shapes *data entry*, not *record visibility*.

> Detail and design rules: `references/object-and-field-access.md`.

## 3. Which Records — the Sharing Model

Each layer only **widens** access from a restrictive baseline; only restriction rules narrow.

1. **Org-Wide Defaults** — the floor, per object: Private, Public Read Only, Public Read/Write, or
   Controlled by Parent (needs a Master-Detail parent). Separate internal and external defaults
   give community and portal users a stricter baseline; external can never be more permissive than
   internal. Start restrictive and open deliberately.
   **Values vary by object:** Case and Lead add `ReadWriteTransfer`, Campaign adds `FullAccess`, and
   Price Book has its own model (`ReadSelect`, `Read`, `None`) with external **fixed at `None`,
   unchangeable** by any API. **Some objects are not configurable:** User is fixed at Read internally
   and externally, Activity's external default is fixed at Private, and Knowledge article visibility
   is governed by channels, not OWD. **OWD changes cascade:** setting Account to Private forces Contact, Case and Opportunity to Private and
   recalculates all four, while Contract follows Account and cannot be set independently.
2. **Role Hierarchy** — a user inherits access to records owned by anyone below them, with no
   per-record configuration. "Grant Access Using Hierarchies" can be switched off for **custom**
   objects; on standard objects it is always on.
3. **Sharing Rules** — owner-based (records owned by this group go to that group) or criteria-based
   (records matching a field filter go to a group). **Model them as immutable:** an owner-based rule
   allows editing only its access level, so changing who it shares from or to fails the deploy and
   needs a delete-and-recreate. Remove a sharing rule with a destructive deploy; a normal deploy is
   **additive** and never removes one.
4. **Manual and Apex Managed Sharing** — one record shared with a user or group. Write Apex shares
   as `__Share` rows with a **sharing reason**; the reason makes the share recalculable and
   survivable across owner changes.
5. **Teams** — Account, Opportunity and Case teams grant named collaborators a defined access level.
6. **Implicit sharing** — grants the platform makes on its own, not configurable: read access to a
   child record grants read on its parent Account; Account access grants access to the associated
   Contacts, Cases and Opportunities under some OWD combinations; and portal and community users get
   implicit access to their own account's records. None appear in any sharing rule, and they explain
   most "why can they see this?" investigations.

### The two narrowing layers

Use a restriction rule for "must not see" and a scoping rule for "should not have to wade through". A
scoping rule for a confidentiality requirement is a data leak.

- **Restriction Rules** *remove* visibility, filtering objects the user already accesses to a subset
  — "this user sees only Cases of type Internal". Excluded records are absent from list views,
  reports and user-mode queries.
- **Scoping Rules** change only the **default view**: which records a user sees *first*, not what
  they *can* reach. Search, a direct link or removing the filter still gets there.

> Evaluation order, Apex sharing shapes and edge cases: `references/record-sharing.md`.

## 4. Guest and Integration Users

**Guest users** — public sites and unauthenticated Experience Cloud pages — run under a dedicated
profile with no role, a separate, restricted class of sharing rules, and no access to most
objects. Anything a guest user can reach, the internet can reach. Read what the guest profile grants;
never assume it is restrictive. See `dya-sf-lwr-sites`.

**Give each integration its own user and permission set**, never a licence borrowed from a departed
admin. Grant exactly the objects and fields the integration touches; API 67.0 user mode enforces it, so
an integration that now returns fewer rows was relying on an over-broad profile.

## 5. How Access Is Enforced in Code

**Fix the model, not the symptom.** A too-narrow permission set or OWD makes user-mode code return
fewer rows or throw. Widening permissions to clear the error also exposes that data in reports, list
views and the API.

- **`WITH USER_MODE` / `AccessLevel.USER_MODE`** enforce CRUD, FLS and sharing for the running user.
- **`with sharing`** enforces record sharing on a class, **`without sharing`** ignores it, and
  **`inherited sharing`** follows the caller. From 67.0 an omitted keyword defaults to
  `with sharing`.
- **Triggers run in system mode on every API version** — they see every record and field regardless
  of the user.
- **Flow** has three run contexts of its own, and the record-triggered default bypasses object and
  field permissions. See `dya-sf-flow`.

## 6. Decision Matrix

| Need | Use |
|---|---|
| Baseline access for everyone | A minimal **Profile** |
| Grant a capability to some users | **Permission Set** |
| Bundle access for a persona | **Permission Set Group** |
| Remove a permission inside a group | **Muting Permission Set** |
| Hide a field everywhere | **Field-Level Security** |
| Control picklists, layout and process | **Record Type** plus page layout |
| Set baseline record visibility | **Org-Wide Defaults** |
| Let managers see their reports' records | **Role Hierarchy** |
| Open records to a group by criteria | Criteria-based **Sharing Rule** |
| Share one record ad hoc | **Manual Sharing** |
| Share records programmatically and recalculably | **Apex Managed Sharing** with a custom reason |
| Grant collaborators on a deal | Account / Opportunity / Case **Team** |
| Make a subset invisible to a user | **Restriction Rule** |
| Change only what a user sees by default | **Scoping Rule** |
| Enforce all of it in Apex | `with sharing` plus `WITH USER_MODE` |
| Grant a permission set access to a Data 360 dataspace | `dataspaceScopes` on the PermissionSet — see `references/dataspace-access.md` |
| Encrypt a field but keep it filterable | A **deterministic** `encryptionScheme`; probabilistic is stronger and unqueryable |
| Export one person's data on request | A `DsarPolicy` — portability, and it **deletes nothing** |
| Mask production data in a sandbox | Data Mask — sandbox only, and it returns 403 in production |

## 7. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct approach |
|---|---|
| Piling permissions onto fat profiles | Minimal profile, capability through permission sets and groups |
| Trying to remove a permission by editing the profile | Muting permission set inside the group |
| Public Read/Write OWD to make something work | Restrictive OWD plus targeted sharing |
| Granting Modify All Data to close a sharing gap | Scoped sharing, or View All / Modify All on the one object |
| Widening FLS or CRUD to silence a user-mode error | Fix the permission set; keep least privilege |
| Granting View All Profiles to undo profile filtering | Find what needed the profile name |
| A scoping rule for a confidentiality requirement | Restriction rule — scoping only changes the default view |
| Confusing record-type access with record visibility | Record types are picklists and layouts; sharing is visibility |
| Assuming a trigger respects the user's sharing | Triggers are system mode; filter explicitly |
| Treating the role hierarchy as the only sharing tool | Combine OWD, rules and restriction/scoping by intent |
| An over-broad guest profile | Minimal guest profile plus guest sharing rules |
| An integration user on a borrowed admin licence | Its own user with a purpose-built permission set |
| Testing access only as an administrator | `System.runAs` a user carrying the real permission set |
| Assuming a deploy removes a sharing rule | Deploys are additive; deletion needs a destructive deploy |
| Editing an owner-based rule's `sharedTo` / `sharedFrom` | Only the access level is editable; delete and recreate |
| Listing a required field in `fieldPermissions` | Required fields cannot carry FLS; omit them or the deploy fails |
| `ProbabilisticEncryption` on a field you filter or sort | A deterministic scheme, accepting the weaker guarantee knowingly |
| Assigning a permission set before its licence | If the set has a `LicenseId`, the `PermissionSetLicenseAssign` goes first |
