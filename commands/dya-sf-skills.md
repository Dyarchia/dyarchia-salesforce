---
description: List every Salesforce skill in this plugin with what it covers, so the user can pick one to invoke by name.
argument-hint: "[filter]"
allowed-tools: Read, Glob
---

Print the catalogue of `dya-` Salesforce skills available in this session.

These skills load **only when invoked by name** — they never auto-trigger. That is deliberate, and
it means nobody discovers them by asking a Salesforce question. This command is how someone finds
out what is on the shelf.

## What to print

Every skill whose name begins with `dya-`, grouped by the families below, each with a one-line
summary of what it actually covers. Take the summaries from the skill descriptions you can already
see — they are in context, so no file reading is needed. If a description is not available to you,
read it from `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` rather than guessing.

Group them like this, and keep the order:

```text
Core development        apex · lwc · flow
Maintenance-mode UI     aura · visualforce
Runtime and sites       lwr · lwr-sites · lightning-out
AI and data             agentforce · data360 · headless360
Product and industry    b2b-commerce · b2c-commerce · field-service ·
                        omni-channel · omnistudio · revenue-cloud
Platform and tooling    permissions · sf-cli
Integration family      integration-overview · integration-inbound-apis ·
                        integration-inbound-apex · integration-outbound ·
                        integration-events · integration-auth ·
                        integration-connectors-mcp
```

Do not print the invocation clause that ends every description — it is identical in all of them and
adds nothing to a catalogue. Print the part that says what the skill covers.

## Arguments

When `$ARGUMENTS` is present, treat it as a filter and print only the skills whose name or coverage
matches it. `/dya-sf-skills integration` prints the integration family; `/dya-sf-skills apex` prints
`dya-apex` and anything else that names Apex in its coverage.

When there are no arguments, print the whole catalogue.

## After the list

Close with one line telling the user how to invoke one, naming a real example from what you just
printed rather than a placeholder. Say that `dya-integration-overview` is the entry point when the
question is which integration pattern to use, since that skill exists to route between its siblings.

Keep the whole thing scannable. This is a menu, not documentation: no preamble, no explanation of
what agent skills are, and no offer to do further work unless the user asks.
