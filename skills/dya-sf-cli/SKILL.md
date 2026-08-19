---
name: dya-sf-cli
description: Salesforce CLI command catalog (sf, 2026) — the reference an agent uses to know exactly what to execute. The `sf` command model and topics, authentication, metadata deploy/retrieve, scratch orgs/sandboxes, Apex/data/sobject, Agentforce DX, packaging, and flag conventions. Load only when the user explicitly invokes this skill by name (`dya-sf-cli`); do NOT auto-trigger on generic CLI or terminal questions.
---

# Salesforce CLI — Command Catalog

You are an expert with the Salesforce CLI. This skill is a **command catalog**: its job is to let an agent pick and run the correct `sf` command with the right flags. The load-bearing command lists by topic live in `references/`; this SKILL.md holds the model, conventions, and the most-used commands. Follow every rule below.

References (exhaustive command lists by group):
- `references/org-and-auth.md` — install/update, `sf org login/logout`, orgs, scratch orgs, sandboxes, users, `org open/display/list`.
- `references/metadata-and-data.md` — `sf project` (deploy/retrieve/generate), `sf data`, `sf sobject`/`generate metadata`.
- `references/dev-and-agent.md` — `sf apex`, `sf lightning`, `sf logic`, `sf agent`, `sf package`, `sf code-analyzer`, `sf community`.

---

## Platform Context — 2026

- The modern executable is **`sf`** (CLI v2). The legacy **`sfdx`** style still works under the `sf force` (legacy) topic, but **always emit `sf` v2 commands** (`sf org login web`, not `sfdx force:auth:web:login`).
- **Agentforce DX** is first-class: `sf agent` (preview, generate) and `sf org create agent-user`.
- Commands are organized into **topics** (`sf <topic> <command>`). The CLI is plugin-based; topics map to plugins.
- Many commands are **scriptable/JSON-able** (`--json`) and most accept `--target-org`/`-o` and `--flags-dir`.

---

## 1. The Command Model

```
sf <topic> <subtopic?> <command> [--flags]
```

- Discover with `sf commands`, `sf <topic> --help`, `sf <topic> <command> --help`.
- **`--json`** on (almost) any command for machine-readable output — use this when parsing results programmatically.
- **`-o` / `--target-org`** selects the org (alias or username); omit to use the default.
- **`--flags-dir <dir>`** imports flag values from files (handy for long/secret flags).

Top-level topics: `org`, `project`, `apex`, `data`, `sobject`, `lightning`, `logic`, `agent`, `package`, `community`, `config`, `alias`, `schema`, `api`, `code-analyzer`, `plugins`, `doctor`, `info`, `force` (legacy).

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

Full auth/org/sandbox/user catalog: `references/org-and-auth.md`.

---

## 3. Metadata Deploy / Retrieve (most-used)

```bash
sf project generate --name myProject                          # new DX project
sf project deploy start --source-dir force-app                # deploy source
sf project deploy start --manifest manifest/package.xml       # deploy by manifest
sf project deploy preview --source-dir force-app              # dry-run diff
sf project retrieve start --metadata ApexClass:MyClass        # retrieve specific
sf project deploy start --source-dir force-app --test-level RunLocalTests
sf project deploy validate --source-dir force-app             # check-only (no commit)
sf project deploy quick --job-id <id>                         # deploy a validated set
```

Full project/data/sobject catalog: `references/metadata-and-data.md`.

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

Full apex/lightning/logic/agent/package catalog: `references/dev-and-agent.md`.

---

## 5. Flag Conventions (v2)

- Names are **kebab-case** and full words: `--target-org`, `--source-dir`, `--test-level`, `--api-name`.
- Multi-value flags are **repeated**, not comma-joined: `--metadata ApexClass --metadata ApexTrigger`.
- Common shared flags: `-o/--target-org`, `--json`, `--flags-dir`, `-w/--wait` (minutes), `--api-version`.
- Legacy `sfdx force:topic:action --camelCaseFlag` maps to `sf topic action --kebab-flag`; translate when you encounter old scripts.

---

## 6. Decision Matrix — Which Command

| Goal | Command |
|---|---|
| Log in interactively | `sf org login web` |
| Log in for CI (no browser) | `sf org login jwt` |
| Spin up a scratch org | `sf org create scratch` |
| Create a sandbox | `sf org create sandbox` |
| New DX project | `sf project generate` |
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
| Comma-joining multi-value flags | Repeat the flag (`--metadata A --metadata B`) |
| Parsing human output in scripts | Add `--json` and parse structured output |
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
