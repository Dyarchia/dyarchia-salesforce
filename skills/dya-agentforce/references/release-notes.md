# Winter '27 — What the Release Adds to Agentforce

Consultative. The facts that **gate behaviour** live in `SKILL.md`'s Platform Context; this file is
the rest of the release surface, for when someone asks what is new rather than what to do.

Status is stated because it decides whether an agent may propose the feature. **Beta and Developer
Preview are not available in production orgs.**

| Change | Status | What it gives you |
|---|---|---|
| `AiAgentDefinition` / `AiAgentDefinitionVersion` metadata types | GA at 68.0 | Agents deploy as source-controlled metadata rather than through the authoring bundle alone |
| MCP interoperability | GA | An agent discovers and calls tools on external MCP servers through a governed connection, instead of every capability being rebuilt as a local action. See `dya-integration-connectors-mcp` |
| Agent observability and analytics | GA | Session-level tracing, usage analytics, and **custom scorers** that measure quality against your own rules rather than a generic metric. See §9 |
| Voice: sharper transcription, less robotic speech | GA | Better recognition accuracy and more natural output for Agentforce Voice |
| 24 additional conversation languages | **Beta** | Check the list before promising a language |
| Execute Data 360 SQL from Apex | GA | An action can query Data 360 alongside org data in one class. See `dya-data360` |

## Standing platform facts

These describe the shape of the product rather than a rule to follow. Each is covered properly by
the section named beside it.

- **Atlas Reasoning Engine 3.0** powers reasoning and multi-agent routing.
- **Multi-Agent Orchestration is GA** — an orchestrator routes work to specialist subagents based on
  their descriptions and actions. See §11.
- **Agent Script is GA and open source.** Natural-language instructions blended with deterministic
  programmatic expressions: conditionals, transitions, variables, subagent and action selection. The
  Agent Builder runs on a graph-based engine, and legacy agents can auto-migrate. See §5 and
  `references/agent-script.md`.
- **Agentforce DX**: `agent preview` is GA for scriptable test sessions, with project scaffolding,
  one-command agent users, trace files, and YAML/JSON-defined evaluations (Beta). See §8 and
  `references/agent-lifecycle-metadata.md`.
- **Agentforce Experience Layer (AXL)** — define an interaction once and render it natively across
  Slack, Teams, Voice, mobile and third-party assistants. See `dya-headless360`.
