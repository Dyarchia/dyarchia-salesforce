# Headless 360 MCP Servers — Reference (Summer '26)

Full detail referenced from SKILL.md §3, §6, §7. Load this when choosing, building, or securing an MCP integration with Salesforce.

## The Server Taxonomy — Don't Conflate These

| Server | Status | Audience | What it's for |
|---|---|---|---|
| **Hosted MCP Servers** | GA | Business agents, production ops | Standard, out-of-the-box tools over Platform, Data 360, Tableau, MuleSoft, Slack |
| **Custom Hosted MCP Servers** | GA | Business agents, production ops | Your chosen tools + prompts; granular control |
| **Salesforce DX MCP Server** | Beta | Developers, IDEs | Dev workflows: metadata, tests, SLDS/ApexGuru/LWC/Aura tooling, Lightning Types, Metadata API context |
| **Data 360 MCP Server** | Dev Preview | Coding agents | Drive Data 360; fronts ~200 REST ops with 3 facade tools (`search`, `payload_examples`, …) |
| **Metadata API Context MCP Server** | Beta | Coding agents | 5 granular tools for accurate metadata generation |

Key distinction: **hosted = run the business; DX = build the business.** Authenticate the DX server via the Salesforce CLI; it is not a production business-user surface.

## Connecting an External Client (e.g. Claude)

Hosted MCP servers let agentic clients (Claude Desktop, Claude Code, ChatGPT, Cursor) act on records and run logic without logging into Lightning Experience. Flow:

1. In the org, enable/confirm the **hosted MCP server** you need (or stand up a **custom** one with the exact tools you want exposed).
2. In the client, register the server URL and authenticate via OAuth — the user/token's permissions bound what the tools can do.
3. The client **discovers** the available tools (names + descriptions + input schemas), then **calls** them and renders results.

Example use case: a hotel-management agent loads upcoming reservations, analyses nearby events, and drafts personalised campaigns — all from the chat client, via MCP tools, never opening the UI.

## Building Custom MCP Tools

A custom hosted MCP server exposes tools built from existing platform artefacts — reuse, don't rebuild:

| Tool source | Built from | Reuse story |
|---|---|---|
| **Apex Action** | `@InvocableMethod` Apex method | The *same* method can be an Agentforce action AND an MCP tool |
| **Lightning Flow** | Autolaunched flow | Declarative logic exposed to external agents |
| **Apex REST** | Custom Apex REST endpoint | Existing REST surface becomes an agent tool |

Design rules:
- **One tool, one clear job.** Narrow, composable tools beat a mega-tool.
- **Descriptions are routing logic.** Write the tool label/description (and input descriptions) as carefully as Agentforce action descriptions — the model decides whether to call a tool from its description.
- **Least privilege.** Expose only the tools a given client needs. Curate per use case rather than dumping the whole org.
- **Bulk/efficient implementations.** An MCP-exposed `@InvocableMethod` is still Apex — `with sharing`, `WITH USER_MODE`, bulkified (see `decimatio-apex` / `decimatio-agentforce`).

## Security

- **Sharing/FLS/permissions carry through** — the calling token's user context governs every tool call.
- **Token-scoped OAuth.** Use External Client Apps with JWT for server-to-server; scope to the minimum. The **Any API Auth** permission governs legacy SOAP `login()` (retiring Summer '27 — migrate to OAuth).
- **Curate the toolset** — a broad, unrestricted toolset is both a security risk and a reliability problem (models mis-call from large, vague tool lists).
- **The Einstein Trust Layer** still applies for agent paths: masking, grounding, zero-retention.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| One MCP server exposing everything | Curated, least-privilege toolset per use case |
| DX MCP server for production business users | Hosted (or custom hosted) server for ops |
| Vague tool descriptions | Intent-rich descriptions; the model routes on them |
| New code per surface | Reuse `@InvocableMethod`/Flow/Apex REST as the tool |
| Broad OAuth scope, secrets in client | Least-privilege token, External Client Apps, Named Credentials |
| Mega-tool doing many things | Narrow, composable tools |
| Assuming MCP bypasses security | It enforces the caller's sharing/FLS + Trust Layer |
