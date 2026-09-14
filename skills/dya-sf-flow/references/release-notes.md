# Winter '27 — What the Release Adds to Flow

Consultative. The facts that **change what you may build or claim** live in `SKILL.md`'s Platform
Context; this is the rest.

| Change | Status | What it gives you |
|---|---|---|
| Flow Test Mode in Flow Builder | **Beta** | Debug, save the run as a reusable test scenario, mock action outputs, and assert on results without leaving the canvas |
| Launch a screen flow for many records from a list view or related list | GA | Selected record Ids arrive in an `ids` text collection variable; from a related list you can also pass the parent record Id |
| Flow Tags | GA | Categorise flows and filter the Automation app list by tag |
| Unused-resources filter in the Toolbox | GA | Surfaces resources and elements nothing references, and elements missing a description |
| Collapsible canvas sections, Time screen component | GA | Large flows stay readable; capturing a time no longer needs a text field and a validation rule |

The Flow Builder UI refresh ships GA with no opt-out.

## Earlier releases, now simply how the platform works

Still worth knowing, because documentation and forum answers predating them read as if they were
new:

- Custom batch size on scheduled flows.
- Flow Orchestration as a Standard feature.
- The Date operator family in Decision elements: `Is Today`, `Is This Month`,
  `Is Anniversary of Today`, `Last Number of Days`. **Date type only — they do not accept
  DateTime**, which is the one that catches people.
- Persistent Email Template references that survive deployment.
- Global Flow Resources for reusable value mappings.
- Collapsible fault paths and the Element Error Rate column.
- `InvocableActionExtension` for configurable Apex actions. See
  `references/invocable-apex-patterns.md`.
