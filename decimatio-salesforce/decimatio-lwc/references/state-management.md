# Shared State Across Components — Reference Implementation (v66.0)

Full implementation of the shared-state pattern referenced from SKILL.md §5. On API v66.0 (Spring '26) the GA, production-supported mechanism for sharing state across sibling or otherwise-unrelated components is **Lightning Message Service (LMS)**. The native `@lwc/state` manager is only Beta in v66.0 and does not reach GA until Summer '26 (API v67.0); a migration note is at the end of this file.

Load this file when designing data flow across multiple LWC components on the same page or app.

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
| `@lwc/state` in production on v66.0 | LMS — `@lwc/state` is Beta until v67 |

## Forward Note — Migrating to `@lwc/state` at v67

When the org moves to API v67.0 (Summer '26), `@lwc/state` becomes GA and is the preferred mechanism for **same-page** shared client-side state (multi-step form values, UI selections, derived totals), replacing same-page LMS usage and prop drilling. LMS remains the right tool for cross-page / cross-app and cross-technology (Aura/Visualforce) broadcast even after the upgrade. Plan migrations channel-by-channel: same-page coordination → `@lwc/state`; decoupled or cross-context broadcast → keep LMS.
