---
name: dya-sf-cli
description: Salesforce CLI command catalog (sf, Winter '27 / API v68.0 era) — the reference an agent uses to know exactly what to execute. The `sf` command model and topics, authentication, metadata deploy/retrieve, scratch orgs/sandboxes, Apex/data/sobject, Agentforce DX, packaging, and flag conventions. Load only when the user explicitly invokes this skill by name (`dya-sf-cli`); do NOT auto-trigger on generic CLI or terminal questions.
---

# Salesforce CLI — Command Catalog

You are an expert with the Salesforce CLI. This skill is a **command catalog**: it exists so an agent
picks and runs the correct `sf` command with the right flags. The exhaustive command lists by topic
live in `references/`; this SKILL.md holds the model, the conventions and the most-used commands.
Follow every rule below.

References (exhaustive command lists by group):
- `references/shared/org-model.md` — **what an org, a sandbox, a scratch org and a DX project actually are.** Start here if the vocabulary below is unfamiliar; every command assumes it.
- `references/shared/metadata-and-api-versions.md` — what the CLI is deploying, and why an API version is not a CLI version.
- `references/shared/platform-deltas.md` — the release-coupled facts behind the deploy and agent commands.
- `references/org-and-auth.md` — install/update, `sf org login/logout`, orgs, scratch orgs, sandboxes, users, `org open/display/list`.
- `references/metadata-and-data.md` — `sf project` (deploy/retrieve/generate), `sf data`, `sf sobject`/`generate metadata`.
- `references/dev-and-agent.md` — `sf apex`, `sf lightning`, `sf logic`, `sf agent`, `sf package`, `sf code-analyzer`, `sf community`.
- `references/devops-center.md` — `sf devops`: projects, pipelines, work items and promotion, plus the two async-result behaviours that make a failed promotion look green.

---

## Platform Context — 2026

- The modern executable is **`sf`** (CLI v2). The legacy **`sfdx`** style still works under the
  `sf force` topic, but **always emit `sf` v2 commands**: `sf org login web`, never
  `sfdx force:auth:web:login`.
- **Agentforce DX** is first-class: `sf agent` (preview, generate) and `sf org create agent-user`.
- Commands are organised into **topics** (`sf <topic> <command>`), and the CLI is plugin-based, so
  topics map to plugins.
- Most commands are **scriptable** with `--json`, and accept `--target-org` (`-o`) and `--flags-dir`.
- **The CLI versions on its own weekly cadence, not the platform release.** A `sf` version is not an
  API version and the two move independently, which is why this skill carries no platform version in
  its heading.

What the Winter '27 platform release changes for CLI work:

- **Only invalid Apex classes and triggers recompile on deploy** (GA), so deploys against large orgs
  get materially faster with no change on your side.
- **`AiAgentDefinition` and `AiAgentDefinitionVersion` are metadata types at API 68.0** (GA), so
  agents deploy and retrieve like any other source. **Both orgs must be on 68.0.**
- **A Salesforce plugin for Claude Code** (GA) detects a DX project and supplies org context through
  hosted MCP servers, installed from the Claude Plugin Marketplace. See `dya-headless360`.
- **DevOps Center MCP** (GA) brings the same programmatic access into a CI/CD pipeline.

---

## 1. The Command Model

```
sf <topic> <subtopic?> <command> [--flags]
```

- Discover with `sf commands`, `sf <topic> --help`, `sf <topic> <command> --help`.
- **`--json`** works on almost any command. Use it whenever results are parsed programmatically.
- **`-o` / `--target-org`** selects the org by alias or username; omit it to use the default.
- **`--flags-dir <dir>`** imports flag values from files, which is how long or secret flags are
  passed.

Top-level topics: `org`, `project`, `template`, `apex`, `data`, `sobject`, `lightning`, `logic`,
`agent`, `devops`, `package`, `community`, `config`, `alias`, `schema`, `api`, `code-analyzer`,
`plugins`, `doctor`, `info`, `force` (legacy).

---

## 2. Authentication & Org Setup (most-used)

```bash
sf org login web --alias DevHub --set-default-dev-hub        # interactive login
sf org login jwt --username svc@org.com \                    # CI / headless
  --jwt-key-file server.key --client-id <consumerKey> --alias ci
sf org list                                                   # connected orgs
sf org display --target-org DevHub                            # details + access token
sf org open --target-org myorg                                # open in browser
sf config set target-org=myorg                                # set default org
```

Create dev environments:

```bash
sf org create scratch --definition-file config/project-scratch-def.json \
  --alias scratch1 --set-default --duration-days 7
sf org create sandbox --definition-file sandbox-def.json --alias uat
sf org create agent-user --alias myorg                        # Agentforce service user
```

Full auth, org, sandbox and user catalog: `references/org-and-auth.md`.

---

## 3. Metadata Deploy / Retrieve (most-used)

```bash
sf template generate project --name myProject                 # new DX project (`sf project generate` is deprecated)
sf project deploy start --source-dir force-app                # deploy source
sf project deploy start --manifest manifest/package.xml       # deploy by manifest
sf project deploy preview --source-dir force-app              # dry-run diff
sf project retrieve start --metadata ApexClass:MyClass        # retrieve specific
sf project deploy start --source-dir force-app --test-level RunLocalTests
sf project deploy validate --source-dir force-app             # check-only (no commit)
sf project deploy quick --job-id <id>                         # deploy a validated set
```

Full project, data and sobject catalog: `references/metadata-and-data.md`.

---

## 4. Data & Dev (most-used)

```bash
# Apex
sf apex run --file scripts/anon.apex                          # anonymous Apex
sf apex run test --test-level RunLocalTests --code-coverage --result-format human
sf apex tail log --color                                      # stream debug logs

# Data
sf data query --query "SELECT Id, Name FROM Account LIMIT 5"
sf data query --query "..." --bulk                            # Bulk API 2.0 query
sf data import tree --files data/accounts.json
sf data export tree --query "SELECT Id, Name FROM Account" --output-dir data

# Agentforce DX
sf agent generate template
sf agent preview --api-name My_Agent --output-dir transcripts
```

Full apex, lightning, logic, agent and package catalog: `references/dev-and-agent.md`.

---

## 5. Flag Conventions (v2)

- Names are **kebab-case** and full words: `--target-org`, `--source-dir`, `--test-level`,
  `--api-name`.
- Multi-value flags are **repeated**, never comma-joined:
  `--metadata ApexClass --metadata ApexTrigger`. Space-separating after a single flag also works,
  `--metadata ApexClass ApexTrigger`, but **never wrap the group in quotes**: `--metadata "A B"` is
  read as one nonexistent type.
- Common shared flags: `-o/--target-org`, `--json`, `--flags-dir`, `-w/--wait` (minutes),
  `--api-version`.
- Legacy `sfdx force:topic:action --camelCaseFlag` maps to `sf topic action --kebab-flag`. Translate
  old scripts when you meet them.

---

## 6. Decision Matrix — Which Command

| Goal | Command |
|---|---|
| Log in interactively | `sf org login web` |
| Log in for CI (no browser) | `sf org login jwt` |
| Spin up a scratch org | `sf org create scratch` |
| Reuse an existing org's configuration | `sf org create shape`, then `sf org create scratch --source-org <00D…>` |
| Start from a captured org state | `sf org create snapshot`, then `--snapshot` |
| Assign a permission set | `sf org assign permset --name <PermSet>` |
| Check API and storage allocations | `sf org list limits` |
| Promote work through DevOps Center | `sf devops promote` — see `references/devops-center.md` |
| Create a sandbox | `sf org create sandbox` |
| New DX project | `sf template generate project` |
| Deploy source | `sf project deploy start` |
| Check-only deploy | `sf project deploy validate` |
| Retrieve metadata | `sf project retrieve start` |
| Run anonymous Apex | `sf apex run` |
| Run Apex tests | `sf apex run test` |
| Stream logs | `sf apex tail log` |
| Run a SOQL query | `sf data query` |
| Bulk load/export records | `sf data import/export` (or `--bulk`) |
| Scaffold/preview an agent | `sf agent generate` / `sf agent preview` |
| Create the agent run-as user | `sf org create agent-user` |
| Build/install a package | `sf package ...` |
| Static code analysis | `sf code-analyzer run` |
| Machine-readable output | append `--json` |

---

## 7. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Emitting `sfdx force:...` commands | Use `sf` v2 (`sf org login web`, etc.) |
| Running `sf org display --verbose` for yourself | It returns a refresh token. Plain `sf org display`; let the user run the verbose form in their own terminal |
| Comma-joining multi-value flags | Repeat the flag (`--metadata A --metadata B`), or space-separate them — never quote the group |
| Parsing human output in scripts | Add `--json` and parse structured output — except `sf code-analyzer run`, which rejects it |
| `sf scanner run` | `sf code-analyzer run` (v3 is deprecated) |
| `--format` on `code-analyzer` | `--output-file results.<ext>`; the extension picks the format |
| `sf project generate` for a new project | `sf template generate project` |
| Deploying straight to prod without validation | `sf project deploy validate` then `deploy quick` |
| Hard-coding org usernames everywhere | Aliases + `sf config set target-org` |
| Putting secrets inline in CI commands | `--flags-dir` / env vars / JWT key file |
| `--target-org` omitted in CI ambiguity | Always pass `-o` explicitly in automation |

---

## Summary — The Five Commandments

1. **Emit `sf` v2 syntax** — topic + command + kebab-case flags; never legacy `sfdx force:`.
2. **`--json` for automation**, human format only for interactive use.
3. **Be explicit about the org** — aliases and `-o/--target-org`, especially in CI.
4. **Validate before prod** — `deploy validate` → `deploy quick`.
5. **Discover, don't guess** — `sf <topic> <command> --help`; the exhaustive lists are in `references/`.
