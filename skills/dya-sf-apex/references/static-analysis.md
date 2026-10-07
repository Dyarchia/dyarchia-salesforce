# Static Analysis — Code Analyzer

Salesforce Code Analyzer is the unified front end over seven analysis engines.

Run **`sf code-analyzer run`**. Never call `sf scanner run`, the deprecated v3 command; a CI config
that still calls it runs nothing.

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

Scope `sfge` with `--workspace` and run it on a schedule, not on every commit; it is slow — 10 to 20
minutes on a real codebase.

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

### Flag pitfalls

- **There is no `--format`.** The **extension of `--output-file` decides the format** — `.json`,
  `.html`, `.sarif`, `.csv`, `.xml`. `--format` is a v3 flag and errors.
- **`--json` is rejected**, as are `--engine` and `--category`. For machine-readable output, use
  `--output-file results.json`.
- **`--rule-selector` takes the exact full rule name, no wildcards:**
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

Gate a pipeline on `all:Security:(1,2)`: every engine, security findings, critical and high only.

## Configuration

Put the config file, **`code-analyzer.yml`**, at the **project root**; a file anywhere else is
silently not read.

Two silent failures that look like a broken rule:

- **A misspelled or partial rule name in `code-analyzer.yml` is ignored without an error or
  warning**: the override never applies. Verify it by running with and without it, not by reading
  the file.
- `regex_ignore` is **per line**, not per file. `ignores.files` is **global across every engine and
  rule**, so a path excluded there is excluded from security analysis too.

Use a simple extension such as `.xml`, never a compound one like `.permissionset-meta.xml`: Code
Analyzer's file-extension validator accepts only extensions matching `/^[.][a-zA-Z0-9]+$/`.

## Writing a custom PMD rule

Two PMD 7 traps make an XPath rule silently match nothing:

- **Boolean attributes are always present on the node.** `@WithSharing`, `@Abstract` and `@Final`
  exist whether or not they are set, so test them with the XPath function:

  ```text
  //UserClass[@WithSharing = false()]      ✅
  //UserClass[@WithSharing = 'false']      ❌ compares against a string
  //UserClass[not(@WithSharing)]           ❌ the attribute is present, so this is never true
  ```

- **Use `local-name()` in XML metadata rules.** Salesforce metadata carries a namespace, so bare
  element names never match.

`sf code-analyzer ast-dump --file <x.cls>` prints the tree a rule matches against.

## Prerequisites

`@salesforce/plugin-code-analyzer` v5 or later, plus the runtimes each engine needs:

| Engine | Needs |
|---|---|
| PMD, CPD, SFGE | Java 11+ |
| ESLint, RetireJS | Node 18+ |
| Flow | Python 3 |
| ApexGuru | An authenticated org |

Check the engine list in the output. A missing runtime disables its engines rather than failing the
run, so a pipeline can pass while analysing only part of the code.
