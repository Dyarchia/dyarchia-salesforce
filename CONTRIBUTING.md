# Contributing to dyarchia-salesforce

This is a published skill library: people install it as a plugin or read `skills/` from a clone,
so a broken frontmatter key or a lying catalogue reaches real users on their next pull.

[`CLAUDE.md`](CLAUDE.md) is the **contract** — frontmatter rules, body conventions, the branch
model, the shared-reference canon and every validator check. This page is the **procedure**. Read
both before your first change; neither is inferable from a diff, and they exist to prevent drift
between them.

Every procedure here ends with `scripts/validate-skills` exiting 0.

## Branches

Work flows one way: **feature → `develop` → `master`**.

- Branch from `develop`, and **set the pull-request base to `develop` by hand**. GitHub offers
  `master` as the default branch, and accepting it skips `develop` entirely.
- Publishing is a fast-forward, never a merge: `git push origin develop:master`. Never force-push
  `master`.
- `master` lagging `develop` between publishes is normal. It means unpublished work.

## Adding a skill

1. **Confirm the gap is real.** A skill enters the library on a recurring need from actual project
   work, not because a topic exists. Growing `references/` in a sibling beats a thin new skill.
2. **Create `skills/dya-sf-<name>/SKILL.md`** with two frontmatter keys: `name`, identical to the
   folder name, and `description` stating domain, version and surface, then the files and metadata
   that put an edit in scope, closing on the trigger clause verbatim: *Applies to `<files and
   metadata>`. Load before creating or editing anything in this scope, or when the user invokes this
   skill by name (`dya-sf-<name>`).*
3. **Write the body** to the conventions in `CLAUDE.md`: scope and its **explicit exclusions**
   first, then the numbered rules. Say what the skill is not — the commerce and integration families
   route on those boundaries. Never open by assigning an identity.
4. **Wire the routing graph.** Name siblings in backticks wherever a reader should hand off, and add
   the reverse pointer in every sibling that should hand off to the new skill.
5. **Move consultative material into `references/`** and cite every file from `SKILL.md`; an uncited
   reference fails validation. The `SKILL.md` ceiling is 20480 bytes.
6. **Declare shared fragments** in `shared-refs.txt`, then sync. Always sync *before* validating, or
   your canon edit is reported as drift in every skill that declares it:

   ```bash
   scripts/sync-shared-refs.sh dya-sf-<name>
   ```

   ```powershell
   pwsh -NoProfile -File scripts/sync-shared-refs.ps1 dya-sf-<name>
   ```

7. **Update the skill count everywhere it is asserted.** The validator checks five sites and fails
   on any that disagrees with the number of folders under `skills/`; it does not check the prose in
   `CLAUDE.md` and this file, so update those two by hand.
8. **Add the skill to the README catalogue and layout diagram**, then a CHANGELOG entry under
   `## [Unreleased]` → `### Added`.
9. **Validate, then commit** as `feat(skills): add dya-sf-<name> skill`, on a branch cut from `develop`.

## Editing, splitting, removing

- **Editing** — source only, never a file under `references/shared/`, which is generated. Edit a
  shared fact in `references-shared/` and re-sync. CHANGELOG under `### Changed`, describing what a
  consumer would notice rather than which lines moved.
- **Splitting** past the ceiling — the trigger is not size alone but material *consulted* rather
  than *obeyed*. Move it verbatim, never summarised, and leave a one-line pointer naming the
  reference file and when to open it. An orphaned reference is worse than an inline section.
- **Removing** — delete the folder, strip every README mention including the layout diagram, and
  amend CHANGELOG entries only while unreleased; released history stays. The validator names every
  file still holding a dangling handoff; that list is the work.

## Validation

```bash
scripts/validate-skills.sh
```

```powershell
pwsh -NoProfile -File scripts/validate-skills.ps1
```

It must exit 0 before any commit touching `skills/`. A clean tree validates with **zero errors and
zero warnings** — fix a new warning in the same commit; do not carry it as debt.

## Commits

Conventional Commits, scoped by area:

```text
feat(skills): add dya-sf-<name> skill
fix(skills): correct the callout-after-DML rule in dya-sf-integration-outbound
docs(repo): state the shared-reference sync order in CONTRIBUTING
```

One skill per commit when adding. A shared-reference sync travels in the same commit as the canon
edit that caused it.
