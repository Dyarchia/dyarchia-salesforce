---
name: dya-permissions
description: Salesforce permissions & sharing model (Summer '26 / API v67.0) — the conceptual reference so an agent knows the access model end to end. Profiles, permission sets, permission set groups and muting, the "who sees what" sharing model (OWD, role hierarchy, sharing rules, manual/Apex sharing, teams), restriction and scoping rules, field-level security, record types, and how it all interacts with Apex user mode. Load only when the user explicitly invokes this skill by name (`dya-permissions`); do NOT auto-trigger on generic permission or security questions.
---

# Salesforce Permissions & Sharing Model

You are an expert on the Salesforce access model. This skill is **conceptual** — it gives the complete mental model of "who can do what" and "who can see what" so the right design choice is obvious. It pairs with `dya-apex` (user-mode enforcement) and `dya-integration-auth` (authentication, a separate concern). Follow every rule below.

References:
- `references/object-and-field-access.md` — profiles vs permission sets vs permission set groups vs muting; object (CRUD) and field (FLS) permissions; system/user permissions; record types.
- `references/record-sharing.md` — the sharing model: OWD, role hierarchy, sharing rules, manual/Apex sharing, teams, implicit sharing, restriction & scoping rules.

---

## Platform Context — Summer '26 / API v67.0

- **"Minimum access" is the modern default.** Salesforce steers orgs toward a minimal base profile + additive permission sets. Treat profiles as a thin baseline; grant capability through permission sets and permission set groups.
- **Apex v67 user mode** makes this model *enforced in code*: SOQL/DML default to `USER_MODE`, so the running user's object, field, and sharing access now governs what integration/controller code can read and write. The permission model is no longer "just UI" — it shapes code behaviour. See `dya-apex`.
- **Triggers always run in system mode** (all API versions) — they bypass CRUD/FLS/sharing regardless of v67.
- **"Any API Auth" permission** (new v67) gates legacy SOAP `login()` authentication — enforced by default in new orgs. Treat SOAP `login()` as end-of-life; migrate to OAuth + External Client Apps. See `dya-integration-auth`.
- Profiles are not being removed, but feature investment is in **permission sets / permission set groups**; design new access additively.

---

## 1. Two Independent Questions

The model splits into two orthogonal axes. Always reason about them separately.

```
WHAT can the user DO?         →  Object (CRUD) + Field (FLS) + System/User permissions
                                 Source: Profile (baseline) + Permission Sets (+ Groups)

WHICH RECORDS can they SEE?   →  Sharing model
                                 Source: OWD → Role Hierarchy → Sharing Rules →
                                         Manual/Apex sharing → Teams → (Restriction/Scoping rules)
```

Object/field access answers "can this user edit *Accounts* and the *Revenue* field at all?" Sharing answers "which *specific Account records* can they see/edit?" A user needs **both** to act on a record.

---

## 2. WHAT Can They Do — Permissions

### Sources, in additive order
1. **Profile** — exactly one per user; the baseline. Keep it minimal ("Minimum Access - Salesforce").
2. **Permission Sets** — additive grants layered on top; assign many per user.
3. **Permission Set Groups (PSG)** — bundles of permission sets for a role/persona; assign the group.
4. **Muting Permission Sets** — *subtract* specific permissions within a PSG (the only way to remove, since permissions are otherwise purely additive).

Permissions are **additive**: if any assigned source grants a permission, the user has it (except where a muting permission set removes it within a group).

### What they grant
- **Object permissions (CRUD)** — Create / Read / Edit / Delete + View All / Modify All per object.
- **Field-Level Security (FLS)** — Read / Edit per field. A field hidden by FLS is invisible everywhere (UI, API, reports).
- **System & user permissions** — app-wide capabilities (e.g. "Manage Users", "API Enabled", "Author Apex", "Run Flows").
- **Other access** delivered via permission sets: app/tab visibility, Apex class & VF page access, custom permissions, connected/external-app access, record-type access.

### Record Types
Control which **picklist values** and **page layouts** a user sees and which business process applies. Record-type *access* is granted via profile/permission set; it shapes data entry, not record visibility.

Full detail and decision rules: `references/object-and-field-access.md`.

---

## 3. WHICH Records — the Sharing Model

Evaluated as a widening pipeline; each layer can only **open up** access beyond the baseline (except restriction rules, which narrow).

1. **Org-Wide Defaults (OWD)** — the baseline per object: Private, Public Read Only, Public Read/Write, (Controlled by Parent). Start restrictive; open selectively.
2. **Role Hierarchy** — users above in the hierarchy inherit access to records owned by those below (if "Grant Access Using Hierarchies" is on).
3. **Sharing Rules** — owner-based or criteria-based rules that open records to roles/groups. (Guest user sharing rules are separate and tightly governed.)
4. **Manual Sharing / Apex Managed Sharing** — share a specific record with a user/group; Apex sharing (`__Share` rows) for programmatic, reason-coded sharing.
5. **Teams** (Account/Opportunity/Case teams) — grant access to named collaborators.
6. **Implicit sharing** — built-in parent↔child access (e.g. access to a child can grant limited parent visibility) you can't configure away.

### Narrowing layers (newer)
- **Restriction Rules** — *filter down* what a user can see within objects they already have access to (e.g. only their own records of a type).
- **Scoping Rules** — set the *default* set of records a user sees, without changing what they *can* access.

Full evaluation order, Apex sharing, and edge cases: `references/record-sharing.md`.

---

## 4. How Access Is Enforced in Code (the v67 link)

- **`WITH USER_MODE` / `AccessLevel.USER_MODE`** enforce CRUD + FLS + sharing for the running user — now the Apex default at v67.
- **`with sharing`** enforces record sharing on a class; **`without sharing`** ignores it; **`inherited sharing`** takes the caller's mode. At v67, omitted sharing defaults to `with sharing`.
- **Triggers run in system mode** always — they see all records and fields regardless of the user's permissions.
- Practical consequence: a too-narrow permission set or OWD can make user-mode code return fewer rows or throw; widening permissions to "fix" it also exposes data in reports and APIs. Fix the *model*, not the symptom. See `dya-apex`.

---

## 5. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| Baseline access for everyone | Minimal **Profile** (Minimum Access) |
| Grant a capability to some users | **Permission Set** |
| Bundle access for a persona/role | **Permission Set Group** |
| Remove a permission inside a group | **Muting Permission Set** |
| Hide a field everywhere | **Field-Level Security** |
| Control picklists/layouts/process | **Record Type** + page layout |
| Set baseline record visibility | **Org-Wide Defaults** |
| Let managers see reports' records | **Role Hierarchy** |
| Open records to a group by criteria | **Sharing Rule** (criteria-based) |
| Share one record ad hoc | **Manual Sharing** |
| Share records programmatically | **Apex Managed Sharing** (`__Share`) |
| Grant collaborators on a deal | **Account/Opportunity/Case Team** |
| Narrow what a user sees within access | **Restriction Rule** |
| Set a user's default record scope | **Scoping Rule** |
| Enforce all of it in Apex | `with sharing` + `WITH USER_MODE` |

---

## 6. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Piling permissions onto fat profiles | Minimal profile + additive permission sets/PSGs |
| Trying to "remove" a permission by editing the profile inside a PSG | Muting permission set |
| Public Read/Write OWD "to make it work" | Restrictive OWD + targeted sharing |
| Granting "Modify All Data" to solve a sharing gap | Sharing rules / Apex sharing scoped to need |
| Widening FLS/CRUD to silence a v67 user-mode error | Fix the permission set; keep least privilege |
| Confusing record-type access with record visibility | Record types = picklists/layouts; sharing = visibility |
| Assuming a trigger respects the user's sharing | Triggers run in system mode — guard explicitly |
| Using the role hierarchy as the only sharing tool | Combine OWD + rules + (restriction/scoping) by intent |
| Over-broad guest user sharing | Minimal guest profile + guest sharing rules |

---

## Summary — The Five Commandments

1. **Two questions, always separate** — *what can they do* (CRUD/FLS/permissions) vs *which records* (sharing).
2. **Additive by design** — minimal profile, capability via permission sets and groups, removal only via muting.
3. **Sharing widens from a restrictive OWD** — role hierarchy, sharing rules, manual/Apex sharing, teams; restriction/scoping rules narrow.
4. **The model is enforced in code now** — `with sharing` + `WITH USER_MODE`; triggers are the system-mode exception.
5. **Least privilege, fix the model** — never widen access to silence an error; correct the permission/sharing design.
