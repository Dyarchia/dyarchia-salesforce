# Trigger Framework — Tony Scott (2013), Modernised

Verbatim reference implementation of the trigger pattern this codebase enforces. Load when writing, refactoring or extending a trigger or the framework.

The original 2013 pattern used `Trigger.isBefore && Trigger.isInsert` cascades. We keep Scott's interface and factory as designed but dispatch on the modern `Trigger.operationType` enum — the same evolution Scott accepted from Steve Cox in 2013 when `Type` replaced strings.

## Notes on alternatives

Kevin O'Hara's `TriggerHandler` (abstract virtual class with `beforeInsert/afterUpdate` etc., plus runtime bypass by name) and `fflib_SObjectDomain` from Apex Enterprise Patterns are also legitimate, actively-maintained options; any one beats no framework. The non-negotiable is *picking one and applying it everywhere*; Tony Scott is imposed here for consistency with the rest of this codebase. If you adopt another, do so org-wide — never mix.

## The `ITrigger` Interface

Never modified. Every handler implements it in full.

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

One line, no logic. Declaring `with sharing` / `without sharing` / `inherited sharing` on a trigger is a compile error in API 67+. Triggers always run in `SYSTEM_MODE`; the sharing declaration lives on the handler class.

```java
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    TriggerFactory.createAndExecuteHandler(AccountHandler.class);
}
```

## The Handler — Skeleton

All trigger logic lives here: the sharing declaration, bulk caching in `bulkBefore`/`bulkAfter`, per-record work in the iterative methods, and accumulated DML in `andFinally`.

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

For triggers that may re-fire themselves via DML, use a static guard:

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

Bake the check once into the framework entry point — it resolves the object from the trigger
context, so every framework trigger inherits its own per-object switch and stays a single line:

```java
public static void createAndExecuteHandler(Type handlerType) {
    List<SObject> records = Trigger.new != null ? Trigger.new : Trigger.old;
    if (!TriggerBypass.isEnabled(records[0].getSObjectType())) {
        return;
    }
    ...
}
```

For a trigger that does **not** use the framework (brownfield, legacy), name its object explicitly
as the first statement:

```java
trigger LegacyContactTrigger on Contact (before insert, after update) {
    if (!TriggerBypass.isEnabled(Contact.SObjectType)) {
        return;
    }
    LegacyContactHandler.run();
}
```

The kill-switch is a circuit-breaker, not a recursion guard — keep the recursion handling
regardless. Disabling an object's trigger org-wide is a footgun: prefer Profile or User scope, and
re-enable the moment the bulk operation completes.

## Handler Rules

- One trigger per object. Order of execution between triggers is undefined.
- No logic in the trigger file. One line: `TriggerFactory.createAndExecuteHandler(XxxHandler.class);`.
- No SOQL or DML in the iterative `beforeX`/`afterX` methods. Cache in `bulkBefore`/`bulkAfter`, DML in `andFinally`.
- Field-value validation goes in the `after` methods (other before-triggers or workflows can still modify the values).
- Delegate all SOQL to a Gateway/Selector class — no SOQL inside the handler itself.
- For callouts caused by DML, enqueue ONE Queueable in `andFinally` with the full batch (never a `@future` per iteration).
