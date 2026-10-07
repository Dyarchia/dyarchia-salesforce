# Record Sharing — Reference (Winter '27 / API v68.0)

The "which records can the user see" axis of `dya-sf-permissions`.

## Layer Details

- **OWD values:**
  - **Private** — only the owner and those above in the role hierarchy.
  - **Public Read Only** — everyone reads; only the owner and hierarchy edit.
  - **Public Read/Write** — everyone reads and edits.
  - **Controlled by Parent** — inherits the parent's access (detail and junction objects).
- **Guest user sharing rules** are read-only and never use the role hierarchy.
- **Manual sharing** — a user or admin shares one record with a user, group or role; available only
  when the OWD is more restrictive than Public Read/Write.

## Apex Managed Sharing — Shape

```apex
// Share an Account with read access, reason-coded.
AccountShare share = new AccountShare(
    AccountId          = acctId,
    UserOrGroupId      = groupOrUserId,
    AccountAccessLevel = 'Read',          // 'Read' | 'Edit'
    OpportunityAccessLevel = 'None',      // required for AccountShare
    RowCause           = Schema.AccountShare.RowCause.Manual   // or a custom Apex sharing reason
);
insert share;
```

For managed logic, use a custom **Apex sharing reason** defined on the object, not
`RowCause.Manual`; the custom reason enables recalculation and clean maintenance. Apex managed
sharing requires the right permissions. Custom objects use `MyObject__Share` with `AccessLevel` and
`RowCause`.

## The Metadata Behind It

### Org-Wide Defaults

OWD lives on the object itself — `<ObjectName>.object-meta.xml` — as `<sharingModel>` for internal
access and `<externalSharingModel>` for external. Standard objects, `Account` included, are retrieved
and deployed as `--metadata CustomObject:<ObjectName>`.

Valid values:

| Object | Values |
|---|---|
| Custom objects | `Private`, `Read`, `ReadWrite`, `ControlledByParent` (needs a Master-Detail field) |
| Case | `Private`, `Read`, `ReadWrite`, **`ReadWriteTransfer`** |
| Lead | `Private`, `Read`, `ReadWrite`, **`ReadWriteTransfer`** |
| Campaign | `Private`, `Read`, `ReadWrite`, **`FullAccess`** |
| Price Book (`Pricebook2`) | **`ReadSelect`** (Use), `Read` (View Only), `None` — the standard values are invalid here |

Not configurable:

| Object | Fixed at |
|---|---|
| `User` | `Read`, internal **and** external |
| `Activity` | External fixed at `Private`; only internal is configurable |
| `Pricebook2` | External fixed at `None` — immutable through Metadata API, Tooling API and Setup alike |
| Knowledge article | Governed by channel visibility rather than OWD |

### Sharing rules

All rules for one object live in one `sharingRules/<ObjectName>.sharingRules-meta.xml`, under three
element names by kind: `sharingCriteriaRules`, `sharingOwnerRules` and `sharingGuestRules`.
Retrieve with `--metadata "SharingRules:<ObjectName>"`.

`<sharedTo>` targets a `<role>`, `<roleAndSubordinates>` or `<group>` — except in guest rules, where
it targets the site guest user. Account sharing rules also require an `<accountSettings>` block
with all three of its sub-elements present.

Editable after creation:

| Kind | Editable |
|---|---|
| `sharingOwnerRules` | `<accessLevel>` **only** |
| `sharingCriteriaRules` | `<accessLevel>`, `<criteriaItems>`, `<label>`, `<booleanFilter>` |
| `sharingGuestRules` | `<accessLevel>`, `<criteriaItems>`, `<label>`, `<includeHVUOwnedRecords>` |

**Never edit `<sharedTo>` or `<sharedFrom>` in place, in any kind**; the deploy fails. Delete and
recreate the rule.

### Deleting a rule

Delete a rule with a destructive deploy; `sf project deploy start` does not remove a sharing rule
absent from the source. Name the per-kind types — `SharingCriteriaRule`, `SharingOwnerRule`,
`SharingGuestRule` — with members of the form `<ObjectName>.<RuleFullName>`.

### Guest sharing rules

- `<sharedTo><guestUser>…</guestUser></sharedTo>`, where the value is the site guest user's
  **`CommunityNickname`** — not the site's URL path prefix, and not a `<role>` or `<group>`.
- **`<includeHVUOwnedRecords>` is required.** Set it to `false` unless records owned by high-volume
  site users should be included.
- Never put `<includeRecordsOwnedByAll>` in a guest rule; it belongs to `sharingCriteriaRules` and
  **fails** there.
- Guest user Ids start with `005`, like any user.

## Design Rules

- Prefer **declarative sharing rules** over Apex sharing where criteria or ownership suffices.
