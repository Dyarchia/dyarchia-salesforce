# DevOps Center — `sf devops`

A top-level topic driving DevOps Center from the command line: projects, pipelines, stages, work
items, reviews and promotions. It is the scriptable face of what DevOps Center otherwise does through
Setup.

Two of its behaviours will mislead an automation that treats it like the rest of the CLI, and both
are covered at the end. Read those before writing a promotion script.

## Command surface

```bash
# Projects
sf devops project list   --target-org <a>
sf devops project create --name <n> --description <d> --target-org <a>
sf devops project update --project-id <1Qg…> --is-active

# Pipelines
sf devops pipeline list | get --pipeline-id <id>
sf devops pipeline create --name <n> --activate
sf devops pipeline update --pipeline-id <id>
sf devops pipeline project add | delete --pipeline-id <id>
sf devops pipeline stage   add | delete | update --pipeline-id <id>
sf devops stage environment add | delete --pipeline-id <id>

# Work items
sf devops work-item list | create | update --project-id <1Qg…>
sf devops work-item prepare | combine     --work-item-id <id>
sf devops review create --work-item-name <n>

# Promotion
sf devops promote
sf devops promotion validate --work-item-id <id> --target-stage-id <id>
sf devops promotion complete --work-item-id <id>
sf devops request status -i <requestToken> -o <a>
sf devops conflict …
```

Id prefixes worth recognising in output: **`1Qg…`** a DevOps Center project, **`0Xt…`** a promotion
request.

## Gotcha 1 — the async id changes name between commands

`sf devops promote` returns the async identifier as **`.result.requestId`**. `sf devops request
status` echoes the same value back as **`.result.requestToken`**. A script that reads one field name
throughout works until it does not.

Capture it defensively:

```bash
token=$(sf devops promote --json | jq -r '
    .result.requestId
    // .result.requestToken
    // .result.promotionId
    // .result.asyncOperationId')
```

## Gotcha 2 — status reports the request, not the outcome

This is the one that turns a red deploy into a green pipeline.

`sf devops request status` tells you how the *request* is progressing. Statuses are uppercase and
prefixed by the operation — `PROMOTE_IN_PROGRESS`, `PROMOTE_SUCCESS`, `DEPLOY_FAILED` — so match on
the **suffix**, never on the whole string, or a new operation prefix silently stops matching.

**The outcome oracle is `.result.errorDetails`,** not the status:

- `null` — the operation succeeded.
- Anything else — it failed, and the value is an **escaped JSON string** carrying `errorType` and
  `errorMessage`, so it needs a second parse.

**A `*_SUCCESS` status with a non-null `errorDetails` means the operation FAILED.** The request was
processed successfully; what it was asking for was not. Gate on `errorDetails` and use the status
only to decide whether to keep polling.

```bash
sf devops request status -i "$token" -o "$alias" --json > out.json
status=$(jq -r '.result.status' out.json)
details=$(jq -r '.result.errorDetails // "null"' out.json)

case "$status" in
    *_IN_PROGRESS) : keep polling ;;
    *) [ "$details" = "null" ] || { echo "failed: $details" >&2; exit 1; } ;;
esac
```
