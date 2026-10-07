---
description: List every Salesforce skill in this plugin with what it covers, so the user can pick one to invoke by name.
argument-hint: "[filter]"
allowed-tools: Read, Glob
---

Print the catalogue of `dya-sf-` Salesforce skills available in this session.

These skills load on their own only before an edit in their scope, so a reader who is asking
rather than editing never sees them.

## What to print

Every skill whose name begins with `dya-sf-`, grouped by the families below, each with a one-line
summary of what it covers. Take the summaries from the skill descriptions already in context; no
file reading is needed. If a description is not available, read it from
`${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` rather than guessing.

Keep this grouping and order:

```text
Core development        apex · lwc · flow
Maintenance-mode UI     aura · visualforce
Runtime and sites       lwr · lwr-sites · lightning-out
AI and data             agentforce · data360 · headless360
Product and industry    b2b-commerce · b2c-commerce · field-service ·
                        omni-channel · omnistudio · revenue-cloud
Platform and tooling    permissions · cli
Integration family      integration-overview · integration-inbound-apis ·
                        integration-inbound-apex · integration-outbound ·
                        integration-events · integration-auth ·
                        integration-connectors-mcp
```

Print only the part of each description that says what the skill covers. Omit the `Applies to`
list and the closing trigger clause.

## Arguments

When `$ARGUMENTS` is present, treat it as a filter and print only the skills whose name or coverage
matches it. `/dya-sf-skills integration` prints the integration family; `/dya-sf-skills apex` prints
`dya-sf-apex` and anything else naming Apex in its coverage.

With no arguments, print the whole catalogue.

## After the list

Close with one line on how to invoke a skill, naming a real example from the list rather than a
placeholder. Say that `dya-sf-integration-overview` is the entry point for choosing an integration
pattern, since it routes between its siblings.

Keep it scannable. This is a menu, not documentation: no preamble, no explanation of what agent
skills are, and no offer of further work unless the user asks.
