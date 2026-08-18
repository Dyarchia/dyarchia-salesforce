# B2C Commerce — SFRA, Script API, Hooks, Jobs (server-side)

Load from `dya-b2c-commerce`. Server-side B2C Commerce development: cartridges, controllers, `dw.*` Script API, ISML, hooks, jobs. This is JavaScript on the B2C Commerce Script API (Rhino-based) — **not** Node.js, **not** Apex.

## Cartridges & the Cartridge Path

- A **cartridge** packages controllers, scripts, templates, static assets, and config.
- The **cartridge path** (per site, left-to-right; leftmost wins) layers your cartridge **before** `app_storefront_base`. **Never edit the base cartridge** — place an overriding file in your cartridge so it takes precedence.
- Scaffold with `sgmf-scripts` (`sgmf-scripts --help`; `createCartridge`). Upload/activate a **code version** (B2C CLI / `dw.json`) to deploy.

## Controllers (SFRA)

CommonJS modules exposing routes via `server.get/post(name, ...middleware)`. Build view data and `res.render('template', data)` or `res.json(data)`.

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

Extend base controllers — never copy them:

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

> Caution: `server.append` can re-execute logic — make sure you don't run the controller twice when appending and rendering.

## Script API (`dw.*`)

`Mgr` classes retrieve business objects. Common packages/classes:
- `dw/catalog` — `ProductMgr.getProduct(id)`, `CatalogMgr`, `Product`, price/availability models.
- `dw/order` — `BasketMgr.getCurrentBasket()` / `getCurrentOrNewBasket()`, `OrderMgr`, `Basket`, `Order`.
- `dw/customer` — `CustomerMgr`, `Customer`, `Profile`.
- `dw/system` — `Transaction`, `Site`, `Logger`, `HookMgr`, `Status`, `CacheMgr`.
- `dw/web` — `URLUtils`, `Resource` (i18n).
- `dw/util` — collections, `Calendar`, `HashMap`.

Wrap DML in a transaction:

```javascript
var Transaction = require('dw/system/Transaction');
var BasketMgr   = require('dw/order/BasketMgr');

Transaction.wrap(function () {
    var basket = BasketMgr.getCurrentOrNewBasket();
    basket.createProductLineItem('682875090845M', basket.defaultShipment);
});
```

> Hybrid sites: do **not** use `getCurrentOrNewBasket()` for basket creation; create via SCAPI `POST .../baskets`. `getCurrentBasket()` inside a read-only hook (`beforeGet`/`modifyResponse`) won't update the last-modified date.

## ISML Templates

Server-rendered `.isml`; keep **logic-light** — compute in controllers/models, render in ISML. Use `<isloop>`, `<isif>`, `<isset>`, `<isinclude>`, `<isscript>`, and `${...}`. Embedding Script API calls in ISML via `<isscript>`/`<isset>` is possible but **not recommended**.

## Hooks

CommonJS modules registered for extension points; logic applies to controller and API paths. Functions must be exported.

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

Rules: all registered modules for an extension point run across the cartridge path; **order isn't guaranteed**, and **only the last hook returns a value** (all still execute). Use `HookMgr.callHook(extensionPoint, function, args...)` to invoke custom hooks.

## Jobs Framework

Custom job steps for batch/scheduled work. Two module shapes:

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

Register in **`steptypes.json`** at the cartridge root (one per cartridge):

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

Constraints & best practices: explicit transactions limited to **1,000 modified business objects**; design loops so memory doesn't grow with result-set size; use `getTotalCount` to show progress; use standard imports over custom logic; iterate/run from the B2C CLI `job` commands. `steptypes.json` is parsed at server startup, on code-version change, and (on sandboxes) each run.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Editing `app_storefront_base` | Override via cartridge path |
| Copying a base controller | `server.append/prepend/replace` |
| Re-running the controller via append+render | Append only view data, render once |
| Business logic in ISML | Controllers/models compute; ISML renders |
| DML without `Transaction.wrap` | Wrap data changes in a transaction |
| `getCurrentOrNewBasket()` in hybrid | SCAPI `POST .../baskets` |
| Relying on hook order / multiple return values | Order undefined; only the last returns |
| Row-by-row job over huge data | Chunk module; ≤1,000 objects/transaction |
| Treating this like Node.js/Apex | It's the B2C Commerce Script API runtime |
