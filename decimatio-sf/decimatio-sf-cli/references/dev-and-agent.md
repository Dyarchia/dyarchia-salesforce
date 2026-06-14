# sf CLI — Apex, Lightning, Logic, Agent, Package, Analysis (2026)

Load from `decimatio-sf-cli`. Catalog for `apex`, `lightning`, `logic`, `agent`, `package`, `code-analyzer`, and `community`. All `sf` v2.

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

```bash
sf agent generate template                                # scaffold a sample agent
sf agent generate agent-spec --type customer --role "..." # generate an agent spec
sf agent create --spec agentSpec.yaml --target-org <a>
sf agent preview --api-name My_Agent --output-dir transcripts [--use-live-actions] [--apex-debug]
sf agent preview start --api-name My_Agent --output-dir transcripts   # programmatic session
sf agent preview send --session-id <id> --message "Where is order 123?"
sf agent preview end --session-id <id>
# Related: create the run-as user
sf org create agent-user --alias <a>
```

`agent preview` writes trace files; `--use-live-actions` runs real actions, otherwise actions are AI-simulated (mocked).

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
```

Runs the unified Code Analyzer (PMD, ESLint, Graph/Flow engines) for best-practice and security checks; wire into CI before deploy.

## Experience Cloud (`sf community`)

```bash
sf community create --name "My Site" --template-name "Customer Service" --url-path-prefix mysite
sf community list template
sf community publish --name "My Site" --target-org <a>
```

## Notes

- Use `sf apex run test ... --code-coverage` to gate deploys on coverage; production deploys require ≥75% org-wide.
- `sf agent preview` is the primary local loop for testing Agentforce agents (see `decimatio-agentforce`).
- Add `--json` to anything for structured automation output.
