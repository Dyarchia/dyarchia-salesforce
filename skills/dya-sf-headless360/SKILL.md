---
name: dya-sf-headless360
description: Salesforce Headless 360 (Winter '27, API v68.0) — every capability as API, MCP tool or CLI command; MCP servers, custom MCP tools, the Experience Layer and Lightning Types, Agentforce Vibes and React apps, headless DevOps. Applies to custom MCP tools and servers, Lightning Types, Agentforce Vibes or React apps on the platform, headless DevOps pipelines. Load before creating or editing anything in this scope.
---

# Salesforce Headless 360

Headless 360 is the **access and distribution layer** over the whole platform, Agentforce
(`dya-sf-agentforce`) and Data 360 (`dya-sf-data360`) included. You **always** expose the smallest
approved set of tools, **always** rely on the Trust Layer rather than bypassing it, and **always**
define an experience once and render it everywhere. Follow every rule below.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts behind the surfaces below.
- `references/shared/metadata-and-api-versions.md` — API version semantics for anything addressing the platform by version.
- `references/shared/org-model.md` — orgs, DX projects and deployment, which the CLI and DevOps surfaces assume.
- `references/agentic-dev-tooling.md` — **Agentforce Vibes v4.0+**: Plan Mode and its approval gate, Rules and their context cost, permission modes and safety guardrails, MCP inside the IDE, model tiers.
- `references/react-and-data-sdk.md` — **Salesforce Multi-Framework**: the React-versus-LWC decision, the framework decision, the feasibility constraints (Hyperforce only, Dev Hub packaging toggle), `UIBundle` project structure and 2GP distribution, and the Data SDK with its LWC translation table.
- `references/building-mcp-tools.md` — **standard versus custom servers, the five backing types for a custom tool, and connecting a client** with its callback URL. Start here to expose org capability to an AI client.
- `references/lightning-types.md` — the `LightningTypeBundle` structure, channel folders, and the Apex requirements that fail at invocation rather than at deploy.
- `references/mcp-servers.md` — the MCP server taxonomy with maturity status (hosted vs DX vs custom vs Data 360 vs Metadata API Context), connecting external clients (Claude), and design rules for custom tools.
- `references/experience-layer.md` — the Headless/Agentforce Experience Layer (HXL/AXL), Lightning Types, "define once, render everywhere", native React, and when to use which surface.

Load a reference when building that exact thing.

---

## Platform Context — Winter '27 / API v68.0

Three things decide whether a project can use Headless 360:

- **Maturity is uneven and mostly not GA.** The Apex Symbol API, the Salesforce DX MCP Server and
  the Metadata API Context MCP Server are **Beta**; the Data 360 MCP Server is **Developer Preview**.
  Hosted MCP servers and the Claude Code plugin are GA. Beta and Developer Preview do not run in
  production orgs. Check the label before designing around a tool.
- **Agentforce Vibes carries no maturity label**, and its features are individually Beta. It is
  **not available in EU Operating Zone**, nor in Group, Professional or Essentials editions — an
  availability wall, not a licensing upsell.
- **Security carries through every surface unchanged** (§7). An MCP tool runs as the authenticated
  user.

> Per-feature release additions, the addressable-surface numbers, and the Vibes naming lineage that
> hides older documentation: `references/release-notes.md`.

## Summary — The Five Commandments

1. **Pick the surface by need** — API for control, MCP for agent-discoverable capabilities, CLI for automation/DevOps; all three are one platform and enforce the same trust layer.
2. **Use Headless 360 to distribute, Agentforce to reason, Data 360 to feed** — Headless 360 is the access/render layer over both, not a replacement for either.
3. **Build the capability once, expose it everywhere** — the same `@InvocableMethod` is an Agentforce action *and* an MCP tool; the same Lightning Type renders across every channel.
4. **Curate and describe tools like code** — least-privilege, well-described MCP toolsets; descriptions are how models route.
5. **Rely on the security model on every surface** — sharing, FLS, Trust Layer, token-scoped OAuth and Named Credentials apply on API, MCP, and CLI alike.

---

## 1. Foundations — What Headless 360 Is

A headless system exposes its functionality through **programmatic access** instead of screens.
Headless 360 does that for the **entire** platform — records, business logic, automations, metadata,
DevOps, Agentforce and Data 360.

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

**What is new:** **AI models discover, call and compose capabilities at runtime**, with no
per-integration glue, because every capability is described as an agent-accessible tool. Headless
access itself predates this, through REST APIs, the Mobile SDK and React on Experience Cloud.

**Where the others fit:** Agentforce reasons and *provides* capabilities, Data 360 is the data mesh
underneath, and Headless 360 exposes and renders both.

---

## 2. Surface 1 — APIs

The 4,000+ existing REST/Connect/Platform APIs are the foundation. Headless 360 documents every
endpoint as an **agent-accessible surface**, with guidance on **token-scoped access** and **Named
Credentials**.

- REST and Connect remain the workhorse for programmatic data and logic access.
- The **Agent API** (REST) invokes agent sessions headlessly from an external system — see
  `dya-sf-agentforce` §7.
- The **Data 360 APIs** (Query, Profile, Connect) expose the data mesh — see `dya-sf-data360` §5.
- **Named Query API** (GA) exposes custom SOQL as scalable, agent-callable actions.

APIs are the lowest-level surface: maximal control, but you write the integration.

---

## 3. Surface 2 — MCP

The **Model Context Protocol** is the open standard that lets AI clients **discover** approved tools,
understand their inputs, **call** them and receive results. Do not conflate the four server
categories:

| Server | Audience | Purpose |
|---|---|---|
| **Hosted MCP Servers** (GA) | Business agents / production | Standard, out-of-the-box access to Platform, Data 360, Tableau, MuleSoft, Slack |
| **Custom Hosted MCP Servers** | Business agents / production | Granular control: expose *your* chosen tools and prompts |
| **Salesforce DX MCP Server** (Beta) | Developers / IDEs | Dev workflows: metadata, tests, SLDS/ApexGuru/LWC tooling, Lightning Types |
| **Data 360 MCP Server** (Dev Preview) | Coding agents | Drive Data 360 via three facade tools (`search`, `payload_examples`, …) |

**The DX MCP server is not for production business users**; it authenticates through the Salesforce
CLI.

### Building custom MCP tools

A custom hosted MCP server builds tools from existing platform artefacts, with no new runtime:

- **Flow** — an **autolaunched** flow with defined inputs and outputs. Not screen, not scheduled.
- **Apex Invocable Action** — a **`global`** method annotated `@InvocableMethod`.
- **`@AuraEnabled` Apex method** — existing Lightning controller methods become agent tools with
  **no new code**.
- **Apex REST** — a `@RestResource` class.
- **API Catalog endpoint** — registered platform and Connect APIs; coverage is still expanding.

Flatten nested types: the method's inputs and outputs **are** the tool's parameter schema, and nested
types make a tool hard to call. After every change to the Apex, update the tool configuration in
Setup; it does **not** resync.

Build the capability once: an `@InvocableMethod` written as an **Agentforce action** is also an
**MCP tool** for an external coding or business agent.

### Golden rule of MCP exposure

**Expose the smallest set of approved tools, never unrestricted access.** Curate each server for one
persona; past a few dozen tools an AI client starts choosing badly. Write descriptions as routing
logic, with the same discipline as Agentforce action descriptions; the model picks a tool from its
description.

> Standard versus custom servers, the backing-type requirements, and the External Client App
> callback URL per client: `references/building-mcp-tools.md`. Wider taxonomy and design rules:
> `references/mcp-servers.md`.
> Vibes itself — Plan Mode, Rules, permission modes: `references/agentic-dev-tooling.md`.

---

## 4. Surface 3 — CLI

The Salesforce CLI's **220+ commands** are a first-class surface for automation and DevOps. The
current emphasis is Agentforce DX and credential security:

```bash
sf agent generate template      # scaffold a runnable sample agent
sf org create agent-user        # provision a service agent user in one command
sf agent preview start|send|sessions|end   # scriptable interactive test sessions (GA)
```

Use the CLI for headless DevOps: deploy and retrieve metadata, run tests, and promote **Data 360**
logic like Apex and LWC, through DevOps data kits.

---

## 5. The Experience Layer (HXL / AXL)

The **Headless Experience Layer** — agent-facing form: the **Agentforce Experience Layer, AXL** —
**decouples a capability's definition from its rendering surface**. Define a UI fragment or
interaction **once**; HXL renders it natively as a Slack block, a Teams card, a mobile card, a voice
interaction or a response inside ChatGPT, Claude or Gemini, with no per-channel rebuild.

- Business logic, data and permissions stay **separate** from the screen.
- It is built on **Lightning Types**, JSON-based types that structure, validate and display data.
  Standard types ship with an editor and renderer; custom ones are `LightningTypeBundle` metadata
  (API 64.0+) with optional per-channel UI overrides. See `references/lightning-types.md`.
- **Native React** support lets developers build custom interfaces in any design language over the
  same capabilities.
- The build-time surface is mature; the runtime surface handles straightforward cases — a support
  agent returning a case summary in a Slack thread — and is expanding.

When the target is only Lightning Experience, use plain LWC or Aura (`dya-sf-lwc`, `dya-sf-aura`).
Full detail: `references/experience-layer.md`.

---

## 6. Dev Tooling — Agentforce Vibes, DX MCP, Skills & Rules

- **Agentforce Vibes (v4.0+)** — an agentic development environment, as a VS Code extension and a
  cloud IDE. A lead agent delegates to specialised sub-agents running in parallel, **each in its own
  Git worktree**, so concurrent work does not collide. **Plan Mode changes no files until you approve
  the plan.** **Rules** are always-on standards in `.vibes/rules/` — commit them — while **Skills**
  activate on demand. Permission modes run from *Ask every time* through *Run safe defaults* to
  *Bypass*; the safety guardrails apply **only** in the middle one.
- **Salesforce DX MCP Server** (Beta) — preconfigured in the Vibes extension. Toolsets include
  `lwc-experts`, `aura-experts` (Aura→LWC migration), SLDS guidance, ApexGuru code review, Lightning
  Types (`create_lightning_type`, Developer Preview) and Metadata API context. Some require enabling global rules such
  as `a4d-general-rules` and `a4d-lwc-rules`.
- **Coding skills** (30+) — preconfigured capability bundles giving coding agents live,
  best-practice-aware access to your platform.
- **React and Angular apps on Salesforce Multi-Framework** — the framework-agnostic runtime behind
  §5's native React. The app is a DX project carrying the **`UIBundle`** metadata type under
  `uiBundles/`, scaffolded with `sf template generate project` (or `sf template generate ui-bundle`
  inside an existing project), with data access through the GraphQL **Data SDK**. Check feasibility
  first: **Hyperforce only**, and the Dev Hub packaging toggle before any 2GP work. Distribution is
  managed or unlocked 2GP, namespace supported, but platform security is **not** inherited the way
  LWC inherits it.

These accelerate *building on* Salesforce, distinct from the hosted servers that let business agents
*operate* your org.

---

## 7. Security & Trust

Headless 360 changes the surface, **not** the security model:

- **Your existing model carries through.** Sharing rules, FLS and permission sets are enforced
  automatically however the data is reached — API, MCP or CLI.
- **The Einstein Trust Layer** applies on every agent path: masking, dynamic grounding, FLS,
  zero-data-retention with LLM providers.
- **Token-scoped, least-privilege access.** Authenticate with OAuth — External Client Apps, or JWT
  for server-to-server — scope tokens to the minimum, and use **Named Credentials** for outbound.
  The **Use Any API Auth** permission governs who may use legacy SOAP `login()`, retiring Summer '27;
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
| Run an agent server-side, no UI | **Agent API** (`dya-sf-agentforce`) |
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
