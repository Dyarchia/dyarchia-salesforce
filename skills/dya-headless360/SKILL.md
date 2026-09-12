---
name: dya-headless360
description: Salesforce Headless 360 (Winter '27 / API v68.0) — from zero to expert. The platform theme that turns every Salesforce capability into an API, MCP tool, or CLI command for apps, humans, and AI agents. Covers the three surfaces (API/MCP/CLI), the MCP server taxonomy (hosted, DX, custom, Data 360), building custom MCP tools, the Headless/Agentforce Experience Layer (HXL/AXL) and Lightning Types, Agentforce Vibes and React apps, headless DevOps, and the Trust Layer. Load only when the user explicitly invokes this skill by name (`dya-headless360`); do NOT auto-trigger on generic headless, MCP, API, or Salesforce questions.
---

# Salesforce Headless 360 — From Zero to Expert

The reader may be **new to Headless 360**, so this skill builds the mental model first, then the
implementation, then what this release changes. You **always** expose the smallest approved set of
tools, **always** rely on the Trust Layer rather than bypassing it, and **always** define an
experience once and render it everywhere. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts behind the surfaces below.
- `references/shared/metadata-and-api-versions.md` — API version semantics for anything addressing the platform by version.
- `references/shared/org-model.md` — orgs, DX projects and deployment, which the CLI and DevOps surfaces assume.
- `references/agentic-dev-tooling.md` — **Agentforce Vibes v4.0+**: Plan Mode and its approval gate, Rules and their context cost, permission modes and safety guardrails, MCP inside the IDE, model tiers.
- `references/react-and-data-sdk.md` — **Salesforce Multi-Framework**: the React-versus-LWC decision, the framework decision, the constraints that decide feasibility (Hyperforce only, Dev Hub packaging toggle), `UIBundle` project structure and 2GP distribution, and the Data SDK with its LWC translation table.
- `references/building-mcp-tools.md` — **standard versus custom servers, the five backing types for a custom tool, and connecting a client** with its callback URL. Start here to expose org capability to an AI client.
- `references/lightning-types.md` — the `LightningTypeBundle` structure, channel folders, and the Apex requirements that fail at invocation rather than at deploy.
- `references/mcp-servers.md` — the MCP server taxonomy (hosted vs DX vs custom vs Data 360), building custom MCP tools from Apex Actions / Flows / Apex REST, connecting external clients (Claude), and token-scoped security.
- `references/experience-layer.md` — the Headless/Agentforce Experience Layer (HXL/AXL), Lightning Types, "define once, render everywhere", native React, and when to use which surface.

Load a reference when building that exact thing. Headless 360 is the **access and distribution layer**
over the whole platform, Agentforce (`dya-agentforce`) and Data 360 (`dya-data360`) included.

---

## Platform Context — Winter '27 / API v68.0

Headless 360 turns every Salesforce capability into an API, MCP tool or CLI command, usable by an
app, a human or an autonomous agent. Three things decide whether a project can use it at all:

- **Maturity is uneven and mostly not GA.** The Apex Symbol API, the Salesforce DX MCP Server and
  the Metadata API Context MCP Server are **Beta**; the Data 360 MCP Server is **Developer Preview**.
  Hosted MCP servers and the Claude Code plugin are GA. Beta and Developer Preview do not run in
  production orgs, so check the label before designing around a tool.
- **Agentforce Vibes carries no maturity label at all**, and features inside it are individually
  Beta. It is **not available in EU Operating Zone**, nor in Group, Professional or Essentials
  editions — an availability wall, not a licensing upsell.
- **Security carries through every surface unchanged.** The Einstein Trust Layer and the org's
  permission model apply identically whether a capability is reached as an API, an MCP tool or a CLI
  command. A capability exposed as an MCP tool runs as the authenticated user.

> What the release adds feature by feature, the addressable-surface numbers, and the Vibes naming
> lineage that makes older documentation hard to find: `references/release-notes.md`.

---

## 1. Foundations — What Headless 360 Is

"Headless" means removing the head: the UI. A headless system exposes its functionality through
**programmatic access** instead of screens, and Headless 360 does that for the **entire** platform —
records, business logic, automations, metadata, DevOps, Agentforce and Data 360, all reachable
without a browser.

There are **three surfaces**, all enforcing the same trust layer:

```
            ┌───────────────────────────────────────────────┐
            │              Headless 360                       │
            │   API  ·  MCP tools  ·  CLI commands            │
            ├───────────────────────────────────────────────┤
   reach →  │  Salesforce Platform · Agentforce · Data 360 ·  │
            │  Tableau · MuleSoft · Slack                     │
            ├───────────────────────────────────────────────┤
  render →  │  Headless Experience Layer (Slack/Teams/Voice/  │
            │  mobile/web/ChatGPT/Claude/Gemini)              │
            └───────────────────────────────────────────────┘
```

Two lanes converge:
- **Build-time** — coding agents and developers build *against* your org: DX MCP tools, coding
  skills, CLI, Agentforce Vibes.
- **Runtime** — business agents and apps *serve from* your org, output rendered natively per channel
  by the Experience Layer.

**What is actually new:** headless has existed for years through REST APIs, the Mobile SDK and React
on Experience Cloud. What changed is that **AI models now discover, call and compose capabilities at
runtime**, with no per-integration glue written in advance, because every capability is described as
an agent-accessible tool.

**Where the others fit:** Agentforce reasons, Data 360 is the data mesh underneath, and Headless 360
exposes and renders both. Agentforce *provides* capabilities; Headless 360 *distributes* them.

---

## 2. Surface 1 — APIs

The 4,000+ existing REST/Connect/Platform APIs are the foundation. Headless 360 adds **intent**:
every endpoint is documented as an **agent-accessible surface**, with guidance on **token-scoped
access** and **Named Credentials**.

- REST and Connect remain the workhorse for programmatic data and logic access.
- The **Agent API** (REST) invokes agent sessions headlessly from an external system — see
  `dya-agentforce` §7.
- The **Data 360 APIs** (Query, Profile, Connect) expose the data mesh — see `dya-data360` §5.
- **Named Query API** (GA) exposes custom SOQL as scalable, agent-callable actions.

APIs are the lowest-level surface: maximal control, but you write the integration. Reach for MCP when
an *agent* must discover and call capabilities dynamically.

---

## 3. Surface 2 — MCP (the Headline)

The **Model Context Protocol** is the open standard that lets AI clients **discover** approved tools,
understand their inputs, **call** them and receive results, instead of guessing how to use your org.
There are four server categories, and conflating them is the common error:

| Server | Audience | Purpose |
|---|---|---|
| **Hosted MCP Servers** (GA) | Business agents / production | Standard, out-of-the-box access to Platform, Data 360, Tableau, MuleSoft, Slack |
| **Custom Hosted MCP Servers** | Business agents / production | Granular control: expose *your* chosen tools and prompts |
| **Salesforce DX MCP Server** (Beta) | Developers / IDEs | Dev workflows: metadata, tests, SLDS/ApexGuru/LWC tooling, Lightning Types |
| **Data 360 MCP Server** (Dev Preview) | Coding agents | Drive Data 360 via three facade tools (`search`, `payload_examples`, …) |

**The DX MCP server is not a production business-user server.** It serves development workflows and
authenticates through the Salesforce CLI.

### Building custom MCP tools

A custom hosted MCP server exposes tools built from existing platform artefacts, with no new runtime:

- **Flow** — an **autolaunched** flow with defined inputs and outputs. Not screen, not scheduled.
- **Apex Invocable Action** — a **`global`** method annotated `@InvocableMethod`.
- **`@AuraEnabled` Apex method** — the one people miss: methods already serving as Lightning
  controllers become agent tools with **no new code**.
- **Apex REST** — a `@RestResource` class.
- **API Catalog endpoint** — registered platform and Connect APIs; coverage is still expanding.

The method's inputs and outputs **are** the tool's parameter schema, so nested types make a tool hard
to call correctly — and changing the Apex does **not** resync the tool configuration in Setup.

This is the bridge: the same `@InvocableMethod` written as an **Agentforce action** is also an **MCP
tool** for an external coding or business agent. Build the capability once, expose it through
whichever surface the caller uses.

### Golden rule of MCP exposure

**Expose the smallest set of approved tools, never unrestricted access.** Past a few dozen tools an
AI client starts choosing badly, so curation is the design rather than housekeeping: every tool on
the platform is a buffet, and a server is the plate curated for one persona. A tool's description is
how the model decides to call it — write descriptions like the routing logic they are, with the same
discipline as Agentforce action descriptions.

> Standard versus custom servers, the backing-type requirements, and the External Client App
> callback URL per client: `references/building-mcp-tools.md`. Wider taxonomy and security:
> `references/mcp-servers.md`.
> Vibes itself — Plan Mode, Rules, permission modes: `references/agentic-dev-tooling.md`.

---

## 4. Surface 3 — CLI

The Salesforce CLI's **220+ commands** are a first-class surface for automation and DevOps. The
current emphasis is Agentforce DX and credential security:

```bash
sf agent generate template      # scaffold a runnable sample agent
sf agent generate agent-user    # provision a service agent user in one command
sf agent preview start|send|sessions|end   # scriptable interactive test sessions (GA)
```

Use the CLI for headless DevOps: deploy and retrieve metadata, run tests, and promote **Data 360**
logic exactly as you promote Apex and LWC, through DevOps data kits. Anything clickable is
increasingly scriptable.

---

## 5. The Experience Layer (HXL / AXL)

The **Headless Experience Layer** — its agent-facing form is the **Agentforce Experience Layer,
AXL** — **decouples a capability's definition from its rendering surface**. Define a UI fragment or
interaction **once**; HXL renders it natively as a Slack block, a Teams card, a mobile card, a voice
interaction or a response inside ChatGPT, Claude or Gemini, with no per-channel rebuild.

- Business logic, data and permissions stay **separate** from the screen: define intent once, render
  natively everywhere.
- It is built on **Lightning Types**, JSON-based types that structure, validate and display data.
  Standard types ship with an editor and renderer; custom ones are `LightningTypeBundle` metadata
  (API 64.0+) with optional per-channel UI overrides. See `references/lightning-types.md`.
- **Native React** support lets developers who want full control build custom interfaces in any
  design language over the same capabilities.
- The build-time surface is mature; the runtime surface already handles straightforward cases — a
  support agent returning a case summary in a Slack thread — and is expanding.

Use HXL and Lightning Types when the **same capability must appear across multiple channels**. Use
plain LWC or Aura (`dya-lwc`, `dya-aura`) when the target is only Lightning Experience. Full detail:
`references/experience-layer.md`.

---

## 6. Dev Tooling — Agentforce Vibes, DX MCP, Skills & Rules

- **Agentforce Vibes (v4.0+)** — an agentic development environment, as a VS Code extension and as a
  cloud IDE. A lead agent delegates to specialised sub-agents running in parallel, **each in its own
  Git worktree**, so concurrent work does not collide. **Plan Mode changes no files until you approve
  the plan.** **Rules** are always-on standards in `.vibes/rules/` — commit them — while **Skills**
  activate on demand. Permission modes run from *Ask every time* through *Run safe defaults* to
  *Bypass*, and the safety guardrails apply **only** in the middle one.
- **Salesforce DX MCP Server** (Beta) — preconfigured in the Vibes extension. Toolsets include
  `lwc-experts`, `aura-experts` (Aura→LWC migration), SLDS guidance, ApexGuru code review, Lightning
  Types (`create_lightning_type`) and Metadata API context. Some require enabling global rules such
  as `a4d-general-rules` and `a4d-lwc-rules`.
- **Coding skills** (30+) — preconfigured capability bundles giving coding agents live,
  best-practice-aware access to your platform.
- **React and Angular apps on Salesforce Multi-Framework** — the framework-agnostic runtime, and what
  "native React" in §5 means concretely. The app is a DX project carrying the **`UIBundle`** metadata
  type under `uiBundles/`, scaffolded with `sf template generate project` (or
  `sf template generate ui-bundle` inside an existing project), with data access through the GraphQL
  **Data SDK**. Check
  feasibility before designing: **Hyperforce only**, and the Dev Hub packaging toggle before any 2GP
  work. Distribution is solved — managed or unlocked 2GP, namespace supported — but platform security
  is **not** inherited the way LWC inherits it.

These accelerate *building on* Salesforce. They are distinct from the hosted servers that let
business agents *operate* your org.

---

## 7. Security & Trust

Headless 360 changes the surface, **not** the security model:

- **Your existing model carries through.** Sharing rules, FLS and permission sets are enforced
  automatically however the data is reached — API, MCP or CLI.
- **The Einstein Trust Layer** applies on every agent path: masking, dynamic grounding, FLS,
  zero-data-retention with LLM providers.
- **Token-scoped, least-privilege access.** Authenticate with OAuth — External Client Apps, or JWT
  for server-to-server — scope tokens to the minimum, and use **Named Credentials** for outbound.
  The **Any API Auth** permission governs who may use legacy SOAP `login()`, retiring Summer '27;
  migrate to OAuth and External Client Apps.
- **Curate the toolset.** A broad toolset is both a security and a reliability liability.

---

## 8. Decision Matrix — Which Surface?

| Need | Surface |
|---|---|
| Full control, you write the integration | **API** (REST/Connect) |
| Let an AI client discover & call capabilities dynamically | **MCP** (hosted or custom) |
| Connect Claude/ChatGPT/Cursor to your org | **Hosted MCP Server** |
| Expose *your* logic to an external agent | **Custom hosted MCP** (Apex Action / Flow / Apex REST tool) |
| In-IDE coding assistance over your metadata | **DX MCP Server** + Agentforce Vibes |
| A full-page React UI running on the platform | Salesforce Multi-Framework: a `UIBundle` DX project + the Data SDK |
| A reusable component inside Lightning Experience | LWC — React there needs Micro-Frontend (Developer Preview) |
| Drive Data 360 from a coding agent | **Data 360 MCP Server** |
| Automate deploys/tests/agent setup | **CLI** (`sf …`, `sf agent …`) |
| Promote Data 360 logic through CI/CD | **CLI** + DevOps data kits |
| Run an agent server-side, no UI | **Agent API** (`dya-agentforce`) |
| Same interaction across Slack/Teams/voice/web | **Experience Layer** + Lightning Types |
| Custom UI in React over platform capabilities | **HXL native React** |
| UI only for Lightning Experience | LWC / Aura (not HXL) |

---

## 9. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Exposing broad/unrestricted MCP access | Curate the smallest approved, well-described toolset |
| Vague MCP tool descriptions | Intent-rich descriptions — the model routes on them |
| Using the DX MCP server for production business users | DX MCP is for dev workflows; use hosted servers for ops |
| Bypassing the Trust Layer / sharing model | Rely on it — it enforces on every surface |
| Broad OAuth scopes / stored secrets in clients | Least-privilege tokens, External Client Apps, Named Credentials |
| SOAP `login()` for new integrations | OAuth / JWT via External Client Apps (SOAP login retiring) |
| Rebuilding the same UI per channel | Define once via Lightning Types; HXL renders everywhere |
| HXL for a Lightning-only screen | Plain LWC/Aura |
| Rewriting an action as a separate MCP tool | Reuse the `@InvocableMethod` as both an agent action and an MCP tool |
| Clicking deploys for Data 360 logic | CLI + DevOps data kits (headless, repeatable) |

---

## Summary — The Five Commandments

1. **Three surfaces, one platform** — API for control, MCP for agent-discoverable capabilities, CLI for automation/DevOps; all enforce the same trust layer.
2. **Headless 360 distributes; Agentforce reasons; Data 360 feeds** — it's the access/render layer over both, not a replacement for either.
3. **Build the capability once, expose it everywhere** — the same `@InvocableMethod` is an Agentforce action *and* an MCP tool; the same Lightning Type renders across every channel.
4. **Curate and describe tools like code** — least-privilege, well-described MCP toolsets; descriptions are how models route.
5. **Security carries through** — sharing, FLS, Trust Layer, token-scoped OAuth and Named Credentials apply on API, MCP, and CLI alike.
