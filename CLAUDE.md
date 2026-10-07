# dyarchia-salesforce

The Salesforce domain plugin of the Dyarchia umbrella: a library of agent skills targeting
Winter '27 / API v68.0, published as a Claude Code plugin and marketplace, and readable as-is by any
host that implements Agent Skills.

This repo ships **content**, not software: no application, no runtime — only the `SKILL.md` files,
the manifests that let hosts install them, and the packaging scripts.

One repo per domain, one plugin per repo. Sibling domains get their own repos under the same org.

## Branches

Work flows one way: **feature → `develop` → `master`**.

`develop` is the working branch and carries everything this file describes. `master` is the
published branch and GitHub's default; nothing lands on it directly.

**Publishing is a fast-forward, never a merge:**

```bash
git push origin develop:master
```

`master` points at whichever `develop` commit was last published, so the two share one history and
cannot diverge. Mark the publish with an annotated tag, not a commit: a tag is a release marker and
does not distort the branch graph.

This replaced a merge-based sync in September 2026. Each merge of `develop` into `master` created a
commit on `master` that never flowed back, so GitHub reported `develop` one more commit behind per
release, eight in the end, while the two were byte-identical. The "behind" banner also invites a
`git merge master` on `develop`, which drags publish-only commits into the working branch and breaks
the one-way flow.
**If the two ever diverge again, reconcile with a single merge of `master` into `develop` — never
force-push `master`.**

Three consequences, all silent:

- **Branch from `develop`, and set the pull-request base to `develop`.** GitHub offers `master` as
  the default, so change the base by hand every time; a pull request that keeps it skips `develop`.
- A clone or worktree created under a different default has a stale `refs/remotes/origin/HEAD`, so
  checking out the bare default gives the wrong branch. Repair it with `git remote set-head origin -a`
  instead of routing around it.
- **`master` lagging `develop` between publishes is normal**, and GitHub will say so. It means
  unpublished work, not something to fix by merging backwards.

This file and `CONTRIBUTING.md` are **versioned on every branch**. They are the contributor
contract: a clone without them cannot be contributed to correctly, and drift between them is this
repo's defining failure mode. Like every file here, they are written in English.

Untracked and gitignored by design: `.claude/` in full (the per-machine agent workspace: local
settings, repo-local skills, worktrees), plus `docs/` and `.docs/` in full (private working notes).
They record what someone is thinking about, not how the library works, and are not part of the
contract: anything a contributor must know belongs in this file or `CONTRIBUTING.md`.

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
│   └── dya-sf-<name>/
│       ├── SKILL.md               # load-bearing instructions
│       ├── shared-refs.txt        # which shared fragments this skill needs
│       └── references/            # loaded on demand, never at invocation time
│           └── shared/            # GENERATED copies of references-shared/, committed
├── references-shared/             # the canon: platform fundamentals, written once
├── scripts/                       # shared-reference sync and validation
└── docs/                          # local working notes, untracked
```

**The validator does not walk `commands/`**, only `skills/`, so a command is not counted as a skill
and needs no Platform Context heading. That is why a meta-command like `/dya-sf-skills` lives there:
it is not a Salesforce domain playbook and must not inflate the skill count.

Reserved by convention, not present yet: `agents/`, `hooks/`, and `mcp/` for MCP servers written
here. Third-party MCP servers are not vendored and not declared. Hosts discover all three from the
repository root, so adding one ships it without touching any script.

`sources/` may exist locally: read-only clones of third-party repos kept as raw material. It is
gitignored, never installed, never published, and large; do not glob or grep across it by accident.

## Commands

No test runner, no linter, no CI. Two scripts, each with a PowerShell and a bash twin, are the
entire tooling surface. **Sync, then validate**: the validator compares each synced copy against its
canon, so validating first reports your edit as drift. Both `.ps1` files declare
`#Requires -Version 7.0`.

```bash
scripts/sync-shared-refs.sh            # materialise references-shared/ into each skill
scripts/validate-skills.sh             # the gate; must exit 0
```

```powershell
pwsh -NoProfile -File scripts/sync-shared-refs.ps1
pwsh -NoProfile -File scripts/validate-skills.ps1
```

- The source root is overridable (`-SourceRoot` in PowerShell, the `SOURCE_ROOT` environment
  variable in bash) and defaults to `skills`. It is joined onto the repo root, so it must be
  **relative**; an absolute path produces a nonsense concatenated path and the run dies.
- The bash validator needs `sha256sum` on PATH and exits 1 without it.

### What the validator enforces

`validate-skills` is the closest thing to a test suite. It walks every folder under `skills/`,
checks it against the contract, and cross-checks the README and the manifests.

Hard failures — exit 1:

```text
condition                                              check
-----------------------------------------------------  ------------------------------------------
SKILL.md absent                                        per skill folder
no YAML frontmatter block                              the leading ---...--- must parse
no name key, or name differs from the folder name      exact string match
no description key                                     presence
description lacks the trigger clause                   literal substring match
skill has no README catalogue bullet                   a `- **`name`**` line
```

Warnings — still exit 0:

```text
condition                                            threshold
---------------------------------------------------  --------------------
SKILL.md over the size ceiling                       20480 bytes
SKILL.md over the ceiling with no references/        20480 bytes
README names a dya-sf-* token that is not a folder      allowlist-filtered
```

Further hard failures, added with the shared-reference canon:

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
a skill cites `dya-sf-<name>` that is not a folder         backticked tokens, per .md, shared/ excluded
a stated skill count disagrees with skills/             5 sites: 3 in README, both plugin manifests
the Claude and Codex manifests disagree                 name, version, and the skills/ path
```

**README is the single source of truth for the platform version.** The catalogue line
(`N skills, all targeting **<version>**`) is parsed, and the badge, every Platform Context heading
and the plugin description are checked against it. A version bump lands everywhere or fails, never
one skill at a time.

`$versionNeutralSkills` / `VERSION_NEUTRAL_SKILLS` exempts `dya-sf-b2c-commerce` (Demandware lineage,
no core API version) and `dya-sf-cli` (versions on the CLI's own weekly cadence). Like
`$nonSkillTokens`, it is hardcoded in **both** scripts.

The trigger clause is matched as the literal substring `Load before creating or editing anything in
this scope`. Reword it and the skill fails validation.

The allowlist behind the README-token warning (`$nonSkillTokens` in PowerShell, `NON_SKILL_TOKENS`
in bash) holds two entries: `dya-sf-skills`, the catalogue command, and the bare prefix `dya-sf-`,
which the README layout diagram states as `dya-sf-&lt;name&gt;/` and the token scan reads as a name.
It is for `dya-sf-`-prefixed names the README mentions on purpose without a folder under `skills/`;
add any such name to **both** scripts, or the scan flags it. It also covers the cross-reference
check below.

**The routing graph is validated.** Skills hand off by naming a sibling in backticks, which is why a
reader can start anywhere. A rename used to break every prose mention of the old name silently, so
the validator scans every `.md` under a skill, excluding the generated `references/shared/`, and
**fails** on a backticked `dya-sf-<name>` with no matching folder. It reads the graph from the prose
rather than from frontmatter, so a handoff costs only the sentence. After a rename or removal, the
validator names every file still pointing at the old name.

## The frontmatter contract

Every `SKILL.md` opens with YAML frontmatter carrying exactly two keys:

```yaml
---
name: dya-sf-<name>
description: <domain and version> — <what it covers, comma-separated>. Applies to <the files and
  metadata that put an edit in scope>. Load before creating or editing anything in this scope, or
  when the user invokes this skill by name (`dya-sf-<name>`).
---
```

Three load-bearing invariants:

- `name` matches the containing folder name exactly.
- The description ends with the trigger clause, preceded by an `Applies to` list of concrete files
  and metadata types. The skill loads before any edit in its scope, so the rules are in context when
  the code is written; a question that changes no code loads nothing. Name file extensions and
  metadata types, not topics: the router matches an edit against this list, and an edit crossing
  scopes loads every skill it touches.
- The description enumerates the surface covered, so the router can pick between siblings without
  loading them.

The `dya-sf-` prefix stays on skill names even though the repo name no longer repeats it, because
skill names share a global namespace inside the assistant with `sf-apex`, `salesforce-skills` and
other third-party Salesforce skills. The `sf` segment carries the domain, so a sibling domain repo
under the same org names its skills `dya-<domain>-<name>` and the two sets cannot collide.
**`dya-sf-cli` is not an exception to the scheme**: it was named before the sweep and already
matched it, and the string parses correctly either way.

## Skill body conventions

- **Never assign an identity.** No skill opens with "You are an expert X": the `#` heading already
  names the domain, and these skills compose; a reader loading `dya-sf-apex`, `dya-sf-lwc` and
  `dya-sf-flow` would be told they are three different people. Open on what is true about the
  domain, and keep the second-person imperative for the rules, which do compose:
  "You **always** ... Follow every rule below."
- **Close the opening paragraph with "Follow every rule below."** It is the compliance imperative
  and all 26 carry it. Introduce the reference list with a bare `References:`; the bullets say what
  each file is for.
- Cross-reference siblings by bare skill name in backticks. The integration family is a routing
  graph: `dya-sf-integration-overview` routes, the others build.
- State scope exclusions in the opening paragraph. Example: `dya-sf-b2c-commerce` declares up front
  that there is no Apex, LWC or SOQL on that platform.
- `SKILL.md` holds what must be true on every invocation. Anything consulted occasionally (full code
  listings, command catalogues, per-vendor detail) belongs in `references/`.
- `SKILL.md` size ceiling: 20480 bytes; `validate-skills` warns above it. Past that, split into
  `references/`. **All 26 skills are under the ceiling, so a clean tree validates with zero errors
  and zero warnings.** Fix a new warning in the same commit; do not accept it as debt.
- Platform fundamentals (governor limits, the access model, SOQL selectivity, API version
  semantics, the org and deployment model, the release deltas) are **never written into a skill
  body**. They live once in `references-shared/`; a skill declares what it needs in its own
  `shared-refs.txt` and `scripts/sync-shared-refs` materialises the copies. Editing a synced copy is
  a validation error.

### The section skeleton

All 26 skills share one shape, so a reader can jump between them without relearning the layout.
Match it.

- Open with `## Platform Context — Winter '27 / API v68.0`, stating the release's relevant changes
  and versioned defaults before any rule.
- Carry the rules in numbered `## N. Title` sections.
- Express decision matrices as **markdown pipe tables**. This house convention for skill bodies
  overrides any general preference for ASCII tables in documentation.
- Annotate code blocks inline with `✅` and `❌` on the lines they judge.
- Close with a fixed pair: `## N. Anti-Patterns — NEVER Do These`, a two-column
  anti-pattern-to-replacement table, then `## Summary — The Five Commandments`, a numbered list of
  exactly five.

## Platform version

`Winter '27 / API v68.0` is a repo-wide invariant, not a per-skill detail. It is asserted in all 26
Platform Context sections, the README badge, and the descriptions in `plugin.json` and
`marketplace.json`, so a version bump is a coordinated sweep across every source file, never a
single-skill edit.

It is no longer a manual sweep across 267 occurrences. Edit the README catalogue line and badge,
the plugin description, and `references-shared/platform-deltas.md`; then update each skill's
`## Platform Context` heading and re-verify its per-domain claims. The validator reports every skill
you missed.

The plugin `version` field is duplicated in `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (`0.3.0` in both). `validate-skills` checks that they agree but
cannot tell which is right; bump them together.

## Host manifests

**The skills are not Claude-specific; only the manifests are.** A skill is a folder with a `SKILL.md`
carrying `name` and `description` in frontmatter, the Agent Skills shape that Codex, Grok and
Mistral Vibe all read. That is why the frontmatter contract is exactly two keys: the intersection
every host requires, and hosts ignore keys they do not know.

Two manifests serve the one `skills/` tree:

```text
.claude-plugin/plugin.json + marketplace.json    Claude Code
.codex-plugin/plugin.json                        Codex / ChatGPT
```

Grok needs neither; it reads Claude Code's marketplaces, plugins, skills and instruction files with
no configuration. Anything reading `.agents/skills/` finds the tree through a symlink.

The two manifests **duplicate the plugin name, version and description**, so `validate-skills`
checks all three against each other and against `skills/` and fails on disagreement. Adding a third
host means adding it to that check in both script twins, never a manifest on its own.

`.codex-plugin/plugin.json` also declares `"skills": "./skills/"`, which the validator pins to the
source root. Changing `SourceRoot` without changing that string silently breaks the Codex install.

## Plugin and marketplace identity

Both Claude manifests carry the name **`dyarchia-salesforce`**, and must match. The repository is
both the plugin and the marketplace that serves it, so a consumer installs with
`/plugin install dyarchia-salesforce@dyarchia-salesforce`, where the part after the `@` is the
marketplace.

The marketplace was called `dyarchia` until September 2026. That name belonged to the organisation,
not this repository, so every sibling domain repo would have declared a marketplace of the same name
and a consumer adding two would have collided. **Name a domain repo's marketplace after the repo,
never after the org.**

The **skill count is checked wherever a script can read it**: the README catalogue line, layout
diagram and install line, and the description of **both** plugin manifests. Disagreeing with the
number of folders under `skills/` is a hard failure.

Rewording an assertion so no number survives produces a **warning**, not silence; a check that
quietly stops applying is worse than one that fails. `CLAUDE.md` and `CONTRIBUTING.md` also assert
the count in prose, which nothing verifies; update those two by hand.

## Adding or editing a skill

Follow the procedure in `CONTRIBUTING.md` rather than improvising. In short:

1. Author or edit `skills/dya-sf-<name>/SKILL.md`.
2. Sync if you touched a shared fragment: `scripts/sync-shared-refs.ps1` (or the `.sh` twin).
3. Validate: `scripts/validate-skills.ps1` (or the `.sh` twin). It must exit 0.
4. Update the README catalogue and the CHANGELOG in the same commit.

Drift between what a document asserts and what the tree holds is this repo's main exposure. Run
`validate-skills` before every commit that touches `skills/`.

## Commit conventions

Conventional Commits, scoped by area:

```text
feat(skills): add dya-sf-<name> skill
fix(skills): correct the callout-after-DML rule in dya-sf-integration-outbound
fix(repo): pin the Codex manifest skills path to the source root
docs(repo): state the shared-reference sync order in CONTRIBUTING
```

One skill per commit when adding. A shared-reference sync travels in the same commit as the canon
edit that caused it.

## Out of scope

- **Project context.** Consuming repos carry their own `CLAUDE.md` with stack, org and deploy
  commands. This repo supplies reusable capability; mixing the two kills portability.
- **Third-party MCP servers.** Not vendored, not declared in `plugin.json`; consumers wire their
  own. Only MCP servers written here would ship.
- **The `dyarchia` CLI.** Developed and distributed separately. Scripts here may call it if it is
  on PATH, as an external dependency like `sf` or `jq`.

## Architecture status

Implemented: the plugin, marketplace and Codex manifests, `skills/`, `commands/`, the packaging and
validation scripts.

`commands/` holds one entry, `/dya-sf-skills`. Skills load on their own only before an edit in
their scope, so a reader who is asking rather than editing never sees them; the command prints the
catalogue. It reads the descriptions already in context rather than the filesystem, so it cannot
drift from what is installed.

**Not implemented:** `agents/`, `hooks/` and `mcp/`. Nothing depends on them; they are added when a
real recurring need shows up in project work. Their governing principles are already decided:

- Sub-agents declare their tool list and model in frontmatter. Review and audit agents get no write
  tools; the guarantee is structural, not an instruction the model can forget.
- Frontmatter restricts by tool, not by path. Confining an agent to `*Test.cls` needs a PreToolUse
  hook that validates the path and blocks with exit 2.
- Hooks carry the guardrails that must not depend on the model remembering: secret scanning,
  hardcoded-ID detection, analyzer after each edit.
