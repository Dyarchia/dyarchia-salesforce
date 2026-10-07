# Building and Serving MCP Tools — Reference (Winter '27 / API v68.0)

Load from `dya-sf-headless360` when exposing org capability to an AI client, or connecting a client to
an org. Configuration is in Setup › **Integration › Salesforce MCP Servers**; the server itself needs
no code.

## Standard servers versus custom servers

**Standard servers** are pre-configured by Salesforce, expose a fixed set of tools from one product
area (SObject operations, Data 360 SQL, Tableau), are **disabled by default**, and are **immutable** —
an admin can enable one but cannot change its contents.

**Custom servers** are admin-configured and the only way to:

- **Combine tools from several standard servers under one URL** — SObject reads plus a Tableau
  analytics tool for a reporting persona, say.
- **Expose tools backed by your own logic**, because standard servers cannot be extended.
- **Scope to a persona** — a sales rep server, a support server, a data-hygiene server, each with a
  different mix.
- **Deploy between sandbox and production via Metadata API.**

Each custom server has its **own URL**, so different teams point at different tool sets without
separate OAuth apps or orgs.

## The five backing types for a custom tool

| Backing type | Requirement | Use it for |
|---|---|---|
| **Flow** | **Autolaunched only** — not screen, not scheduled — with defined input and output variables | Reusing declarative automation: multi-step processes, branching, callouts via Named Credentials |
| **Apex Invocable Action** | A **`global`** method annotated `@InvocableMethod` | Logic beyond Flow: complex calculation, custom integration, performance-sensitive work |
| **`@AuraEnabled` Apex method** | The existing annotation | Methods already serving as Lightning controllers become agent tools with **no new code** |
| **Apex REST** | A `@RestResource` class | Existing custom REST endpoints on the platform |
| **API Catalog endpoint** | Registered in the API Catalog | Standard platform APIs and a growing subset of Connect APIs — coverage is still expanding |

### The tool schema

The method's input and output variables define the tool's parameter schema:

- **Flatten complex or nested types** so an agent can call the tool reliably.
- **Changing the underlying Apex — adding a parameter, changing a type — requires updating the tool
  configuration in Setup.** Otherwise the agent calls with a stale schema.

For a Flow-backed tool, the server generates the schema from the flow's input and output variables,
launches the flow server-side, and returns the outputs.

### Security

Governor limits, sharing rules and field permissions apply exactly as for any execution by the
authenticated user — see `dya-sf-permissions`. Exposing
something as an MCP tool neither widens nor narrows it: if the user can do it, the agent can.

## Connecting a client

Client access goes through an **External Client App** (Setup › External Client App Manager › New
External Client App), with OAuth enabled and a callback URL that depends on the client:

| Client | Callback URL |
|---|---|
| Claude | `https://claude.ai/api/mcp/auth_callback` |
| Cursor | `http://localhost:8787/callback` — older versions used `cursor://anysphere.cursor-mcp/oauth/callback`; register both if you can |
| Postman | `https://oauth.pstmn.io/v1/callback`, or `https://oauth.pstmn.io/v1/browser-callback` in the browser version |
| ChatGPT | Copy it from ChatGPT's Advanced settings |

A failed authorisation is usually a callback-URL mismatch, not a scope problem; check that first.

For production, the app supports requiring client secrets (web-based clients), restricting to
specific users, restricting by IP, shortening the token lifecycle, and single logout. See
`dya-sf-integration-auth` for the wider identity picture.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Trying to edit a standard server | They are immutable — build a custom server |
| Assuming only Flow, Apex Action and Apex REST can back a tool | `@AuraEnabled` methods and API Catalog endpoints also can |
| A screen or scheduled flow as a tool | Autolaunched only, with defined inputs and outputs |
| A non-`global` `@InvocableMethod` | It must be `global` to back an MCP tool |
| Deeply nested parameter types | Flatten the signature so an agent can call it correctly |
| Changing the Apex and expecting the tool to follow | Update the tool configuration in Setup — it does not resync |
| A terse tool description | The description is how the client decides to call it |
| Assuming MCP bypasses the security model | It runs as the authenticated user, limits and sharing intact |
| Click-configuring custom servers per environment | Deploy them via Metadata API |
