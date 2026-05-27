# LWC State Management — Reference Implementation

Full implementation of the `@lwc/state` pattern referenced from SKILL.md §5. State Management graduated to GA in Summer '26 (API v67.0). Load this file when designing data flow across multiple LWC components on the same page or app.

## When to Use a State Manager

Use a state manager when **two or more components on the same page need to share or react to the same data**, and the relationship is not a simple parent → child prop passing. Concrete examples: a multi-step form spread across sibling components, a shopping cart whose total is rendered in a header while items are managed elsewhere, an opportunity page where a line-item list and a summary card must stay synchronised.

Do NOT use a state manager for:
- Local component state (just use a JS property — primitives are reactive by default).
- Single parent → child data flow (`@api` / properties).
- Cross-app or cross-page broadcast (use Lightning Message Service).
- Salesforce record data when LDS or GraphQL is already updating it (let the wire adapter own it).

State managers are not available in Experience Cloud as of Summer '26.

## Define a State Manager

A state manager is a JavaScript module that exports a factory describing the state and the actions that mutate it.

```javascript
// cartStateManager.js
import { defineState } from '@lwc/state';

export default defineState((atom, computed, update) => () => {
    const items = atom([]);
    const discount = atom(0);

    const total = computed({ items, discount }, ({ items, discount }) =>
        items.reduce((sum, i) => sum + i.price, 0) * (1 - discount)
    );

    const addItem = update({ items }, ({ items }, newItem) => ({
        items: [...items, newItem]
    }));

    const removeItem = update({ items }, ({ items }, itemId) => ({
        items: items.filter((i) => i.id !== itemId)
    }));

    const applyDiscount = update({ discount }, (_, value) => ({
        discount: value
    }));

    return { items, discount, total, addItem, removeItem, applyDiscount };
});
```

## Consume the State Manager in a Component

```javascript
// cartList.js
import { LightningElement } from 'lwc';
import { fromContext } from '@lwc/state';
import cartStateManager from 'c/cartStateManager';

export default class CartList extends LightningElement {
    cart = fromContext(this, cartStateManager);

    handleAdd(event) {
        // calling the action updates shared state — every component
        // consuming the same manager re-renders automatically.
        this.cart.value.addItem({
            id: event.detail.id,
            name: event.detail.name,
            price: event.detail.price
        });
    }

    get items() {
        return this.cart.value.items;
    }

    get formattedTotal() {
        return `$${this.cart.value.total.toFixed(2)}`;
    }
}
```

```html
<!-- cartList.html -->
<template>
    <ul>
        <template for:each={items} for:item="item">
            <li key={item.id}>{item.name} — ${item.price}</li>
        </template>
    </ul>
    <p>Total: {formattedTotal}</p>
</template>
```

A sibling component (e.g., `cartSummary`) consuming `fromContext(this, cartStateManager)` will receive the same instance and re-render whenever any atom it reads from changes.

## Architectural Rules

- One state manager per logical concern. Resist the temptation to build a single mega-store — Salesforce LWC is not Redux.
- Mutations only via `update(...)` actions. Never mutate `cart.value.items` directly from a component; reactivity will not fire.
- `computed(...)` for derived values — never compute in a getter that reads multiple atoms (will not auto-track).
- State managers can be nested: a parent manager can expose child managers, allowing scoped state inside a larger feature.
- For Salesforce record data, prefer LDS or GraphQL wire adapters; use state managers for **client-side application state** (UI mode, selections, multi-step form values, derived totals).

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| One global store for the whole app | One state manager per logical concern |
| Mutating `state.value.foo = bar` directly | Define an `update(...)` action and call it |
| Computing derived data in a component getter | Define a `computed(...)` atom in the manager |
| Using a state manager for parent→child props | Just pass `@api` properties |
| Using a state manager for cross-page broadcast | Use Lightning Message Service |
| Using a state manager to mirror Salesforce records | Let LDS / GraphQL own that data |
