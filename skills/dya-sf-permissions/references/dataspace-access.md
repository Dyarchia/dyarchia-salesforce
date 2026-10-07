# Data 360 Dataspace Access

Data 360 objects — DMOs, DLOs and Calculated Insight objects — sit outside OWD, role hierarchy and
sharing rules, and are granted through a permission set element with no analogue elsewhere in the
platform.

What a dataspace *is*, and what a DMO or DLO holds, belongs to `dya-sf-data360`.

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

- **`dataAccessLevel`** — what this permission set may do inside the dataspace at all.
- **`objectAccessLevel`** — how far the grant reaches into individual objects. **`BY_POLICY`**
  delegates row and column filtering to central governance policies, so no per-object grants are
  needed and the policy stays in one place. Prefer it when governance policies exist.

Deploy the element only where Data Cloud is provisioned; without it the element is ignored or
rejected depending on the deploy path, so a permission set carrying it is not portable to an
arbitrary org.
`minApiVersion` for the element is 67.0.

## Object grants go through a Connect API, not metadata

Script the Connect API calls for object grants and keep the script in the repo beside the
permission set, so the grants are reproducible.

Grants on individual **DMO, DLO and CIO** objects are made at runtime through the **Object Access
Grants Connect API**. There is no metadata for them, so they are not in source control and a fresh
org needs them replayed rather than deployed.

## Entities SOQL cannot query

**Never query `DataspaceScope` or `DataspaceScopeAccess` with SOQL; neither is queryable.** A query
against either returns `INVALID_TYPE` whatever permissions are granted, which looks like a
permissions problem.

Inspect what a permission set grants by retrieving it through the Metadata API and reading the
`<dataspaceScopes>` blocks:

```bash
sf project retrieve start --metadata PermissionSet:Marketing_Analytics --target-org <alias>
```

## Where this connects

- A permission set carrying `<dataspaceScopes>` is otherwise ordinary — assignment order, licences
  and muting behave normally.
- What the granted objects contain, and how to query them once granted:
  `dya-sf-data360`.
