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
sf org resume scratch --job-id <id>
sf org delete scratch --target-org <a> [--no-prompt]
sf org list --all                         # includes expired scratch orgs
```

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
