# Shared State Across Components — Reference Implementation (v67.0)

Full implementation of the shared-state patterns referenced from SKILL.md §5. On API v67.0 (Summer '26) there are two GA mechanisms with different jobs: **`@lwc/state`** for same-page shared **reactive** state, and **Lightning Message Service (LMS)** for broadcast that crosses the DOM, pages, apps, or technologies (LWC / Aura / Visualforce).

Load this file when designing data flow across multiple LWC components on the same page or app.

## `@lwc/state` — Same-Page Shared Reactive State (GA)

Prefer `@lwc/state` for siblings or decoupled components on the **same page** that share reactive state (UI selections, multi-step form values, derived totals). It moves the state and its logic out of components into a reusable, testable module, so you neither prop-drill nor lift state into a common parent.

Define the manager with `defineState` and the `atom` / `computed` / `setAtom` primitives. `atom` holds a reactive value, `computed` derives from atoms and recomputes automatically, and `setAtom` is the only way to mutate an atom. The callback returns the public surface; consumers reach it through the instance's `.value`.

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

For record-backed shared state, Salesforce ships built-in managers that wrap Lightning Data Service — records, object info, layouts, and related lists — so you do not hand-write a manager just to share LDS data across components. Reach for a built-in manager (or a GraphQL wire) before writing your own for record data.

### Rules

- One manager module per logical concern; import the same module from every component that shares it.
- Mutate only through actions that call `setAtom` — never reassign atoms directly from a consumer.
- Derive with `computed`; do not duplicate derived values as separate atoms.
- `@lwc/state` is same-page client state — it does not cross the DOM, pages, or technologies. For that, use LMS below.

## When to Use LMS

Use LMS when **two or more components need to share or react to the same data** and they are not in a simple parent → child relationship. Concrete examples: a product list and a cart summary on the same page, a filter panel that drives a results grid rendered by a different component, an Aura component that needs to react to an event published by an LWC.

Do NOT reach for LMS for:
- Local component state (just use a JS property — primitives are reactive by default).
- Single parent → child data flow (`@api` properties).
- Child → parent notification (a `CustomEvent` bubbling up is simpler and more contained).
- Salesforce record data when LDS or GraphQL is already updating it (let the wire adapter own it).

LMS publishes across the whole application context, so prefer scoped events (`CustomEvent`) when the relationship is local — overusing LMS makes data flow hard to trace.

## Define a Message Channel

A message channel is metadata deployed with your project at `force-app/main/default/messageChannels/Cart.messageChannel-meta.xml`.

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

Import it into a component via `@salesforce/messageChannel/Cart__c`.

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

- Default scope: the active subscriber receives messages only while it is on the active page/tab.
- `APPLICATION_SCOPE`: the subscriber receives messages regardless of where it sits in the app (e.g., in a utility bar). Import `APPLICATION_SCOPE` from `lightning/messageService` and pass it in the subscribe options.

## Architectural Rules

- Always `unsubscribe` in `disconnectedCallback` — orphaned subscriptions leak and cause duplicate handling.
- Guard against double-subscription in `connectedCallback` (the early-return pattern above).
- Keep message payloads small and serialisable — primitives and plain objects, never component instances or DOM nodes.
- Treat received data immutably: build a new array/object (`[...items, message]`) so reactivity fires.
- One channel per logical concern; don't multiplex unrelated events through a single channel.
- LMS bridges LWC, Aura and Visualforce — the same channel can be published/subscribed from any of them.

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

## `@lwc/state` vs LMS — Decision

- Same-page shared **reactive** state (UI selections, form values, derived totals) → `@lwc/state`.
- Record-backed shared state → a built-in Lightning State Manager or a GraphQL wire.
- Broadcast across the DOM, pages, apps, or technologies (LWC / Aura / Visualforce) → LMS.
- Direct parent ↔ child → `@api` props and `CustomEvent`, not either of the above.

If you are migrating an older codebase, move same-page LMS channels and prop drilling to `@lwc/state` concern by concern, and keep LMS only where the communication genuinely crosses a boundary `@lwc/state` cannot.
