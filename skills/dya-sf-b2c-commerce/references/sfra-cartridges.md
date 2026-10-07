# B2C Commerce — SFRA, Script API, Hooks, Jobs (server-side)

Load from `dya-sf-b2c-commerce`.

## Cartridges & the Cartridge Path

- A **cartridge** packages controllers, scripts, templates, static assets, and config.
- Override a base-cartridge file with a same-path file in your cartridge.
- Scaffold with `sgmf-scripts` (`sgmf-scripts --help`; `createCartridge`). Deploy by uploading and activating a **code version** (B2C CLI / `dw.json`).

## Controllers (SFRA)

Routes take `server.get/post(name, ...middleware)`; respond with `res.render('template', data)` or `res.json(data)`.

```javascript
'use strict';
var server = require('server');
var ProductMgr = require('dw/catalog/ProductMgr');
var BasketMgr  = require('dw/order/BasketMgr');

server.get('Show', function (req, res, next) {
    var product = ProductMgr.getProduct(req.querystring.pid);
    res.render('product/productDetails', { product: product });
    next();
});
module.exports = server.exports();
```

```javascript
'use strict';
var server = require('server');
server.extend(module.superModule);

server.append('Show', function (req, res, next) {      // augment view data after base runs
    var vd = res.getViewData();
    vd.extra = 'value';
    res.setViewData(vd);
    next();
});
// server.prepend(...) runs before base; server.replace(...) replaces the route entirely
module.exports = server.exports();
```

> `server.append` can re-execute logic; do not run the controller twice when appending and rendering.

## Script API (`dw.*`)

`Mgr` classes retrieve business objects.
- `dw/catalog` — `ProductMgr.getProduct(id)`, `CatalogMgr`, `Product`, price/availability models.
- `dw/order` — `BasketMgr.getCurrentBasket()` / `getCurrentOrNewBasket()`, `OrderMgr`, `Basket`, `Order`.
- `dw/customer` — `CustomerMgr`, `Customer`, `Profile`.
- `dw/system` — `Transaction`, `Site`, `Logger`, `HookMgr`, `Status`, `CacheMgr`.
- `dw/web` — `URLUtils`, `Resource` (i18n).
- `dw/util` — collections, `Calendar`, `HashMap`.

```javascript
var Transaction = require('dw/system/Transaction');
var BasketMgr   = require('dw/order/BasketMgr');

Transaction.wrap(function () {
    var basket = BasketMgr.getCurrentOrNewBasket();
    basket.createProductLineItem('682875090845M', basket.defaultShipment);
});
```

> `getCurrentBasket()` inside a read-only hook (`beforeGet`/`modifyResponse`) won't update the last-modified date.

## ISML Templates

Server-rendered `.isml`; compute in controllers/models, render in ISML. Tags: `<isloop>`, `<isif>`, `<isset>`, `<isinclude>`, `<isscript>`, and `${...}`. Script API calls via `<isscript>`/`<isset>` work but are **not recommended**.

## Hooks

Hook functions must be exported.

```json
// hooks.json
{ "hooks": [
  { "name": "dw.order.calculate", "script": "./cartridge/scripts/hooks/cart/calculate.js" },
  { "name": "dw.ocapi.shop.basket.billing_address.beforePUT", "script": "./cartridge/scripts/hooks/basket.js" },
  { "name": "dw.ocapi.shop.basket.billing_address.afterPUT",  "script": "./cartridge/scripts/hooks/basket.js" }
]}
```

```javascript
// calculate.js — custom cart calculation
var HookMgr = require('dw/system/HookMgr');
exports.calculate = function (basket) {
    return HookMgr.callHook('dw.order.calculate', 'calculate', basket);
};
```

```javascript
// basket.js — OCAPI hook extension points
var Status = require('dw/system/Status');
exports.beforePUT = function (basket, doc) {
    // custom logic before the PUT is processed
    return new Status(Status.OK);
};
```

Signature: `HookMgr.callHook(extensionPoint, function, args...)`. Every registered hook still executes even though only the last returns a value.

## Jobs Framework

**Task-oriented** — one function runs the step:

```javascript
// cartridge/scripts/steps/importCatalog.js
var Status = require('dw/system/Status');
exports.run = function (parameters, stepExecution) {
    // parameters = business-user-configured values
    return new Status(Status.OK);
};
```

**Chunk-oriented** — `read`/`process`/`write` over chunks, plus optional lifecycle hooks:

```javascript
// cartridge/scripts/steps/exportOrders.js
var Status = require('dw/system/Status');
var iterator;
exports.beforeStep = function (parameters, stepExecution) { /* open iterator */ };
exports.getTotalCount = function () { return iterator.getCount(); };  // total-count-function
exports.read  = function () { return iterator.hasNext() ? iterator.next() : null; };
exports.process = function (order) { return mapOrder(order); };       // return processed item or null to skip
exports.write = function (chunkList) { /* persist the chunk */ };
exports.afterStep = function (success, parameters, stepExecution) { return new Status(Status.OK); };
```

```json
{ "step-types": {
  "chunk-script-module-step": [{
    "@type-id": "custom.ExportOrders",
    "module": "my_cartridge/cartridge/scripts/steps/exportOrders.js",
    "function": "read",
    "transactional": "true",
    "chunk-size": 100,
    "read-function": "read", "process-function": "process", "write-function": "write",
    "total-count-function": "getTotalCount",
    "before-step-function": "beforeStep", "after-step-function": "afterStep",
    "parameters": { "parameter": [ { "@name": "Locale", "@type": "string", "@required": "false" } ] },
    "status-codes": { "status": [ { "@code": "OK", "description": "Success." } ] }
  }]
}}
```

Use `getTotalCount` to show progress; prefer standard imports over custom logic. `steptypes.json` is parsed at server startup, on code-version change, and (on sandboxes) each run.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Re-running the controller via append+render | Append only view data, render once |
| DML without `Transaction.wrap` | Wrap data changes in a transaction |
