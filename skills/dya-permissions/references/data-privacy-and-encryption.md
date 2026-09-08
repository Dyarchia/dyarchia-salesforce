# Regulated Data — Encryption, Subject Requests, and Masking

The third axis of the access model. "What can they do" and "which records" decide who reaches a
value; this file covers what the value itself looks like at rest, what has to be handed back when a
person asks for their data, and how production data is made safe to copy into a sandbox.

All three are configured through different APIs, and the split is the thing people get wrong most
often — so each section names which API owns which entity.

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

**The enum has exactly four values.** Any other string fails the deployment outright:

| Value | Filterable / sortable / groupable | Use when |
|---|---|---|
| `CaseInsensitiveDeterministicEncryption` | Yes | You must still match on the value and case is noise |
| `CaseSensitiveDeterministicEncryption` | Yes | You must match on the value exactly |
| `ProbabilisticEncryption` | **No** | The value is only ever displayed, never queried |
| `None` | n/a | Removing encryption from a field |

This is the trade-off that decides the design: probabilistic encryption is the stronger guarantee
because the same plaintext produces different ciphertext each time, and that is precisely why nothing
can index it. A field that a report filters on, a SOQL `WHERE` touches, or a matching rule uses has
to be deterministic. Choosing probabilistic and discovering this later means re-encrypting the field
and re-testing every query that touched it.

Shield `encryptionScheme` is **not** the same feature as Classic Encryption's `EncryptedText` field
type. Classic Encryption is a separate, older mechanism with its own limitations; do not mix the two
in one design or in one sentence.

### Org-level settings

Two metadata types, both singletons:

- **`PlatformEncryptionSettings`** — whether deterministic encryption is available at all, whether
  field history is encrypted, and the permission governing the master encryption key.
- **`EncryptionKeySettings`** — `enableCacheOnlyKeys`, `enableReplayDetection`,
  `canExternalKeyManagement`, plus the Data 360 and transactional-database toggles.

**`enableReplayDetection` can only be set once `enableCacheOnlyKeys` is already `true`.** Enabling
Cache-Only Keys does not turn replay detection on for you, and a deploy that sets both in one pass
in the wrong order fails.

### Three key models, often conflated

| Model | Where the key material lives | What Salesforce holds |
|---|---|---|
| **BYOK** | You generate it and upload it | Salesforce stores your key material |
| **BYOKMS / EKM** | Your external KMS, permanently | A reference, never the material |
| **Cache-Only Key** | Your endpoint, fetched on demand | Nothing durable — it is cached and re-fetched |

"Bring your own key" is used loosely in conversation for all three. They have materially different
recovery and availability stories, so name the specific one in any design document.

## Data Subject Requests — `DsarPolicy`

A DSAR policy describes how to gather everything the org holds about one person so it can be handed
back. Its `minApiVersion` is **68.0**, which makes it the one piece of this material that arrives at
the version this library targets rather than below it.

**Right To Portability is export, not erasure.** A `DsarPolicy` deletes nothing, ever. If the
requirement is deletion, this is the wrong tool and saying so early saves a rebuild.

Four entities, three different APIs:

| Entity | Reached through |
|---|---|
| `DsarPolicy` | Metadata API |
| `DsarPolicyPath` | Metadata API, a child of the policy |
| `DsarPolicyField` | Metadata API, a child of a path |
| `DsarPolicyLog` | **Standard SOQL only** — run history is a query, not a list view |

Execution, status and file retrieval are Connect DSR endpoints rather than metadata.

Hard structural caps on the traversal tree: **10 children per path, depth 10, 200 nodes total.** A
data model wide enough to exceed them needs the policy split, and that is a modelling decision to
make before authoring rather than after a rejection.

Lifecycle: a policy is created **INACTIVE**. Activating it is a deliberate step, and editing an
ACTIVE policy requires deactivating first — so a change to a live policy is a three-step operation
with a window where nothing is active.

Three traps worth knowing before the first attempt:

- **The URL segment is `dsr`, not `dsar`.** The entity is spelled one way and the endpoint the
  other.
- **A failed run can return HTTP 201.** Read the response envelope and `RequestStatus`; the HTTP
  status is not the outcome.
- An early file retrieval returns `NOT_FOUND` with "this file isn't ready yet". That is the contract
  working, not an error to retry against blindly — poll the status resource instead.

## Data Mask

Data Mask rewrites sensitive values in a sandbox so a refreshed copy of production is safe to work
in. **It is sandbox-only: the run and abort endpoints return 403 in production.**

Two user permissions gate it, and they are worth knowing by API name because they are the kind of
thing a permission set has to grant explicitly: `PermissionsManageDataMaskPolicies` and
`PermissionsAccessDataMaskAndSeed`.

### The per-entity API split

This is the part that wastes an afternoon if you guess:

| Entity | Query | Write |
|---|---|---|
| `DataMaskPolicy` | **Tooling API** (Id prefix `8dm`) | A thin **Metadata API** shell, then Tooling |
| `DataMaskPolicyObject` | **Tooling API** | Tooling API |
| `DataMaskPolicyField` | **Tooling API** | Tooling API |
| `DataMaskPolicyJobRun` | Standard SOQL | — |
| `DataMaskPolicyJobRunDtl` | Standard SOQL (FK `DataMaskPolicyJobRunId`) | — |
| `DataMaskCustomValueLibrary` | Standard SOQL | — |

Consequences you will hit immediately: `sf sobject describe --sobject DataMaskPolicy` returns
`NOT_FOUND`, and `SELECT ... FROM DataMaskPolicy` through `sf data query` returns `INVALID_TYPE`.
Neither means the feature is missing.

### Authoring is two ordered steps

1. Deploy the policy shell through the **Metadata API in mdapi format** — a `--metadata-dir` with a
   `package.xml`. A source-format `--source-dir` deploy fails with "Could not infer a metadata type".
   The shell carries only `<label>`, `<description>` and `<runOnRefresh>`; its directory is
   `dataMaskPolicies` and it declares no child XML names.
2. **Then** insert the `DataMaskPolicyObject` and `DataMaskPolicyField` rows through the Tooling API.

Reversing the order fails with `INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY`, because the children
have nothing to attach to.

### Field treatment and row filtering

A `DataMaskPolicyField` carries **`MaskingCategory`** (`library` or `replaceRandom`) and
**`MaskValue`**. There is no `MaskingRuleType` column, however plausible the name looks.

Row subsetting lives on `DataMaskPolicyObject` as `FilterEnabled` plus `WhereCriteria`, a SOQL-style
predicate capped at **40 characters**, with the structured form in `RawFilterData`. Three things to
know:

- **There is no `sampleSize`, and a `LIMIT` is silently ignored** — the run masks the whole table.
  This is the failure mode with no error message, so never assume a limit took effect.
- `RawFilterData.operation` accepts only `eq, ne, lt, gt, ge, le, contains, not_contains, in,
  not_in`. Anything else — `startsWith`, for instance — fails the run with a **422**.
- The predicate must be valid SOQL. `Id != 'null'` fails the job with `invalid ID field: null`,
  because the string `'null'` is not the null literal.

Scheduling lives on the policy itself: `RunFrequency` (`once`, `daily`, `weekly`, `monthly`),
`ScheduledStart`, and `RunOnRefresh` to mask automatically whenever the sandbox is refreshed. The
last one is usually what you actually want — a masking policy that has to be remembered after every
refresh is a policy that will be forgotten after some refresh.

## Where this connects

- Field-level security decides who sees a field at all; encryption decides what the value looks like
  underneath. They are independent, and encrypting a field is not a substitute for FLS on it. See
  `references/object-and-field-access.md`.
- Data 360 has its own access layer that these do not cover — see `references/dataspace-access.md`
  and `dya-data360`.
