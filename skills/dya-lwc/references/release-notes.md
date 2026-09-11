# Standing Platform Behaviour and Winter '27 Changes

Consultative. The facts that **gate what compiles or deploys** live in `SKILL.md`'s Platform
Context; this file is the rest — stated once here rather than repeated in the section that uses
each one, so a section and this file cannot drift apart.

## What Winter '27 adds

| Change | Status | What it gives you |
|---|---|---|
| Complex template expressions | **GA** (was Beta) | JavaScript expressions directly inside `{}` in a template. Needs the bundle's `apiVersion` at **66.0 or higher**. Replaces most formatting getters |
| `lwc:external` | GA | Use a third-party custom element directly in a template, removing the iframe workaround that used to be the only option |

## Standing behaviour, by the section that uses it

- **`@lwc/state` is GA** — shared reactive state across components on a page, with built-in Lightning
  State Managers wrapping LDS. §5.
- **GraphQL queries and mutations are GA** through `lightning/graphql` (v2). The v1
  `lightning/uiGraphQLApi` is deprecated. §4 and `references/graphql-patterns.md`.
- **`lwc:on` is GA** — event listeners attached from a JavaScript object. §2.
- **`standard__flow` PageReference is GA** — launch any active flow with one `navigate` call.
- **`lightning/accApi` is GA** — drive the Agentforce side panel headlessly.
- **Grouped `<details>`** gives native single-open accordions with no JavaScript.
- **Component Preview (Local Dev) is GA.** See `references/dev-tooling-and-config.md`.
