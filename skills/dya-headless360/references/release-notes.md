# Winter '27 — What the Release Adds to Headless 360

Consultative. The facts that **gate what you can build or ship** live in `SKILL.md`'s Platform
Context — maturity labels, edition and region availability, and the security carry-through. This
file is the rest of the surface.

| Change | Status | What it gives you |
|---|---|---|
| Salesforce plugin for Claude Code | GA | Detects a DX project and supplies org context through hosted MCP servers; installed from the Claude Plugin Marketplace. The clearest example of the whole theme — a coding agent with live org grounding. See `dya-sf-cli` |
| DevOps Center MCP | GA | The same programmatic access inside a CI/CD pipeline: describe a deployment and let an agent execute it |
| MCP interoperability for agents | GA | The direction reversed — an Agentforce agent calling *out* to external MCP servers. See `dya-integration-connectors-mcp` |
| Apex Symbol API | **Beta** | Compiler-grade Apex type metadata over the Tooling API, so an IDE or AI tool can reason about Apex accurately instead of guessing from text |

## Scale of the addressable surface

**60+ MCP tools, 30+ preconfigured coding skills, 4,000+ APIs and 220+ CLI commands** are reachable
by an authorised caller. The numbers move every release; treat them as an order of magnitude rather
than a specification.

## Hosted MCP servers

GA. Connect any MCP client to the org and the Headless 360 portfolio: Salesforce Platform, Data 360,
Tableau, MuleSoft, Slack.

## Agentforce Vibes lineage

At v4.0+, a ground-up rebuild on Salesforce's Coding Agent Platform, orchestrated by Claude and
Mastra and exposing an Agent SDK. It installs from the VS Code Marketplace and Open VSX, and also
runs as a cloud-hosted IDE.

Material describing a "2.0" is a previous generation. The lineage **Einstein for Developers →
Agentforce for Developers → Agentforce Vibes** survives in documentation URLs and in the extension
id `salesforcedx-einstein-gpt`, which is why searching for the current name misses older answers.

Its availability constraints are in `SKILL.md` because they decide whether a project can use it at
all.

## The Experience Layer

**HXL / AXL** — define an interaction once and render it natively across Slack, Teams, Voice, mobile
and third-party assistants, built on Lightning Types with native React support. Covered properly in
§5.
