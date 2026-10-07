# Jest Testing for LWC — Reference (Winter '27 / API v68.0)

Implementations of the LWC Jest testing patterns from SKILL.md §10. Load when writing or refactoring Jest tests for a Lightning web component.

`@salesforce/sfdx-lwc-jest` runs Jest with `jsdom`: no browser, org or network. The package has its own release cadence, independent of the Salesforce release; match its installed major version with an active Node LTS. These are unit tests of one component, not end-to-end tests.

## Install & npm Scripts

```bash
# Recommended: installs the package and seeds the package.json scripts
sf force lightning lwc test setup

# Manual equivalent
npm install --save-dev @salesforce/sfdx-lwc-jest
```

```json
// package.json
{
    "scripts": {
        "test:unit": "sfdx-lwc-jest",
        "test:unit:watch": "sfdx-lwc-jest --watch",
        "test:unit:debug": "sfdx-lwc-jest --debug",
        "test:unit:coverage": "sfdx-lwc-jest --coverage"
    }
}
```

```bash
# Run every test in the project (CLI wrapper)
sf force lightning lwc test run
```

## jest.config.js (Project Root)

Extend the package's default config; never hand-roll one. Add `moduleNameMapper` entries pointing `@salesforce/*` imports with no platform default (Apex methods, custom labels, custom permissions, etc.) at local mocks.

```javascript
const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    moduleNameMapper: {
        '^@salesforce/apex/AccountController\\.getSummaries$':
            '<rootDir>/force-app/test/jest-mocks/apex/getSummaries',
        '^lightning/navigation$':
            '<rootDir>/force-app/test/jest-mocks/lightning/navigation'
    },
    // Optional: enforce a floor so coverage gaps fail CI
    coverageThreshold: {
        global: { branches: 80, functions: 80, lines: 80, statements: 80 }
    }
};
```

`jestConfig` stubs base `lightning/*` components and the standard LDS / GraphQL adapters; map only modules with no built-in stub.

## Test File Layout

- One `__tests__` folder in each component bundle (next to the `.js`/`.html`).
- Test file named after the component plus `.test.js` — `helloWorld/__tests__/helloWorld.test.js`.
- Top-level `describe` whose label matches the rendered element name (`c-hello-world`).
- Store mock payloads as JSON beside the test, e.g. `__tests__/data/getRecord.json`.

## Canonical Test — createElement, Cleanup, Async Render

```javascript
import { createElement } from 'lwc';
import HelloWorld from 'c/helloWorld';

// Wait until the microtask queue drains so the component finishes re-rendering
async function flushPromises() {
    return Promise.resolve();
}

describe('c-hello-world', () => {
    afterEach(() => {
        // jsdom is shared across tests in a file and is NOT reset automatically;
        // tear the DOM down and clear mock state between tests
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the default greeting', () => {
        const element = createElement('c-hello-world', { is: HelloWorld });
        document.body.appendChild(element);

        const p = element.shadowRoot.querySelector('p');
        expect(p.textContent).toBe('Hello, World!');
    });

    it('re-renders after a public property changes', async () => {
        const element = createElement('c-hello-world', { is: HelloWorld });
        element.name = 'Dyarchia';
        document.body.appendChild(element);

        // Property changes re-render asynchronously — wait before asserting
        await flushPromises();

        const p = element.shadowRoot.querySelector('p');
        expect(p.textContent).toBe('Hello, Dyarchia!');
    });
});
```

### The async-render rule

`await flushPromises()` (equivalently `await Promise.resolve()`) between act and assert. A returned `.then()` chain also works, but `async/await` is the project default. For chained updates (promise → state → render), await once per microtask boundary.

## Querying & Interacting With the Shadow DOM

- Drive interactions by dispatching real DOM events on the queried node, then await a render.

```javascript
it('emits the selected id when a row is clicked', async () => {
    const element = createElement('c-record-list', { is: RecordList });
    document.body.appendChild(element);

    const handler = jest.fn();
    element.addEventListener('rowselect', handler);

    const firstRow = element.shadowRoot.querySelector('tr[data-id]');
    firstRow.dispatchEvent(new CustomEvent('click'));
    await flushPromises();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.id).toBe('001xx0000000001');
});
```

For form inputs, set the value then dispatch the matching event:

```javascript
const input = element.shadowRoot.querySelector('lightning-input');
input.value = 'new value';
input.dispatchEvent(new CustomEvent('change'));
await flushPromises();
```

Base `lightning/*` mocks render as custom elements with the real public API but no internal behaviour — you can read their properties and dispatch events on them, but they emit nothing themselves.

## Wire Service — Modern `.emit()` / `.error()` API

Import the adapter under test directly; the test environment turns it into a test wire adapter exposing `.emit(data)` and `.error()`. **Do not** call `registerTestWireAdapter` / `registerLdsTestWireAdapter` / `registerApexTestWireAdapter` — that registration style is legacy (Spring '21 and earlier).

### LDS adapter (getRecord, getRelatedListRecords, …)

```javascript
import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import AccountDetail from 'c/accountDetail';

const mockGetRecord = require('./data/getRecord.json');

describe('c-account-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the account name from the wire', async () => {
        const element = createElement('c-account-detail', { is: AccountDetail });
        element.recordId = '001xx0000000001';
        document.body.appendChild(element);

        // Push mock data through the wire
        getRecord.emit(mockGetRecord);
        await flushPromises();

        const name = element.shadowRoot.querySelector('.account-name');
        expect(name.textContent).toBe('Acme Corp');
    });

    it('renders an error when the wire fails', async () => {
        const element = createElement('c-account-detail', { is: AccountDetail });
        element.recordId = '001xx0000000001';
        document.body.appendChild(element);

        getRecord.error();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error')).not.toBeNull();
    });
});
```

### Apex wired method

A wired `@salesforce/apex/...` import is also a test wire adapter — emit through it the same way.

```javascript
import getSummaries from '@salesforce/apex/AccountController.getSummaries';

const mockSummaries = require('./data/getSummaries.json');

it('lists the summaries returned by the wired Apex', async () => {
    const element = createElement('c-summary-list', { is: SummaryList });
    document.body.appendChild(element);

    getSummaries.emit(mockSummaries);
    await flushPromises();

    const rows = element.shadowRoot.querySelectorAll('tr.summary');
    expect(rows.length).toBe(mockSummaries.length);
});
```

### GraphQL adapter

```javascript
import { graphql } from 'lightning/graphql';

const mockGraphql = require('./data/accountQuery.json');

it('renders accounts from the GraphQL wire', async () => {
    const element = createElement('c-account-list', { is: AccountList });
    document.body.appendChild(element);

    graphql.emit(mockGraphql);          // graphql.error() for the failure path
    await flushPromises();

    const items = element.shadowRoot.querySelectorAll('li');
    expect(items.length).toBe(20);
});
```

## Imperative Apex — `jest.mock` + Resolved/Rejected Values

Imperative Apex calls are not wires: mock the module with a Jest fn and control the returned promise per test.

```javascript
import { createElement } from 'lwc';
import saveRecords from '@salesforce/apex/AccountController.saveRecords';
import RecordEditor from 'c/recordEditor';

jest.mock(
    '@salesforce/apex/AccountController.saveRecords',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

async function flushPromises() {
    return Promise.resolve();
}

describe('c-record-editor', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('calls Apex with the modified records on save', async () => {
        saveRecords.mockResolvedValue({ success: true });

        const element = createElement('c-record-editor', { is: RecordEditor });
        document.body.appendChild(element);

        element.shadowRoot.querySelector('lightning-button.save').click();
        await flushPromises();

        expect(saveRecords).toHaveBeenCalledWith({
            records: expect.any(Array)
        });
    });

    it('surfaces an error when Apex rejects', async () => {
        saveRecords.mockRejectedValue({ body: { message: 'DML failed' } });

        const element = createElement('c-record-editor', { is: RecordEditor });
        document.body.appendChild(element);

        element.shadowRoot.querySelector('lightning-button.save').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error').textContent)
            .toContain('DML failed');
    });
});
```

## Mocking `@salesforce/*` Scoped Modules

- **Custom labels** — `@salesforce/label/c.MyLabel` resolves to the label name string by default; override with a `moduleNameMapper` mock only when a test needs a specific value.
- **Schema** — `@salesforce/schema/Account.Name` resolves to `{ objectApiName, fieldApiName }`; usable as-is.
- **`lightning/navigation`** — map a mock module in `jest.config.js` so `NavigationMixin.Navigate` is an assertable `jest.fn()`. The `lwc-recipes` repo ships a reusable mock.
- **Toast events** — listen for the platform event the component dispatches:

```javascript
it('fires a success toast after save', async () => {
    const element = createElement('c-record-editor', { is: RecordEditor });
    document.body.appendChild(element);

    const toastHandler = jest.fn();
    // ShowToastEvent dispatches a 'lightning__showtoast' DOM event
    element.addEventListener('lightning__showtoast', toastHandler);

    element.shadowRoot.querySelector('lightning-button.save').click();
    await flushPromises();

    expect(toastHandler).toHaveBeenCalled();
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
});
```

## Accessibility Tests with Sa11y

`@sa11y/jest` runs axe assertions inside the Jest suite, so accessibility regressions fail the build.

```bash
npm install --save-dev @sa11y/jest
npm test -- --testMatch="**/*.accessibility.test.js"
```

Convention is a separate `*.accessibility.test.js` file per component, so the a11y suite runs and
reports independently of the unit suite.

**Do not prefix the command with `SA11Y_*` environment variables.** Once wired into the project's Jest
setup, `@sa11y/jest` runs automatically; `SA11Y_AUTO`,
`SA11Y_ENABLE_DOM_MUTATION_OBSERVER` and `SA11Y_ENABLE_RENDERED_DOM_SAVE` belong to Salesforce's
internal Bazel builds and do nothing in a DX project. Exit codes are Jest's usual 0 or 1.

## Coverage & CI

- `npm run test:unit:coverage` writes an Istanbul report; gate the build with `coverageThreshold` in `jest.config.js`.
- Test rendered output and emitted events, not private details, so refactors do not break passing tests.
- Keep each `it` focused on one observable behaviour; one `expect` per concept reads best.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| `document.querySelector(...)` in a test | `element.shadowRoot.querySelector(...)` |
| Asserting right after a property/wire change | `await flushPromises()` first, then assert |
| `registerTestWireAdapter` / `registerLdsTestWireAdapter` | Import the adapter and call `.emit()` / `.error()` |
| Hitting a real org / network in a unit test | Emit mock JSON through the wire adapter |
| Reusing DOM/mocks across tests | Tear down `document.body` and `jest.clearAllMocks()` in `afterEach` |
| Hand-written `jest.config.js` | Spread `jestConfig` from `@salesforce/sfdx-lwc-jest/config` |
| Testing private methods directly | Test rendered output and dispatched events |
| Mocking imperative Apex with a wire emit | `jest.mock(...)` + `mockResolvedValue` / `mockRejectedValue` |
| Snapshotting whole component trees | Assert specific nodes/text; snapshots are brittle here |

## Quick Reference — What to Mock How

| Dependency | How to mock | Inject data with |
|---|---|---|
| LDS wire (`getRecord`, related lists, object info) | Auto test wire adapter | `adapter.emit(json)` / `adapter.error()` |
| GraphQL wire (`lightning/graphql`) | Auto test wire adapter | `graphql.emit(json)` / `graphql.error()` |
| Wired Apex (`@wire(getX)`) | Auto test wire adapter | `getX.emit(json)` / `getX.error()` |
| Imperative Apex | `jest.mock(module, () => ({ default: jest.fn() }), { virtual: true })` | `fn.mockResolvedValue` / `mockRejectedValue` |
| Base `lightning/*` components | Built-in stubs | n/a — query and dispatch events |
| Custom label / schema | Built-in default (string / object) | `moduleNameMapper` only if a value matters |
| `lightning/navigation`, `lightning/messageService` | `moduleNameMapper` to a local mock | assert the `jest.fn()` calls |
| Toast (`ShowToastEvent`) | Listen for `'lightning__showtoast'` | assert handler `detail` |
