# Winter '27 — What the Release Adds to Data 360

The facts that **gate the work** — the SQL-from-Apex GA, the MCP server's Developer Preview status,
and the credit cost of every query — live in `SKILL.md`'s Platform Context.

## Standing facts

- **Data 360 MCP Server (Developer Preview)** — an open-source MCP server fronting roughly 200 REST
  operations behind a few facade tools, so a coding agent can drive Data 360. Not production. See
  `dya-sf-headless360`.
- **Headless DevOps for Data 360** — a pipeline promotes Data 360 logic (data transforms, code
  extensions) like Apex and LWC, through DevOps data kits.
- **Data Custom Code (Python SDK)** — author Python data-processing code locally, validate against a
  sandbox, deploy and monitor; logs surface in a code-extensions DLO. Full toolchain in
  `references/code-extensions.md`.
