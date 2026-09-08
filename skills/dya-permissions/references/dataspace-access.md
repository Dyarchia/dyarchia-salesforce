# Data 360 Dataspace Access

Data 360 does not reuse the core sharing model. Its objects — DMOs, DLOs and Calculated Insight
objects — sit outside OWD, role hierarchy and sharing rules, and are granted through a permission
set element that has no analogue anywhere else in the platform.

This file covers the access layer only. What a dataspace *is*, and what a DMO or DLO holds, belongs
to `dya-data360`.

## `dataspaceScopes` on a permission set

A `PermissionSet` gains one `<dataspaceScopes>` block per dataspace it grants. Removing a block
revokes that grant; there is no separate revoke operation.

```xml
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Marketing Analytics</label>
    <dataspaceScopes>
        <dataspace>Marketing</dataspace>
        <dataAccessLevel>Read</dataAccessLevel>
        <objectAccessLevel>BY_POLICY</objectAccessLevel>
    </dataspaceScopes>
</PermissionSet>
```

Two levels, and they answer different questions:

- **`dataAccessLevel`** — what this permission set may do inside the dataspace at all.
- **`objectAccessLevel`** — how far the grant reaches into individual objects. Setting it to
  **`BY_POLICY`** delegates row and column filtering to central governance policies, which means no
  per-object grants are needed and the policy stays in one place. Prefer it when governance policies
  exist; the alternative scatters equivalent rules across permission sets.

Requires Data Cloud to be provisioned. On an org without it the element is ignored or rejected
depending on the deploy path, so a permission set carrying it is not portable to an arbitrary org.
`minApiVersion` for the element is 67.0.

## Object grants go through a Connect API, not metadata

Grants on individual **DMO, DLO and CIO** objects are made at runtime through the **Object Access
Grants Connect API**. There is no metadata deploy for them, which has a practical consequence: this
part of the access model is not in source control alongside the permission set that references it,
and a fresh org needs the grants replayed rather than deployed.

Treat that as a design constraint, not an oversight. If the grants must be reproducible, script the
Connect API calls and keep the script in the repo beside the permission set.

## The two entities you cannot query with SOQL

**`DataspaceScope` and `DataspaceScopeAccess` are not SOQL-queryable.** A query against either
returns `INVALID_TYPE`, and no amount of permission granting changes that.

To inspect what a permission set actually grants, retrieve it through the Metadata API and read the
`<dataspaceScopes>` blocks:

```bash
sf project retrieve start --metadata PermissionSet:Marketing_Analytics --target-org <alias>
```

Do not fall back to SOQL when that feels slower. There is no view of these entities through the
query API, so a SOQL attempt is not a slower path to the same answer — it is a dead end that reads
like a permissions problem.

## Where this connects

- The permission set carrying `<dataspaceScopes>` is an ordinary permission set in every other
  respect — assignment order, licences and muting all behave normally. See
  `references/object-and-field-access.md`.
- What the granted objects contain, and how to query them once granted:
  `dya-data360`.
