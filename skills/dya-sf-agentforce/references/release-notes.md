# Winter '27 — What the Release Adds to Agentforce

The facts that **gate behaviour** are in `SKILL.md`'s Platform Context; this file covers the rest of
the release.

Propose a feature only where its status allows it. **Beta and Developer Preview are not available
in production orgs.**

| Change | Status | What it gives you |
|---|---|---|
| `AiAgentDefinition` / `AiAgentDefinitionVersion` metadata types | GA at 68.0 | Agents deploy as source-controlled metadata, not through the authoring bundle alone |
| MCP interoperability | GA | An agent discovers and calls tools on external MCP servers through a governed connection, instead of rebuilding every capability as a local action. See `dya-sf-integration-connectors-mcp` |
| Agent observability and analytics | GA | Session-level tracing, usage analytics, and **custom scorers** that measure quality against your own rules. See §9 |
| Voice: sharper transcription, more natural speech | GA | Applies to Agentforce Voice |
| 24 additional conversation languages | **Beta** | Check the list before promising a language |
| Execute Data 360 SQL from Apex | GA | An action can query Data 360 alongside org data in one class. See `dya-sf-data360` |

## Standing platform facts

- **Atlas Reasoning Engine 3.0** powers reasoning and multi-agent routing.
- **Multi-Agent Orchestration is GA.** See §11.
- **Agent Script is GA and open source.** Natural-language instructions blended with deterministic
  programmatic expressions: conditionals, transitions, variables, subagent and action selection. The
  Agent Builder runs on a graph-based engine, and legacy agents can auto-migrate. See §5 and
  `references/agent-script.md`.
- **Agentforce DX**: `agent preview` is GA for scriptable test sessions, with project scaffolding,
  one-command agent users, trace files, and YAML/JSON-defined evaluations (Beta). See §8 and
  `references/agent-lifecycle-metadata.md`.
- **Agentforce Experience Layer (AXL)** — define an interaction once and render it natively across
  Slack, Teams, Voice, mobile and third-party assistants. See `dya-sf-headless360`.
