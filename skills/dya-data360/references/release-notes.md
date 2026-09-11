# Winter '27 — What the Release Adds to Data 360

Consultative. The facts that **gate the work** — the SQL-from-Apex GA, the MCP server's Developer
Preview status, and the credit cost of every query — live in `SKILL.md`'s Platform Context.

**Data 360 ships on its own monthly cadence**, not the platform's three releases a year. The
Winter '27 changes are dated around October 2026, and a feature can appear between platform
releases, so the platform release notes are never the whole story for this product. Check the Data
360 release notes.

| Change | Status | What it gives you |
|---|---|---|
| Execute Data 360 SQL from Apex | GA | Run a Data 360 SQL query directly from Apex, so custom logic and Data 360 data live in one class instead of an integration between them. See `dya-apex` |

## Standing facts

- **Data 360 MCP Server (Developer Preview)** — an open-source MCP server fronting roughly 200 REST
  operations behind a few facade tools, so a coding agent can drive Data 360. Not production. See
  `dya-headless360`.
- **Headless DevOps for Data 360** — a pipeline can promote Data 360 logic (data transforms, code
  extensions) the way it promotes Apex and LWC, through DevOps data kits.
- **Data Custom Code (Python SDK)** — author Python data-processing code locally, validate against a
  sandbox, deploy and monitor; logs surface in a code-extensions DLO. Full toolchain in
  `references/code-extensions.md`.
