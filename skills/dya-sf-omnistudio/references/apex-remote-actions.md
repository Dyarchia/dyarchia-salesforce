# OmniStudio — Apex Remote Actions (real contract)

Load from `dya-sf-omnistudio`. `dya-sf-apex` rules apply.

## Standard vs Managed Package — which interface

| | OmniStudio Standard | OmniStudio for Vlocity (Managed Package) |
|---|---|---|
| Namespace | `omnistudio` | industry: `vlocity_cmt` / `vlocity_ins` / `vlocity_ps` |
| Apex contract | implement **`Callable`** (Salesforce standard) | extend **`VlocityOpenInterface`** or **`VlocityOpenInterface2`** |
| Entry method | `Object call(String action, Map<String,Object> args)` | `Boolean invokeMethod(String methodName, Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options)` |

Confirm the org's flavor first; the wrong interface or namespace is the most common failure.

## Standard — `Callable`

```apex
global with sharing class AccountRemoteActions implements Callable {
    // ONE args map; unpack input/output/options.
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

Sample: `SKILL.md` section 2.

`VlocityOpenInterface` is the older single-method variant; prefer `VlocityOpenInterface2`. The namespace prefix — `vlocity_cmt` (Comms/Media), `vlocity_ins` (Insurance), `vlocity_ps` (Public Sector) — depends on the installed industry package.

## Registering & Calling

- In the **Remote Action** element (IP, OmniScript, or FlexCard): set **Remote Class** = the Apex class name and **Remote Method** = the dispatched `methodName`.
- Map element inputs to the `input` map; read results from the `output`/`outMap` node.

## Rules

- `with sharing` unless justified.
- One class can host many methods.
- **`WITH USER_MODE`** SOQL / `AccessLevel.USER_MODE` or `as user` DML.
- **Test** the class as normal Apex and through the component.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Hard-coding the wrong managed namespace | Confirm `vlocity_cmt`/`vlocity_ins`/`vlocity_ps` |
