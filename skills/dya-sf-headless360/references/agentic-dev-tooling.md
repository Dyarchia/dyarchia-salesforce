# Agentforce Vibes — Reference (Winter '27 / API v68.0)

Load from `dya-sf-headless360` when working in or advising on Agentforce Vibes, the build-time half of
Headless 360; the runtime half is the Experience Layer.

## What it is, and what version

**Agentforce Vibes v4.0+** is a VS Code extension, also available as a cloud-hosted **Agentforce Vibes
IDE**. It installs from the VS Code Marketplace and Open VSX as part of the Salesforce Extension Pack.
It is built on Salesforce's **Coding Agent Platform**, orchestrated by **Claude and Mastra**, and on
an **Agent SDK** for building your own agents, MCP integrations and agentic workflows.

Do not assign the **product** a GA, Beta or Developer Preview label; the documentation gives it none.
Individual features carry their own: Metadata Experts MCP Server (Beta), Metadata API Context MCP
Server (Beta), Content Read-Only MCP Server (Beta), Data SDK and GraphQL (Beta).

Treat material describing a "2.0" as a different product generation: **v4.0 was rebuilt from the
ground up**. Carried over: Rules and Skills as concepts, inline completions for Apex and LWC, the
Salesforce Trust Boundary, and the marketplace and cloud IDE presence. Moved: rule and skill files
went from `.a4drules/` to **`.vibes/rules/`** and **`.vibes/skills/`**.

## Availability

| | Status |
|---|---|
| Editions | **Not available** in Group, Professional or Essentials |
| **EU Operating Zone** | **Not available**, on data-residency grounds. EU orgs *not* in EU Operating Zone are supported under standard terms |
| Government Cloud | **The documentation contradicts itself — see below** |

Check whether the org is in EU Operating Zone; being in the EU does not settle it. EU Operating Zone
is a paid data-residency offering an enterprise customer may hold without the developer knowing.

**On Government Cloud the docs disagree.** Treat Government Cloud as **unconfirmed** and verify
against the org and with Salesforce before promising it either way. Three pages — admin settings, extension setup and the
FAQ — list Government Cloud as unavailable, for data-residency reasons. A fourth is a dedicated guide
to *using Agentforce Vibes with Government Cloud orgs*, stating FedRAMP High and DoD Impact Level 5
authorization, automatic routing of AI requests to a dedicated Government Cloud endpoint, and
authentication steps.

**Salesforce Multi-Framework** is separately and unambiguously unavailable on Government Cloud and
Alibaba Cloud — see `references/react-and-data-sdk.md`.

## The name fossil

The extension identifier is still **`salesforcedx-einstein-gpt`**, and the older documentation path
`platform/einstein-for-devs/` redirects to the Agentforce Vibes guide. The product went Einstein for
Developers → Agentforce for Developers → Agentforce Vibes; the URLs and identifiers did not follow.

## Autonomous sub-agents

A lead agent delegates to specialised sub-agents working **in parallel**: Apex logic, LWC, Jest
testing and SOQL. Each runs in an isolated context and **its own Git worktree**, so parallel work
neither conflicts nor serialises.

## Plan Mode — the approval gate

With Plan Mode off the agent acts directly on your prompt. With it on, it produces a structured plan
and changes nothing until you click **Approve Plan**; the mode then switches to Agent mode and
execution begins.

| Section | Holds |
|---|---|
| **Context** | A summary of what you asked for |
| **Goals** | What the plan aims to achieve |
| **Non-Goals** | What it does not touch — the part most worth reading |
| **Approach** | Task count, overall strategy, and which sub-agent roles are assigned (Logic Builder for Apex, Component Builder for LWC, QA Validator for coverage) |
| **Tasks** | Numbered steps with expected outcomes and file paths |

**To change scope, give feedback rather than approving** — approval is the commit point. The agent
can also *suggest* a plan for a complex request without Plan Mode enabled.

Use it for multi-file changes with an order of operations, deployments needing a validation pass,
metadata migrations between orgs, and anything where you want to see the approach first.

Split very large tasks; Plan Mode consumes context while building the plan. Avoid manual changes
between approval and execution; they can invalidate a plan.

## Rules — always-on standards

**Rules apply to every interaction**, so conventions need not be repeated in every prompt.

| Scope | Stored | Use for |
|---|---|---|
| **Project** | `.vibes/rules/` — **commit these** so the team shares standards | Conventions specific to this codebase |
| **Global** | Per user, across workspaces | Personal preferences |
| **Salesforce** | Built in, toggle only | `a4v-expert-global-rule`, `production-guardrails`, `metadata-best-practices` |

Create one from Toolkit › Rules › **+ Add Rule**: a kebab-case name, a scope, an application mode,
and markdown content.

Application modes:

- **Always** — active in every interaction. Use for broad standards ("never deploy to production
  without running tests").
- **File pattern** — active only when the agent touches files matching a glob, e.g. `**/*.cls`. Use
  for language-specific conventions.

Put an Apex naming rule behind a file pattern, not loaded while the agent edits an LWC template:
**every rule consumes context in every interaction it applies to**. Keep each rule to a single
concern.

Salesforce rules cannot be edited or deleted, only toggled. Project rules override global rules when
both cover the same ground.

## Permissions and safety

Settings › **Permissions & Safety**. The session mode sets the agent's autonomy:

| Mode | Behaviour |
|---|---|
| **Ask every time** | Pauses before every tool call — reads, edits, commands, MCP tools |
| **Run safe defaults** | Auto-approves read-only actions and allowed shell commands; still asks before file edits, other commands and write tools |
| **Bypass (trust all)** | Runs everything with no confirmation |

**Start in Run safe defaults**, the recommended mode.

**Safety guardrails apply only in Run safe defaults.** They list the shell commands that run without
prompting, defaulting to filesystem reads, shell basics, git reads, Node/npm/pnpm and the Salesforce
CLI. In the other two modes they are inert.

Scope guardrail entries to verified commands. A broad pattern like `git *` widens autonomy far more
than it appears to.

**Auto-approve Salesforce MCP write tools** is off by default. Enabling it auto-approves
*non-destructive* MCP writes; deploy and delete still ask.

**Permission modes are not code review.** They manage filesystem access; the agent can produce code
that compiles and is wrong.

## MCP inside Vibes

Vibes connects to MCP servers through a user-level **`mcp.json`**, with a platform-hosted server
bundle, trust controls, and per-row reconnect. Salesforce Platform servers include **Salesforce DX**
and the **Salesforce Hosted MCP Servers**; third-party and custom servers can be added alongside.

An admin must activate **`metadata-experts`** and **`salesforce-api-context`** in Setup › MCP Servers
before Vibes can use them; once activated they are enabled in Vibes automatically.

> Building and serving the org-side tools: `references/building-mcp-tools.md`.

## Model selection

Match the tier to the task and do not default to the largest model; token consumption differs by
tier. Tiers: most capable for multi-file work and architectural planning, balanced for everyday
development, fastest for questions and simple generation. The model picker sits in the bottom-left
of the chat. Models are grouped by provider and depend on what the org has configured; switching
mid-conversation does **not** reset context.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Calling it "Vibes 2.0" | v4.0+ is a ground-up rebuild — a different product generation |
| Assigning the product a GA or Preview status | The docs give it none; individual features carry their own labels |
| Looking for rules in `.a4drules/` | `.vibes/rules/` and `.vibes/skills/` since v4.0 |
| Leaving project rules uncommitted | Commit `.vibes/rules/` so the team shares the standards |
| Every rule set to Always | File patterns keep irrelevant rules out of context |
| One rule covering several concerns | One concern per rule; they cost context on every interaction |
| Tuning safety guardrails then switching to Bypass | Guardrails only apply in Run safe defaults |
| Adding `git *` to the guardrails | Specific verified commands |
| Approving a plan to then redirect it | Give feedback first — approval is the commit point |
| Treating permission modes as code review | They manage filesystem access, not correctness |
| Defaulting to the most capable model | Match the tier to the task; token cost differs |
