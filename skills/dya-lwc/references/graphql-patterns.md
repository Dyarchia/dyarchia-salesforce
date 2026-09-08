# GraphQL Wire Adapter — Reference (Winter '27 / API v68.0)

Full implementations of the GraphQL patterns referenced from SKILL.md §4. Load this file when writing a new GraphQL-backed component or refactoring an Apex-backed one.

Always use `lightning/graphql` (v2), never the deprecated `lightning/uiGraphQLApi` (v1). The v2 adapter uses `errors` (plural), not `error` like the other wire adapters.

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

Use `variables` with a getter for reactivity — never hardcode dynamic values inside the query string.

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

Default page size is 10. Use `first` to set explicitly, `after` with `endCursor` to paginate forward.

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

Two shapes here are easy to get wrong and fail in different ways:

- The mutation payload field is **`Record`**, capitalised. The lowercase `record` does not exist in
  the schema, so the query is rejected rather than returning null. Selecting it needs API 64.0 or
  above, which is below our floor.
- **`executeMutation` takes the document first and the options second** — `executeMutation(document,
  { variables })`. Passing a single `{ query, variables }` object leaves the document undefined and
  the call fails with nothing useful to read.

Update uses `<Object>Update` and Delete uses `<Object>Delete` with the same shape, with two
restrictions: `Create` and `Update` payloads must not select child relationships and may reach a
`REFERENCE` field only through its `ApiName`, and **`Delete` may select only `Id`**. Fields the user
cannot see arrive in the payload's `errors` array instead of failing the request.

## Multi-Object Query in One Call

Multiple queries can run in one operation. Use aliases when querying the same object twice.

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

Dependent queries (query B depends on the result of query A) require separate calls — the second `@wire` reacts to the first's result via a getter.

## Chained Mutations

There is **no `allOrNone` flag on a GraphQL mutation**, and aliasing the `uiapi` field itself does
not batch anything. What the API does support is **reference chaining**: a later mutation consumes
an Id produced by an earlier one through the `@{alias}` token.

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

Three constraints, all load-bearing:

- **The producing mutation must appear first** in the document. Order is the dependency, not the
  alias name.
- **Only `Create` and `Delete` can be chained from.** Referencing `@{A}` where `A` is an `Update`
  fails.
- The token is the whole value — `"@{A}"`, not interpolated into a larger string.

For mutations with no dependency between them, issue separate calls. Nothing rolls them back
together, so make each one idempotent rather than assuming transactional behaviour that is not
there.
