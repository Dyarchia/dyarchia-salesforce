# sf CLI — Org, Auth, Scratch & Sandbox (2026)

Load from `dya-sf-cli`. Exhaustive-ish catalog for the `org`, `config`, and `alias` topics. All commands are `sf` v2; flags are kebab-case; `-o/--target-org` selects the org.

## Install / Update / Info

```bash
npm install --global @salesforce/cli      # install
sf update                                 # update the CLI
sf version                                # version
sf --help                                 # top-level help
sf commands                               # list every command
sf doctor                                 # diagnostics
sf info releasenotes display              # release notes
```

## Authentication (`sf org login` / `logout`)

```bash
sf org login web --alias <a> [--set-default] [--set-default-dev-hub] [--instance-url https://test.salesforce.com]
sf org login jwt --username <u> --jwt-key-file <key.pem> --client-id <consumerKey> --alias <a> [--set-default-dev-hub]
sf org login device                       # device flow (input-constrained)
sf org login access-token --instance-url <url>   # login with an existing access token
sf org logout --target-org <a>            # log out one org
sf org logout --all
```

Use **web** for humans, **jwt** for CI/headless (certificate-based, no password).

## Orgs

```bash
sf org list [--all] [--clean]             # connected orgs
sf org display [--target-org <a>] [--verbose]   # details, incl. access token + instance URL
sf org open [--target-org <a>] [--path lightning/setup/SetupOneHome/home] [--source-file force-app/.../page]
sf org list metadata --metadata-type ApexClass --target-org <a>
sf org list metadata-types --target-org <a>
```

## Scratch Orgs

```bash
sf org create scratch --definition-file config/project-scratch-def.json \
  --alias <a> [--set-default] --duration-days <1-30> [--no-namespace] [--admin-email me@x.com]
sf org resume scratch --job-id <id> | --use-most-recent
sf org delete scratch --target-org <a> [--no-prompt]
sf org list --all                         # includes expired scratch orgs
sf org assign permset --name <PermSet> --target-org <a>
sf org list limits --target-org <a>
```

**Three mutually exclusive creation sources**, each with a definition-file key and a matching flag.
Overriding a def-file value with the same-dimension flag is supported; mixing two *kinds* is not:

| Source | Def-file key | Flag |
|---|---|---|
| A fresh org of an edition | `edition` | `--edition` |
| A shape captured from an existing org | `sourceOrg` | `--source-org` |
| A snapshot | `snapshot` | `--snapshot` |

Editions are `developer`, `enterprise`, `group`, `professional`, plus the hyphenated partner forms
(`partner-developer`) which need the Dev Hub to be a Partner Business Org. A wrong value fails with
`edition value must be one of`.

Facts that change how a script is written:

- **`--duration-days` maxes at 30**; the CLI default is 7.
- **The command blocks.** When it returns `username` and `orgId` the org is ready — do not poll
  `sf org list` afterwards.
- **A timeout is exit code 69**, and the CLI prints a resume command. `--use-most-recent` saves
  storing the job id.
- **A reused alias is not rejected.** The CLI silently re-points it at the new org and the previous
  one loses its alias, so batch creation must generate distinct aliases. There is no `--count`; loop.
- **`target-dev-hub` is directory-scoped.** `sf config get target-dev-hub` can come back empty after
  a `cd` even with a hub authenticated. Resolve it to a concrete username *before* changing
  directory and pass `--target-dev-hub` explicitly.
- **A Dev Hub can appear in any bucket of `sf org list --json`** — `devHubs`, `nonScratchOrgs`,
  `other`, `sandboxes` or `scratchOrgs`. Inspecting one bucket silently misses it:

  ```bash
  sf org list --json | jq -r '[.result.devHubs[]?, .result.nonScratchOrgs[]?, .result.other[]?,
      .result.sandboxes[]?, .result.scratchOrgs[]?] | map(select(.isDevHub == true).username) | unique | .[]'
  ```

- Definition files are auto-detected only at `config/*scratch-def.json`; any other path needs an
  explicit `--definition-file`. Nested `settings` cannot be expressed as CLI flags, which is why a
  def file is needed even outside a DX project.

Error strings worth recognising: `NotADevHubError`, `NoDefaultDevHubError`, `NamedOrgNotFoundError`,
`Definition file not found`, `Snapshot not found`.

## Org Shapes and Snapshots

```bash
sf org create shape --target-org <sourceOrg>     # legacy: sf force org shape create
sf org list shape                                # legacy: sf force org shape list
sf org delete shape --target-org <sourceOrg>

sf org create snapshot --source-org <a> --snapshot-name <n>
sf org list snapshot
```

Two flag facts that are easy to assume wrong:

- On `sf org create shape`, **`--target-org` is the org being shaped, not a Dev Hub.** There is no
  `--target-dev-hub`, no `--name` and no `--description`; a shape is identified by its source org's
  Id.
- **`sf org list shape` takes only global flags** — no `--target-org`. It lists across every
  authenticated org.

Consuming a shape uses `sf org create scratch --source-org <sourceOrgId>`, and that value is the
**15- or 18-character `00D…` Id of the org the shape was captured from** — *not* the `3SR…` shape
record Id that `sf org list shape` prints. Passing the shape Id fails with `InvalidIdLengthError` or
`InvalidPrefixError`.

## Sandboxes

```bash
sf org create sandbox --definition-file sandbox-def.json --alias <a> [--async] [--poll-interval 30 --wait 30]
sf org resume sandbox --name <SandboxName>
sf org refresh sandbox --name <SandboxName>
sf org delete sandbox --target-org <a>
sf org clone sandbox --name <New> --source-sandbox-name <Existing>
```

## Users

```bash
sf org create user --definition-file user-def.json --set-alias newuser --target-org <a>
sf org generate password --target-org <a>
sf org display user --target-org <a>
sf org list users --target-org <a>
sf org create agent-user --alias <a> [--first-name X --last-name Y --base-username z]   # Agentforce run-as user
```

## Config & Aliases

```bash
sf config set target-org=<a>                      # default org for this project
sf config set target-dev-hub=<DevHub> --global    # global default Dev Hub
sf config list
sf config unset target-org
sf alias set MyOrg=user@org.com
sf alias list
sf alias unset MyOrg
```

## Notes

- Scratch orgs require a **Dev Hub** (`--set-default-dev-hub` at login, or `target-dev-hub` config).
- **Never run `sf org display --verbose` on the user's behalf.** It returns `sfdxAuthUrl`, which is a
  **refresh token** — running it pulls a live, long-lived credential into whatever transcript or log
  the command output lands in. Plain `sf org display` is fine and is what you want; current CLIs
  redact the access token from it and point at `sf org auth show-access-token`. If the user needs the
  auth URL, tell them to run the verbose form themselves in their own terminal. The same care applies
  to `sf org open --url-only`, whose front-door URL carries a one-time token.
- Add `--json` to any command for structured output in automation — **except `sf code-analyzer run`**,
  which rejects the flag. See `references/dev-and-agent.md`.
