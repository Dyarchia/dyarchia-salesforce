# Modern Apex Syntax — Reference (Winter '27 / API v68.0)

Each modern construct beside the legacy form it replaces.

## Safe navigation and null coalescing

```apex
// ✅
String street   = account?.BillingAddress?.Street;
String username = getUserFromSession() ?? 'Guest';
Account acct    = [SELECT Id FROM Account WHERE Name = 'Acme' LIMIT 1] ?? new Account(Name = 'Default');

// ❌
String street = account != null && account.BillingAddress != null ? account.BillingAddress.Street : null;
```

`?.` short-circuits the whole chain to `null` on the first null link. `??` returns the right operand
only when the left is `null` — not when it is empty or zero.

## `switch on` instead of `if/else` chains

Use it when branching on more than two discrete values of one variable. It is exhaustive over enums.

```apex
switch on Trigger.operationType {
    when BEFORE_INSERT { handler.beforeInsert(); }
    when AFTER_UPDATE  { handler.afterUpdate(); }
    when else          { /* no-op */ }
}
```

`Trigger.operationType` is the type-safe enum form of `Trigger.isBefore && Trigger.isInsert`
cascades: the compiler catches a missing case, string comparison does not.

## Multiline string literals (API 67.0+)

Use them for any string spanning more than one logical line, replacing `+` concatenation or embedded `\n`.

```apex
// ✅
String payload = '''
{
  "currency": "USD",
  "amount": 1500
}
''';

// ❌
String payload = '{\n  "currency": "USD",\n  "amount": 1500\n}';
```

## String templates (API 67.0+)

`.template(Map<String, Object>)` interpolates named placeholders. Use it instead of `+`
concatenation or `String.format(..., new String[]{...})`, both of which lose the placeholder–value
association.

```apex
// ✅
String message = '''
Hello ${firstName},
Your order was dispatched on ${dispatchDate}.
'''.template(new Map<String, Object>{
    'firstName'    => contact.FirstName,
    'dispatchDate' => order.ShipDate__c
});

// ❌
String message = 'Hello ' + contact.FirstName + ',\nYour order was dispatched on ' + order.ShipDate__c + '.';
```

## Assertions

```apex
// ✅
Assert.areEqual(expected, actual, 'Account count should match');
Assert.isTrue(result.isSuccess());
Assert.isNotNull(account.Id);
Assert.fail('Should have thrown');

// ❌ — legacy, no failure-message discipline
System.assertEquals(expected, actual);
```

Always pass the message: without one, a failing assertion tells you a number differed, not which
business rule broke.

## Schema references, never strings

```apex
// ✅
String objectName = Account.SObjectType.getDescribe().getName();
Schema.SObjectField nameField = Account.Name;

// ❌ — silently survives a rename, fails at runtime
String objectName = 'Account';
```

Use schema references; they break the build when the metadata changes. String literals for object
and field names are invisible to the compiler and to "where is this used" tooling.

## Collection initialisers

```apex
Map<String, Object> binds = new Map<String, Object>{
    'industry' => industryFilter,
    'minRev'   => 1000000
};
Set<Id> ids = new Set<Id>{ a.Id, b.Id };
List<String> names = new List<String>{ 'Acme', 'Globex' };
```

## Anti-Patterns

| Anti-Pattern | Modern replacement |
|---|---|
| Verbose null-check ladders | `?.` and `??` |
| `if/else` chain on a single variable | `switch on` |
| `Trigger.isBefore && Trigger.isInsert` | `Trigger.operationType == BEFORE_INSERT` |
| `'a' + '\n' + 'b'` across lines | Multiline literal `'''…'''` |
| `String.format(tmpl, new String[]{...})` | `'''…${name}…'''.template(new Map<String,Object>{...})` |
| `System.assertEquals(...)` | `Assert.areEqual(..., 'message')` |
| `'Account.Name'` as a string | `Account.Name` schema reference |
