# DataPacks — Moving OmniStudio Between Orgs

OmniScripts, FlexCards, Integration Procedures and Data Mappers are **records**, not metadata, so
they do not move with `sf project deploy`; they travel as **DataPacks** through the Vlocity Build
tool.

Establish this first on a project: an OmniStudio deployment is a second pipeline beside the metadata
one, with its own tool, failure modes and idea of identity.

## The tool

```bash
npm install --global vlocity          # 1.16.0 or later
```

Invoke it against an authenticated CLI org instead of storing credentials:

```bash
vlocity -sfdx.username <alias> -job <job-file>.yaml <command>
```

**Prefer `-sfdx.username` over a username/password properties file.** The password form still works
and still circulates in old runbooks; it puts a credential in a file that ends up committed.

## The commands, in order of use

| Command | Does |
|---|---|
| `validateLocalData` | Checks the local DataPacks before anything touches the org |
| `packGetDiffs` | Shows what would change in the target |
| `packExport` | Pulls DataPacks out of an org into the local project |
| `packDeploy` | Pushes them into an org |
| `packRetry` | Re-attempts the entries that failed |
| `packContinue` | Resumes an interrupted run |
| `packUpdateSettings` | Refreshes the DataPack settings in the org |

**The gate is `validateLocalData`, and it is not optional.** Run it, optionally `packGetDiffs` to see
the blast radius, then `packDeploy`.

Then **`packRetry` repeatedly while the error count drops.** Deployment is order-sensitive, and the
tool resolves that by re-attempting: a pack whose dependency had not landed yet succeeds on the next
pass. Stop when a retry stops improving the count — the remaining errors are real and the table
below applies.

## The job file

```yaml
projectPath: ./vlocity
expansionPath: datapacks
manifest:
    - OmniScript/Account_Create_English
queries:
    - VlocityDataPackType: OmniScript
      query: SELECT Id FROM %vlocity_namespace%__OmniScript__c WHERE %vlocity_namespace%__IsActive__c = true
gitCheck: true
gitCheckKey: myproject
```

`gitCheck` with a `gitCheckKey` gives incremental deploys: only DataPacks changed since the last
recorded commit are processed. On a large estate that is a two-minute deploy instead of a
forty-minute one.

The namespace appears as the **`%vlocity_namespace%`** token, or literally as `vlocity_cmt` for the
industries managed package, or not at all on core OmniStudio.

## Error to cause

Most DataPack failures are identity failures, and the message does not say so:

| Error | Cause |
|---|---|
| `No match found for …` | A dependency the pack references does not exist in the target |
| `Duplicate Results found for … GlobalKey` | Duplicate records in the target for that key |
| `Multiple Imported Records … same Salesforce Record` | Duplicate matching-key records in the **source** |
| `No Configuration Found` | Stale DataPack settings — run `packUpdateSettings`, or set `autoUpdateSettings` |
| SASS or template compile failure | A referenced UI template asset is missing |

The common root cause under the first three: **matching-key strategy and GlobalKey integrity must be
consistent across source and target.** A DataPack is identified by its GlobalKey, so where the same
logical artifact has a different key, every deploy creates duplicates.

`--fixLocalGlobalKeys` regenerates them. It is a real fix and a destructive one — only on explicit
request, after explaining that it rewrites identity for every affected pack.
