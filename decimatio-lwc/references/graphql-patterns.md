# GraphQL Wire Adapter — Reference Implementations

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
                        record {
                            Id
                            Name { value }
                        }
                    }
                }
            }
        `;

        try {
            const result = await executeMutation(mutation);
            const newId = result.data.uiapi.AccountCreate.record.Id;
        } catch (error) {
            // handle
        }
    }
}
```

Update uses `<Object>Update` and Delete uses `<Object>Delete` mutation operations with the same shape.

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

## Batch Mutations

Multiple mutations in one call use aliases and the `allOrNone` flag (when supported by the mutation type).

```javascript
const mutation = gql`
    mutation BatchUpdate {
        first: uiapi {
            AccountUpdate(input: { Id: "001...", Account: { Industry: "Tech" } }) {
                record { Id }
            }
        }
        second: uiapi {
            AccountUpdate(input: { Id: "001...", Account: { Industry: "Finance" } }) {
                record { Id }
            }
        }
    }
`;
```
