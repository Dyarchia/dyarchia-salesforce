---
name: decimatio-skill-authoring
description: Authoring procedure for the decimatio-salesforce skill library — adding a skill, editing an existing one, splitting an oversized SKILL.md, rebuilding and validating .skill bundles, and updating README and CHANGELOG so they never drift. Load only when the user explicitly invokes this skill by name (`decimatio-skill-authoring`); do NOT auto-trigger on generic skill, documentation, or Salesforce questions.
---

# decimatio-salesforce — Skill Authoring

You are maintaining a published skill library. Consumers download `.skill` bundles and install them
into their own assistants, so a broken frontmatter key or a stale bundle ships to real users. Every
procedure below ends in `scripts/validate-skills` exiting 0. Do not declare work finished before it does.

## The two artifacts that must agree

Every skill exists twice: as a source folder under `skills/decimatio-<name>/` and as a committed
bundle `dist/decimatio-<name>.skill`. **Drift between them is the failure mode of this repo.** The
validator compares them file by file, by content hash. Never edit a bundle directly; always
regenerate it from source.

The plugin path (`.claude-plugin/plugin.json`) serves Claude Code straight from `skills/` and needs
no build step. The bundles exist for every other assistant.

## Adding a new skill

1. Confirm the gap is real. A skill enters the library only when a recurring need has shown up in
   actual project work, not because a topic exists. Check whether an existing skill should absorb
   the material instead — prefer growing `references/` in a sibling over a thin new skill.
2. Create `skills/decimatio-<name>/SKILL.md` with the frontmatter contract:
   - `name` identical to the folder name.
   - `description` stating domain and platform version, then the surface covered, then verbatim:
     `Load only when the user explicitly invokes this skill by name (\`decimatio-<name>\`); do NOT
     auto-trigger on generic <domain> questions.`
3. Write the body in the house voice: second-person expert framing, an opening paragraph that
   states scope **and explicit exclusions**, then the rules. State what the skill is not — the
   commerce and integration families depend on those boundaries to route correctly.
4. Wire the routing graph. Name sibling skills in backticks wherever the reader should hand off,
   and add the reverse pointer in each sibling that should hand off to the new one.
5. Move occasional-consultation material into `references/`. `SKILL.md` carries only what must be
   true on every invocation; the ceiling is roughly 20 KB.
6. Build the bundle:

```bash
scripts/build-skill.sh decimatio-<name>
```

```powershell
pwsh -NoProfile -File scripts/build-skill.ps1 decimatio-<name>
```

7. Add the skill to the README catalogue and to the layout diagram.
8. Add a CHANGELOG entry under `## [Unreleased]` → `### Added`.
9. Run the validator. It must exit 0.
10. Commit as `feat(skills): add decimatio-<name> skill`, source and bundle together.

## Editing an existing skill

1. Edit only the source under `skills/decimatio-<name>/`.
2. Rebuild that skill's bundle — step 6 above. A source edit without a rebuild is the drift the
   validator exists to catch.
3. Add a CHANGELOG entry under `### Changed` describing what a consumer would notice, not what
   lines moved.
4. Run the validator. It must exit 0.
5. Commit as `feat(skills): ...` or `fix(skills): ...`, scoped to the one skill.

## Splitting an oversized SKILL.md

The validator warns past 20 KB. Size alone is not the trigger — the trigger is material that is
consulted rather than obeyed.

1. Classify every section as **load-bearing** (a rule the agent must hold on every invocation) or
   **consultative** (a listing, catalogue, or worked example the agent looks up when the topic
   comes up).
2. Move consultative sections verbatim into `references/<topic>.md`. Do not summarise while moving
   — the point of the split is that the detail survives at full fidelity, just deferred.
3. Leave in `SKILL.md` a one-line pointer at the position the section occupied, naming the
   reference file and when to open it. An orphaned reference file is worse than an inline section.
4. Rebuild the bundle, update the CHANGELOG, run the validator.

## Removing a skill

1. Delete the source folder under `skills/` and its bundle under `dist/`.
2. Remove every mention from the README, including the layout diagram.
3. Remove or amend its CHANGELOG entries only if unreleased; released history stays.
4. Grep the remaining skills for cross-references to the removed name and repair those handoffs.
5. Run the validator. It must exit 0.

## Validation

```bash
scripts/validate-skills.sh
```

```powershell
pwsh -NoProfile -File scripts/validate-skills.ps1
```

Checks performed, all of them errors except the last:

```text
Check                                    Meaning of a failure
--------------------------------------   ------------------------------------------------
SKILL.md present                         Folder is not a skill
Frontmatter parses                       YAML block missing or malformed
name matches folder                      Bundle will install under the wrong identity
description present                      Assistant cannot route to the skill
Explicit-invocation clause present       Skill will pollute unrelated sessions
Listed in README                         Catalogue drift, the published index lies
Bundle exists                            Nothing to download
Entries rooted at <name>/                Unzips to the wrong path
Entries use forward slashes              Strict parsers reject the archive
Bundle content matches source            Consumers download stale instructions
SKILL.md under 20 KB                     Warning only, invocation cost is high
```

## Anti-patterns

- Editing a `.skill` bundle directly, or hand-zipping with `Compress-Archive`. It writes backslash
  entry names that strict importers reject. Use the scripts.
- Dropping the explicit-invocation clause to make a skill "more discoverable". These are reference
  playbooks; ambient triggering is the thing the contract prevents.
- Adding a skill without the reverse cross-references. The router silently stops finding it.
- Adding to the README table but not the layout diagram, or the reverse. The validator only proves
  the name appears somewhere in the file; the diagram is on you.
- Deferring the bundle rebuild "to the next commit". That is exactly how the two artifacts diverge.
