# Aura Events & Communication — Reference Implementation (API v67.0)

Full implementations referenced from SKILL.md §6. Load this when wiring communication between Aura components, or between Aura and LWC/Visualforce, on Summer '26 (API v67.0).

Preference order: `aura:method` (parent → child) → component event (child → ancestor) → Lightning Message Service (cross-tree / LWC / Visualforce) → application event (last resort, app-wide broadcast).

## `aura:method` — Parent Calls Child Synchronously

Cleanest way for a parent to invoke a child. No event plumbing.

```html
<!-- child: c:searchPanel -->
<aura:method name="reset" action="{!c.reset}" description="Clears the search input">
    <aura:attribute name="keepFilters" type="Boolean" default="false" />
</aura:method>
```

```javascript
// child controller
({ reset: function (component, event) {
    const keepFilters = event.getParam("arguments").keepFilters;
    component.set("v.searchTerm", "");
    if (!keepFilters) { component.set("v.filters", []); }
}})
```

```javascript
// parent calls it
({ clearChild: function (component) {
    component.find("panel").reset(false);   // <c:searchPanel aura:id="panel" .../>
}})
```

## Component Event — Child Notifies Ancestor

The default for child → parent. Bubbles up the containment hierarchy; only ancestors can handle it.

```xml
<!-- event definition: c:rowSelected (RowSelected.evt) -->
<aura:event type="COMPONENT" description="Fired when a row is selected">
    <aura:attribute name="recordId" type="Id" />
</aura:event>
```

```html
<!-- child registers it -->
<aura:registerEvent name="rowSelect" type="c:rowSelected" />
```

```javascript
// child fires it
({ select: function (component, event) {
    const evt = component.getEvent("rowSelect");
    evt.setParams({ recordId: component.get("v.row.Id") });
    evt.fire();
}})
```

```html
<!-- parent handles it (must contain the child) -->
<aura:handler name="rowSelect" event="c:rowSelected" action="{!c.onRowSelect}" />
<c:dataRow aura:id="row" />
```

```javascript
// parent controller
({ onRowSelect: function (component, event) {
    const recordId = event.getParam("recordId");
    component.set("v.selectedId", recordId);
}})
```

## Application Event — Last Resort, App-Wide Broadcast

Use only when genuinely unrelated components must react and no containment relationship exists. Every registered handler in the app receives it.

```xml
<!-- c:cartUpdated (CartUpdated.evt) -->
<aura:event type="APPLICATION" description="Broadcasts cart changes app-wide">
    <aura:attribute name="itemCount" type="Integer" />
</aura:event>
```

```javascript
// publisher (anywhere)
({ addToCart: function (component) {
    const evt = $A.get("e.c:cartUpdated");
    evt.setParams({ itemCount: component.get("v.count") });
    evt.fire();
}})
```

```html
<!-- subscriber (anywhere) -->
<aura:handler event="c:cartUpdated" action="{!c.onCartUpdate}" />
```

Application events are expensive and hard to trace. On a Lightning page, prefer Lightning Message Service (below) — it does the same job, also reaches LWC/Visualforce, and supports scoping.

## Lightning Message Service From Aura

The supported way to talk to LWC, Visualforce, or components in a separate tree on the same Lightning page. The message channel (`*.messageChannel-meta.xml`) is shared across LWC, Aura, and Visualforce.

```html
<!-- assign an aura:id so the controller can call publish() -->
<lightning:messageChannel type="OrderEvents__c"
                          aura:id="orderChannel"
                          onMessage="{!c.handleMessage}"
                          scope="APPLICATION" />
```

```javascript
({
    // publish
    publishOrder: function (component) {
        const payload = { orderId: component.get("v.orderId") };
        component.find("orderChannel").publish(payload);
    },

    // subscribe handler — wrap re-rendering work in $A.getCallback
    handleMessage: function (component, message) {
        $A.getCallback(function () {
            component.set("v.lastOrderId", message.getParam("orderId"));
        })();
    }
})
```

The `onMessage` attribute subscribes declaratively; no manual subscribe/unsubscribe needed. `scope="APPLICATION"` receives messages regardless of where the component sits (e.g. utility bar). For the LWC side of the same channel see `dya-lwc`; for the Visualforce side (`sforce.one.publish/subscribe`) see `dya-visualforce`.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Application event for child → parent | Component event (bubbles to ancestors) |
| Application event for cross-tree / LWC comms | Lightning Message Service |
| Component event expecting a non-ancestor to handle it | Use LMS, or restructure the hierarchy |
| Mutating state in `onMessage` without `$A.getCallback` | Wrap the re-rendering work in `$A.getCallback` |
| Parent reaching into child internals | `aura:method` (parent → child) |
| Forgetting `aura:registerEvent` on the firing component | Register before `getEvent`/`fire` |
