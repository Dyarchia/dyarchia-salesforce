---
name: dya-omnistudio
description: Salesforce OmniStudio developer surface (Summer '26 / API v67.0) — the programmatic side, with real contracts and compilable Apex. OmniScripts, FlexCards, Integration Procedures, DataRaptors/Data Mappers, and Apex Remote Actions (the Callable vs VlocityOpenInterface2 contract), OmniStudio Standard vs Managed Package, and invoking IPs from Apex/LWC via IntegrationProcedureService. Load only when the user explicitly invokes this skill by name (`dya-omnistudio`); do NOT auto-trigger on generic OmniStudio, Vlocity, or Salesforce questions.
---

# Salesforce OmniStudio — Developer Surface

You are an expert OmniStudio (formerly Vlocity) developer. OmniStudio is the **Salesforce Industries** low-code + pro-code toolkit. This skill covers the **programmatic** surface with **real contracts and compilable Apex**. It builds on `dya-apex`/`lwc`. Follow every rule below.

References:
- `references/apex-remote-actions.md` — the full Remote Action contract: `Callable` (Standard) vs `VlocityOpenInterface2` (Managed Package), the args/input/output/options maps, error handling, and registration.
- `references/ips-and-datamappers.md` — Integration Procedures (actions, invoke modes), Data Mappers, and invoking IPs from Apex (`IntegrationProcedureService.runIntegrationService`) / LWC / REST.

---

## Platform Context — Summer '26 / API v67.0

- **Two flavors, and they differ in code:** **OmniStudio Standard** (metadata-based, on core, **`omnistudio`** namespace, implement **`Callable`**) vs the original **Managed Package** ("OmniStudio for Vlocity", industry namespace like **`vlocity_cmt`** / `vlocity_ins` / `vlocity_ps`, extend **`VlocityOpenInterface`/`VlocityOpenInterface2`**). Always confirm which the org uses — class references, interfaces, and tooling differ.
- Components are **LWC-based at runtime** (OmniScripts/FlexCards render as Lightning Web Components) and **JSON-defined** in metadata.
- Custom logic plugs in via **Apex Remote Actions**; **Apex v67** defaults apply (`with sharing`, `USER_MODE`; `WITH SECURITY_ENFORCED` no longer compiles → `WITH USER_MODE`).
- IPs and Data Mappers are invocable from **Apex**, **LWC**, **REST/Connect API**, and OmniStudio components — build once, reuse everywhere.

---

## 1. The Four Tools

| Tool | What it is | Use |
|---|---|---|
| **OmniScript** | Guided, multi-step UI wizard (renders as LWC; JSON-defined) | Self-service flows, claims, onboarding, guided selling |
| **FlexCard** | Declarative card UI surfacing data + actions | Dashboards, record summaries, action launchers |
| **Integration Procedure (IP)** | Server-side, declarative orchestration in a single server call | Data read/write, callouts, transformation; the "controller" behind OmniScripts/FlexCards |
| **DataRaptor / Data Mapper** | Extract / Transform / Load / Turbo for shaping Salesforce data | Read/write/transform data inside IPs and components |

Mental model: **OmniScript/FlexCard = presentation; Integration Procedure = server-side logic; Data Mapper = data access/shaping; Apex Remote Action = custom code escape hatch.**

---

## 2. Apex Remote Actions — the Real Contract

When configuration can't do it, call Apex from FlexCards, OmniScripts, or IPs via a **Remote Action**. The class **must** implement the right contract for the org's flavor:

**OmniStudio Standard — implement `Callable`:**

```apex
global with sharing class AccountRemoteActions implements Callable {
    // Standard entry point. OmniStudio passes one args map containing input/output/options.
    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> input   = (Map<String, Object>) args.get('input');
        Map<String, Object> output  = (Map<String, Object>) args.get('output');
        Map<String, Object> options = (Map<String, Object>) args.get('options');
        return invokeMethod(action, input, output, options);
    }

    private Boolean invokeMethod(String methodName, Map<String,Object> input,
                                 Map<String,Object> output, Map<String,Object> options) {
        if (methodName == 'getContacts') {
            Id accountId = (Id) input.get('accountId');
            output.put('contacts', [
                SELECT Id, Name, Email FROM Contact WHERE AccountId = :accountId WITH USER_MODE
            ]);
            return true;     // success
        }
        return false;        // unhandled method
    }
}
```

**Managed Package (OmniStudio for Vlocity) — extend `VlocityOpenInterface2`:**

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

Rules: `global with sharing`; only methods on classes implementing `Callable` / extending `VlocityOpenInterface(2)` are invocable from OmniStudio; dispatch on `methodName`; read `input`, write `outMap`/`output`, read `options`; return `Boolean` success. **Bulk-safe, `WITH USER_MODE`, no SOQL/DML in loops** (it's Apex). Register the class + method in the Remote Action element (**Remote Class** + **Remote Method**). Full contract + errors: `references/apex-remote-actions.md`.

---

## 3. Integration Procedures (the server-side workhorse)

IPs run **multiple actions in a single server call** (declarative, server-side). Common actions: DataRaptor Extract/Load, **HTTP Action** (callout), **Remote Action** (Apex), Set Values, Response Action, Conditional/Loop Block, Integration Procedure Action (compose).

- **Invoke from Apex** with `omnistudio.IntegrationProcedureService.runIntegrationService(...)` (Standard) / the `vlocity_*` equivalent (Managed):

```apex
Map<String, Object> output = (Map<String, Object>) omnistudio.IntegrationProcedureService
    .runIntegrationService('myType_mySubType',
                           new Map<String, Object>{ 'accountId' => acctId },  // input
                           new Map<String, Object>());                         // options
```

- Invoke from **OmniScripts/FlexCards**, **LWC**, and **REST/Connect API** too.
- **Invoke modes:** non-blocking (run while the OmniScript continues) vs blocking; map the **Response JSON Node/Path** so downstream elements receive a non-blocking result.

Full IP/Data Mapper patterns: `references/ips-and-datamappers.md`.

---

## 4. Data Mappers (DataRaptors)

| Type | Purpose |
|---|---|
| **Extract** | Read Salesforce data into JSON |
| **Transform** | Reshape JSON without DML |
| **Load** | Write JSON to Salesforce (DML) |
| **Turbo Extract** | High-performance single-object read |

Prefer Data Mappers over Apex for standard read/transform/write inside IPs; reserve Apex Remote Actions for logic they can't express.

---

## 5. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| Guided multi-step UI | OmniScript |
| Card UI with data + actions | FlexCard |
| Server-side orchestration/transformation | Integration Procedure |
| Read Salesforce data to JSON | DataRaptor Extract / Turbo |
| Reshape JSON | DataRaptor Transform |
| Write JSON to Salesforce | DataRaptor Load |
| Call external API server-side | IP HTTP Action |
| Custom logic config can't express | Apex Remote Action (`Callable` / `VlocityOpenInterface2`) |
| Reuse an IP from server code | `IntegrationProcedureService.runIntegrationService` |
| Expose orchestration to external systems | Invoke IP via REST/Connect API |

---

## 6. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Apex for standard read/transform/write | Data Mappers (Extract/Transform/Load) |
| Apex for orchestration an IP handles | Integration Procedure |
| Remote Action class not `global` / wrong contract | `global with sharing` + `Callable` (Standard) or `VlocityOpenInterface2` (Managed) |
| Mixing up the flavor's namespace/interface | Confirm Standard (`omnistudio`/`Callable`) vs Managed (`vlocity_*`/`VlocityOpenInterface2`) |
| SOQL/DML in a loop in a Remote Action | Bulkify |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` (removed at v67) |
| Throwing raw exceptions to the runtime | Structured `error` in output + return `false` |
| Per-element server calls | Bundle actions into one IP server call |
| Heavy logic in OmniScript steps | Push to Integration Procedures (server-side) |

---

## Summary — The Five Commandments

1. **Presentation vs logic vs data vs code** — OmniScript/FlexCard, Integration Procedure, Data Mapper, Apex Remote Action; each for its job.
2. **Know your flavor** — Standard (`omnistudio` namespace, `Callable`) vs Managed Package (`vlocity_*`, `VlocityOpenInterface2`); the Apex contract differs.
3. **Remote Actions follow the contract** — `global with sharing`, dispatch on `methodName`, read `input`/write `output`/read `options`, return `Boolean`, bulk-safe, `WITH USER_MODE`.
4. **Configure first, code second** — IPs and Data Mappers over Apex; Apex is the escape hatch for the inexpressible.
5. **One server call, reuse everywhere** — IPs bundle actions; invoke them from Apex (`IntegrationProcedureService.runIntegrationService`), LWC, and REST.
