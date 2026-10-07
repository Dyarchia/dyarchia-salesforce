# Headless 360 MCP Servers — Reference (Winter '27 / API v68.0)

Detail for SKILL.md §3. Load when choosing, building, or securing an MCP integration with Salesforce.

## The Server Taxonomy

| Server | Status | Audience | What it's for |
|---|---|---|---|
| **Hosted MCP Servers** | GA | Business agents, production ops | Standard, out-of-the-box tools over Platform, Data 360, Tableau, MuleSoft, Slack |
| **Custom Hosted MCP Servers** | GA | Business agents, production ops | Your chosen tools + prompts; granular control |
| **Salesforce DX MCP Server** | Beta | Developers, IDEs | Dev workflows: metadata, tests, SLDS/ApexGuru/LWC/Aura tooling, Lightning Types, Metadata API context |
| **Data 360 MCP Server** | Dev Preview | Coding agents | Drive Data 360; fronts ~200 REST ops with 3 facade tools (`search`, `payload_examples`, …) |
| **Metadata API Context MCP Server** | Beta | Coding agents | 5 granular tools for accurate metadata generation |

## Connecting an External Client (e.g. Claude)

Hosted MCP servers let agentic clients (Claude Desktop, Claude Code, ChatGPT, Cursor) act on records and run logic without logging into Lightning Experience:

1. In the org, enable the **hosted MCP server** you need, or stand up a **custom** one with the exact tools to expose.
2. In the client, register the server URL and authenticate via OAuth — the user's token permissions bound what the tools do.
3. The client **discovers** the available tools (names, descriptions, input schemas), then **calls** them and renders results.

## Design Rules for Custom Tools

- **Give each tool one clear job.** Build narrow, composable tools, not a mega-tool.
- **Write input descriptions as routing logic too**, alongside the tool label and description.
- **An MCP-exposed `@InvocableMethod` is still Apex** — `with sharing`, `WITH USER_MODE`, bulkified (see `dya-sf-apex` / `dya-sf-agentforce`).

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| New code per surface | Reuse `@InvocableMethod`/Flow/Apex REST as the tool |
| Mega-tool doing many things | Narrow, composable tools |
