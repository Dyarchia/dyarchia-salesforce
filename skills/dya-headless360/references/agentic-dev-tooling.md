# Agentforce Vibes — Reference (Winter '27 / API v68.0)

Load from `dya-headless360` when working in or advising on Agentforce Vibes, the build-time half of
Headless 360. This is the agentic development environment; the runtime half is the Experience Layer.

## What it is, and what version

**Agentforce Vibes v4.0+** is a VS Code extension, also available as a cloud-hosted **Agentforce Vibes
IDE**. It installs from the VS Code Marketplace and Open VSX as part of the Salesforce Extension Pack.
It is built on Salesforce's **Coding Agent Platform**, orchestrated by **Claude and Mastra**, and on
an **Agent SDK** you can use to build your own agents, MCP integrations and agentic workflows.

The documentation attaches **no maturity label to the product** — no GA, no Beta, no Developer
Preview. It is installable from a marketplace today. Individual features inside it carry their own
labels: Metadata Experts MCP Server (Beta), Metadata API Context MCP Server (Beta), Content
Read-Only MCP Server (Beta), Data SDK and GraphQL (Beta). Say that rather than assigning the product
a status the source does not give it.

**v4.0 was reimagined from the ground up**, so material describing a "2.0" is describing a different
product generation. What carried over: Rules and Skills as concepts, inline completions for Apex and
LWC, the Salesforce Trust Boundary, and the marketplace and cloud IDE presence. What moved: rule and
skill files went from `.a4drules/` to **`.vibes/rules/`** and **`.vibes/skills/`**.

## Availability — check before recommending it

| | Status |
|---|---|
| Editions | **Not available** in Group, Professional or Essentials |
| **EU Operating Zone** | **Not available.** Stated on three separate pages, on data-residency grounds. EU orgs that are *not* part of EU Operating Zone are supported under standard terms |
| Government Cloud | **The documentation contradicts itself — see below** |

**EU Operating Zone is the one to remember**, because it is a paid data-residency offering an
enterprise customer may well hold without the developer knowing. "We're in the EU" does not settle
it; whether the org is in EU OZ does.

**On Government Cloud the docs disagree with themselves.** Three pages — admin settings, extension
setup and the FAQ — list Government Cloud alongside EU Operating Zone as unavailable, for data
residency reasons. A fourth page is a dedicated guide to *using Agentforce Vibes with Government
Cloud orgs*, stating FedRAMP High and DoD Impact Level 5 authorization, automatic routing of AI
requests to a dedicated Government Cloud endpoint, and step-by-step authentication instructions.

Both cannot be current. Treat Government Cloud as **unconfirmed** and verify against the org and
with Salesforce before promising it either way. Do not resolve the contradiction by picking the
answer that suits the conversation.

Note the distinction from **Salesforce Multi-Framework**, which is separately and unambiguously
unavailable on Government Cloud and Alibaba Cloud — see `references/react-and-data-sdk.md`. Two
different products with two different availability stories; conflating them is easy and wrong.

## The name fossil

The extension identifier is still **`salesforcedx-einstein-gpt`**, and the older documentation path
`platform/einstein-for-devs/` now redirects to the Agentforce Vibes guide. The product went Einstein
for Developers → Agentforce for Developers → Agentforce Vibes, and the URLs and identifiers did not
follow. Expect to meet all three names in the wild; they are the same lineage.

## Autonomous sub-agents

A coordinating lead agent delegates to specialised sub-agents working **in parallel** — Apex logic,
LWC, Jest testing, SOQL. Each runs in an isolated context and **its own Git worktree**, which is how
concurrent work avoids workspace conflicts rather than serialising.

## Plan Mode — the approval gate

With Plan Mode off the agent acts directly on your prompt. With it on, it produces a structured plan
and **changes no files until you click Approve Plan**. On approval the mode switches to Agent mode and
execution begins.

A plan has a fixed anatomy, and it is worth knowing because it is what you review:

| Section | Holds |
|---|---|
| **Context** | A summary of what you asked for |
| **Goals** | What the plan aims to achieve |
| **Non-Goals** | What it explicitly does not touch — the part most worth reading |
| **Approach** | Task count, overall strategy, and which sub-agent roles are assigned (Logic Builder for Apex, Component Builder for LWC, QA Validator for coverage) |
| **Tasks** | Numbered steps with expected outcomes and file paths |

You iterate on the plan in conversation before approving. **To change scope, give feedback rather
than approving** — approval is the commit point. The agent can also *suggest* a plan when it judges a
request complex enough, without Plan Mode being enabled first.

Reach for it on multi-file changes with an order of operations, deployments needing a validation
pass, metadata migrations between orgs, and anything where you want to see the approach first.

Plan Mode consumes context while building the plan, so very large tasks are better split. And a plan
references the project state at the time it was made — manual changes between approval and execution
can invalidate it.

## Rules — always-on standards

**Rules are persistent instructions applied to every interaction**, as opposed to Skills, which
activate on demand. They exist so conventions do not have to be repeated in every prompt.

| Scope | Stored | Use for |
|---|---|---|
| **Project** | `.vibes/rules/` — **commit these** so the team shares standards | Conventions specific to this codebase |
| **Global** | Per user, across workspaces | Personal preferences |
| **Salesforce** | Built in, toggle only | `a4v-expert-global-rule`, `production-guardrails`, `metadata-best-practices` |

Create one from Toolkit › Rules › **+ Add Rule**: a kebab-case name, a scope, an application mode,
and markdown content.

**Two application modes, and choosing right matters for cost:**

- **Always** — active in every interaction. Use for broad standards ("never deploy to production
  without running tests").
- **File pattern** — active only when the agent touches files matching a glob, e.g. `**/*.cls`. Use
  for language-specific conventions.

**Every rule consumes context in every interaction it applies to.** That is the argument for file
patterns: an Apex naming rule has no business loading while the agent edits an LWC template. Keep
each rule to a single concern.

Salesforce rules cannot be edited or deleted, only toggled. Project rules override global rules when
both cover the same ground.

## Permissions and safety

Settings › **Permissions & Safety**. The session mode decides how much autonomy the agent has:

| Mode | Behaviour |
|---|---|
| **Ask every time** | Pauses before every tool call — reads, edits, commands, MCP tools |
| **Run safe defaults** | Auto-approves read-only actions and allowed shell commands; still asks before file edits, other commands and write tools |
| **Bypass (trust all)** | Runs everything with no confirmation |

**Run safe defaults is the recommended starting point.**

**Safety guardrails only apply in Run safe defaults.** They list the shell commands that run without
prompting, defaulting to filesystem reads, shell basics, git reads, Node/npm/pnpm and the Salesforce
CLI. In *Ask every time* everything prompts regardless; in *Bypass* everything runs regardless — the
guardrails are inert in both. That asymmetry catches people who tune the list and then switch mode.

Scope guardrail entries to commands you have verified. Adding a broad pattern like `git *` widens
autonomy considerably more than it appears to.

**Auto-approve Salesforce MCP write tools** is off by default. Enabling it auto-approves
*non-destructive* MCP writes; deploy and delete still ask.

The documentation makes a point worth repeating: **permission modes are not code review.** The agent
can produce code that compiles and is wrong. Modes manage filesystem access; correctness is still
yours.

## MCP inside Vibes

Vibes connects to MCP servers through a user-level **`mcp.json`**, with a platform-hosted server
bundle, trust controls, and per-row reconnect. Salesforce Platform servers include **Salesforce DX**
and the **Salesforce Hosted MCP Servers**; third-party and custom servers can be added alongside.

Two servers must be activated by an admin before Vibes can use them — Setup › MCP Servers, then
activate **`metadata-experts`** and **`salesforce-api-context`**. After activation they are enabled in
Vibes automatically with no further configuration.

> Building and serving the org-side tools: `references/building-mcp-tools.md`.

## Model selection

The model picker sits in the bottom-left of the chat. Models are grouped by provider and depend on
what the org has configured; switching mid-conversation does **not** reset context. The tiers are the
familiar ones — most capable for multi-file work and architectural planning, balanced for everyday
development, fastest for questions and simple generation. Token consumption differs by tier, which is
the actual argument for not defaulting to the largest model.

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
