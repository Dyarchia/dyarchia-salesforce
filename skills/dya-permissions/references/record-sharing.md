# Record Sharing — Reference (Winter '27 / API v68.0)

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

## The Metadata Behind It

### Org-Wide Defaults

OWD lives on the object itself — `<ObjectName>.object-meta.xml` — as `<sharingModel>` for internal
access and `<externalSharingModel>` for external. Standard objects included: retrieve and deploy them
as `--metadata CustomObject:<ObjectName>`, which reads oddly for `Account` but is correct.

The valid values are **not the same for every object**:

| Object | Values |
|---|---|
| Custom objects | `Private`, `Read`, `ReadWrite`, `ControlledByParent` (needs a Master-Detail field) |
| Case | `Private`, `Read`, `ReadWrite`, **`ReadWriteTransfer`** |
| Lead | `Private`, `Read`, `ReadWrite`, **`ReadWriteTransfer`** |
| Campaign | `Private`, `Read`, `ReadWrite`, **`FullAccess`** |
| Price Book (`Pricebook2`) | **`ReadSelect`** (Use), `Read` (View Only), `None` — the standard values are invalid here |

And some are not configurable at all:

| Object | Fixed at |
|---|---|
| `User` | `Read`, internal **and** external |
| `Activity` | External fixed at `Private`; only internal is configurable |
| `Pricebook2` | External fixed at `None` — immutable through Metadata API, Tooling API and Setup alike |
| Knowledge article | Governed by channel visibility rather than OWD |

Cross-object constraints that turn a one-object ticket into a four-object change:

- Setting **Account** to `Private` forces **Contact**, **Case** and **Opportunity** to Private, and
  all four recalculate together.
- **Contract** follows Account's setting and cannot be set independently.
- External access can never be more permissive than internal.

### Sharing rules

All rules for one object live in a single `sharingRules/<ObjectName>.sharingRules-meta.xml`, under
three element names depending on kind: `sharingCriteriaRules`, `sharingOwnerRules` and
`sharingGuestRules`. Retrieve with `--metadata "SharingRules:<ObjectName>"`.

`<sharedTo>` targets a `<role>`, `<roleAndSubordinates>` or `<group>` — except in guest rules, where
it targets the site guest user. Account sharing rules additionally require an `<accountSettings>`
block with all three of its sub-elements present.

**What is editable after creation, by rule kind:**

| Kind | Editable |
|---|---|
| `sharingOwnerRules` | `<accessLevel>` **only** |
| `sharingCriteriaRules` | `<accessLevel>`, `<criteriaItems>`, `<label>`, `<booleanFilter>` |
| `sharingGuestRules` | `<accessLevel>`, `<criteriaItems>`, `<label>`, `<includeHVUOwnedRecords>` |

**`<sharedTo>` and `<sharedFrom>` cannot be edited in place in any kind.** The platform does not
support it and the deploy fails; the rule has to be deleted and recreated. Design owner-based rules
on the assumption that only their access level will ever change.

### Deleting a rule

A normal `sf project deploy start` is **additive** and will not remove a sharing rule, however
absent it is from the source. Deletion needs a destructive deploy naming the per-kind types —
`SharingCriteriaRule`, `SharingOwnerRule`, `SharingGuestRule` — with members of the form
`<ObjectName>.<RuleFullName>`. A source tree that "no longer has" a rule is not an org that no longer
has it.

### Guest sharing rules, specifically

Guest rules are the mechanism behind exposing records to an unauthenticated site visitor, and they
have their own shape:

- `<sharedTo><guestUser>…</guestUser></sharedTo>`, where the value is the site guest user's
  **`CommunityNickname`** — not the site's URL path prefix, and not a `<role>` or `<group>`.
- **`<includeHVUOwnedRecords>` is required.** Set it to `false` unless records owned by high-volume
  site users should be included. Omitting it is the most common authoring mistake.
- `<includeRecordsOwnedByAll>` belongs to `sharingCriteriaRules` and **fails** inside a guest rule.
- Guest user Ids start with `005`, like any user.

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
