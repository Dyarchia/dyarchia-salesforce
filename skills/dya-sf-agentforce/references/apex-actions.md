# Agentforce Apex Actions — Reference (Winter '27 / API v68.0)

`@InvocableMethod` actions in depth. Choosing an action type, Agent Script wiring, display flags and
the security model: `references/agent-actions.md`. The rules in `dya-sf-apex` apply on top.

## 1. The invocable contract

| Rule | Detail |
|---|---|
| One per class | A class holds at most one `@InvocableMethod` |
| Shape | `public` or `global`, `static`, in an outer class |
| Parameter | One `List<Request>`; the agent and Flow always pass a list, even for one call |
| Return | `List<Result>`, one result per request, in request order |
| Method attributes | `label`, `description`, `category`, `callout=true` when the method makes a callout |
| Variable attributes | `label`, `description`, `required` on each non-static `public` / `global` field |

Agentforce Builder lists the method under Reference Action Type **Apex**, category **Invocable
Method**; Agent Script reaches it with `target: "apex://<ClassName>"`.

## 2. How the signature becomes the action

- **Field names are the parameter keys.** `public String order_number;` binds to `order_number:` in
  the script's `inputs:`, case-sensitive. Choose field names you want in the script; renaming a field
  breaks the binding until the script changes too.
- `required=true` → `is_required: True`; `label` and `description` seed the action's own.
- **Write `description` on the method and every variable as routing copy:** the LLM decides whether
  to call the action and how to fill each input from them. Describe format and examples
  (`'Maximum price in dollars, as a number, e.g. 200'`), and on outputs say what an empty value means.

| Apex field type | Agent Script declaration |
|---|---|
| `String`, `Id` | `string` |
| `Boolean` | `boolean` |
| `Decimal` | `number` |
| `Date` (input) | `object` + `complex_data_type_name: "lightning__dateType"` |
| Apex-defined class | `object` + `complex_data_type_name: "@apexClassType/c__<ClassName>"` |
| A list of an Apex-defined class | `list[object]` + `"@apexClassType/c__<ElementClass>"` |

For any other type, add the action in Agentforce Builder and keep the declaration it generates.

## 3. Complex inputs and outputs

Use an Apex-defined class when a parameter is structured (a filter set, a list of offers). It is also
the only route to a custom Lightning type UI: custom rendering applies only to actions whose inputs
or outputs are Apex classes.

```apex
@JsonAccess(serializable='always' deserializable='always')
global class OfferList {
    @AuraEnabled global List<Offer> offers;
}
```

```apex
@JsonAccess(serializable='always' deserializable='always')
global class Offer {
    @AuraEnabled global String code;
    @AuraEnabled global String title;
    @AuraEnabled global Decimal monthlyPrice;
}
```

- Mark the data classes `@JsonAccess(serializable='always' deserializable='always')` and their
  fields `@AuraEnabled`, as the official Lightning type examples do.
- Make every class referenced through `@apexClassType` a **top-level** class; `c__` is the prefix
  for classes without a namespace.
- The request / response wrappers carry the `@InvocableVariable` fields; the classes they reference
  carry `@AuraEnabled` fields.

```agentscript
outputs:
    offer_list: object
        label: "Offers"
        complex_data_type_name: "@apexClassType/c__OfferList"
        is_displayable: True
```

## 4. Canonical action

```apex
public with sharing class GetOrderStatusAction {

    public class Request {
        @InvocableVariable(label='Order Number' description='Order number the customer gives, e.g. 00000123' required=true)
        public String order_number;
        @InvocableVariable(label='Contact Id' description='Id of the verified contact asking' required=true)
        public Id contact_id;
    }

    public class Result {
        @InvocableVariable(label='Found' description='True when the order exists and belongs to the contact')
        public Boolean found;
        @InvocableVariable(label='Status' description='Order status to tell the customer')
        public String status;
        @InvocableVariable(label='Message' description='Outcome to relay; when Found is false, say the order could not be found and ask the customer to check the number')
        public String message;
    }

    @InvocableMethod(
        label='Get Order Status'
        description='Returns the status of one order owned by the verified contact. Use when a customer asks where their order is.'
        category='Orders'
    )
    public static List<Result> run(List<Request> requests) {
        Set<String> orderNumbers = new Set<String>();
        for (Request req : requests) {
            orderNumbers.add(req.order_number);
        }

        Map<String, Order> ordersByNumber = new Map<String, Order>();
        for (Order o : [
            SELECT OrderNumber, Status, BillToContactId
            FROM Order
            WHERE OrderNumber IN :orderNumbers
            WITH USER_MODE
        ]) {
            ordersByNumber.put(o.OrderNumber, o);
        }

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Order o = ordersByNumber.get(req.order_number);
            Result res = new Result();
            res.found = o != null && o.BillToContactId == req.contact_id;  // ✅ ownership re-checked
            res.status = res.found ? o.Status : null;
            res.message = res.found ? 'Order found.' : 'No order with that number for this customer.';
            results.add(res);
        }
        return results;
    }
}
```

- The agent supplies `contact_id` from a verified variable, never from slot-filling; see
  `references/agent-actions.md` §4.
- A not-found order returns a value, not an exception, so the LLM has something true to say.

## 5. Bulk in, bulk out

An agent passes one request per call, but a Flow reusing the method passes a whole batch.

```apex
Request req = requests[0];                  // ❌ silently drops every other request
for (Request req : requests) { ... }        // ✅ one result per request, same order
```

- Query once for the whole list, map the rows, then build results; DML once, after the loop.
- Return exactly `requests.size()` results.
- Each agent call runs in its own transaction; the governor budget it spends is in
  `references/shared/governor-limits.md`.

## 6. Security inside the method

- Declare `with sharing` on the action class.
- Use `WITH USER_MODE` on SOQL, `Database.queryWithBinds(query, binds, AccessLevel.USER_MODE)` on
  dynamic SOQL, `AccessLevel.USER_MODE` on DML. The running user is the agent user for a service
  agent, so its permission sets decide what the action can see.
- **Bind, never concatenate,** values the LLM supplied into dynamic SOQL.

```apex
String soql = 'SELECT Id, Name FROM Product2 WHERE IsActive = true AND Family = :family';
List<Product2> rows = Database.queryWithBinds(
    soql, new Map<String, Object>{ 'family' => req.category }, AccessLevel.USER_MODE);  // ✅
List<Product2> unsafe = Database.query(
    'SELECT Id FROM Product2 WHERE Family = \'' + req.category + '\'');               // ❌ injectable, system mode
```

- Re-derive authorization from records, not from inputs: an LLM-filled Id is a claim, not proof.
- Grant the agent user access to the action class **and every class it calls**:

```xml
<classAccesses>
    <apexClass>GetOrderStatusAction</apexClass>
    <enabled>true</enabled>
</classAccesses>
```

## 7. Errors

- **Return failures as values:** a `found` / `success` flag plus a message the agent can relay, and
  describe in the output's `description` what the agent must do with it.
- Use partial-success DML and map each `SaveResult` back to its request:

```apex
Database.SaveResult[] saves = Database.insert(cases, false, AccessLevel.USER_MODE);
for (Integer i = 0; i < saves.size(); i++) {
    Result res = new Result();
    res.success = saves[i].isSuccess();
    res.message = res.success ? 'Case created.' : 'The case could not be created.';
    if (!res.success) {
        System.debug(LoggingLevel.ERROR, 'Case insert failed: ' + saves[i].getErrors()[0].getMessage());
    }
    results.add(res);
}
```

- Keep internal detail (stack traces, field API names) out of the message; record it with
  `System.debug` at a level, or through the error handling the org already has (`dya-sf-apex`).
- A method shared with Flow faces the opposite convention: a thrown exception is how a Flow reaches
  its Fault Path. Return the result and let the Flow branch on the flag. See `dya-sf-flow`.

## 8. Callouts

- Set `callout=true` on the `@InvocableMethod` when it calls out.
- Make the callout before any DML in the transaction; a callout after uncommitted DML throws a
  `CalloutException`.
- Call through a named credential; endpoint, auth and retry rules live in
  `dya-sf-integration-outbound`.

## 9. Citations

To cite sources in the agent's answer, add a citation-typed output to the result class:

| Output type | Use |
|---|---|
| `AiCopilot.GenAiCitationInput` | Hand source references to the reasoning engine, which places the citations |
| `AiCopilot.GenAiCitationOutput` | Supply finished citations directly |

```apex
public class Result {
    @InvocableVariable(required=true description='Answer text')
    public String answer;
    @InvocableVariable(required=true description='Sources behind the answer')
    public AiCopilot.GenAiCitationInput sources;
}
```

Build `sources` from `AiCopilot.GenAiSourceReference` items (content plus link and record
metadata), typically transformed from a prompt template's `ConnectApi` generation response. The
`label` on each citation is customisable; the end user must be able to open its URL. Platform
citations require an active agent created after 26 May 2025.

## 10. Testing

- Unit-test the static method directly with a `List<Request>` of several rows, including one that
  must fail; assert one result per request, in order (`dya-sf-apex` covers test structure).
- Run the test as a user with the agent user's permission sets (`System.runAs`) to prove the
  `USER_MODE` paths.
- Deploy the class before previewing; preview live with Apex debugging:

```bash
sf project deploy start --metadata "ApexClass:GetOrderStatusAction"
sf agent preview --authoring-bundle Order_Agent --use-live-actions --apex-debug
```

## 11. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| `requests[0]` only | Loop every request; return one result per request |
| Scalar parameters with no wrapper | `Request` / `Result` classes with `@InvocableVariable` fields |
| Missing or vague `description`s | Format, example and meaning on the method and every variable |
| Renaming a field without the script | Change the field and the Agent Script key together |
| No sharing keyword, `WITH SECURITY_ENFORCED` | `with sharing`, `WITH USER_MODE`, `AccessLevel.USER_MODE` |
| String-concatenated dynamic SOQL | `Database.queryWithBinds` with `AccessLevel.USER_MODE` |
| Trusting an LLM-supplied Id | Re-check ownership against the record |
| `throw` to the agent | A status flag and message output |
| Raw exception text in the message | Plain message out; detail to `System.debug` with a level |
| Nested data classes referenced by `@apexClassType` | Top-level classes with `@JsonAccess` and `@AuraEnabled` fields |
| SOQL or DML inside the loop | Query before, DML once after |
| Callout after DML | Callout first, or move the DML out of the transaction |
| Forgetting class access for helpers | `classAccesses` for the action and every class it calls |
| One giant multi-purpose action | Several narrow, well-described actions |
