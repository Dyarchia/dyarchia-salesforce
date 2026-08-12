# decimatio-salesforce

The Salesforce domain plugin of the Decimatio umbrella: a library of agent skills targeting
Summer '26 / API v67.0, packaged as a Claude Code plugin and as portable `.skill` bundles.

This repo ships **content**, not software. There is no application and no runtime — only the
`SKILL.md` files, the manifests that let Claude Code install them, and two packaging scripts.

One repo per domain, one plugin per repo. Sibling domains get their own repos under the same org.

## Layout

```text
decimatio-salesforce/
├── .claude-plugin/
│   ├── plugin.json                # plugin identity; components auto-discovered
│   └── marketplace.json           # the repo is its own marketplace
├── CLAUDE.md                      # this file
├── README.md                      # public catalogue and install instructions
├── CHANGELOG.md                   # Keep a Changelog format
├── skills/
│   └── decimatio-<name>/
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

## The frontmatter contract

Every `SKILL.md` opens with YAML frontmatter carrying exactly two keys:

```yaml
---
name: decimatio-<name>
description: <domain and version> — <what it covers, comma-separated>. Load only when the user
  explicitly invokes this skill by name (`decimatio-<name>`); do NOT auto-trigger on generic
  <domain> questions.
---
```

Three invariants, all load-bearing:

- `name` matches the containing folder name, exactly.
- The description ends with the explicit-invocation clause. These are reference playbooks, not
  ambient context — auto-triggering them on generic questions poisons unrelated sessions.
- The description enumerates the actual surface covered, so the router can pick between siblings
  without loading them.

The `decimatio-` prefix stays on skill names even though the repo no longer repeats it. Skill names
live in a global namespace inside the assistant, alongside `sf-apex`, `salesforce-skills` and other
third-party Salesforce skills; that is where the prefix earns its keep.

## Skill body conventions

- Second-person expert framing: "You are an expert X. You **always** ... Follow every rule below."
- Cross-reference siblings by bare skill name in backticks. The integration family in particular
  is a routing graph: `decimatio-integration-overview` routes, the others build.
- Scope exclusions are stated in the opening paragraph, not buried. Example: `decimatio-b2c-commerce`
  declares up front that there is no Apex, LWC or SOQL on that platform.
- `SKILL.md` holds what must be true on every invocation. Anything consulted occasionally —
  full code listings, command catalogues, per-vendor detail — belongs in `references/`.
- Target ceiling for `SKILL.md`: roughly 20 KB. Past that, split into `references/`.

## Adding or editing a skill

The prescriptive procedure lives in `.claude/skills/decimatio-skill-authoring/SKILL.md`. Invoke it
rather than improvising. The short version:

1. Author or edit `skills/decimatio-<name>/SKILL.md`.
2. Rebuild the bundle: `scripts/build-skill.ps1 decimatio-<name>` (or the `.sh` twin).
3. Validate: `scripts/validate-skills.ps1` (or the `.sh` twin). It must exit 0.
4. Update the README catalogue and the CHANGELOG in the same commit.

Source and bundle drift is the failure mode this repo is most exposed to. `validate-skills`
exists to catch it; run it before every commit that touches `skills/`.

## Bundle packaging

A `.skill` file is a ZIP whose top-level entry is the skill folder — unzipping yields
`decimatio-apex/SKILL.md`, never a nested `skills/decimatio-apex/SKILL.md`.

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
feat(skills): add decimatio-<name> skill
fix(skills): correct the callout-after-DML rule in decimatio-integration-outbound
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
- **The `decimatio` CLI.** Developed and distributed separately. Scripts here may call it if it
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
