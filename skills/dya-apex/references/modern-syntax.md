# Modern Apex Syntax — Reference (Winter '27 / API v68.0)

Load from `dya-apex` when writing or refactoring code and you need the exact form of a modern
construct. Everything here is the current idiom; the older equivalent it replaces is shown so you
can recognise what to change.

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

Use whenever branching on more than two discrete values of one variable. It is exhaustive over enums
and reads as a table rather than a ladder.

```apex
switch on Trigger.operationType {
    when BEFORE_INSERT { handler.beforeInsert(); }
    when AFTER_UPDATE  { handler.afterUpdate(); }
    when else          { /* no-op */ }
}
```

`Trigger.operationType` is the type-safe enum form of `Trigger.isBefore && Trigger.isInsert`
cascades. Prefer it: the compiler catches a missing case, string comparison does not.

## Multiline string literals (API 67.0+)

For any string spanning more than one logical line. Concatenating with `+` or embedding `\n` is the
pattern this replaces.

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
concatenation or `String.format(..., new String[]{...})`, both of which lose the association between
placeholder and value.

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

Combined with multiline literals this removes almost every legitimate use of `+` on strings.

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

Always pass the message argument. A failing assertion without one tells you a number differed, not
which business rule broke.

## Schema references, never strings

```apex
// ✅
String objectName = Account.SObjectType.getDescribe().getName();
Schema.SObjectField nameField = Account.Name;

// ❌ — silently survives a rename, fails at runtime
String objectName = 'Account';
```

String literals for object and field names are invisible to the compiler and to "where is this
used" tooling. Schema references break the build the moment the metadata changes, which is what you
want.

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
