# Static Analysis — Code Analyzer

Salesforce Code Analyzer is the unified front end over seven analysis engines. It is the closest
thing Apex has to a linter with teeth, and the piece most often left out of a pipeline because the
command surface changed and old instructions stopped working.

The command is **`sf code-analyzer run`**. `sf scanner run` is the deprecated v3 command; if you find
it in a repo's CI config, that config is running nothing.

## The engines

| Engine | Analyses |
|---|---|
| `pmd` | Apex and Visualforce rules — the bulk of Apex findings |
| `eslint` | JavaScript, including LWC |
| `cpd` | Copy-paste detection across languages |
| `retire-js` | Known vulnerabilities in bundled JavaScript libraries |
| `flow` | Flow definitions |
| `sfge` | Salesforce Graph Engine — data-flow analysis, finds CRUD/FLS violations across call paths |
| `apexguru` | Org-side performance analysis; needs an authenticated org |

Plus a `regex` selector for custom pattern rules.

`sfge` is the one that finds security problems a per-file linter cannot, because it follows values
across method boundaries. It is also the slow one — 10 to 20 minutes on a real codebase — so scope it
with `--workspace` and run it on a schedule rather than on every commit.

## Running it

```bash
sf code-analyzer run --workspace force-app --view detail
sf code-analyzer run --rule-selector Recommended --output-file results.html
sf code-analyzer run --rule-selector all:Security:(1,2) --output-file findings.sarif
sf code-analyzer rules --rule-selector all
sf code-analyzer config --rule-selector Security          # writes code-analyzer.yml
sf code-analyzer ast-dump --file MyClass.cls --output-file ast.xml
```

`--workspace` sets what the engines index; `--target` narrows what is reported on.

### Three flag facts that fail quietly

- **There is no `--format`.** The **extension of `--output-file` decides the format** — `.json`,
  `.html`, `.sarif`, `.csv`, `.xml`. Passing `--format` is a v3 flag and errors.
- **`--json` is rejected.** So are `--engine` and `--category`. This is the one command in the CLI
  where the reflex of appending `--json` for machine-readable output is wrong; use `--output-file
  results.json` instead.
- **`--rule-selector` takes the exact full rule name and no wildcards.** It is
  `@salesforce-ux/slds/no-hardcoded-values-slds2`, not `no-hardcoded-values`. Look names up with
  `sf code-analyzer rules --rule-selector all`.

### Selector grammar

```text
Recommended                    the curated default set
<engine>                       pmd | eslint | cpd | retire-js | sfge | flow | apexguru | regex | all
<engine>:<category>            Security | Performance | BestPractices | CodeStyle | Design |
                               ErrorProne | Documentation
<engine>:<category>:(<sev>)    severity 1 (Critical) … 5 (Info)
```

`all:Security:(1,2)` is a reasonable pipeline gate: every engine, security findings, critical and
high only.

## Configuration

The config file is **`code-analyzer.yml`** and it must sit at the **project root** — auto-discovery
looks nowhere else, and a file one directory down is silently not read.

Two silent failures live here, and both look like "the rule is not working":

- **A misspelled or partial rule name in `code-analyzer.yml` is ignored without an error.** The
  override simply never applies. There is no warning, so verify an override took effect by running
  with and without it rather than by reading the file.
- `regex_ignore` is **per line**, not per file. `ignores.files` is **global across every engine and
  rule**, so a path excluded there is excluded from security analysis too.

Code Analyzer's file-extension validator only accepts simple extensions matching
`/^[.][a-zA-Z0-9]+$/`, so a compound extension like `.permissionset-meta.xml` is rejected — use
`.xml`.

## Writing a custom PMD rule

Two things about PMD 7 that make an XPath rule silently match nothing:

- **Boolean attributes are always present on the node.** `@WithSharing`, `@Abstract` and `@Final`
  exist whether or not they are set, so test them with the XPath function:

  ```text
  //UserClass[@WithSharing = false()]      ✅
  //UserClass[@WithSharing = 'false']      ❌ compares against a string
  //UserClass[not(@WithSharing)]           ❌ the attribute is present, so this is never true
  ```

- **XML metadata rules must use `local-name()`.** Salesforce metadata carries a namespace, so bare
  element names never match.

`sf code-analyzer ast-dump --file <x.cls>` prints the tree a rule is matching against, which is
faster than guessing at node names.

## Prerequisites

`@salesforce/plugin-code-analyzer` v5 or later, plus the runtimes each engine needs:

| Engine | Needs |
|---|---|
| PMD, CPD, SFGE | Java 11+ |
| ESLint, RetireJS | Node 18+ |
| Flow | Python 3 |
| ApexGuru | An authenticated org |

A missing runtime disables its engines rather than failing the run, so a pipeline can appear to pass
while analysing half of what you think it is. Check the engine list in the output.
