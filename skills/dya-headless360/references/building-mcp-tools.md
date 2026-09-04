# Building and Serving MCP Tools — Reference (Winter '27 / API v68.0)

Load from `dya-headless360` when exposing org capability to an AI client, or connecting a client to
an org. Configuration happens in Setup › **Integration › Salesforce MCP Servers**; no code is needed
for the server itself.

## Standard servers versus custom servers

**Standard servers** are pre-configured by Salesforce, expose a fixed set of tools from one product
area (SObject operations, Data 360 SQL, Tableau), are **disabled by default**, and are **immutable** —
an admin can enable one but cannot change its contents.

**Custom servers** are admin-configured and are the only way to:

- **Combine tools from several standard servers under one URL** — SObject reads plus a Tableau
  analytics tool for a reporting persona, say.
- **Expose tools backed by your own logic**, because standard servers cannot be extended.
- **Scope to a persona** — a sales rep server, a support server, a data-hygiene server, each with a
  different mix.
- **Deploy between sandbox and production via Metadata API.**

Each custom server has its **own URL**, so different teams point at different tool sets without
needing separate OAuth apps or separate orgs.

## Why curation is the design, not housekeeping

MCP clients have practical limits on how many tools they can handle. **Past a few dozen tools an AI
client starts choosing badly.** The documentation's own analogy is worth keeping: every MCP tool
across the platform is a **buffet**; a server is the **plate** curated for one persona. You cannot
serve every dish on one plate — it does not fit, and it would not be useful.

This is the same shape as Lightning page composition: contributors add capability without knowing who
will use it, and admins assemble a focused experience from what exists.

## The five backing types for a custom tool

The skill body lists three of these; there are five.

| Backing type | Requirement | Use it for |
|---|---|---|
| **Flow** | **Autolaunched only** — not screen, not scheduled — with defined input and output variables | Reusing declarative automation: multi-step processes, branching, callouts via Named Credentials |
| **Apex Invocable Action** | A **`global`** method annotated `@InvocableMethod` | Logic beyond Flow: complex calculation, custom integration, performance-sensitive work |
| **`@AuraEnabled` Apex method** | The existing annotation | Methods already serving as Lightning controllers become agent tools with **no new code** |
| **Apex REST** | A `@RestResource` class | Existing custom REST endpoints on the platform |
| **API Catalog endpoint** | Registered in the API Catalog | Standard platform APIs and a growing subset of Connect APIs — coverage is still expanding |

The `@AuraEnabled` route is the one people miss: if the org already has Lightning controllers, a good
part of its capability is already agent-addressable without writing anything.

### What the tool schema is made of

**The method's input and output variables define the tool's parameter schema.** Two consequences:

- **Complex or nested types make a tool hard for an agent to call correctly.** Flatten the signature
  if you want it used reliably.
- **Changing the underlying Apex — adding a parameter, changing a type — requires updating the tool
  configuration in Setup.** It does not resync itself, and the failure is an agent calling with a
  stale schema.

For a Flow-backed tool, the server generates the schema from the flow's input and output variables,
launches the flow server-side, and returns the outputs.

### Security is not special-cased

Tools **run as the authenticated user**. Governor limits, sharing rules and field permissions apply
exactly as they would for any execution by that user — see `dya-permissions` and
`references/shared/governor-limits.md`. Exposing something as an MCP tool does not widen it, and does
not narrow it either: if the user can do it, the agent can.

## Tool descriptions are the routing logic

The name and description you give a tool matter as much as the implementation, because that text is
what an AI client reads to decide whether to call it. This is the same discipline as an Agentforce
action description — see `dya-agentforce`.

## Connecting a client

Client access goes through an **External Client App** (Setup › External Client App Manager › New
External Client App), with OAuth enabled and a callback URL that depends on the client:

| Client | Callback URL |
|---|---|
| Claude | `https://claude.ai/api/mcp/auth_callback` |
| Cursor | `http://localhost:8787/callback` — older versions used `cursor://anysphere.cursor-mcp/oauth/callback`; register both if you can |
| Postman | `https://oauth.pstmn.io/v1/callback`, or `https://oauth.pstmn.io/v1/browser-callback` in the browser version |
| ChatGPT | Copy it from ChatGPT's Advanced settings |

A failed authorisation is usually a callback-URL mismatch rather than a scope problem — check that
first.

For production, the app supports requiring client secrets (web-based clients), restricting to
specific users, restricting by IP, shortening the token lifecycle, and single logout. See
`dya-integration-auth` for the wider identity picture.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Exposing everything on one server | Curate per persona; past a few dozen tools the client chooses badly |
| Trying to edit a standard server | They are immutable — build a custom server |
| Assuming only Flow, Apex Action and Apex REST can back a tool | `@AuraEnabled` methods and API Catalog endpoints also can |
| A screen or scheduled flow as a tool | Autolaunched only, with defined inputs and outputs |
| A non-`global` `@InvocableMethod` | It must be `global` to back an MCP tool |
| Deeply nested parameter types | Flatten the signature so an agent can call it correctly |
| Changing the Apex and expecting the tool to follow | Update the tool configuration in Setup — it does not resync |
| A terse tool description | The description is how the client decides to call it |
| Assuming MCP bypasses the security model | It runs as the authenticated user, limits and sharing intact |
| Click-configuring custom servers per environment | Deploy them via Metadata API |
