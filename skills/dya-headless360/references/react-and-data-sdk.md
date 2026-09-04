# React Apps and the Data SDK — Reference (Winter '27 / API v68.0)

Load from `dya-headless360` when building a React application that runs on the platform. This is what
"native React support" in the Experience Layer actually means in practice.

**Scope note:** the deep guide is the *Salesforce Multi-Framework Developer Guide* under
`developer.salesforce.com/docs/platform/multiframework/`, which covers org configuration, project
structure and integration in full. What follows is the developer-facing shape and the parts that
decide a design.

## A React app is Salesforce metadata

**A React app is a Salesforce DX project containing React metadata represented by the `UIBundle`
metadata type.** That single fact settles most architectural questions: it deploys, retrieves,
version-controls and packages like any other metadata, through the same DX project and pipeline
described in `references/shared/org-model.md`.

## Starting points

**Templates** give the `UIBundle` structure and basic features, with no Salesforce metadata of their
own:

| Template | For |
|---|---|
| **Internal User App** | Employees signing in with Salesforce credentials. Includes an Agentforce Conversation Client and object search |
| **External User App** | B2B and B2C — partners or customers signing in from outside the org. Prebuilt shell with an Experience Cloud site, navigation, authentication and object search |

**Sample apps** are fuller, including custom objects, permission sets, sample data and Apex:

- **Property Management App** — internal app for rentals, tenant applications and maintenance, with a dashboard and an Agentforce Conversation Client.
- **Property Rental App** — the external companion where prospective tenants view and apply for listings; adds an Experience Cloud site plus Apex classes and triggers.

The External templates and the Rental sample bring an Experience Cloud site with them, so the guest
and sharing model applies — see `dya-lwr-sites` and `dya-permissions`.

## Org prerequisites

Vibes is enabled by default in supported editions, but two MCP servers must be **activated by an
admin** before the React workflow works properly. Setup › Quick Find › **MCP Servers**, then activate:

- **`metadata-experts`** — Metadata Experts MCP Server (Beta)
- **`salesforce-api-context`** — Metadata API Context MCP Server (Beta)

Both are enabled in Vibes automatically after activation, with no further configuration. To pull
imagery or brand assets from Salesforce CMS you also need the **Content Read-Only MCP Server (Beta)**.

## The Data SDK — GraphQL, typed

Data access goes through `@salesforce/platform-sdk/data`, and the whole workflow is built around
generating TypeScript types from the org's schema rather than hand-writing shapes.

```javascript
import { createDataSDK, gql } from "@salesforce/platform-sdk/data";
import type {
  GetPropertiesQuery,
  GetPropertiesQueryVariables,
} from "../graphql-operations-types";

const GET_PROPERTIES = gql`
  query GetProperties($first: Int) {
    uiapi {
      query {
        Property__c(first: $first) {
          edges { ... }
        }
      }
    }
  }
`;
```

Queries follow the **UI API structure** — `uiapi` → `query` → object — which is the same shape LWC's
GraphQL wire adapter uses. If you know one you know the other; see `dya-lwc`.

### The workflow, in the order it actually goes

1. **Explore the schema.** Search `schema.graphql` for `type <ObjectName> implements Record` to find
   the available fields. Vibes does this before writing an operation, and so should you — guessing
   field names is where this goes wrong.
2. **Choose the query pattern.**
3. **Write the query.** Complex operations are generated as `.graphql` files under
   `src/api/utils/query`.
4. **Generate types.**
   ```bash
   npm run graphql:codegen
   ```
   Types land at `src/api/graphql-operations-types.ts`.
5. **Implement the data access function**, importing the generated types.

Mutations follow the same shape for create, update and delete.

**Regenerate types after any schema change.** The generated file is the contract between your React
code and the org; when a field is added or renamed and codegen has not run, TypeScript still compiles
against a stale contract and the failure surfaces at runtime.

**Data SDK and GraphQL are Beta.** Not production, and worth stating before someone plans a delivery
around them.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Treating a React app as something outside the metadata model | It is a DX project with a `UIBundle` — deploy and version it like any metadata |
| Starting from an empty project | A template gives the `UIBundle` structure; a sample app gives working metadata to read |
| Writing GraphQL field names from memory | Search `schema.graphql` for `type <ObjectName> implements Record` |
| Editing generated types by hand | Re-run `npm run graphql:codegen` |
| Skipping codegen after a schema change | The stale contract compiles and fails at runtime |
| Expecting the React workflow to work without the MCP servers | An admin activates `metadata-experts` and `salesforce-api-context` in Setup |
| Planning a production delivery on the Data SDK | It is Beta |
| Forgetting the guest model on an external template | It ships an Experience Cloud site — see `dya-lwr-sites` and `dya-permissions` |
