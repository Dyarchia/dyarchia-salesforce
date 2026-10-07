# Trigger Framework — Tony Scott (2013), Modernised

Verbatim reference implementation of the trigger pattern this codebase enforces.

Keep Scott's interface and factory, but dispatch on the modern `Trigger.operationType` enum instead of the original 2013 `Trigger.isBefore && Trigger.isInsert` cascades — the same kind of change Scott accepted from Steve Cox in 2013 when `Type` replaced strings.

## Notes on alternatives

Kevin O'Hara's `TriggerHandler` (abstract virtual class with `beforeInsert/afterUpdate` etc., plus runtime bypass by name) and `fflib_SObjectDomain` from Apex Enterprise Patterns are also legitimate, maintained options; any one beats none. Use Tony Scott for consistency with the rest of this codebase. Apply whichever you adopt org-wide — never mix.

## The `ITrigger` Interface

Never modify it. Implement it in full in every handler.

```java
/**
 * Interface containing methods Trigger Handlers must implement.
 * Source: Tony Scott, 2013 — Trigger Pattern for Tidy, Streamlined, Bulkified Triggers.
 */
public interface ITrigger {
    void bulkBefore();
    void bulkAfter();
    void beforeInsert(SObject so);
    void beforeUpdate(SObject oldSo, SObject so);
    void beforeDelete(SObject so);
    void afterInsert(SObject so);
    void afterUpdate(SObject oldSo, SObject so);
    void afterDelete(SObject so);
    void andFinally();
}
```

## The `TriggerFactory`

```java
public with sharing class TriggerFactory {

    public static void createAndExecuteHandler(Type t) {
        ITrigger handler = getHandler(t);
        if (handler == null) {
            throw new TriggerException('No Trigger Handler found named: ' + t.getName());
        }
        execute(handler);
    }

    private static void execute(ITrigger handler) {
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                handler.bulkBefore();
                for (SObject so : Trigger.new) { handler.beforeInsert(so); }
            }
            when BEFORE_UPDATE {
                handler.bulkBefore();
                for (SObject so : Trigger.old) {
                    handler.beforeUpdate(so, Trigger.newMap.get(so.Id));
                }
            }
            when BEFORE_DELETE {
                handler.bulkBefore();
                for (SObject so : Trigger.old) { handler.beforeDelete(so); }
            }
            when AFTER_INSERT {
                handler.bulkAfter();
                for (SObject so : Trigger.new) { handler.afterInsert(so); }
            }
            when AFTER_UPDATE {
                handler.bulkAfter();
                for (SObject so : Trigger.old) {
                    handler.afterUpdate(so, Trigger.newMap.get(so.Id));
                }
            }
            when AFTER_DELETE {
                handler.bulkAfter();
                for (SObject so : Trigger.old) { handler.afterDelete(so); }
            }
            when AFTER_UNDELETE {
                // Scott's original ITrigger has no afterUndelete;
                // if needed, add it to the interface and the handler.
                handler.bulkAfter();
            }
            when else { /* unreachable for trigger context */ }
        }
        handler.andFinally();
    }

    private static ITrigger getHandler(Type t) {
        Object o = t.newInstance();
        if (!(o instanceOf ITrigger)) { return null; }
        return (ITrigger) o;
    }

    public class TriggerException extends Exception {}
}
```

## The Trigger File

```java
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    TriggerFactory.createAndExecuteHandler(AccountHandler.class);
}
```

## The Handler — Skeleton

```java
public with sharing class AccountHandler implements ITrigger {

    private Set<Id> m_inUseIds = new Set<Id>();
    private List<Task> m_followUps = new List<Task>();

    public void bulkBefore() {
        if (Trigger.isDelete) {
            m_inUseIds = AccountGateway.findAccountIdsInUse(Trigger.oldMap.keySet());
        }
    }

    public void bulkAfter() { /* cache cross-object data once for the batch */ }

    public void beforeInsert(SObject so) { /* per-record before-insert work */ }
    public void beforeUpdate(SObject oldSo, SObject so) { /* per-record before-update work */ }

    public void beforeDelete(SObject so) {
        Account acc = (Account) so;
        if (m_inUseIds.contains(acc.Id)) {
            so.addError('You cannot delete an Account that is in use.');
        } else {
            m_followUps.add(new Task(Subject = 'Account deleted: ' + acc.Name));
        }
    }

    public void afterInsert(SObject so) { /* field validation; record is read-only */ }
    public void afterUpdate(SObject oldSo, SObject so) { /* field validation */ }
    public void afterDelete(SObject so) { /* per-record post-delete */ }

    public void andFinally() {
        // single DML pass for everything accumulated
        if (!m_followUps.isEmpty()) {
            Database.insert(m_followUps, AccessLevel.USER_MODE);
        }
    }
}
```

## Recursion Guard

For a trigger that can re-fire itself through DML, use a static guard:

```java
public with sharing class AccountHandler implements ITrigger {
    private static Boolean alreadyProcessed = false;

    public void bulkBefore() {
        if (alreadyProcessed) return;
        alreadyProcessed = true;
        // ...
    }
    // ... other ITrigger methods omitted ...
}
```

## Per-Object Kill-Switch — `TriggerBypass`

`Trigger_Settings__c` is a Hierarchy Custom Setting carrying one Checkbox field per controlled
object, named `<Object>_Trigger_Enabled__c` with the `__c` of custom objects stripped
(`Invoice__c` → `Invoice_Trigger_Enabled__c`) and **Default Value = Checked**. An object with no
matching field always runs.

```java
public with sharing class TriggerBypass {
    private static final Map<String, Schema.SObjectField> FIELDS =
        Trigger_Settings__c.SObjectType.getDescribe().fields.getMap();

    public static Boolean isEnabled(SObjectType sObjType) {
        String field = sObjType.getDescribe().getName().replace('__c', '') + '_Trigger_Enabled__c';
        if (!FIELDS.containsKey(field.toLowerCase())) {
            return true;
        }
        Object value = Trigger_Settings__c.getInstance().get(field);
        return value == null ? true : (Boolean) value;
    }
}
```

Put the check once in the framework entry point; it resolves the object from the trigger context,
so every framework trigger gets its own per-object switch and stays one line:

```java
public static void createAndExecuteHandler(Type handlerType) {
    List<SObject> records = Trigger.new != null ? Trigger.new : Trigger.old;
    if (!TriggerBypass.isEnabled(records[0].getSObjectType())) {
        return;
    }
    ...
}
```

For a trigger that does **not** use the framework (brownfield, legacy), name its object in the
first statement:

```java
trigger LegacyContactTrigger on Contact (before insert, after update) {
    if (!TriggerBypass.isEnabled(Contact.SObjectType)) {
        return;
    }
    LegacyContactHandler.run();
}
```

Avoid disabling an object's trigger org-wide: prefer Profile or User scope, and re-enable as soon
as the bulk operation completes.
