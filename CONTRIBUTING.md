# Contributing to dyarchia-salesforce

This is a published skill library. People install it as a plugin or read `skills/` straight from a
clone, so a broken frontmatter key or a catalogue that lies reaches real users on their next pull.
Every procedure on this page ends the same way: `scripts/validate-skills` exits 0. Nothing is
finished before it does.

Read this page and [`CLAUDE.md`](CLAUDE.md) before your first change. These conventions are not
inferable from a diff.

## The artifacts that must agree

A skill is a folder under `skills/dya-<name>/` and nothing else is generated from it. What drifts
here is prose: the README catalogue, the skill count, the platform version and the handoffs between
skills all assert things about a tree that changes under them. **That drift is this repository's
defining failure mode**, and `validate-skills` exists to catch every kind of it a script can read.

One generated artifact does exist. Platform fundamentals — governor limits, the
access model, SOQL selectivity, API version semantics, the org and deployment model, the release
deltas — live exactly once, in `references-shared/` at the repository root. A skill declares the
fragments it needs in `skills/dya-<name>/shared-refs.txt`, one name per line, and
`scripts/sync-shared-refs` copies them into `skills/dya-<name>/references/shared/`. Those copies are
committed, so a clone carries everything a skill needs with no build step.

**Never edit a file under `references/shared/`.** Edit the canon and re-sync. The validator hashes
every copy against its canon and fails on any difference. A fact that belongs to more than one skill
belongs in the canon rather than pasted into each body — that duplication is what turned the last
platform version bump into a sweep across 267 occurrences in 58 files.

Every host reads `skills/` directly: `.claude-plugin/plugin.json` serves Claude Code,
`.codex-plugin/plugin.json` serves Codex, and Grok and Mistral read the tree as it sits. There is no
build step and no packaged artifact to keep in sync.

## Branches and pull requests

Work flows in one direction: **feature → `develop` → `master`**.

- Branch from `develop`, and set the pull-request base to `develop` by hand. GitHub offers `master`
  because it is the default branch; accepting the offer skips `develop` entirely.
- `master` is the published branch and nothing lands on it directly. **Publishing is a fast-forward,
  never a merge**, so the two branches share one history and cannot diverge:

```bash
git push origin develop:master
```

- Mark the publish with an annotated tag rather than a commit. A merge-based sync used to leave a
  commit on `master` that never flowed back, so `develop` was reported as eight commits behind while
  being byte-identical to it — and that banner invites a `git merge master` on `develop`, which
  drags publish-only commits into the working branch. If the two ever diverge again, reconcile with
  a single merge of `master` into `develop`; **never force-push `master`**.
- `master` lagging `develop` between publishes is the normal state. It means unpublished work.
- A clone or worktree created under a different default carries a stale `refs/remotes/origin/HEAD`,
  so checking out the bare default hands you the wrong branch. Repair the ref rather than routing
  around it:

```bash
git remote set-head origin -a
```

## Adding a new skill

1. Confirm the gap is real. A skill enters the library when a recurring need has shown up in actual
   project work, not because a topic exists. Check first whether an existing skill should absorb the
   material — growing `references/` in a sibling beats a thin new skill.
2. Create `skills/dya-<name>/SKILL.md` with the frontmatter contract:
   - `name`, identical to the folder name.
   - `description`, stating domain and platform version, then the surface covered, then the
     explicit-invocation clause verbatim: *Load only when the user explicitly invokes this skill by
     name (`dya-<name>`); do NOT auto-trigger on generic `<domain>` questions.*
3. Write the body in the house voice: an opening paragraph that states scope **and its explicit
   exclusions**, then the numbered rules. Say what the skill is not — the commerce and integration
   families depend on those boundaries to route correctly. **Do not open by assigning an identity.**
   "You are an expert X" is redundant with the heading and incoherent once two skills load at once;
   the second-person imperative belongs on the rules, not on who the reader is.
4. Wire the routing graph. Name sibling skills in backticks wherever a reader should hand off — the
   validator checks every one of those names resolves — and add the reverse pointer in every sibling
   that should hand off to the new skill.
5. Move occasional-consultation material into `references/`. `SKILL.md` carries only what must be
   true on every invocation; the ceiling is 20480 bytes.
6. Declare any shared fragments in `skills/dya-<name>/shared-refs.txt`, cite each one by filename
   from `SKILL.md` — an uncited reference is a validation error — then sync:

   ```bash
   scripts/sync-shared-refs.sh dya-<name>
   ```

   ```powershell
   pwsh -NoProfile -File scripts/sync-shared-refs.ps1 dya-<name>
   ```

   The order is always **sync, then validate**. Validating first reports the canon edit you just
   made as drift in every skill that declares the fragment.
7. Add the skill to the README catalogue and to the layout diagram, and move the skill count
   everywhere it is asserted. The validator checks five of those sites and **fails** on any that
   disagree with the number of folders under `skills/` — the README catalogue line, the `skills/`
   box of its layout diagram, the install line, and the description of **both**
   `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`. It cannot check the prose in
   `CLAUDE.md` and this file, so update those two by hand.
8. Add a CHANGELOG entry under `## [Unreleased]` → `### Added`.
9. Run the validator. It must exit 0.
10. Commit as `feat(skills): add dya-<name> skill`, on a branch cut from `develop`.

## Editing an existing skill

1. Edit only the source under `skills/dya-<name>/` — and never a file under `references/shared/`,
   which is generated. A shared fact is edited in `references-shared/` and re-synced everywhere.
2. If the edit touched a shared fragment, edit the canon and re-sync, as in step 6 above.
3. Add a CHANGELOG entry under `### Changed`, describing what a consumer would notice rather than
   which lines moved.
4. Run the validator. It must exit 0.
5. Commit as `feat(skills): ...` or `fix(skills): ...`, scoped to the one skill.

## Splitting an oversized SKILL.md

The validator warns past 20480 bytes, but size alone is not the trigger. The trigger is material
that is consulted rather than obeyed.

1. Classify every section as **load-bearing** (a rule that must hold on every invocation) or
   **consultative** (a listing, catalogue or worked example looked up when the topic comes up).
2. Move the consultative sections verbatim into `references/<topic>.md`. Do not summarise while
   moving — the point of the split is that the detail survives at full fidelity, just deferred.
3. Leave a one-line pointer in `SKILL.md` where the section stood, naming the reference file and
   when to open it. An orphaned reference file is worse than an inline section.
4. Update the CHANGELOG and run the validator.

## Removing a skill

1. Delete the source folder under `skills/`.
2. Remove every mention from the README, including the layout diagram.
3. Remove or amend its CHANGELOG entries only while unreleased; released history stays.
4. Repair the handoffs. Run the validator: it **fails** on every backticked `dya-<name>` that no
   longer resolves to a folder, and names the file each one is in, so the list is the work.
5. Run the validator. It must exit 0.

## Validation

```bash
scripts/validate-skills.sh
```

```powershell
pwsh -NoProfile -File scripts/validate-skills.ps1
```

Every check below is an error except the last, which is a warning:

```text
Check                                    Meaning of a failure
--------------------------------------   ------------------------------------------------
SKILL.md present                         Folder is not a skill
Frontmatter parses                       YAML block missing or malformed
name matches folder                      The host loads the skill under the wrong identity
description present                      The assistant cannot route to the skill
Explicit-invocation clause present       The skill will pollute unrelated sessions
Listed in the README catalogue           Catalogue drift, the published index lies
Platform Context declares the version    A version bump landed half-applied
README badge agrees with catalogue       The two halves of the README disagree
plugin.json states the version           The published description is stale
plugin/marketplace versions agree        The marketplace advertises a different build
Host manifests agree                     Claude and Codex disagree on name or version
Every references/ file is cited          A reference no agent can ever reach
Cross-referenced skills exist            A handoff points at a skill that is gone
Stated skill counts match skills/        The catalogue lies about how much is in the box
Shared fragments match their canon       Someone edited a generated copy
Synced files are all declared            sync-shared-refs was not re-run
SKILL.md under 20480 bytes               Warning only, invocation cost is high
```

The platform version is read from the README catalogue line, so **the README is the single source of
truth** and every other assertion is checked against it. Two skills are exempt by allowlist:
`dya-b2c-commerce` (Demandware lineage, no core API version) and `dya-sf-cli` (the CLI versions on
its own weekly cadence). That allowlist is hardcoded in **both** script twins, PowerShell and bash.

All 26 skills sit under the size ceiling today, so a clean tree validates with **zero errors and
zero warnings**. Treat a new warning as something to fix in the same commit, not as debt to carry.

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

## Anti-patterns

- Editing a file under `references/shared/`. It is generated; the next sync overwrites it and the
  validator fails before then. Edit `references-shared/`.
- Restating a platform fundamental in a skill body because it is "only one line". That is exactly
  how one fact became twenty-six copies.
- Dropping the explicit-invocation clause to make a skill "more discoverable". These are reference
  playbooks; ambient triggering is the thing the contract prevents.
- Adding a skill without the reverse cross-references. The router silently stops finding it.
- Adding to the README catalogue but not the layout diagram, or the reverse. The validator only
  proves the name appears somewhere in the file; the diagram is on you.
- Deferring a README or CHANGELOG update "to the next commit". That is precisely how the published
  catalogue starts lying about what is in the box.
