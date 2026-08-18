# Agentforce Apex Actions — Reference Implementation (API v67.0)

Full implementations referenced from SKILL.md §3–§4. Load this when building or reviewing an agent action. Actions are how an agent *does* things; Apex actions are the deterministic backbone for logic the LLM must not improvise. They are Apex — the deep rules in `dya-apex` apply on top.

## Action Type Comparison

| Type | Build with | Best for | Notes |
|---|---|---|---|
| **Flow** | Autolaunched flow | Declarative orchestration, approvals, record DML | No code; reuse existing flows |
| **Prompt Template** | Prompt Builder | Text generation/transformation grounded in records | No code; LLM-backed |
| **Named Query** | SOQL in Setup | Exposing a query as a capability | No code; read-only |
| **Apex `@InvocableMethod`** | Apex class | Deterministic logic, callouts, cross-object work | Code; the focus of this file |
| **Apex REST agent action** | Apex REST + OpenAPI | Reusing an existing REST endpoint | Generates an OpenAPI doc into the API catalog |
| **AI Agent action** | Apex/Flow | Invoking another active agent | Enables limited agent-to-agent |

Choose the least-code option that fits. Keep each action narrow — Atlas composes small, well-described actions better than one monolith.

## Canonical Apex Action

```java
public with sharing class CreateCaseAction {

    public class Request {
        @InvocableVariable(label='Contact Id' description='Id of the contact raising the case' required=true)
        public Id contactId;
        @InvocableVariable(label='Subject' description='Short summary of the issue' required=true)
        public String subject;
        @InvocableVariable(label='Priority' description='High, Medium, or Low')
        public String priority;
    }

    public class Result {
        @InvocableVariable(label='Case Id' description='Id of the created case')
        public Id caseId;
        @InvocableVariable(label='Success' description='Whether the case was created')
        public Boolean success;
        @InvocableVariable(label='Message' description='Human-readable outcome for the agent to relay')
        public String message;
    }

    @InvocableMethod(
        label='Create Support Case'
        description='Creates a support Case for a contact. Use when a customer wants to log a new issue. Returns the new Case Id or a clear failure message.'
    )
    public static List<Result> run(List<Request> requests) {
        // 1) Build records in bulk
        List<Case> cases = new List<Case>();
        for (Request r : requests) {
            cases.add(new Case(
                ContactId = r.contactId,
                Subject   = r.subject,
                Priority  = String.isBlank(r.priority) ? 'Medium' : r.priority,
                Origin    = 'Agentforce'
            ));
        }

        // 2) One bulk DML, partial success, user-mode security
        Database.SaveResult[] srs = Database.insert(cases, false, AccessLevel.USER_MODE);

        // 3) Map results back, never throw raw to the agent
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < srs.size(); i++) {
            Result res = new Result();
            if (srs[i].isSuccess()) {
                res.success = true;
                res.caseId  = srs[i].getId();
                res.message = 'Case created.';
            } else {
                res.success = false;
                res.message = 'Could not create the case: ' + srs[i].getErrors()[0].getMessage();
                // Logger.error(...) via Platform Events — see dya-apex §11
            }
            results.add(res);
        }
        return results;
    }
}
```

## Rules

- **Bulk in, bulk out.** Signature is `List<Request>` → `List<Result>`. Actions do not bulkify automatically; each invocation is its own transaction, and the same class is often reused in Flows. Assume 200.
- **Wrapper classes** for input and output, each field an `@InvocableVariable` with a `label` and `description`. Mark truly required inputs `required=true`.
- **Descriptions feed Atlas.** The method `label`/`description` and each variable `description` are how the engine matches intent and fills parameters. Keep them synced with the Agent Builder action config.
- **Security:** `with sharing`, `WITH USER_MODE` on SOQL, `AccessLevel.USER_MODE` on DML. `WITH SECURITY_ENFORCED` does not compile at API 67.
- **No raw exceptions to the agent.** Return a structured `Result` with a `success` flag and a clear `message`; log the real cause via Platform Events. A thrown exception gives the agent nothing useful to say.
- **Determinism:** put the business rule in code. The action exists so the LLM does not have to reason about it.
- **Idempotency:** where the agent might retry, make the action safe to call twice (e.g. upsert by external id).

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Scalar params instead of a wrapper | One `Request` / `Result` wrapper with `@InvocableVariable`s |
| Missing/weak `description`s | Intent-rich label + description on method and every variable |
| One record assumed | Bulk `List<Request>` → `List<Result>` |
| `WITH SECURITY_ENFORCED` | `WITH USER_MODE` |
| No sharing keyword | `with sharing` |
| `throw new ...` to the agent | Structured failure `Result` + Platform Event log |
| SOQL/DML in a loop | Bulk query before, single DML after |
| One giant multi-purpose action | Several narrow, well-described actions |
| Apex for declarative orchestration | Flow action |
