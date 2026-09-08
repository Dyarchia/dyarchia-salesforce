# sf CLI — Apex, Lightning, Logic, Agent, Package, Analysis (2026)

Load from `dya-sf-cli`. Catalog for `apex`, `lightning`, `logic`, `agent`, `package`, `code-analyzer`, and `community`. All `sf` v2.

## Apex (`sf apex`)

```bash
sf apex run --file scripts/anon.apex                      # anonymous Apex (or pipe via stdin)
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 10
sf apex run test --class-names MyTest --code-coverage --detailed-coverage
sf apex get test --test-run-id <id> --code-coverage
sf apex tail log --color                                  # stream logs live
sf apex get log --number 1                                # fetch recent log(s)
sf apex list log
sf apex generate class --name MyClass --output-dir force-app/main/default/classes
sf apex generate trigger --name MyTrigger --sobject Account --event "before insert" --event "after update"
```

## Lightning (`sf lightning`)

```bash
sf lightning generate component --name myCmp --type lwc --output-dir force-app/main/default/lwc
sf lightning generate component --name myAura --type aura --output-dir force-app/main/default/aura
sf lightning generate app --name myApp
sf lightning generate event --name myEvent
sf lightning generate interface --name myInterface
```

## Logic — Flow & Apex Tests (`sf logic`)

```bash
sf logic run test --flow-names MyFlow --result-format human    # run Flow tests
sf logic run test                                               # Apex + Flow tests
```

## Agentforce DX (`sf agent`)

The lifecycle runs on an **authoring bundle**: generate, validate, publish, activate. `sf agent
generate agent-spec` and `sf agent create --spec` are gone — do not reach for them.

```bash
sf agent generate authoring-bundle --name My_Agent        # scaffold; --no-spec to skip the spec
sf agent validate authoring-bundle --api-name My_Agent
sf agent publish  authoring-bundle --api-name My_Agent    # compiles to the runtime metadata
sf agent activate --api-name My_Agent                     # and `sf agent deactivate`
sf agent generate template                                # packaging for AppExchange distribution

sf agent preview start --api-name My_Agent --output-dir transcripts
sf agent preview start --authoring-bundle My_Agent        # preview the bundle, not a published agent
sf agent preview send --session-id <id> --message "Where is order 123?"
sf agent preview end --session-id <id>

sf agent test create --spec test-specs/my-tests.yaml
sf agent test run | list | results --job-id <id> | resume --job-id <id>

# Related: create the run-as user
sf org create agent-user --alias <a>
```

Two sub-topics beyond the core lifecycle:

```bash
sf agent mcp create | get | list | update | delete | fetch     # MCP servers from the CLI
sf agent mcp asset list | replace -i <id>
sf agent adl create | get | list | update | delete | status    # Agentforce Data Libraries
sf agent adl upload --source-type sfdrive --library-id <id>
sf agent adl file add | list | delete -i <id>
```

`agent preview` writes trace files. `--use-live-actions` runs real actions; `--simulate-actions` is
its explicit counterpart and the default. **`sf agent generate test-spec` is an interactive REPL** —
it stalls under automation, so write the spec YAML directly. `sf` must be **2.139.6 or newer** for
agent work. Agent Script `.agent` bundles roll out through the publish workflow above, not through
`sf agent generate template`.

## Packaging (`sf package`)

```bash
sf package create --name "My Pkg" --package-type Unlocked --path force-app
sf package version create --package "My Pkg" --installation-key-bypass --code-coverage --wait 20
sf package version list --packages "My Pkg"
sf package install --package <04t...> --target-org <a> --wait 10 [--installation-key <k>]
sf package version promote --package <04t...>            # mark released
sf package uninstall --package <04t...> --target-org <a>
```

Supports **unlocked** and **managed 2GP** packages (1GP via `sf package1` legacy).

## Code Analysis (`sf code-analyzer`)

```bash
sf code-analyzer run --workspace force-app --view detail
sf code-analyzer run --rule-selector Recommended --output-file results.html
sf code-analyzer rules --rule-selector all
sf code-analyzer config --rule-selector Security          # writes code-analyzer.yml
sf code-analyzer ast-dump --file MyClass.cls --output-file ast.xml
```

`sf scanner run` is the deprecated v3 command; use `sf code-analyzer run`. **Seven engines**, not
three: PMD, ESLint, CPD, RetireJS, Flow, SFGE and ApexGuru, plus a `regex` selector.

Three flag facts that produce silent or confusing failures:

- **There is no `--format`.** The output file's extension decides the format — `.json`, `.html`,
  `.sarif`, `.csv`, `.xml` — via `--output-file`.
- **`--json` is rejected here**, along with the other v3 flags `--format`, `--engine` and
  `--category`. This is the one documented exception to adding `--json` everywhere for automation.
- **`--rule-selector` needs the exact full rule name and takes no wildcards.** Compose it as
  `<engine>:<category>:<severity>`, e.g. `all:Security:(1,2)`; severities run 1 (Critical) to
  5 (Info). Look names up with `sf code-analyzer rules --rule-selector all`. A misspelled or partial
  rule name inside `code-analyzer.yml` is **ignored without an error** — the override simply never
  applies — and the file must sit at the project root or auto-discovery misses it.

Prerequisites: `@salesforce/plugin-code-analyzer` v5+, Java 11+ (PMD, CPD, SFGE), Node 18+ (ESLint,
RetireJS), Python 3 (Flow), and an authenticated org for ApexGuru. `sfge` wants `--workspace` and
takes 10–20 minutes, so scope it deliberately rather than running it on every commit.

## Experience Cloud (`sf community`)

```bash
sf community create --name "My Site" --template-name "Customer Service" --url-path-prefix mysite
sf community list template
sf community publish --name "My Site" --target-org <a>
```

## Notes

- Use `sf apex run test ... --code-coverage` to gate deploys on coverage; production deploys require ≥75% org-wide.
- `sf agent preview` is the primary local loop for testing Agentforce agents (see `dya-agentforce`).
- Add `--json` to anything for structured automation output.
