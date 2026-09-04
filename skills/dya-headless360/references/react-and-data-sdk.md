# Salesforce Multi-Framework, React and the Data SDK — Reference (Winter '27 / API v68.0)

Load from `dya-headless360` when building a React application that runs on the platform. **Salesforce
Multi-Framework** is the framework-agnostic runtime behind it: your app runs on the Headless 360
platform, reaches org data through GraphQL and the Data SDK, and inherits authentication, security
and governance instead of reimplementing them.

## React or LWC — decide first

They are not competitors; they answer different questions.

- **LWC** for native platform integration: automatic data binding, built-in security, and reusable
  components that compose inside Lightning Experience, Experience Builder sites and the mobile app.
  It remains the optimal choice for components *within* Salesforce.
- **React** for self-contained single-page applications or highly customised experiences that use
  Salesforce as host and data source.

| | LWC | React on Multi-Framework |
|---|---|---|
| Integration | Deep and native — LDS, Apex, platform services | Full-page apps and custom experiences; brings your React expertise and libraries |
| Security | Platform security enforced automatically | **Managed externally — you implement and maintain it** |
| Performance | Optimised for the Salesforce UI | High for complex UIs, but depends on your API and data-retrieval design |
| Reuse | Excellent across Lightning Experience and LWC projects | Within the React app. Embedding React components **in** Lightning Experience needs Micro-Frontend support, which is **Developer Preview** |

That security row is the one to weigh honestly: choosing React moves a responsibility onto your team
that LWC handles for you.

## Constraints that decide feasibility

Check these before designing anything. Each of them ends a project that assumed otherwise.

- **Hyperforce only.** Confirm in Setup › Company Information: an instance name with a three-letter
  prefix followed by digits (`abc123`) means Hyperforce. **Unavailable on Alibaba Cloud and on
  Salesforce Government Cloud.**
- **English as the org's default language.**
- **Editions**: Enterprise, Performance, Unlimited, Developer, Partner Developer.
- **Packaging is unsupported.**
- **Namespaced orgs are unsupported.** Developer orgs support the `c` namespace only.

Packaging plus namespaced orgs being out means this is not currently a path for ISV work.

## Org setup

**Internal apps** are served from the **Salesforce App Domain** at `.my.salesforce.app`, a separate
top-level domain that enforces browser-native isolation. It is enabled automatically in most orgs;
otherwise Setup › *React Development with Salesforce Multi-Framework* › **Enable Domain**. It
requires **Salesforce Edge Network** — Setup › My Domain › Routing and Policies. Enabling the domain
needs **Customize Application**.

**External apps** (partner or customer portals) need **Digital Experiences** enabled, plus the right
licences: Customer Community or Customer Community Plus for B2C, Partner Community and Channel
Account for B2B.

Optional additions: the **Agentforce Conversation Client** (with routing, policies and trusted
domains configured), and the **Content Read-Only MCP Server (Beta)** for Salesforce CMS content.

## The project is a DX project

A React app is Salesforce metadata: the **`UIBundle`** type, living under `uiBundles/` in the
package directory. Each application subdirectory is a **self-contained unit** — metadata definition,
runtime configuration, source and build output together.

```shell
my-sfdx-project
└── force-app/main/default/uiBundles/myapp/
    ├── myapp.uibundle-meta.xml    # Salesforce metadata
    ├── ui-bundle.json             # Application configuration
    ├── package.json               # Application dependencies
    ├── vite.config.ts
    ├── vitest.config.ts
    ├── tsconfig.json
    ├── src/
    │   ├── app.html               # Entry HTML
    │   ├── components/
    │   ├── pages/
    │   ├── assets/
    │   └── styles/
    └── dist/                      # Build output (generated)
```

## Generating and running

```shell
# a UI bundle inside an existing DX project
sf template generate ui-bundle --name MyReactApp --template reactbasic

# or a whole project from a use-case template
sf template generate project --name MyReactApp --template reactinternalapp
sf template generate project --name MyReactProject --template reactexternalapp
```

`reactinternalapp` brings the required `CustomApplication` metadata; `reactexternalapp` brings the
site metadata types.

**Install dependencies inside the UI bundle directory, not at the project root.** This is the step
that silently produces a broken app when skipped:

```shell
cd force-app/main/default/uiBundles/MyReactProject
npm install
npm run sf-project-setup       # builds and opens the dev server at http://localhost:5173
```

Building without a React template, add `@salesforce/vite-plugin-ui-bundle` (wires the Vite dev server
to your org's data) and `@salesforce/ui-bundle` (Data SDK helpers).

Beyond templates there are sample apps carrying real metadata, custom objects, permission sets and
Apex — Property Management (internal) and Property Rental (external, with an Experience Cloud site).

## The Data SDK

```javascript
import { createDataSDK, gql } from "@salesforce/platform-sdk/data";

const dataSdk = await createDataSDK();

const result = await dataSdk.graphql?.query<MyQueryType>({ query, variables });
```

`createDataSDK(options?)` returns a `DataSDK` whose `graphql` and `fetch` members are **both
optional**, because they are supported only in specific environments. **Use optional chaining
(`graphql?.`, `fetch?.`) every time** — this is not defensive style, it is the documented contract.
Options cover surface detection, a `basePath` for API calls, and `on401` / `on403` callbacks.

**Access data in this order of preference:**

1. **GraphQL** — `dataSdk.graphql?.query()` and `.mutate()`. The preferred path for record data.
2. **UI API or another REST endpoint** through `dataSdk.fetch?.()` — including an Apex controller
   exposed via Apex REST.
3. **GraphQL over GET** through `fetch?.()` when the query is small enough for a URL, or when you
   need a round-trip CSRF token.
4. **Apex REST** for custom logic GraphQL cannot express.

**Never call `fetch()` or `axios` directly against Salesforce endpoints.** The SDK handles
authentication and CSRF validation; bypassing it means reimplementing both, incorrectly.

### Typed queries

Queries follow the UI API shape (`uiapi` → `query` → object), the same structure as LWC's GraphQL
wire adapter. Explore the schema before writing one — search `schema.graphql` for
`type <ObjectName> implements Record` rather than guessing field names.

```shell
npm run graphql:codegen     # types generated at src/api/graphql-operations-types.ts
```

**Re-run codegen after any schema change.** The generated file is the contract between your React
code and the org; a stale one still compiles and fails at runtime.

Complex operations are generated as `.graphql` files under `src/api/utils/query`.

## Coming from LWC

Most of the LWC toolbox is unavailable. **Not supported**: `@salesforce` scoped modules other than
`@salesforce/platform-sdk/data`, Lightning base components and any `lightning/*` module, and the
`@wire` service. Use standard web APIs and npm packages.

| Don't use (LWC only) | Use in React |
|---|---|
| `@salesforce/apex/Class.method` | `dataSdk.fetch?.()` against `/services/apexrest/...` |
| `@salesforce/schema/Object.Field` | The API name as a string in the GraphQL query |
| `@salesforce/user/Id` | GraphQL `uiapi.currentUser` |
| `getRecord`, `getListUi` and other `lightning/uiRecordApi` reads | `dataSdk.graphql?.query(...)` |
| `createRecord`, `updateRecord`, `deleteRecord` | `dataSdk.graphql?.mutate(...)` |
| The `@wire` decorator | `useEffect` plus `dataSdk.graphql?.query(...)`; `QueryResult.subscribe` for reactive updates |

Note what the second row costs: **schema imports are gone**, so a renamed field no longer breaks the
build — it breaks at runtime. That safety net is one of the things you trade away.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Designing before checking Hyperforce, edition and language | The constraints are absolute — verify first |
| Planning an ISV or packaged deliverable | Packaging and namespaced orgs are unsupported |
| Reaching for React for a component inside Lightning Experience | LWC. Embedding React there needs Micro-Frontend, still Developer Preview |
| Assuming platform security carries over | With React you implement and maintain it |
| `npm install` at the project root | Inside the `uiBundles/<app>` directory |
| `fetch()` or `axios` straight at a Salesforce endpoint | `dataSdk.fetch?.()` — it handles auth and CSRF |
| `dataSdk.graphql.query(...)` without optional chaining | `graphql?.` and `fetch?.` are optional by contract |
| Looking for `lightning/*` or `@wire` | Only `@salesforce/platform-sdk/data`; use `useEffect` and `subscribe` |
| Guessing GraphQL field names | Search `schema.graphql` for `type <ObjectName> implements Record` |
| Skipping codegen after a schema change | The stale contract compiles and fails at runtime |
