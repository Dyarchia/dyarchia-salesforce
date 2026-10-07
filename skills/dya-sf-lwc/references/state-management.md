# Shared State Across Components — Reference Implementation (Winter '27 / API v68.0)

Implementation of the shared-state patterns from SKILL.md §5: **`@lwc/state`** and **Lightning Message Service (LMS)**. Load when designing data flow across LWC components on the same page or app.

## `@lwc/state` — Same-Page Shared Reactive State (GA)

Typical state: UI selections, multi-step form values, derived totals.

Define the manager with `defineState` and the `atom` / `computed` / `setAtom` primitives. `atom` holds a reactive value, `computed` derives from atoms and recomputes, and `setAtom` is the only way to mutate an atom. The callback returns the public surface, which consumers reach through the instance's `.value`.

```javascript
// selectionState.js
import { defineState } from '@lwc/state';

export const selectionState = defineState(({ atom, computed, setAtom }) => {
    const selectedIds = atom([]);
    const count = computed([selectedIds], (ids) => ids.length);

    const toggle = (id, current) =>
        setAtom(selectedIds, current.includes(id) ? current.filter((x) => x !== id) : [...current, id]);

    const clear = () => setAtom(selectedIds, []);

    return { selectedIds, count, toggle, clear };
});
```

```javascript
// any sibling component
import { LightningElement } from 'lwc';
import { selectionState } from 'c/selectionState';

export default class ResultsGrid extends LightningElement {
    state = selectionState();

    get count() {
        return this.state.value.count;
    }

    handleRowSelect(event) {
        this.state.value.toggle(event.detail.id, this.state.value.selectedIds);
    }
}
```

### Built-in Lightning State Managers

Built-in managers wrap Lightning Data Service for records, object info, layouts and related lists. For record data, use one (or a GraphQL wire) before writing your own.

### Rules

- One manager module per logical concern; import the same module from every component that shares it.
- Mutate only through actions that call `setAtom` — never reassign atoms directly from a consumer.
- Derive with `computed`; do not duplicate derived values as separate atoms.

## When to Use LMS

Use LMS when **two or more components react to the same data** outside a parent → child relationship, for example a product list and a cart summary on the same page, a filter panel driving a results grid in another component, an Aura component reacting to an event an LWC published.

Do NOT use LMS for:
- Local component state (a plain property).
- Single parent → child data flow (`@api` properties).
- Child → parent notification (a bubbling `CustomEvent`).
- Salesforce record data LDS or GraphQL already updates .

LMS publishes across the whole application context; overusing it makes data flow hard to trace.

## Define a Message Channel

A message channel is metadata deployed at `force-app/main/default/messageChannels/Cart.messageChannel-meta.xml`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningMessageChannel xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>Cart</masterLabel>
    <isExposed>true</isExposed>
    <description>Broadcasts cart item changes across the page.</description>
    <lightningMessageFields>
        <fieldName>id</fieldName>
    </lightningMessageFields>
    <lightningMessageFields>
        <fieldName>name</fieldName>
    </lightningMessageFields>
    <lightningMessageFields>
        <fieldName>price</fieldName>
    </lightningMessageFields>
</LightningMessageChannel>
```

Import it via `@salesforce/messageChannel/Cart__c`.

## Publish

```javascript
// productTile.js
import { LightningElement, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import CART_CHANNEL from '@salesforce/messageChannel/Cart__c';

export default class ProductTile extends LightningElement {
    @wire(MessageContext) messageContext;

    handleAdd(event) {
        publish(this.messageContext, CART_CHANNEL, {
            id: event.detail.id,
            name: event.detail.name,
            price: event.detail.price
        });
    }
}
```

## Subscribe

```javascript
// cartSummary.js
import { LightningElement, wire } from 'lwc';
import {
    subscribe,
    unsubscribe,
    MessageContext,
    APPLICATION_SCOPE
} from 'lightning/messageService';
import CART_CHANNEL from '@salesforce/messageChannel/Cart__c';

export default class CartSummary extends LightningElement {
    @wire(MessageContext) messageContext;
    items = [];
    subscription;

    connectedCallback() {
        if (this.subscription) {
            return;
        }
        this.subscription = subscribe(
            this.messageContext,
            CART_CHANNEL,
            (message) => this.handleMessage(message),
            { scope: APPLICATION_SCOPE }
        );
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        // immutable update → reactive re-render
        this.items = [...this.items, message];
    }

    get total() {
        return this.items.reduce((sum, i) => sum + (i.price ?? 0), 0);
    }
}
```

```html
<!-- cartSummary.html -->
<template>
    <ul>
        <template for:each={items} for:item="item">
            <li key={item.id}>{item.name} — ${item.price}</li>
        </template>
    </ul>
    <p>Total: ${total}</p>
</template>
```

## Scope Options

- Default scope: the subscriber receives messages only while on the active page/tab.
- `APPLICATION_SCOPE`: the subscriber receives messages wherever it sits in the app (e.g., a utility bar). Import it from `lightning/messageService` and pass it in the subscribe options.

## Architectural Rules

- `unsubscribe` in `disconnectedCallback`; orphaned subscriptions leak and cause duplicate handling.
- Guard against double-subscription in `connectedCallback` (the early-return pattern above).
- Keep message payloads small and serialisable — primitives and plain objects, never component instances or DOM nodes.
- Treat received data immutably: build a new array/object (`[...items, message]`) so reactivity fires.
- One channel per logical concern; don't multiplex unrelated events through a single channel.
- LWC, Aura and Visualforce can all publish and subscribe on the same channel.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Using LMS for parent → child props | Pass `@api` properties |
| Using LMS for a child → parent notification | Dispatch a `CustomEvent` that bubbles |
| Forgetting to `unsubscribe` | Always unsubscribe in `disconnectedCallback` |
| Mutating received payload in place | Build a new array/object so reactivity fires |
| Putting non-serialisable data in a message | Send ids/primitives; re-fetch records via LDS/GraphQL |
| Using LMS to mirror Salesforce records | Let LDS / GraphQL own that data |
| LMS (or prop drilling) for same-page reactive state | `@lwc/state` (GA) |

## Migration

When migrating an older codebase, move same-page LMS channels and prop drilling to `@lwc/state` concern by concern; keep LMS only where communication crosses a boundary `@lwc/state` cannot.
