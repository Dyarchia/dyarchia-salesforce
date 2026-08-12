# sf CLI — Metadata & Data (2026)

Load from `decimatio-sf-cli`. Catalog for `project` (deploy/retrieve/generate), `data`, `sobject`/`generate metadata`, and `schema`. All `sf` v2.

## Project Scaffolding (`sf project generate`)

```bash
sf project generate --name <proj> [--default-package-dir force-app] [--manifest]
sf project generate manifest --source-dir force-app --name package
sf project generate manifest --from-org <a> --include-packages managed
```

## Deploy (`sf project deploy`)

```bash
sf project deploy start --source-dir force-app
sf project deploy start --metadata ApexClass:MyClass --metadata ApexTrigger
sf project deploy start --manifest manifest/package.xml --test-level RunLocalTests
sf project deploy validate --source-dir force-app --test-level RunLocalTests   # check-only
sf project deploy quick --job-id <validatedId>                                  # promote a validation
sf project deploy preview --source-dir force-app                                # diff/dry-run
sf project deploy report --job-id <id>
sf project deploy resume --job-id <id>
sf project deploy cancel --job-id <id>
```

Test levels: `NoTestRun`, `RunSpecifiedTests` (+ `--tests`), `RunLocalTests`, `RunAllTestsInOrg`. Production deploys require tests.

## Retrieve (`sf project retrieve`)

```bash
sf project retrieve start --source-dir force-app
sf project retrieve start --metadata ApexClass:MyClass
sf project retrieve start --manifest manifest/package.xml
sf project retrieve preview --target-org <a>
sf project retrieve start --package-name "My Managed Package"
```

## Source Tracking (scratch/sandbox)

```bash
sf project deploy start            # respects local source tracking
sf project retrieve start          # pulls remote changes
sf project reset tracking --target-org <a>
```

## Data — Records (`sf data`)

```bash
# Query
sf data query --query "SELECT Id, Name FROM Account LIMIT 50"
sf data query --query "SELECT Id FROM Account" --bulk --wait 5           # Bulk API 2.0
sf data query --query "..." --result-format csv > out.csv

# Single-record CRUD
sf data create record --sobject Account --values "Name='Acme' Industry='Tech'"
sf data get record --sobject Account --record-id 001...
sf data update record --sobject Account --record-id 001... --values "Industry='Finance'"
sf data delete record --sobject Account --record-id 001...

# Bulk + tree
sf data import bulk --sobject Account --file accounts.csv --wait 10
sf data export bulk --query "SELECT Id, Name FROM Account" --output-file accounts.csv --wait 10
sf data import tree --files data/Account.json data/Contact.json
sf data export tree --query "SELECT Id, Name, (SELECT LastName FROM Contacts) FROM Account" --output-dir data --plan
sf data delete bulk --sobject Account --file ids.csv --wait 10
sf data upsert bulk --sobject Account --file accounts.csv --external-id External_Id__c --wait 10
```

## Schema & Metadata Generation (`sf sobject` / `sf schema` / `generate metadata`)

```bash
sf sobject describe --sobject Account --target-org <a>
sf sobject list --sobject all --target-org <a>
sf schema generate field --label "My Field" --object force-app/.../Account/Account.object-meta.xml
sf schema generate sobject --label "My Object"
sf schema generate platformevent --label "Order Placed"
sf schema generate tab --output-dir force-app/.../tabs --icon 1 --directory-name MyObject__c
```

## API Passthrough (`sf api`)

```bash
sf api request rest "/services/data/v67.0/limits" --target-org <a>
sf api request rest "/services/data/v67.0/sobjects/Account/001..." --method GET
sf api request graphql --body query.graphql --target-org <a>
```

## Notes

- Prefer **`--bulk`** / `import|export bulk` for large data sets (Bulk API 2.0); `tree` for related sample data with relationships.
- `upsert bulk --external-id` is the idempotent load pattern.
- `--json` everywhere for automation; `--result-format csv|human|json` on queries.
