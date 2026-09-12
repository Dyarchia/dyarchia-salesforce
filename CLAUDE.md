# dyarchia-salesforce

The Salesforce domain plugin of the Dyarchia umbrella: a library of agent skills targeting
Winter '27 / API v68.0, published as a Claude Code plugin and marketplace, and readable as-is by any
host that implements Agent Skills.

This repo ships **content**, not software. There is no application and no runtime — only the
`SKILL.md` files, the manifests that let hosts install them, and the packaging scripts.

One repo per domain, one plugin per repo. Sibling domains get their own repos under the same org.

## Branches

Work flows in one direction: **feature → `develop` → `master`**.

`develop` is the working branch and carries everything described in this file. `master` is the
published branch and GitHub's default; nothing lands on it directly.

**Publishing is a fast-forward, never a merge:**

```bash
git push origin develop:master
```

`master` is a pointer at whichever `develop` commit was last published, so the two branches share one
history and cannot diverge. Mark the publish with an annotated tag rather than a commit — a tag is
what a release marker is for, and it does not distort the branch graph.

This replaced a merge-based sync in September 2026. Merging `develop` into `master` created a commit
on `master` that never flowed back, so the counter grew by one per release and GitHub reported
`develop` as eight commits behind `master` while the two were byte-identical. Worse than cosmetic:
the "behind" banner invites a `git merge master` on `develop`, which drags publish-only commits into
the working branch and breaks the one-way flow. **If you ever find the two diverged again, reconcile
with a single merge of `master` into `develop` — never force-push `master`.**

Three consequences follow, and they bite silently:

- **Branch from `develop`, and set the pull-request base to `develop`.** GitHub offers `master`
  because it is the default, so the base must be changed by hand every time. A pull request that
  keeps the offered base skips `develop` entirely.
- A clone or worktree created under a different default still has a stale
  `refs/remotes/origin/HEAD`, so checking out the bare default hands you the wrong branch. Repair it
  with `git remote set-head origin -a` instead of routing around it.
- **`master` lagging `develop` between publishes is the normal state**, and GitHub will say so. It
  means unpublished work, not a problem to fix by merging anything backwards.

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
├── .codex-plugin/
│   └── plugin.json                # the same skills/ tree, served to Codex
├── commands/                      # slash commands; outside the validator's reach
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
├── scripts/                       # shared-reference sync and validation
└── docs/                          # local working notes, untracked
```

`.claude/` may exist locally — agent settings, repo-local skills, worktrees — and is gitignored in
full. Nothing inside it is part of the contract; `CONTRIBUTING.md` is.

`commands/` holds slash commands. **The validator does not walk it** — it only walks `skills/` — so a
command is not counted as a skill and needs no Platform Context heading.
That is the reason a meta-command like `/dya-sf-skills` lives there rather than under `skills/`:
it is not a Salesforce domain playbook and must not inflate the skill count.

Not present yet, reserved by convention: `agents/`, `hooks/`, and `mcp/` for MCP servers written
here. Third-party MCP servers are not vendored and not declared. Hosts discover all three from the
repository root, so adding one ships it without touching any script.

`sources/` may exist locally: read-only clones of third-party repos kept as raw material. It is
gitignored, never installed, never published. Do not glob or grep across it by accident — it is
large.

## Commands

There is no test runner, no linter and no CI. Two scripts, each with a PowerShell and a bash twin,
are the entire tooling surface. The order matters: **sync, then validate** — the validator compares
each synced copy against its canon, so validating before syncing reports the edit you just made as
drift. Both `.ps1` files declare `#Requires -Version 7.0`.

```bash
scripts/sync-shared-refs.sh            # materialise references-shared/ into each skill
scripts/validate-skills.sh             # the gate; must exit 0
```

```powershell
pwsh -NoProfile -File scripts/sync-shared-refs.ps1
pwsh -NoProfile -File scripts/validate-skills.ps1
```

- The source root is overridable: a `-SourceRoot` parameter in PowerShell, a `SOURCE_ROOT`
  environment variable in bash, defaulting to `skills`. It is joined onto the repo root, so it must
  be **relative**; an absolute path produces a nonsense concatenated path and the run dies.
- The bash validator needs `sha256sum` on PATH and exits 1 without it.

### What the validator enforces

`validate-skills` is the closest thing this repo has to a test suite. It walks every folder under
`skills/`, checks it against the contract, and cross-checks the README and the manifests.

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
a stated skill count disagrees with skills/             5 sites: 3 in README, both plugin manifests
the Claude and Codex manifests disagree                 name, version, and the skills/ path
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
`marketplace.json`. A version bump is therefore a coordinated sweep across every source file — never
a single-skill edit.

The plugin `version` field is duplicated across `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (`0.3.0` in both). `validate-skills` now checks that they agree,
but it cannot tell you which one is right — bump them together.

A version bump is no longer a manual sweep across 267 occurrences. Edit the README catalogue line
and badge, the plugin description, and `references-shared/platform-deltas.md`; then update each
skill's `## Platform Context` heading and re-verify its per-domain claims. The validator reports
every skill you missed.

## Host manifests

**The skills are not Claude-specific; only the manifests are.** A skill is a folder with a `SKILL.md`
carrying `name` and `description` in frontmatter — the Agent Skills shape that Codex, Grok and
Mistral Vibe all read. That is why the frontmatter contract below is exactly two keys: it is the
intersection every host requires, and hosts ignore keys they do not know.

Two manifests serve the one `skills/` tree:

```text
.claude-plugin/plugin.json + marketplace.json    Claude Code
.codex-plugin/plugin.json                        Codex / ChatGPT
```

Grok needs neither — it reads Claude Code's marketplaces, plugins, skills and instruction files with
no configuration. Anything reading `.agents/skills/` finds the tree through a symlink.

The two manifests **duplicate the plugin name, version and description**, which is exactly the drift
this repo is built to prevent, so `validate-skills` checks all three against each other and against
`skills/` and fails on disagreement. Adding a third host means adding it to that check in both script
twins — never a manifest on its own.

`.codex-plugin/plugin.json` also declares `"skills": "./skills/"`, which the validator pins to the
source root. Changing `SourceRoot` without changing that string breaks the Codex install silently.

## Plugin and marketplace identity

Both Claude manifests carry the name **`dyarchia-salesforce`**, and they are meant to match. The repository
is simultaneously the plugin and the marketplace that serves it — one repo per domain, one plugin per
repo — so a consumer installs with `/plugin install dyarchia-salesforce@dyarchia-salesforce`, where
the part after the `@` is the marketplace.

The marketplace was called `dyarchia` until September 2026. That name belonged to the organisation
rather than to this repository, so every sibling domain repo would have declared a marketplace by the
same name and a consumer adding two of them would have collided. **Name a domain repo's marketplace
after the repo, never after the org.**

The **skill count is checked wherever a script can read it**, the same way the platform version is:
the README catalogue line, both boxes of the README layout diagram, the README install line, and the
description of **both** plugin manifests. A disagreement with the number of folders under `skills/`
is a hard failure, so the count either lands everywhere or the build stops.

Two things follow. Rewording an assertion so no number survives produces a **warning** rather than
silence — a check that quietly stops applying is worse than one that fails. And the count is still
asserted in prose in `CLAUDE.md` and `CONTRIBUTING.md`, which nothing verifies; those are the two
places to update by hand.

## Adding or editing a skill

The prescriptive procedure lives in `CONTRIBUTING.md`. Follow it rather than improvising. The short
version:

1. Author or edit `skills/dya-<name>/SKILL.md`.
2. Sync if you touched a shared fragment: `scripts/sync-shared-refs.ps1` (or the `.sh` twin).
3. Validate: `scripts/validate-skills.ps1` (or the `.sh` twin). It must exit 0.
4. Update the README catalogue and the CHANGELOG in the same commit.

Drift between what a document asserts and what the tree holds is the failure mode this repo is most
exposed to. `validate-skills` exists to catch it; run it before every commit that touches `skills/`.

## Commit conventions

Conventional Commits, scoped by area:

```text
feat(skills): add dya-<name> skill
fix(skills): correct the callout-after-DML rule in dya-integration-outbound
fix(repo): pin the Codex manifest skills path to the source root
docs(repo): state the shared-reference sync order in CONTRIBUTING
```

One skill per commit when adding. A shared-reference sync travels in the same commit as the canon
edit that caused it.

## Out of scope

- **Project context.** Consuming repos carry their own `CLAUDE.md` with stack, org and deploy
  commands. This repo supplies reusable capability; mixing the two kills portability.
- **Third-party MCP servers.** Not vendored, not declared in `plugin.json`. Consumers wire their
  own. Only MCP servers written here would ship.
- **The `dyarchia` CLI.** Developed and distributed separately. Scripts here may call it if it
  is on PATH, treating it as an external dependency like `sf` or `jq`.

## Architecture status

Implemented: the plugin, marketplace and Codex manifests, `skills/`, `commands/`, the packaging and
validation scripts.

`commands/` holds one entry, `/dya-sf-skills`, and it exists because of a consequence of the
frontmatter contract. Skills that load **only on explicit invocation** are undiscoverable by
definition: asking a Salesforce question never surfaces them, so a reader who does not already know
the catalogue never finds it. The command prints that catalogue. It reads the descriptions already in
context rather than the filesystem, so it cannot drift from what is installed.

**Not implemented:** `agents/`, `hooks/` and `mcp/`. Nothing depends on them; they are additive
whenever a real recurring need shows up in project work. When they arrive, the principles that
govern them are already decided:

- Sub-agents declare their tool list and model in frontmatter. Review and audit agents get no write
  tools — the guarantee is structural, not an instruction the model can forget.
- Frontmatter restricts by tool, not by path. Confining an agent to `*Test.cls` needs a PreToolUse
  hook that validates the path and blocks with exit 2.
- Hooks carry the guardrails that must not depend on the model remembering: secret scanning,
  hardcoded-ID detection, analyzer after each edit.
