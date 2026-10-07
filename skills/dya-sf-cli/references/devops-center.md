# DevOps Center — `sf devops`

A top-level topic that scripts what DevOps Center otherwise does through Setup: projects,
pipelines, stages, work items, reviews and promotions.

Before writing a promotion script, read the two gotchas at the end.

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

Id prefixes in output: **`1Qg…`** a DevOps Center project, **`0Xt…`** a promotion
request.

## Gotcha 1 — the async id changes name between commands

`sf devops promote` returns the async identifier as **`.result.requestId`**; `sf devops request
status` echoes it back as **`.result.requestToken`**. Capture it
defensively:

```bash
token=$(sf devops promote --json | jq -r '
    .result.requestId
    // .result.requestToken
    // .result.promotionId
    // .result.asyncOperationId')
```

## Gotcha 2 — status reports the request, not the outcome

`sf devops request status` reports how the *request* is progressing. Statuses are uppercase and
prefixed by the operation — `PROMOTE_IN_PROGRESS`, `PROMOTE_SUCCESS`, `DEPLOY_FAILED` — so match the
**suffix**, never the whole string, or a new operation prefix silently stops matching.

**The outcome oracle is `.result.errorDetails`,** not the status:

- `null` — the operation succeeded.
- Anything else — it failed; the value is an **escaped JSON string** carrying `errorType` and
  `errorMessage`, needing a second parse.

**A `*_SUCCESS` status with a non-null `errorDetails` means the operation FAILED.** Use the status
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
