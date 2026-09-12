---
name: dya-permissions
description: Salesforce permissions & sharing model (Winter '27 / API v68.0) — the conceptual reference so an agent knows the access model end to end. Profiles, permission sets, permission set groups and muting, the "who sees what" sharing model (OWD, role hierarchy, sharing rules, manual/Apex sharing, teams), restriction and scoping rules, field-level security, record types, guest access, and how it all interacts with Apex user mode. Load only when the user explicitly invokes this skill by name (`dya-permissions`); do NOT auto-trigger on generic permission or security questions.
---

# Salesforce Permissions & Sharing Model

This skill is **conceptual**: the complete mental model of "who can do what" and "who can see what",
so the right design choice becomes obvious. It is the skill other skills route to — `dya-apex`,
`dya-flow`, `dya-lwc`, `dya-integration-inbound-apex` and `dya-agentforce` all enforce this model
without owning it. Authentication is a different concern and belongs to `dya-integration-auth`.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the API 67.0 security defaults this model is now enforced by.
- `references/object-and-field-access.md` — profiles vs permission sets vs groups vs muting; object (CRUD) and field (FLS) permissions; system and user permissions; record types.
- `references/record-sharing.md` — the sharing model in full: OWD, role hierarchy, sharing rules, manual and Apex sharing, teams, implicit sharing, restriction and scoping rules.
- `references/data-privacy-and-encryption.md` — the regulated-data axis: Shield `encryptionScheme` and the deterministic-versus-probabilistic trade-off, key models, `DsarPolicy` for subject requests, and Data Mask for sandboxes.
- `references/dataspace-access.md` — how Data 360 objects are granted, which is a permission set element rather than any part of the sharing model.

---

## Platform Context — Winter '27 / API v68.0

**Minimum access is the modern default.** A thin base profile plus additive permission sets is the
shape Salesforce steers orgs toward, and where new capability lands. Grant through permission sets
and permission set groups; keep the profile as a baseline.

**The model is enforced in code.** From API 67.0, Apex SOQL, SOSL and DML default to `USER_MODE`, so
the running user's object, field and sharing access governs what controller and integration code can
read and write. This model is no longer "just the UI". Triggers remain the exception: they run in
system mode on every API version. See `references/shared/platform-deltas.md` and `dya-apex`.

What Winter '27 changes:

| Change | Status | Effect |
|---|---|---|
| **Enable Profile Filtering** | Enforced | A user without a bypass permission can no longer see other users' profile names. A query for them returns **empty rather than an error**, so code that reads profile names silently degrades |
| **"Any API Auth" required for SOAP `login()`** | Enforced in new orgs | Legacy username/password SOAP authentication needs the permission explicitly. Treat SOAP `login()` as end-of-life. See `dya-integration-auth` |
| **View Setup Audit Trail becomes a standalone permission** | GA | Auditors can be granted the trail without the broader permission that used to carry it — a real least-privilege improvement |
| **Keep Manual Shares When Transferring Records** | GA, off by default | An org-wide setting. Previously every manual share on a record was destroyed the moment ownership changed; this preserves them |

Profile filtering has a bypass list — View All Profiles, Customize Application, Manage Users and five
others. **Granting View All Profiles to undo it defeats the point.** When something breaks, find out
what actually needed the profile name; broad visibility is the fallback, not the plan.

---

## 1. Two Independent Questions

The model splits into two orthogonal axes. Always reason about them separately.

```text
WHAT can the user DO?         →  Object (CRUD) + Field (FLS) + system/user permissions
                                 Source: Profile (baseline) + Permission Sets (+ Groups)

WHICH RECORDS can they SEE?   →  Sharing model
                                 Source: OWD → Role Hierarchy → Sharing Rules →
                                         Manual/Apex sharing → Teams → (Restriction/Scoping)
```

Object and field access answers "can this user edit *Accounts* and the *Revenue* field at all?";
sharing answers "which *specific Account records*?" A user needs **both** to act on a record, and
almost every access bug is one axis satisfied while the other is not:

- *"It's shared with them but they can't edit it"* → missing object or field permission.
- *"They have Edit on the object but the list is empty"* → missing sharing.

## 2. What Can They Do — Permissions

### Sources, in additive order

1. **Profile** — exactly one per user, the baseline. Keep it minimal ("Minimum Access – Salesforce").
2. **Permission Sets** — additive grants layered on top; a user can have many.
3. **Permission Set Groups** — bundles of permission sets for a persona; assign the group, not the parts.
4. **Muting Permission Sets** — *subtract* specific permissions inside a group.

Permissions are **purely additive**: if any assigned source grants something, the user has it. There
is no deny, and adding a set never takes a permission away. Muting inside a group is the single
exception, and it works only within that group.

### What they grant

- **Object permissions (CRUD)** — Create, Read, Edit, Delete, plus View All and Modify All per
  object.
- **Field-Level Security** — Read and Edit per field. A field hidden by FLS is invisible
  *everywhere*: UI, API, reports and user-mode SOQL.
- **System and user permissions** — org-wide capabilities: Manage Users, API Enabled, Author
  Apex, Run Flows, View Setup Audit Trail.
- **Everything else that travels in a permission set** — app and tab visibility, Apex class and
  Visualforce page access, custom permissions, connected and external app access, record type
  access.

### Record types

A **record type** selects which picklist values and page layout apply to a record, and which business
process it follows. Access to one is granted through the profile or permission set, separately from
field permissions. It shapes *data entry*, not *record visibility* — confusing the two is a common
and expensive mistake.

> Full detail and decision rules: `references/object-and-field-access.md`.

## 3. Which Records — the Sharing Model

Access widens from a restrictive baseline. Each layer only **opens up**; only restriction rules
narrow.

1. **Org-Wide Defaults** — the floor, per object: Private, Public Read Only, Public Read/Write, or
   Controlled by Parent, which needs a Master-Detail parent. Separate internal and external defaults
   give community and portal users a stricter baseline, and external can never be more permissive
   than internal. Start restrictive and open deliberately.
   Three things about OWD catch people mid-design. **The value set is not uniform:** Case and Lead
   add `ReadWriteTransfer`, Campaign adds `FullAccess`, and Price Book has its own model entirely
   (`ReadSelect`, `Read`, `None`) with external **fixed at `None` and unchangeable** by any API.
   **Some objects are not configurable at all:** User is fixed at Read internally and externally,
   Activity's external default is fixed at Private, and Knowledge article visibility is governed by
   channels rather than OWD. And **OWD changes cascade:** setting Account to Private forces Contact,
   Case and Opportunity to Private and recalculates all four together, while Contract follows Account
   and cannot be set independently. A "just tighten Account" ticket is therefore a four-object change
   with a recalculation window.
2. **Role Hierarchy** — a user inherits access to records owned by anyone below them. This is a
   *quiet* grant: nobody configures it per record, and it is easy to forget that a manager sees
   everything their reports own. "Grant Access Using Hierarchies" can be switched off for **custom**
   objects; on standard objects it is always on and cannot be disabled.
3. **Sharing Rules** — owner-based (records owned by this group go to that group) or criteria-based
   (records matching a field filter go to a group). Guest user sharing rules are a separate,
   deliberately restricted kind. **Model them as immutable:** an owner-based rule allows only its
   access level to be edited afterwards, so changing who it shares from or to fails the deploy and
   becomes a delete-and-recreate. And a normal deploy is **additive**: it never removes a sharing
   rule, which needs a destructive deploy. Both facts belong in the design, not the cleanup.
4. **Manual and Apex Managed Sharing** — a single record shared with a user or group. Apex sharing
   writes `__Share` rows with a **sharing reason**, which is what makes the share recalculable and
   survivable across owner changes. Winter '27 adds an org setting to keep manual shares through an
   ownership transfer, which previously wiped them.
5. **Teams** — Account, Opportunity and Case teams grant named collaborators a defined access level.
6. **Implicit sharing** — grants the platform makes on its own and you cannot configure away. The
   ones that surprise people: read access to a child record grants read on its parent Account;
   Account access grants access to the associated Contacts, Cases and Opportunities under some OWD
   combinations; and portal and community users get implicit access to their own account's records.
   None appear in any sharing rule, and they explain most "why can they see this?" investigations.

### The two narrowing layers, and the difference people get wrong

- **Restriction Rules** genuinely *remove* visibility. Within objects the user already has access to,
  they filter down to a subset — "this user sees only Cases of type Internal". What the rule excludes
  is gone: not in list views, not in reports, not in a user-mode query.
- **Scoping Rules** change only the **default view**. They set which records a user sees *first*
  without changing what they *can* reach: search, a direct link or removing the filter still gets
  there.

"Must not see" is a restriction rule. "Should not have to wade through" is a scoping rule. Using a
scoping rule for a confidentiality requirement is a data leak that looks correct in a demo.

> Full evaluation order, Apex sharing shapes, and edge cases: `references/record-sharing.md`.

## 4. Guest and Integration Users

**Guest users** — public sites and unauthenticated Experience Cloud pages — run under a dedicated
profile with no role, a separate and deliberately weak class of sharing rules, and no access to most
objects. Anything a guest user can reach, the internet can reach. Never assume the guest profile is
restrictive by accident; read what it actually grants. See `dya-lwr-sites`.

**Integration users** get their own user and their own permission set, never a licence borrowed from
a departed admin. Grant exactly the objects and fields the integration touches, and expect API 67.0
user mode to enforce it: an integration that "worked before" and now returns fewer rows was quietly
relying on an over-broad profile.

## 5. How Access Is Enforced in Code

- **`WITH USER_MODE` / `AccessLevel.USER_MODE`** enforce CRUD, FLS and sharing for the running
  user, and are the Apex default from API 67.0.
- **`with sharing`** enforces record sharing on a class, **`without sharing`** ignores it, and
  **`inherited sharing`** follows the caller. From 67.0 an omitted keyword defaults to
  `with sharing`.
- **Triggers run in system mode always** — they see every record and field regardless of the user.
- **Flow** has its own three run contexts, and the record-triggered default bypasses object and
  field permissions. See `dya-flow`.

A too-narrow permission set or OWD therefore makes user-mode code return fewer rows or throw.
Widening permissions to clear the error also exposes that data in reports, list views and the API.
**Fix the model, not the symptom.**

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
| Make a user genuinely unable to see a subset | **Restriction Rule** |
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
| Granting View All Profiles to undo profile filtering | Find what actually needed the profile name |
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

## Summary — The Five Commandments

1. **Two questions, always separate** — what they can *do* (CRUD, FLS, permissions) versus which records they can *see* (sharing).
2. **Additive by design** — minimal profile, capability through permission sets and groups, removal only through muting.
3. **Sharing widens from a restrictive OWD** — hierarchy, rules, manual and Apex sharing, teams, implicit grants; only restriction rules genuinely narrow.
4. **The model is enforced in code** — `with sharing` plus `WITH USER_MODE`; triggers are the system-mode exception.
5. **Least privilege: fix the model, never the symptom.** Widening access to make an error disappear exposes the same data in reports and the API.
