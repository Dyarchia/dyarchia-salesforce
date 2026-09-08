# dyarchia-salesforce

The Salesforce domain plugin of the Dyarchia umbrella: a library of agent skills targeting
Winter '27 / API v68.0, packaged as a Claude Code plugin and as portable `.skill` bundles.

This repo ships **content**, not software. There is no application and no runtime — only the
`SKILL.md` files, the manifests that let Claude Code install them, and two packaging scripts.

One repo per domain, one plugin per repo. Sibling domains get their own repos under the same org.

## Branches

Work flows in one direction: **feature → `develop` → `master`**.

`develop` is the working branch and carries everything described in this file. `master` is the
published branch and GitHub's default; it is synced from `develop` after a merge and nothing lands
on it directly.

Two consequences follow, and both bite silently:

- **Branch from `develop`, and set the pull-request base to `develop`.** GitHub offers `master`
  because it is the default, so the base must be changed by hand every time. A pull request that
  keeps the offered base skips `develop` entirely.
- A clone or worktree created under a different default still has a stale
  `refs/remotes/origin/HEAD`, so checking out the bare default hands you the wrong branch. Repair it
  with `git remote set-head origin -a` instead of routing around it.

This file and `CONTRIBUTING.md` are **versioned on every branch**. They are the contributor
contract: a clone that lacks them cannot be contributed to correctly, and the drift between the two
artifacts they exist to prevent is this repo's defining failure mode. Like every other file here,
they are written in English.

Untracked by design: `.claude/` in full (the per-machine agent workspace — local settings,
repo-local skills, worktrees), `docs/TODO.md` and `docs/dyarchia-legio.md` (private working notes).
Those are genuinely internal — they record what someone is thinking about, not how the library
works. Anything a contributor must know belongs in this file or in `CONTRIBUTING.md`, never under
`.claude/`.

## Layout

```text
dyarchia-salesforce/
├── .claude-plugin/
│   ├── plugin.json                # plugin identity; components auto-discovered
│   └── marketplace.json           # the repo is its own marketplace
├── CLAUDE.md                      # this file
├── CONTRIBUTING.md                # the authoring procedure, step by step
├── README.md                      # public catalogue and install instructions
├── CHANGELOG.md                   # Keep a Changelog format
├── skills/
│   └── dya-<name>/
│       ├── SKILL.md               # load-bearing instructions
│       ├── shared-refs.txt        # which shared fragments this skill needs
│       └── references/            # loaded on demand, never at invocation time
│           └── shared/            # GENERATED copies of references-shared/, committed
├── references-shared/             # the canon: platform fundamentals, written once
├── dist/                          # 26 pre-built .skill bundles, committed
├── scripts/                       # packaging, shared-reference sync, validation
└── docs/                          # local working notes, untracked
```

`.claude/` may exist locally — agent settings, repo-local skills, worktrees — and is gitignored in
full. Nothing inside it is part of the contract; `CONTRIBUTING.md` is.

Not present yet, reserved by convention: `agents/`, `commands/`, `hooks/`, and `mcp/` for MCP
servers written here. Third-party MCP servers are not vendored and not declared.

`sources/` may exist locally: read-only clones of third-party repos kept as raw material. It is
gitignored, never installed, never published. Do not glob or grep across it by accident — it is
large.

## Commands

There is no test runner, no linter and no CI. Three scripts, each with a PowerShell and a bash twin,
are the entire tooling surface. The order matters: **sync, then build, then validate** — building
before syncing bundles a stale copy, and the validator catches it. Both `.ps1` files declare `#Requires -Version 7.0`.

```bash
scripts/sync-shared-refs.sh            # materialise references-shared/ into each skill
scripts/build-skill.sh                 # rebuild every bundle
scripts/build-skill.sh dya-apex        # rebuild one; accepts several names
scripts/validate-skills.sh             # the gate; must exit 0
```

```powershell
pwsh -NoProfile -File scripts/sync-shared-refs.ps1
pwsh -NoProfile -File scripts/build-skill.ps1 dya-apex
pwsh -NoProfile -File scripts/validate-skills.ps1
```

- Called with no arguments, either builder rebuilds every folder under `skills/`.
- Roots are overridable: `-SourceRoot` / `-OutputRoot` parameters in PowerShell,
  `SOURCE_ROOT` / `OUTPUT_ROOT` environment variables in bash. Defaults are `skills` and `dist`.
  Both are joined onto the repo root, so they must be **relative**; an absolute path produces a
  nonsense concatenated path and the run dies.
- The bash builder shells out to `zip` and exits 1 when it is not on PATH; the PowerShell one uses
  `System.IO.Compression` and needs nothing external. On a stock Windows box `zip` is usually
  absent while `unzip` is present — meaning the bash builder will not run but the bash validator
  will. Use the PowerShell builder there.

### What the validator enforces

`validate-skills` is the closest thing this repo has to a test suite. It walks every folder under
`skills/`, compares each against its committed bundle, and cross-checks the README.

Hard failures — exit 1:

```text
condition                                              check
-----------------------------------------------------  ------------------------------------------
SKILL.md absent                                        per skill folder
no YAML frontmatter block                              the leading ---...--- must parse
no name key, or name differs from the folder name      exact string match
no description key                                     presence
description lacks the invocation clause                literal substring match
skill name appears nowhere in README.md                full-text scan - a failure, not a warning
no bundle at dist/<name>.skill                         presence
bundle entry contains a backslash                      per ZIP entry
bundle entry not rooted at <name>/                     per ZIP entry
bundle stale: file missing, content differs, orphaned  SHA-256, compared in both directions
```

Warnings — still exit 0:

```text
condition                                            threshold
---------------------------------------------------  --------------------
SKILL.md over the size ceiling                       20480 bytes
SKILL.md over the ceiling with no references/        20480 bytes
README names a dya-* token that is not a folder      allowlist-filtered
```

Additional hard failures added alongside the shared-reference canon:

```text
condition                                              check
-----------------------------------------------------  ------------------------------------------
Platform Context does not declare the README's version  exact heading match, allowlist-filtered
README badge disagrees with the README catalogue line   substring
plugin.json description omits the platform version      substring
plugin.json and marketplace.json versions disagree      exact
a references/ file is never cited from SKILL.md         substring, per file
a declared shared fragment is missing or edited         SHA-256 against references-shared/
a synced file is not declared in shared-refs.txt        set comparison
a skill cites `dya-<name>` that is not a folder         backticked tokens, per .md, shared/ excluded
```

**README is the single source of truth for the platform version.** The catalogue line
(`N skills, all targeting **<version>**`) is parsed, and the badge, every skill's Platform Context
heading and the plugin description are checked against it. A version bump therefore either lands
everywhere or fails — it cannot land one skill at a time.

`$versionNeutralSkills` / `VERSION_NEUTRAL_SKILLS` exempts `dya-b2c-commerce` (Demandware lineage,
no core API version) and `dya-sf-cli` (versions on the CLI's own weekly cadence). Like
`$nonSkillTokens`, it is hardcoded in **both** scripts.

The invocation clause is matched as the literal substring `Load only when the user explicitly
invokes this skill by name`. Reword it and the skill fails validation.

The allowlist behind that second warning is hardcoded in both scripts — `$nonSkillTokens` in the
PowerShell version, `NON_SKILL_TOKENS` in the bash one — and is empty today. It exists for a
`dya-`-prefixed name the README mentions on purpose without a matching folder under `skills/`; add
any such name to **both** scripts, or the scan flags it. The same allowlist covers the
cross-reference check below.

**The routing graph is validated.** Skills hand off to each other by naming a sibling in backticks,
and that graph is the reason a reader can start anywhere. A rename used to break every prose mention
of the old name silently, so the validator now scans every `.md` under a skill — `references/shared/`
excluded, since it is generated — and **fails** on a backticked `dya-<name>` with no matching folder.
It reads the graph that already exists in the prose rather than asking for it a second time in
frontmatter, so adding a handoff costs nothing beyond writing the sentence. When you rename or remove
a skill, the validator tells you which files still point at the old name.

## The frontmatter contract

Every `SKILL.md` opens with YAML frontmatter carrying exactly two keys:

```yaml
---
name: dya-<name>
description: <domain and version> — <what it covers, comma-separated>. Load only when the user
  explicitly invokes this skill by name (`dya-<name>`); do NOT auto-trigger on generic
  <domain> questions.
---
```

Three invariants, all load-bearing:

- `name` matches the containing folder name, exactly.
- The description ends with the explicit-invocation clause. These are reference playbooks, not
  ambient context — auto-triggering them on generic questions poisons unrelated sessions.
- The description enumerates the actual surface covered, so the router can pick between siblings
  without loading them.

The `dya-` prefix stays on skill names even though the repo no longer repeats it. Skill names
live in a global namespace inside the assistant, alongside `sf-apex`, `salesforce-skills` and other
third-party Salesforce skills; that is where the prefix earns its keep.

## Skill body conventions

- Second-person expert framing: "You are an expert X. You **always** ... Follow every rule below."
- Cross-reference siblings by bare skill name in backticks. The integration family in particular
  is a routing graph: `dya-integration-overview` routes, the others build.
- Scope exclusions are stated in the opening paragraph, not buried. Example: `dya-b2c-commerce`
  declares up front that there is no Apex, LWC or SOQL on that platform.
- `SKILL.md` holds what must be true on every invocation. Anything consulted occasionally —
  full code listings, command catalogues, per-vendor detail — belongs in `references/`.
- Size ceiling for `SKILL.md`: 20480 bytes. It is not a style note — `validate-skills` warns above
  it. Past that, split into `references/`. **All 26 skills are under the ceiling, so a clean tree
  validates with zero errors and zero warnings.** Treat a new warning as something to fix in the
  same commit rather than as accepted debt.
- Platform fundamentals — governor limits, the access model, SOQL selectivity, API version
  semantics, the org and deployment model, the release deltas — are **never written into a skill
  body**. They live once in `references-shared/`; a skill declares what it needs in its own
  `shared-refs.txt` and `scripts/sync-shared-refs` materialises the copies. Editing a synced copy is
  a validation error.

### The section skeleton

All 26 skills share the same shape. Match it — the consistency is what lets a reader jump between
skills without relearning the layout.

- Open with `## Platform Context — Winter '27 / API v68.0`, stating the release's relevant changes
  and versioned defaults before any rule.
- Carry the rules in numbered `## N. Title` sections.
- Express decision matrices as **markdown pipe tables**. This is the house convention for skill
  bodies and it overrides any general preference for ASCII tables in documentation.
- Annotate code blocks inline with `✅` and `❌` on the lines they judge.
- Close with a fixed pair: `## N. Anti-Patterns — NEVER Do These`, a two-column
  anti-pattern-to-replacement table, then `## Summary — The Five Commandments`, a numbered list of
  exactly five.

## Platform version

`Winter '27 / API v68.0` is a repo-wide invariant, not a per-skill detail. It is asserted in all 26
Platform Context sections, in the README badge, and in the descriptions inside `plugin.json` and
`marketplace.json`. A version bump is therefore a coordinated sweep across every source file plus a
full rebuild of `dist/` — never a single-skill edit.

The plugin `version` field is duplicated across `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (`0.3.0` in both). `validate-skills` now checks that they agree,
but it cannot tell you which one is right — bump them together.

A version bump is no longer a manual sweep across 267 occurrences. Edit the README catalogue line
and badge, the plugin description, and `references-shared/platform-deltas.md`; then update each
skill's `## Platform Context` heading and re-verify its per-domain claims. The validator reports
every skill you missed.

## Adding or editing a skill

The prescriptive procedure lives in `CONTRIBUTING.md`. Follow it rather than improvising. The short
version:

1. Author or edit `skills/dya-<name>/SKILL.md`.
2. Rebuild the bundle: `scripts/build-skill.ps1 dya-<name>` (or the `.sh` twin).
3. Validate: `scripts/validate-skills.ps1` (or the `.sh` twin). It must exit 0.
4. Update the README catalogue and the CHANGELOG in the same commit.

Source and bundle drift is the failure mode this repo is most exposed to. `validate-skills`
exists to catch it; run it before every commit that touches `skills/`.

## Bundle packaging

A `.skill` file is a ZIP whose top-level entry is the skill folder — unzipping yields
`dya-apex/SKILL.md`, never a nested `skills/dya-apex/SKILL.md`.

ZIP entry names must use forward slashes. PowerShell's `Compress-Archive` writes backslashes and
strict parsers reject the result; `scripts/build-skill.ps1` uses `System.IO.Compression.ZipArchive`
with explicit forward-slash entry names for that reason. Do not replace it with `Compress-Archive`.

Both scripts take `SourceRoot` and `OutputRoot` overrides; the defaults are `skills` and `dist`.

Bundles are committed, so the build must be **reproducible**: both scripts emit entries in sorted
order and stamp every one with a fixed 1980-01-01 timestamp. Without that, a ZIP writer records the
current time and a rebuild produces different bytes from byte-identical sources — which dirties all
26 binaries in the diff and buries whatever actually changed. If you touch the builders, keep that
property and verify it by building the same skill twice and comparing hashes.

Do not assume the PowerShell and bash builders emit identical bytes; they use different ZIP
implementations. Each is deterministic with respect to itself. Pick one and regenerate the whole
`dist/` with it rather than mixing them commit to commit.

## Commit conventions

Conventional Commits, scoped by area:

```text
feat(skills): add dya-<name> skill
fix(skills): correct the callout-after-DML rule in dya-integration-outbound
fix(repo): use forward slashes in .skill ZIP entry paths
docs(repo): correct .skill bundle structure in packaging instructions
```

One skill per commit when adding. Bundle regeneration travels in the same commit as the source
change that caused it.

## Out of scope

- **Project context.** Consuming repos carry their own `CLAUDE.md` with stack, org and deploy
  commands. This repo supplies reusable capability; mixing the two kills portability.
- **Third-party MCP servers.** Not vendored, not declared in `plugin.json`. Consumers wire their
  own. Only MCP servers written here would ship.
- **The `dyarchia` CLI.** Developed and distributed separately. Scripts here may call it if it
  is on PATH, treating it as an external dependency like `sf` or `jq`.

## Architecture status

Implemented: the plugin and marketplace manifests, `skills/`, the packaging and validation scripts.

**Not implemented:** `agents/`, `commands/`, `hooks/` and `mcp/`. Nothing depends on them; they are
additive whenever a real recurring need shows up in project work. When they arrive, the principles
that govern them are already decided:

- Sub-agents declare their tool list and model in frontmatter. Review and audit agents get no write
  tools — the guarantee is structural, not an instruction the model can forget.
- Frontmatter restricts by tool, not by path. Confining an agent to `*Test.cls` needs a PreToolUse
  hook that validates the path and blocks with exit 2.
- Hooks carry the guardrails that must not depend on the model remembering: secret scanning,
  hardcoded-ID detection, analyzer after each edit.
