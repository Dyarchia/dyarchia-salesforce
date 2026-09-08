---
name: dya-headless360
description: Salesforce Headless 360 (Winter '27 / API v68.0) — from zero to expert. The platform theme that turns every Salesforce capability into an API, MCP tool, or CLI command for apps, humans, and AI agents. Covers the three surfaces (API/MCP/CLI), the MCP server taxonomy (hosted, DX, custom, Data 360), building custom MCP tools, the Headless/Agentforce Experience Layer (HXL/AXL) and Lightning Types, Agentforce Vibes and React apps, headless DevOps, and the Trust Layer. Load only when the user explicitly invokes this skill by name (`dya-headless360`); do NOT auto-trigger on generic headless, MCP, API, or Salesforce questions.
---

# Salesforce Headless 360 — From Zero to Expert

You are an expert on Salesforce Headless 360. The reader may be **new to it**, so this skill builds the mental model first, then the implementation, then what this release changes. You **always** expose the smallest approved set of tools, **always** rely on the Trust Layer rather than bypassing it, and **always** define an experience once and render it everywhere. Follow every rule below.

This SKILL.md carries the load-bearing rules. Larger reference implementations live in `references/`:

- `references/shared/platform-deltas.md` — the release-coupled facts behind the surfaces below.
- `references/shared/metadata-and-api-versions.md` — API version semantics for anything addressing the platform by version.
- `references/shared/org-model.md` — orgs, DX projects and deployment, which the CLI and DevOps surfaces assume.
- `references/agentic-dev-tooling.md` — **Agentforce Vibes v4.0+**: Plan Mode and its approval gate, Rules and their context cost, permission modes and safety guardrails, MCP inside the IDE, model tiers.
- `references/react-and-data-sdk.md` — **Salesforce Multi-Framework**: the React-versus-LWC decision, the framework decision, the constraints that decide feasibility (Hyperforce only, Dev Hub packaging toggle), `UIBundle` project structure and 2GP distribution, and the Data SDK with its LWC translation table.
- `references/building-mcp-tools.md` — **standard versus custom servers, the five backing types for a custom tool, and connecting a client** with its callback URL. Start here to expose org capability to an AI client.
- `references/lightning-types.md` — the `LightningTypeBundle` structure, channel folders, and the Apex requirements that fail at invocation rather than at deploy.
- `references/mcp-servers.md` — the MCP server taxonomy (hosted vs DX vs custom vs Data 360), building custom MCP tools from Apex Actions / Flows / Apex REST, connecting external clients (Claude), and token-scoped security.
- `references/experience-layer.md` — the Headless/Agentforce Experience Layer (HXL/AXL), Lightning Types, "define once, render everywhere", native React, and when to use which surface.

Load a reference when building that exact thing. Headless 360 is the **access and distribution layer** over the whole platform — including Agentforce (`dya-agentforce`) and Data 360 (`dya-data360`).

---

## Platform Context — Winter '27 / API v68.0

Headless 360 is the platform theme that turns every Salesforce capability into an API, MCP tool or CLI command, usable by an app, a human, or an autonomous agent. It is an **access and distribution layer, not a replacement for Agentforce** — the two work together.

What Winter '27 adds:

| Change | Status | What it gives you |
|---|---|---|
| **Salesforce plugin for Claude Code** | GA | Detects a DX project and supplies org context through hosted MCP servers; installed from the Claude Plugin Marketplace. The clearest example of the whole theme: a coding agent with live org grounding. See `dya-sf-cli` |
| **DevOps Center MCP** | GA | The same programmatic access inside a CI/CD pipeline — describe a deployment and let an agent execute it |
| **MCP interoperability for agents** | GA | The direction reversed: an Agentforce agent calling *out* to external MCP servers. See `dya-integration-connectors-mcp` |
| **Apex Symbol API** | Beta | Compiler-grade Apex type metadata over the Tooling API, so an IDE or AI tool can reason about Apex accurately instead of guessing from text |

Standing facts:

- **Hosted MCP servers are GA** — connect any MCP client to the org and the Headless 360 portfolio: Salesforce Platform, Data 360, Tableau, MuleSoft, Slack.
- **Agentforce Vibes is at v4.0+**, a ground-up rebuild on Salesforce's Coding Agent Platform, orchestrated by Claude and Mastra and exposing an Agent SDK. It installs from the VS Code Marketplace and Open VSX, and also runs as a cloud-hosted IDE. **The documentation gives the product no maturity label**; individual features inside it are Beta. Material describing a "2.0" is a previous generation, and the lineage Einstein for Developers → Agentforce for Developers → Agentforce Vibes survives in URLs and in the extension id `salesforcedx-einstein-gpt`. **Not available in EU Operating Zone**, nor in Group, Professional or Essentials editions.
- **60+ MCP tools, 30+ preconfigured coding skills, 4,000+ APIs and 220+ CLI commands** are addressable by an authorised caller.
- **Salesforce DX MCP Server (Beta)** — developer and IDE tools: SLDS guidance, ApexGuru, LWC and Aura toolsets, Lightning Types, Metadata API context. **Data 360 MCP Server** is Developer Preview and **Metadata API Context MCP Server** is Beta.
- **Headless and Agentforce Experience Layer (HXL/AXL)** — define an interaction once and render it natively across Slack, Teams, Voice, mobile and third-party assistants, built on Lightning Types with native React support.
- **The Einstein Trust Layer and the org's existing security model carry through every surface unchanged.** A capability exposed as an MCP tool is not a capability with weaker security — it runs as the authenticated user.

---

## 1. Foundations — What Headless 360 Is

"Headless" means removing the "head" — the UI. A headless system exposes its functionality through **programmatic access** instead of screens. Headless 360 does that for the **entire** Salesforce platform: records, business logic, automations, metadata, DevOps, Agentforce, and Data 360 all become reachable without opening a browser.

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

Two lanes that converge:
- **Build-time** — coding agents and developers build *against* your org (DX MCP tools, coding skills, CLI, Agentforce Vibes).
- **Runtime** — business agents and apps *serve from* your org, with output rendered natively per channel via the Experience Layer.

**What's actually new:** you've built headless for years (REST APIs, Mobile SDK, React on Experience Cloud). What changed is that **AI models can now discover, call, and compose capabilities at runtime** — without per-integration glue written in advance — because every capability is described as an agent-accessible tool.

**Where the others fit:** Agentforce is the reasoning/agent layer; Data 360 is the data mesh underneath; Headless 360 is how both (and the rest of the platform) are exposed and rendered. Agentforce *provides* capabilities; Headless 360 *distributes* them.

---

## 2. Surface 1 — APIs

The 4,000+ existing REST/Connect/Platform APIs are the foundation. What Headless 360 adds is **intent**: every endpoint is explicitly documented as an **agent-accessible surface**, with guidance on **token-scoped access** and **Named Credentials**.

- For programmatic data/logic access, the existing REST and Connect APIs remain the workhorse.
- The **Agent API** (REST) lets external systems invoke agent sessions headlessly (see `dya-agentforce` §7).
- The **Data 360 APIs** (Query, Profile, Connect) expose the data mesh (see `dya-data360` §5).
- **Named Query API** (GA) exposes custom SOQL as scalable, agent-callable actions.

Treat APIs as the lowest-level surface: maximal control, but you write the integration. Reach for MCP when you want an *agent* to discover and call capabilities dynamically.

---

## 3. Surface 2 — MCP (the Headline)

The **Model Context Protocol (MCP)** is the open standard that lets AI clients **discover** approved tools, understand their inputs, **call** them, and get results — instead of guessing how to use your org. Headless 360 leans on MCP heavily. There are four server categories — do not conflate them:

| Server | Audience | Purpose |
|---|---|---|
| **Hosted MCP Servers** (GA) | Business agents / production | Standard, out-of-the-box access to Platform, Data 360, Tableau, MuleSoft, Slack |
| **Custom Hosted MCP Servers** | Business agents / production | Granular control: expose *your* chosen tools and prompts |
| **Salesforce DX MCP Server** (Beta) | Developers / IDEs | Dev workflows: metadata, tests, SLDS/ApexGuru/LWC tooling, Lightning Types |
| **Data 360 MCP Server** (Dev Preview) | Coding agents | Drive Data 360 via three facade tools (`search`, `payload_examples`, …) |

**Do not treat the DX MCP server as a production business-user server** — it's for development workflows authenticated via the Salesforce CLI.

### Building custom MCP tools

A custom hosted MCP server can expose tools built from existing platform artefacts — no new runtime needed:

- **Flow** — an **autolaunched** flow with defined inputs and outputs. Not screen, not scheduled.
- **Apex Invocable Action** — a **`global`** method annotated `@InvocableMethod`.
- **`@AuraEnabled` Apex method** — the one people miss: methods already serving as Lightning controllers become agent tools with **no new code**.
- **Apex REST** — a `@RestResource` class.
- **API Catalog endpoint** — registered platform and Connect APIs; coverage is still expanding.

The method's inputs and outputs **are** the tool's parameter schema, so nested types make a tool hard
to call correctly — and changing the Apex does **not** resync the tool configuration in Setup.

This is the bridge: the same `@InvocableMethod` you wrote as an **Agentforce action** can also be an **MCP tool** for an external coding/business agent. Build the capability once; expose it through whichever surface the caller uses.

### Golden rule of MCP exposure

**Expose the smallest set of approved tools, never unrestricted access.** Past a few dozen tools an AI client starts choosing badly — curation is the design, not housekeeping. Think of every tool on the platform as a buffet and a server as the plate curated for one persona. A tool's description is how the model decides to call it — write descriptions like the routing logic they are (same discipline as Agentforce action descriptions).

> Standard versus custom servers, the backing-type requirements, and the External Client App callback URL per client: `references/building-mcp-tools.md`. Wider taxonomy and security: `references/mcp-servers.md`.
> Vibes itself — Plan Mode, Rules, permission modes: `references/agentic-dev-tooling.md`.

---

## 4. Surface 3 — CLI

The Salesforce CLI's **220+ commands** are a first-class Headless 360 surface for automation and DevOps. The current emphasis is Agentforce DX and credential security:

```bash
sf agent generate template      # scaffold a runnable sample agent
sf agent generate agent-user    # provision a service agent user in one command
sf agent preview start|send|sessions|end   # scriptable interactive test sessions (GA)
```

Use the CLI for headless DevOps: deploy/retrieve metadata, run tests, and promote **Data 360** logic the same way you promote Apex/LWC (DevOps data kits). Anything you can click, you can increasingly script.

---

## 5. The Experience Layer (HXL / AXL)

The **Headless Experience Layer** (its agent-facing form is the **Agentforce Experience Layer, AXL**) is a runtime that **decouples a capability's definition from its rendering surface**. You define a UI fragment / interaction **once**; HXL renders it natively as a Slack block, a Teams card, a mobile card, a voice interaction, or a response inside ChatGPT/Claude/Gemini — no per-channel rebuild.

- Business logic, data, and permissions stay **separate** from the screen — "define intent once, render natively everywhere."
- It's built on **Lightning Types** — JSON-based types that structure, validate and display data. Standard types ship with an editor and renderer; custom ones are `LightningTypeBundle` metadata (API 64.0+) with optional per-channel UI overrides. See `references/lightning-types.md`.
- **Native React** support lets developers who want full control build custom interfaces in any design language over the same capabilities.
- Today the build-time surface is mature; the runtime surface already handles straightforward cases (e.g. a support agent returning a case summary in a Slack thread) and is expanding.

Use HXL/Lightning Types when the **same capability must appear across multiple channels**. Use plain LWC/Aura (see `dya-lwc` / `dya-aura`) when the target is only Lightning Experience. Full detail: `references/experience-layer.md`.

---

## 6. Dev Tooling — Agentforce Vibes, DX MCP, Skills & Rules

- **Agentforce Vibes (v4.0+)** — an agentic development environment, as a VS Code extension and as a cloud IDE. A lead agent delegates to specialised sub-agents running in parallel, **each in its own Git worktree** so concurrent work does not collide. **Plan Mode changes no files until you approve the plan.** **Rules** are always-on standards in `.vibes/rules/` (commit them); **Skills** activate on demand. Permission modes run from *Ask every time* through *Run safe defaults* to *Bypass* — and the safety guardrails apply **only** in the middle one.
- **Salesforce DX MCP Server** (Beta) — preconfigured in the Vibes extension; toolsets include `lwc-experts`, `aura-experts` (Aura→LWC migration), SLDS guidance, ApexGuru code review, Lightning Types (`create_lightning_type`), and Metadata API context. Some toolsets require enabling global rules (e.g. `a4d-general-rules`, `a4d-lwc-rules`).
- **Coding skills** (30+) — preconfigured capability bundles that give coding agents live, best-practice-aware access to your platform.
- **React and Angular apps on Salesforce Multi-Framework** — the framework-agnostic runtime. The app is a DX project carrying the **`UIBundle`** metadata type under `uiBundles/`, scaffolded with `sf template generate project` (or `sf template generate ui-bundle` inside an existing project), with data access through the GraphQL **Data SDK**. This is what "native React" in §5 means concretely. Check feasibility before designing: **Hyperforce only**, and the Dev Hub packaging toggle before any 2GP work. Distribution is a solved problem — managed or unlocked 2GP, namespace supported — but platform security is **not** inherited the way LWC inherits it.

These accelerate *building on* Salesforce; they are distinct from the hosted servers that let business agents *operate* your org.

---

## 7. Security & Trust

Headless 360 changes the surface, **not** the security model:

- **Your existing model carries through** — sharing rules, FLS, and permission sets are enforced automatically regardless of how data is accessed (API, MCP, CLI).
- **The Einstein Trust Layer** applies on every agent path: masking, dynamic grounding, FLS, zero-data-retention with LLM providers.
- **Token-scoped, least-privilege access** — authenticate with OAuth (External Client Apps / JWT for server-to-server), scope tokens to the minimum, and use **Named Credentials** for outbound. The new **Any API Auth** permission governs who may use legacy SOAP `login()` (retiring Summer '27 — migrate to OAuth/External Client Apps).
- **Curate the toolset** — expose a small, approved set of MCP tools, not the whole org. A broad toolset is both a security and a reliability liability.

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
