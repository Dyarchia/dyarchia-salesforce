# Record Sharing — Reference (Summer '26)

Load from `dya-permissions` for the "which records can the user see" axis. Access widens through a pipeline from a restrictive baseline; restriction/scoping rules narrow.

## Evaluation Pipeline (widening)

1. **Org-Wide Defaults (OWD)** — the floor, per object:
   - **Private** — only the owner (and those above in the role hierarchy).
   - **Public Read Only** — everyone reads, only owner/hierarchy edits.
   - **Public Read/Write** — everyone reads and edits.
   - **Controlled by Parent** — inherits the parent's access (detail/junction objects).
   - Internal vs External OWD let you set a stricter default for community/portal users.
2. **Role Hierarchy** — when "Grant Access Using Hierarchies" is on, users inherit access to records owned by subordinates. (Can be disabled for custom objects.)
3. **Sharing Rules** — open records beyond OWD:
   - **Owner-based** — share records owned by a group/role with another group/role.
   - **Criteria-based** — share records matching field criteria.
   - **Guest user sharing rules** — separate, tightly restricted (read-only, no role hierarchy).
4. **Manual Sharing** — a user/admin shares a single record with a user/group/role (only when OWD is more restrictive than Public R/W).
5. **Apex Managed Sharing** — programmatic sharing by writing `Object__Share` / `AccountShare` rows with an `AccessLevel` and a **sharing reason** (custom apex reason for maintainable, recalculable shares). Requires the right permissions; survives owner changes when reason-coded.
6. **Teams** — Account, Opportunity, and Case Teams grant named collaborators a defined access level.
7. **Implicit Sharing** — platform built-in: e.g. access to a child record can grant read on its parent Account; portal/community implicit shares. Not configurable.

## Narrowing Layers

- **Restriction Rules** — within objects the user already accesses, filter to a subset (e.g. "only Cases of type Internal"). They *remove* visibility that other layers granted.
- **Scoping Rules** — set the *default* records a user sees (a convenience filter); they don't change what the user *can* access if they search/relist.

## Resulting Access

A user's access to a record = the **most permissive** grant from OWD/hierarchy/rules/manual/Apex/teams/implicit, then **narrowed** by any applicable restriction rule. To *act* on the record they also need the matching **object CRUD + FLS** (the other axis).

## Apex Managed Sharing — Shape

```apex
// Share an Account programmatically with read access, reason-coded.
AccountShare share = new AccountShare(
    AccountId          = acctId,
    UserOrGroupId      = groupOrUserId,
    AccountAccessLevel = 'Read',          // 'Read' | 'Edit'
    OpportunityAccessLevel = 'None',      // required for AccountShare
    RowCause           = Schema.AccountShare.RowCause.Manual   // or a custom Apex sharing reason
);
insert share;
```

Custom objects use `MyObject__Share` with `AccessLevel` and `RowCause` (a custom **Apex sharing reason** defined on the object enables recalculation and clean maintenance). `with sharing`/`without sharing` on the class controls whether record sharing is enforced when querying.

## Design Rules

- Start OWD **Private** (or Read Only) and open deliberately; don't default to Public R/W.
- Prefer **declarative sharing rules** over Apex sharing where criteria/ownership suffices.
- Use **Apex managed sharing with a custom reason** for complex, recalculable programmatic shares.
- Use **restriction rules** to enforce need-to-know within broad access (e.g. HR records).
- Remember the role hierarchy quietly grants upward access — model managers' visibility intentionally.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Public Read/Write OWD as a shortcut | Restrictive OWD + targeted sharing |
| Apex sharing where a criteria rule suffices | Declarative sharing rule |
| Apex shares with `RowCause.Manual` for managed logic | Custom Apex sharing reason (recalculable) |
| Forgetting CRUD/FLS — "they can see it but can't edit" | Grant both axes: sharing *and* object/field access |
| Using "Modify All Data" to bypass a sharing gap | Scoped sharing + View/Modify All on the object |
| Ignoring the role hierarchy's upward grant | Design manager visibility explicitly |
| Assuming triggers honor sharing | Triggers run system mode; filter explicitly |
