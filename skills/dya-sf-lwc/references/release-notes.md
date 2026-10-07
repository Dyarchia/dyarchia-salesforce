# Standing Platform Behaviour and Winter '27 Changes

Consultative. Facts that **gate what compiles or deploys** live in `SKILL.md`'s Platform Context;
this file holds the rest, stated once rather than repeated in each section that uses them, so the two
cannot drift apart.

## What Winter '27 adds

| Change | Status | What it gives you |
|---|---|---|
| Complex template expressions | **GA** (was Beta) | JavaScript expressions directly inside `{}` in a template. Needs the bundle's `apiVersion` at **66.0 or higher**. Replaces most formatting getters |
| `lwc:external` | GA | A third-party custom element used directly in a template, replacing the former iframe-only workaround |

## Standing behaviour, by the section that uses it

- **`@lwc/state` is GA** — shared reactive state across components on a page, with built-in Lightning
  State Managers wrapping LDS. §5.
- **GraphQL queries and mutations are GA** through `lightning/graphql` (v2). The v1
  `lightning/uiGraphQLApi` is deprecated. §4 and `references/graphql-patterns.md`.
- **`lwc:on` is GA** — event listeners attached from a JavaScript object. §2.
- **`standard__flow` PageReference is GA** — launches any active flow with one `navigate` call.
- **`lightning/accApi` is GA** — drives the Agentforce side panel headlessly.
- **Grouped `<details>`** gives native single-open accordions with no JavaScript.
- **Component Preview (Local Dev) is GA.** See `references/dev-tooling-and-config.md`.
