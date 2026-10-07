# GraphQL Wire Adapter — Reference (Winter '27 / API v68.0)

Implementations of the GraphQL patterns from SKILL.md §4. Load when writing a GraphQL-backed component or refactoring an Apex-backed one.

The v2 adapter returns `errors` (plural), not `error` like the other wire adapters.

## Basic Query

```javascript
import { LightningElement, wire } from 'lwc';
import { gql, graphql } from 'lightning/graphql';

export default class AccountList extends LightningElement {
    @wire(graphql, { query: '$accountQuery' })
    graphqlResult;

    get accountQuery() {
        return gql`
            query AccountList {
                uiapi {
                    query {
                        Account(
                            first: 20
                            orderBy: { Name: { order: ASC } }
                        ) {
                            edges {
                                node {
                                    Id
                                    Name { value }
                                    Industry { value }
                                }
                            }
                        }
                    }
                }
            }
        `;
    }

    get accounts() {
        return this.graphqlResult?.data?.uiapi?.query?.Account?.edges?.map(
            (edge) => edge.node
        ) ?? [];
    }
}
```

## Query With Reactive Variables

```javascript
import { LightningElement, wire } from 'lwc';
import { gql, graphql } from 'lightning/graphql';

export default class FilteredAccounts extends LightningElement {
    minRevenue = 1000000;

    get variables() {
        return { minRevenue: this.minRevenue };
    }

    get accountQuery() {
        return gql`
            query FilteredAccounts($minRevenue: Currency) {
                uiapi {
                    query {
                        Account(
                            where: { AnnualRevenue: { gte: $minRevenue } }
                            first: 10
                        ) {
                            edges {
                                node {
                                    Id
                                    Name { value }
                                    AnnualRevenue { value }
                                }
                            }
                        }
                    }
                }
            }
        `;
    }

    @wire(graphql, {
        query: '$accountQuery',
        variables: '$variables'
    })
    result;
}
```

## Cursor-Based Pagination

```javascript
get variables() {
    return { first: 20, after: this.endCursor };
}

get accountQuery() {
    return gql`
        query PagedAccounts($first: Int!, $after: String) {
            uiapi {
                query {
                    Account(first: $first, after: $after) {
                        edges { node { Id Name { value } } }
                        pageInfo { endCursor hasNextPage }
                    }
                }
            }
        }
    `;
}

// In the wire handler, when new data arrives:
this.endCursor = result.data?.uiapi?.query?.Account?.pageInfo?.endCursor;
this.hasNextPage = result.data?.uiapi?.query?.Account?.pageInfo?.hasNextPage;
```

## Mutations — Create / Update / Delete Without Apex

```javascript
import { LightningElement } from 'lwc';
import { gql, executeMutation } from 'lightning/graphql';

export default class CreateAccount extends LightningElement {
    async handleCreate() {
        const mutation = gql`
            mutation CreateAccount {
                uiapi {
                    AccountCreate(input: {
                        Account: {
                            Name: "New Account"
                            Industry: "Technology"
                        }
                    }) {
                        Record {                      // ✅ capital R — `record` does not resolve
                            Id
                            Name { value }
                        }
                    }
                }
            }
        `;

        try {
            const result = await executeMutation(mutation, { variables: {} });  // ✅ two arguments
            const newId = result.data.uiapi.AccountCreate.Record.Id;
        } catch (error) {
            // handle
        }
    }
}
```

- The mutation payload field is **`Record`**, capitalised. Lowercase `record` does not exist in the
  schema, so the query is rejected rather than returning null. Selecting it needs API 64.0 or above,
  below our floor.
- **`executeMutation` takes the document first and options second** — `executeMutation(document,
  { variables })`. A single `{ query, variables }` object leaves the document undefined and the call
  fails without a useful error.

Update (`<Object>Update`) and Delete (`<Object>Delete`) take the same shape, with two restrictions:
`Create` and `Update` payloads must not select child relationships and may reach a `REFERENCE` field
only through its `ApiName`, and **`Delete` may select only `Id`**. Fields the user cannot see arrive
in the payload's `errors` array instead of failing the request.

## Filtering Beyond a Single Object

**Operators:** `eq`, `ne`, `in`, `nin`, `gt`, `gte`, `lt`, `lte`, `like`, `contains`.

**Semi-join and anti-join** filter a parent by a condition on its children:

```graphql
Account(where: {
    Id: { inq: {                       # `ninq` for the anti-join
        Contact: { Title: { like: "%VP%" } }
        ApiName: "AccountId"           # the parent-id field on the child
    } }
}) { edges { node { Id Name { value } } } }
```

Use `Id: { ne: null }` when the only condition is that a matching child exists.

**The running user** is `uiapi.currentUser`, which takes no arguments and returns a `User`.

**Polymorphic references** need inline fragments (`... on Account`). A field is polymorphic when its
`referenceToInfos` has more than one entry. Navigate references by **`relationshipName`**; when that
is null only the raw `Id` can be returned.

### Discovering the schema

There is **no `/graphql/sdl` route**. Introspect through `/services/data/vXX.X/graphql` with a
standard GraphQL introspection query. The SDL runs past 265,000 lines, so grep it:

```text
^type <Object> implements Record
^input <Object>_Filter
^input <Object>_OrderBy
^input <Object>(Create|Update)Input
```

### Mutation input rules

- `Create` must include every required field unless `defaultedOnCreate` is true, and may set only
  `createable` fields.
- `Update` takes the `Id` plus `updateable` fields only.
- `REFERENCE` fields are assigned through their `ApiName`.

## Multi-Object Query in One Call

Alias an object queried twice.

```javascript
get accountsAndContactsQuery() {
    return gql`
        query AccountsAndContacts {
            uiapi {
                query {
                    Account(first: 5) {
                        edges { node { Id Name { value } } }
                    }
                    Contact(first: 5) {
                        edges { node { Id Name { value } Email { value } } }
                    }
                }
            }
        }
    `;
}
```

For dependent queries, the second `@wire` reacts to the first's result via a getter.

## Chained Mutations

There is **no `allOrNone` flag on a GraphQL mutation**, and aliasing the `uiapi` field does not batch
anything. The API supports **reference chaining**: a later mutation consumes an Id produced by an
earlier one through the `@{alias}` token.

```javascript
const mutation = gql`
    mutation CreateAccountThenContact {
        uiapi {
            A: AccountCreate(input: { Account: { Name: "Acme" } }) {
                Record { Id }
            }
            B: ContactCreate(input: {
                Contact: { LastName: "Rivera", AccountId: "@{A}" }   // ✅ resolves to A's Id
            }) {
                Record { Id }
            }
        }
    }
`;
```

- **The producing mutation must appear first** in the document. Order, not alias name, is the
  dependency.
- **Only `Create` and `Delete` can be chained from.** Referencing `@{A}` where `A` is an `Update`
  fails.
- The token is the whole value — `"@{A}"`, not interpolated into a larger string.

Issue independent mutations as separate calls. Nothing rolls them back together, so make each
idempotent rather than assuming transactional behaviour.
