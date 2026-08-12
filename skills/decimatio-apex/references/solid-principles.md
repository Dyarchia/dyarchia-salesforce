# SOLID Principles in Apex

Salesforce developers routinely skip SOLID — a trigger or a "quick" service class always
looks too small to bother. It is not. The Service / Selector / Domain layering in the main
skill **is** SOLID applied; this reference makes the mapping explicit and shows the concrete
failure mode for each principle, with Summer '26 / API v67.0 syntax.

Apply SOLID **first**. Most Salesforce "architecture" problems are a missing SRP split or a
hard-wired dependency — not a missing design pattern. SOLID first, named patterns second.

---

## S — Single Responsibility Principle

One class, one reason to change. The canonical violation is the god handler that queries,
mutates, calls out, and notifies in a single method.

**Violation**

```java
public with sharing class AccountTriggerHandler {
    public void afterInsert(List<Account> accts) {
        List<Contact> contacts = [
            SELECT Id, AccountId FROM Contact WHERE AccountId IN :accts WITH USER_MODE
        ];
        for (Account a : accts) { a.Description = 'Onboarded'; }
        update accts;
        Http http = new Http();
        http.send(buildCrmRequest(accts));
    }
}
```

**Compliant** — each layer owns one concern; the handler only orchestrates.

```java
public with sharing class AccountTriggerHandler {
    public void afterInsert(List<Account> accts) {
        AccountService.onboard(accts);
    }
}

public with sharing class AccountService {
    public static void onboard(List<Account> accts) {
        Map<Id, List<Contact>> contactsByAccount = AccountSelector.contactsByAccount(accts);
        ...
        System.enqueueJob(new CrmSyncQueueable(accts));
    }
}
```

- **Selector** owns SOQL. **Service** owns business rules. **Domain** owns per-record logic.
  **Handler** owns nothing but dispatch.

---

## O — Open/Closed Principle

Open for extension, closed for modification. Adding a behaviour should mean a **new class**,
not editing a growing `switch` inside an existing one.

**Violation** — every new tier reopens and rewrites the method.

```java
public Decimal discountFor(Account a) {
    switch on a.Tier__c {
        when 'Gold'   { return 0.20; }
        when 'Silver' { return 0.10; }
        when else     { return 0; }
    }
}
```

**Compliant** — register a rule, never rewrite the engine.

```java
public interface IDiscountRule {
    Decimal rate(Account a);
}

public class GoldDiscount implements IDiscountRule {
    public Decimal rate(Account a) { return 0.20; }
}

public with sharing class DiscountEngine {
    private static final Map<String, IDiscountRule> RULES = new Map<String, IDiscountRule>{
        'Gold'   => new GoldDiscount(),
        'Silver' => new SilverDiscount()
    };
    public Decimal rateFor(Account a) {
        return RULES.containsKey(a.Tier__c) ? RULES.get(a.Tier__c).rate(a) : 0;
    }
}
```

A new tier is a new `IDiscountRule` class plus one registration. The dispatch logic stays
closed. In an org with the Trigger Actions Framework the same idea is expressed as one
`TriggerAction` class per behaviour.

---

## L — Liskov Substitution Principle

A subtype must honour the base contract: no throwing on a method the base promises, no
weakening of post-conditions. A caller holding the base type must never break.

**Violation** — the cache cannot keep the write promise it inherited.

```java
public virtual class AccountSelector {
    public virtual List<Account> selectByIds(Set<Id> ids) { ... }
    public virtual void persist(List<Account> accts) { update accts; }
}

public class CachedAccountSelector extends AccountSelector {
    public override void persist(List<Account> accts) {
        throw new UnsupportedOperationException('read-only cache');
    }
}
```

**Compliant** — split the contract so nothing promises a write it cannot do. This is LSP
solved by ISP.

```java
public interface IAccountReader {
    List<Account> selectByIds(Set<Id> ids);
}

public interface IAccountWriter {
    void persist(List<Account> accts);
}
```

The cache implements only `IAccountReader`; any reference to it is always substitutable.

---

## I — Interface Segregation Principle

Many small interfaces beat one fat one. A consumer depends only on what it uses — and a
mock only has to stub what it uses.

**Violation** — every stub must fake reads, writes, sync, and email.

```java
public interface IAccountService {
    List<Account> selectByIds(Set<Id> ids);
    void persist(List<Account> accts);
    void syncToCrm(List<Account> accts);
    void emailOwners(List<Account> accts);
}
```

**Compliant** — segregate by capability.

```java
public interface IAccountReader { List<Account> selectByIds(Set<Id> ids); }
public interface IAccountWriter { void persist(List<Account> accts); }
public interface ICrmSync       { void syncToCrm(List<Account> accts); }
```

A read-only consumer depends on `IAccountReader` alone, and its Stub API stub stays tiny.

---

## D — Dependency Inversion Principle

Depend on abstractions, not concretions, and inject collaborators. This is exactly what
makes Apex unit-testable with the Stub API — no SOQL, no DML in a true unit test.

**Violation** — the selector is hard-wired; the only way to test is real data plus DML.

```java
public with sharing class OpportunityService {
    public Decimal pipelineTotal(Id accountId) {
        List<Opportunity> opps = [
            SELECT Amount FROM Opportunity WHERE AccountId = :accountId WITH USER_MODE
        ];
        Decimal total = 0;
        for (Opportunity o : opps) { total += o.Amount; }
        return total;
    }
}
```

**Compliant** — inject the abstraction; production wires the real selector, tests wire a stub.

```java
public with sharing class OpportunityService {
    private final IOpportunitySelector selector;

    public OpportunityService(IOpportunitySelector selector) {
        this.selector = selector;
    }

    public Decimal pipelineTotal(Id accountId) {
        Decimal total = 0;
        for (Opportunity o : selector.byAccount(accountId)) { total += o.Amount; }
        return total;
    }
}
```

```java
IOpportunitySelector stub = (IOpportunitySelector) Test.createStub(
    IOpportunitySelector.class,
    new OpportunitySelectorStub(new List<Opportunity>{
        new Opportunity(Amount = 100), new Opportunity(Amount = 200)
    })
);
Assert.areEqual(300, new OpportunityService(stub).pipelineTotal('001...'));
```

This is the same Stub API wiring shown in the main skill (§8) — DIP is the principle that
earns it.

---

## Apply SOLID first

Before adopting a named pattern (Factory, Strategy, Repository, Unit of Work), check the
five above:

- A class that is hard to name is usually an **SRP** violation.
- A `switch`/`if` chain you edit for every new case is an **OCP** violation.
- A subclass that no-ops or throws on an inherited method is an **LSP** violation.
- A mock that must stub methods nobody calls is an **ISP** violation.
- A class you cannot unit-test without DML is a **DIP** violation.

Fix those, and most patterns either fall out for free or turn out to be unnecessary.
