# DataPacks — Moving OmniStudio Between Orgs

## The tool

```bash
npm install --global vlocity          # 1.16.0 or later
```

Run it against an authenticated CLI org:

```bash
vlocity -sfdx.username <alias> -job <job-file>.yaml <command>
```

**Prefer `-sfdx.username` over a username/password properties file**, which puts a credential in a
file that ends up committed.

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

**`validateLocalData` is not optional.** A pack whose dependency had not landed succeeds on the next
`packRetry` pass. Stop retrying when the error count stops dropping; the remaining errors are real
and the table below applies.

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
recorded commit are processed; on a large estate, two minutes instead of forty.

The namespace appears as the **`%vlocity_namespace%`** token, or literally as `vlocity_cmt` for the
industries managed package, or not at all on core OmniStudio.

## Error to cause

Most DataPack failures are identity failures; the message does not say so.

| Error | Cause |
|---|---|
| `No match found for …` | A dependency the pack references does not exist in the target |
| `Duplicate Results found for … GlobalKey` | Duplicate records in the target for that key |
| `Multiple Imported Records … same Salesforce Record` | Duplicate matching-key records in the **source** |
| `No Configuration Found` | Stale DataPack settings — run `packUpdateSettings`, or set `autoUpdateSettings` |
| SASS or template compile failure | A referenced UI template asset is missing |

Root cause of the first three: **matching-key strategy and GlobalKey integrity must be consistent
across source and target.** Where the same logical artifact has a different key, every deploy creates
duplicates.

`--fixLocalGlobalKeys` regenerates them. It is destructive: run it only on explicit request, after
explaining that it rewrites identity for every affected pack.
