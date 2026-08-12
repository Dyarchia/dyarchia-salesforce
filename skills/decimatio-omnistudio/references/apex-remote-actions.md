# OmniStudio — Apex Remote Actions (real contract)

Load from `decimatio-omnistudio`. The exact contract for calling custom Apex from FlexCards, OmniScripts, and Integration Procedures, for both flavors. It's Apex — `decimatio-apex` rules apply (bulk, `with sharing`, `WITH USER_MODE`, no SOQL/DML in loops).

## Standard vs Managed Package — which interface

| | OmniStudio Standard | OmniStudio for Vlocity (Managed Package) |
|---|---|---|
| Namespace | `omnistudio` | industry: `vlocity_cmt` / `vlocity_ins` / `vlocity_ps` |
| Apex contract | implement **`Callable`** (Salesforce standard) | extend **`VlocityOpenInterface`** or **`VlocityOpenInterface2`** |
| Entry method | `Object call(String action, Map<String,Object> args)` | `Boolean invokeMethod(String methodName, Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options)` |

Confirm the org's flavor first — using the wrong interface/namespace is the most common failure.

## Standard — `Callable`

```apex
global with sharing class AccountRemoteActions implements Callable {
    // OmniStudio Standard passes ONE args map; unpack input/output/options.
    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> input   = (Map<String, Object>) args.get('input');
        Map<String, Object> output  = (Map<String, Object>) args.get('output');
        Map<String, Object> options = (Map<String, Object>) args.get('options');
        return invokeMethod(action, input, output, options);
    }

    private Boolean invokeMethod(String methodName, Map<String,Object> input,
                                 Map<String,Object> output, Map<String,Object> options) {
        switch on methodName {
            when 'getContacts' { return getContacts(input, output); }
            when 'updateRating' { return updateRating(input, output); }
            when else { return false; }
        }
    }

    private Boolean getContacts(Map<String,Object> input, Map<String,Object> output) {
        Id accountId = (Id) input.get('accountId');
        output.put('contacts', [
            SELECT Id, Name, Email FROM Contact WHERE AccountId = :accountId WITH USER_MODE LIMIT 200
        ]);
        return true;
    }

    private Boolean updateRating(Map<String,Object> input, Map<String,Object> output) {
        try {
            update as user new Account(Id = (Id) input.get('accountId'), Rating = (String) input.get('rating'));
            output.put('success', true);
            return true;
        } catch (DmlException e) {
            output.put('success', false);
            output.put('error', e.getMessage());   // structured error, not a raw throw
            return false;
        }
    }
}
```

## Managed Package — `VlocityOpenInterface2`

```apex
global with sharing class AccountRemoteActions implements vlocity_cmt.VlocityOpenInterface2 {
    global Boolean invokeMethod(String methodName, Map<String,Object> input,
                                Map<String,Object> outMap, Map<String,Object> options) {
        Boolean result = true;
        try {
            if ('getContacts'.equalsIgnoreCase(methodName)) {
                getContacts(input, outMap, options);
            } else {
                result = false;
            }
        } catch (Exception e) {
            outMap.put('error', e.getMessage());
            result = false;
        }
        return result;
    }
    public void getContacts(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options) {
        Id accountId = (Id) input.get('accountId');
        outMap.put('contacts', [SELECT Id, Name, Email FROM Contact WHERE AccountId = :accountId WITH USER_MODE]);
    }
}
```

(`VlocityOpenInterface` is the older single-method variant; `VlocityOpenInterface2` is preferred. The namespace prefix — `vlocity_cmt` (Comms/Media), `vlocity_ins` (Insurance), `vlocity_ps` (Public Sector) — varies by the installed industry package.)

## Registering & Calling

- In the **Remote Action** element (IP, OmniScript, or FlexCard): set **Remote Class** = the Apex class name and **Remote Method** = the dispatched `methodName`.
- Map element inputs to the `input` map; read results from the `output`/`outMap` node.
- For non-blocking IP invoke mode, map the **Response JSON Node / Path** so downstream elements get the result.

## Rules

- **`global` class** (required for invocation), `with sharing` unless justified.
- **Dispatch on `methodName`** — one class can host many methods.
- **Read `input`, write `output`/`outMap`, read `options`**; return `Boolean` success.
- **Bulk-safe**, **`WITH USER_MODE`** SOQL / `AccessLevel.USER_MODE` or `as user` DML (no `WITH SECURITY_ENFORCED` at v67).
- **Structured errors** in the output map; don't throw raw exceptions to the runtime.
- **Test** the class as normal Apex plus through the component.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Wrong interface for the flavor | `Callable` (Standard) vs `VlocityOpenInterface2` (Managed) |
| Class not `global` | `global with sharing` |
| SOQL/DML in a loop | Bulkify |
| Throwing raw exceptions | Structured `error` in output, return `false` |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` |
| Apex for what a Data Mapper/IP does | Declarative tool; Apex for the inexpressible |
| Hard-coding the wrong managed namespace | Confirm `vlocity_cmt`/`vlocity_ins`/`vlocity_ps` |
