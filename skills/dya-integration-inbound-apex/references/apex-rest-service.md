# Apex REST Service — Reference Implementation (API v67.0)

Load from `dya-integration-inbound-apex` when building a custom inbound REST endpoint. Apex REST is GA and recommended; this is the canonical multi-verb, transactional, securely-bounded service. Deep Apex rules (bulkification, async, logging) live in `dya-apex`.

## Full Service

```apex
/**
 * Inbound order API. External system POSTs an order with line items;
 * we create the order + lines transactionally and return a stable contract.
 */
@RestResource(urlMapping='/v1/orders/*')
global with sharing class OrderApi {

    // ---- Contracts (versioned DTOs) ----
    global class LineDto {
        global String sku;
        global Integer quantity;
    }
    global class RequestDto {
        global String externalId;     // for idempotency
        global String accountExtId;
        global List<LineDto> lines;
    }
    global class ResponseDto {
        global Boolean success;
        global String orderId;
        global String message;
        global ResponseDto(Boolean s, String id, String m) { success = s; orderId = id; message = m; }
    }

    // ---- POST: create an order (idempotent via externalId) ----
    @HttpPost
    global static ResponseDto createOrder(RequestDto payload) {
        try {
            if (payload == null || String.isBlank(payload.externalId)) {
                RestContext.response.statusCode = 400;
                return new ResponseDto(false, null, 'externalId is required');
            }

            // Resolve parent by external id, user-mode enforced
            List<Account> accts = [
                SELECT Id FROM Account
                WHERE External_Id__c = :payload.accountExtId
                WITH USER_MODE LIMIT 1
            ];
            if (accts.isEmpty()) {
                RestContext.response.statusCode = 422;
                return new ResponseDto(false, null, 'Unknown account');
            }

            // Idempotent upsert of the order by its external id
            Order__c ord = new Order__c(
                External_Id__c = payload.externalId,
                Account__c     = accts[0].Id
            );
            Database.upsert(ord, Order__c.External_Id__c, AccessLevel.USER_MODE);

            // Bulk-build children, single DML
            List<Order_Line__c> lines = new List<Order_Line__c>();
            if (payload.lines != null) {
                for (LineDto l : payload.lines) {
                    lines.add(new Order_Line__c(Order__c = ord.Id, SKU__c = l.sku, Quantity__c = l.quantity));
                }
            }
            if (!lines.isEmpty()) {
                Database.insert(lines, false, AccessLevel.USER_MODE);
            }

            RestContext.response.statusCode = 201;
            return new ResponseDto(true, ord.Id, 'Created');

        } catch (Exception e) {
            // Log durably (Platform Event → log object); never leak the stack trace
            RestContext.response.statusCode = 500;
            return new ResponseDto(false, null, 'Could not process the order.');
        }
    }

    // ---- GET: fetch an order by id from the URL ----
    @HttpGet
    global static ResponseDto getOrder() {
        String orderId = RestContext.request.requestURI.substringAfterLast('/');
        List<Order__c> orders = [
            SELECT Id, Name FROM Order__c WHERE Id = :orderId WITH USER_MODE LIMIT 1
        ];
        if (orders.isEmpty()) {
            RestContext.response.statusCode = 404;
            return new ResponseDto(false, null, 'Not found');
        }
        return new ResponseDto(true, orders[0].Id, 'OK');
    }

    // ---- DELETE ----
    @HttpDelete
    global static void deleteOrder() {
        String orderId = RestContext.request.requestURI.substringAfterLast('/');
        Database.delete(new Order__c(Id = orderId), AccessLevel.USER_MODE);
        RestContext.response.statusCode = 204;
    }
}
```

## Rules Embodied Above

- **`global with sharing`** class; **`global static`** methods, one annotation per verb.
- **User-mode security**: `WITH USER_MODE` on SOQL, `AccessLevel.USER_MODE` on DML — correct and required at v67 (`WITH SECURITY_ENFORCED` would not compile).
- **Idempotency**: upsert by external id so a retried POST updates rather than duplicates.
- **Bulk**: children built in a list, one DML. No DML/SOQL in loops.
- **Stable contract**: explicit DTOs and a versioned URL (`/v1/orders/`).
- **HTTP semantics**: 201 create, 204 delete, 400/422 validation, 404 not found, 500 with a clean message.
- **No leaked internals**: catch, log durably, return a sanitised message.

## Raw Body / Headers When You Need Them

```apex
@HttpPost
global static void webhook() {
    RestRequest req = RestContext.request;
    Blob raw = req.requestBody;                       // raw payload (e.g. to verify a signature)
    String sig = req.headers.get('X-Signature');      // custom header
    // verify signature before trusting the body...
    RestContext.response.statusCode = 200;
}
```

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| `@RestResource` for plain CRUD | Standard REST API |
| SOQL/DML in a loop in the handler | Bulk before/after the loop |
| Blind insert on a retried POST | Upsert by external id |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` |
| No sharing keyword at v67 | Explicit `with sharing` |
| Returning the exception/stack trace | Sanitised error DTO + status code |
| Unversioned URL/contract | `/v1/...` and versioned DTOs |
| Trusting a webhook body without verifying | Verify signature from the raw body + header |
