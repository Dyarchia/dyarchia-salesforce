# DataPacks — Moving OmniStudio Between Orgs

OmniStudio artifacts do not move with `sf project deploy`. OmniScripts, FlexCards, Integration
Procedures and Data Mappers are **records**, not metadata, so they travel as **DataPacks** through the
Vlocity Build tool.

This is the first thing to establish on a project: an OmniStudio deployment is a second pipeline
beside the metadata one, with its own tool, its own failure modes and its own idea of identity.

## The tool

```bash
npm install --global vlocity          # 1.16.0 or later
```

Invoke it against an authenticated CLI org rather than storing credentials:

```bash
vlocity -sfdx.username <alias> -job <job-file>.yaml <command>
```

**Prefer `-sfdx.username` over a username/password properties file.** The password form still works
and is still in circulation in old runbooks; it puts a credential in a file that ends up committed.

## The commands, in the order they are used

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

Then **`packRetry` repeatedly while the error count is dropping.** DataPack deployment is
order-sensitive in ways the tool resolves by re-attempting: a pack that failed because its dependency
had not landed yet will succeed on the next pass. Stop when a retry stops improving the count — at
that point the remaining errors are real and the table below applies.

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
recorded commit are processed. On a large OmniStudio estate this is the difference between a
two-minute deploy and a forty-minute one.

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

The common root cause under the first three: **matching-key strategy and GlobalKey integrity have to
be consistent across source and target.** A DataPack is identified by its GlobalKey, so an org where
the same logical artifact has a different key is an org where every deploy creates duplicates.

`--fixLocalGlobalKeys` regenerates them. It is a real fix and a destructive one — only on explicit
request, and only after explaining that it rewrites identity for every affected pack.
