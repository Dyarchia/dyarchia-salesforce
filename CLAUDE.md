# dyarchia-salesforce

The Salesforce domain plugin of the Dyarchia umbrella: a library of agent skills targeting
Summer '26 / API v67.0, packaged as a Claude Code plugin and as portable `.skill` bundles.

This repo ships **content**, not software. There is no application and no runtime — only the
`SKILL.md` files, the manifests that let Claude Code install them, and two packaging scripts.

One repo per domain, one plugin per repo. Sibling domains get their own repos under the same org.

## Branches

`develop` is the working branch and carries everything described in this file. `master` is still
parked at the initial commit `5b0981d` — the superseded three-skill `decimatio-*` layout, with no
manifests and no scripts. `origin/HEAD` points at `master`, so branching from the repository
default silently yields the obsolete tree.

**Branch from `develop`.**

## Layout

```text
dyarchia-salesforce/
├── .claude-plugin/
│   ├── plugin.json                # plugin identity; components auto-discovered
│   └── marketplace.json           # the repo is its own marketplace
├── CLAUDE.md                      # this file
├── README.md                      # public catalogue and install instructions
├── CHANGELOG.md                   # Keep a Changelog format
├── skills/
│   └── dya-<name>/
│       ├── SKILL.md               # load-bearing instructions
│       └── references/            # loaded on demand, never at invocation time
├── dist/                          # 25 pre-built .skill bundles, committed
├── scripts/                       # packaging and validation
├── docs/                          # postponed work and notes, not published with the skills
└── .claude/skills/                # skills that operate on THIS repo
```

Not present yet, reserved by convention: `agents/`, `commands/`, `hooks/`, and `mcp/` for MCP
servers written here. Third-party MCP servers are not vendored and not declared.

`sources/` may exist locally: read-only clones of third-party repos kept as raw material. It is
gitignored, never installed, never published. Do not glob or grep across it by accident — it is
large.

## Commands

There is no test runner, no linter and no CI. Two scripts, each with a PowerShell and a bash twin,
are the entire tooling surface. Both `.ps1` files declare `#Requires -Version 7.0`.

```bash
scripts/build-skill.sh                 # rebuild every bundle
scripts/build-skill.sh dya-apex        # rebuild one; accepts several names
scripts/validate-skills.sh             # the gate; must exit 0
```

```powershell
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
README names a dya-* token that is not a folder      allowlist-filtered
```

The invocation clause is matched as the literal substring `Load only when the user explicitly
invokes this skill by name`. Reword it and the skill fails validation.

The allowlist behind that second warning is hardcoded in both scripts — `$nonSkillTokens` in the
PowerShell version, `NON_SKILL_TOKENS` in the bash one — and holds a single entry today,
`dya-skill-authoring`. That skill is `dya-`-prefixed but lives under `.claude/skills/` rather than
`skills/`, and the README references it, so without the allowlist the scan would flag it. Any
further repo-local meta-skill must be added to **both** scripts.

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
  it. Past that, split into `references/`. Three skills already breach it and are carried as known
  debt: `dya-apex`, `dya-flow`, `dya-lwc`. A clean tree therefore validates with a non-zero WARN
  count; only errors gate a commit.

### The section skeleton

All 25 skills share the same shape. Match it — the consistency is what lets a reader jump between
skills without relearning the layout.

- Open with `## Platform Context — Summer '26 / API v67.0`, stating the release's relevant changes
  and versioned defaults before any rule.
- Carry the rules in numbered `## N. Title` sections.
- Express decision matrices as **markdown pipe tables**. This is the house convention for skill
  bodies and it overrides any general preference for ASCII tables in documentation.
- Annotate code blocks inline with `✅` and `❌` on the lines they judge.
- Close with a fixed pair: `## N. Anti-Patterns — NEVER Do These`, a two-column
  anti-pattern-to-replacement table, then `## Summary — The Five Commandments`, a numbered list of
  exactly five.

## Platform version

`Summer '26 / API v67.0` is a repo-wide invariant, not a per-skill detail. It is asserted in all 25
Platform Context sections, in the README badge, and in the descriptions inside `plugin.json` and
`marketplace.json`. A version bump is therefore a coordinated sweep across every source file plus a
full rebuild of `dist/` — never a single-skill edit.

The plugin `version` field is duplicated across `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (`0.2.0` in both). Nothing checks that they agree; bump them
together.

## Adding or editing a skill

The prescriptive procedure lives in `.claude/skills/dya-skill-authoring/SKILL.md`. Invoke it
rather than improvising. The short version:

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
25 binaries in the diff and buries whatever actually changed. If you touch the builders, keep that
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
