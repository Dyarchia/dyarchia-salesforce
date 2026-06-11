# Trigger Framework — Tony Scott (2013), Modernised

Verbatim reference implementation of the trigger pattern enforced by this codebase. Load this file when writing a new trigger, refactoring an existing one, or extending the framework.

The original 2013 pattern used `Trigger.isBefore && Trigger.isInsert` cascades. We keep Scott's interface and factory exactly as he designed them, but switch the dispatch to the modern `Trigger.operationType` enum — the same evolution Scott himself accepted from Steve Cox in 2013 when `Type` replaced strings.

## Notes on alternatives

Kevin O'Hara's `TriggerHandler` (abstract virtual class with `beforeInsert/afterUpdate` etc., plus runtime bypass by name) and `fflib_SObjectDomain` from Apex Enterprise Patterns are also legitimate, actively-maintained options. Any one of them is better than no framework. The non-negotiable is *picking one and applying it everywhere*; what is imposed here is Tony Scott for consistency with the rest of this codebase. If you adopt a different one, do so org-wide — never mix.

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
                // Tony Scott's original ITrigger doesn't include afterUndelete;
                // if you need it, add it to the interface and the handler.
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

One line. No logic. Triggers cannot declare `with sharing` / `without sharing` / `inherited sharing` — that is a compile error in API 67+. Triggers always run in `SYSTEM_MODE`; the sharing declaration lives on the handler class.

```java
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    TriggerFactory.createAndExecuteHandler(AccountHandler.class);
}
```

## The Handler — Skeleton

All trigger logic lives here. The handler has the sharing declaration, encapsulates bulk caching in `bulkBefore`/`bulkAfter`, per-record work in the iterative methods, and accumulated DML in `andFinally`.

```java
public with sharing class AccountHandler implements ITrigger {

    private Set<Id> m_inUseIds = new Set<Id>();
    private List<Audit__c> m_audits = new List<Audit__c>();

    public void bulkBefore() {
        if (Trigger.isDelete) {
            m_inUseIds = AccountGateway.findAccountIdsInUse(Trigger.oldMap.keySet());
        }
    }

    public void bulkAfter() { /* cache cross-object data once for the entire batch */ }

    public void beforeInsert(SObject so) { /* per-record before-insert work */ }
    public void beforeUpdate(SObject oldSo, SObject so) { /* per-record before-update work */ }

    public void beforeDelete(SObject so) {
        Account acc = (Account) so;
        if (m_inUseIds.contains(acc.Id)) {
            so.addError('You cannot delete an Account that is in use.');
        } else {
            m_audits.add(new Audit__c(Description__c = 'Deleted: ' + acc.Name));
        }
    }

    public void afterInsert(SObject so) { /* field validation; record is read-only */ }
    public void afterUpdate(SObject oldSo, SObject so) { /* field validation */ }
    public void afterDelete(SObject so) { /* per-record post-delete */ }

    public void andFinally() {
        // single DML pass for everything accumulated during the iteration
        if (!m_audits.isEmpty()) {
            Database.insert(m_audits, AccessLevel.SYSTEM_MODE); // audit log: justified
        }
    }
}
```

## Recursion Guard

For triggers that may re-fire themselves via DML, use a static guard.

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

## Handler Rules

- One trigger per object. Order of execution between triggers is undefined.
- No logic in the trigger file. One line: `TriggerFactory.createAndExecuteHandler(XxxHandler.class);`.
- No SOQL or DML in the iterative `beforeX`/`afterX` methods. Cache in `bulkBefore`/`bulkAfter`, DML in `andFinally`.
- Field-value validation goes in the `after` methods (the values can still be modified by other before-triggers or workflows).
- Delegate all SOQL to a Gateway/Selector class — no SOQL inside the handler itself.
- For callouts triggered by DML, enqueue ONE Queueable in `andFinally` with the full batch (never a `@future` per iteration).
