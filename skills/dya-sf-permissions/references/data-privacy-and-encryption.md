# Regulated Data — Encryption, Subject Requests, and Masking

The third axis of the access model: what a value looks like at rest, what to hand back when a person
requests their data, and how production data is made safe to copy into a sandbox. The three are
configured through different APIs; each section names which API owns which entity.

## Shield Platform Encryption

Encryption is set per field, on `CustomField`, through the `encryptionScheme` element (API 44.0+).

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>NationalId__c</fullName>
    <type>Text</type>
    <length>32</length>
    <encryptionScheme>CaseInsensitiveDeterministicEncryption</encryptionScheme>
</CustomField>
```

**The enum has exactly four values**; any other string fails the deployment:

| Value | Filterable / sortable / groupable | Use when |
|---|---|---|
| `CaseInsensitiveDeterministicEncryption` | Yes | You must still match on the value and case is noise |
| `CaseSensitiveDeterministicEncryption` | Yes | You must match on the value exactly |
| `ProbabilisticEncryption` | **No** | The value is only ever displayed, never queried |
| `None` | n/a | Removing encryption from a field |

Probabilistic encryption is stronger because the same plaintext produces different ciphertext each
time, which is why nothing can index it. A field that a report filters on, a SOQL `WHERE` touches,
or a matching rule uses must be deterministic. Switching later means re-encrypting the field and
re-testing every query that touched it.

Shield `encryptionScheme` is **not** Classic Encryption's `EncryptedText` field type, a separate,
older mechanism with its own limitations. Do not mix the two in one design.

### Org-level settings

Two metadata types, both singletons:

- **`PlatformEncryptionSettings`** — whether deterministic encryption is available at all, whether
  field history is encrypted, and the permission governing the master encryption key.
- **`EncryptionKeySettings`** — `enableCacheOnlyKeys`, `enableReplayDetection`,
  `canExternalKeyManagement`, plus the Data 360 and transactional-database toggles.

**`enableReplayDetection` can be set only once `enableCacheOnlyKeys` is `true`.** Enabling Cache-Only
Keys does not turn replay detection on, and a deploy setting both in the wrong order fails.

### Key models

| Model | Where the key material lives | What Salesforce holds |
|---|---|---|
| **BYOK** | You generate it and upload it | Salesforce stores your key material |
| **BYOKMS / EKM** | Your external KMS, permanently | A reference, never the material |
| **Cache-Only Key** | Your endpoint, fetched on demand | Nothing durable — it is cached and re-fetched |

"Bring your own key" is used loosely for all three; their recovery and availability differ, so name
the specific one in any design document.

## Data Subject Requests — `DsarPolicy`

A DSAR policy gathers everything the org holds about one person to hand back. Its `minApiVersion` is
**68.0**.

**Right To Portability is export, not erasure.** A `DsarPolicy` deletes nothing; if the
requirement is deletion, it is the wrong tool.

| Entity | Reached through |
|---|---|
| `DsarPolicy` | Metadata API |
| `DsarPolicyPath` | Metadata API, a child of the policy |
| `DsarPolicyField` | Metadata API, a child of a path |
| `DsarPolicyLog` | **Standard SOQL only** — run history is a query, not a list view |

Execution, status and file retrieval are Connect DSR endpoints rather than metadata.

Hard caps on the traversal tree: **10 children per path, depth 10, 200 nodes total.** A data model
exceeding them needs the policy split before authoring.

A policy is created **INACTIVE** and activated deliberately. Editing an ACTIVE policy requires
deactivating it first, leaving a window where nothing is active.

- **The URL segment is `dsr`, not `dsar`.**
- **A failed run can return HTTP 201.** Read the response envelope and `RequestStatus`; the HTTP
  status is not the outcome.
- An early file retrieval returns `NOT_FOUND` with "this file isn't ready yet"; poll the status
  resource instead of retrying blindly.

## Data Mask

Data Mask rewrites sensitive values in a sandbox refreshed from production. **It is sandbox-only: the run and abort endpoints return 403 in production.**

Two user permissions, granted by API name, gate it:
`PermissionsManageDataMaskPolicies` and `PermissionsAccessDataMaskAndSeed`.

### The per-entity API split

| Entity | Query | Write |
|---|---|---|
| `DataMaskPolicy` | **Tooling API** (Id prefix `8dm`) | A thin **Metadata API** shell, then Tooling |
| `DataMaskPolicyObject` | **Tooling API** | Tooling API |
| `DataMaskPolicyField` | **Tooling API** | Tooling API |
| `DataMaskPolicyJobRun` | Standard SOQL | — |
| `DataMaskPolicyJobRunDtl` | Standard SOQL (FK `DataMaskPolicyJobRunId`) | — |
| `DataMaskCustomValueLibrary` | Standard SOQL | — |

`sf sobject describe --sobject DataMaskPolicy` returns `NOT_FOUND`, and
`SELECT ... FROM DataMaskPolicy` through `sf data query` returns `INVALID_TYPE`. Neither means the
feature is missing.

### Authoring order

1. Deploy the policy shell through the **Metadata API in mdapi format** — a `--metadata-dir` with a
   `package.xml`. A source-format `--source-dir` deploy fails with "Could not infer a metadata type".
   The shell carries only `<label>`, `<description>` and `<runOnRefresh>`; its directory is
   `dataMaskPolicies` and it declares no child XML names.
2. **Then** insert the `DataMaskPolicyObject` and `DataMaskPolicyField` rows through the Tooling API.

Reversed, it fails with `INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY`: the children have nothing to
attach to.

### Field treatment and row filtering

A `DataMaskPolicyField` carries **`MaskingCategory`** (`library` or `replaceRandom`) and
**`MaskValue`**. There is no `MaskingRuleType` column.

Row subsetting lives on `DataMaskPolicyObject` as `FilterEnabled` plus `WhereCriteria`, a SOQL-style
predicate capped at **40 characters**, with the structured form in `RawFilterData`.

- **There is no `sampleSize`, and a `LIMIT` is silently ignored** — the run masks the whole table
  with no error.
- `RawFilterData.operation` accepts only `eq, ne, lt, gt, ge, le, contains, not_contains, in,
  not_in`. Anything else — `startsWith`, for instance — fails the run with a **422**.
- The predicate must be valid SOQL. `Id != 'null'` fails the job with `invalid ID field: null`,
  because the string `'null'` is not the null literal.

Scheduling lives on the policy itself: `RunFrequency` (`once`, `daily`, `weekly`, `monthly`),
`ScheduledStart`, and `RunOnRefresh` to mask automatically on every sandbox refresh; prefer it to masking manually
after each refresh.

## Where this connects

- Encryption and field-level security are independent: encrypting a field does not substitute for FLS
  on it. See
  `references/object-and-field-access.md`.
- Data 360 has its own access layer that these do not cover — see `references/dataspace-access.md`
  and `dya-sf-data360`.
