---
name: dya-sf-integration-inbound-apex
description: Salesforce custom inbound endpoints (Winter '27, API v68.0) — Apex REST, legacy Apex SOAP web services, @RestResource vs @InvocableMethod, Sites and Experience Cloud endpoints with guest-user security. Applies to @RestResource classes, webservice methods, and Sites or Experience Cloud endpoints exposed to guests. Load before creating or editing anything in this scope.
---

# Salesforce Custom Inbound Endpoints (Apex)

Author a custom inbound endpoint only when the standard APIs (`dya-sf-integration-inbound-apis`) cannot
express the contract: bespoke payloads, transactional units of work, or boundary logic.
Authentication is `dya-sf-integration-auth`; deep Apex rules are `dya-sf-apex`; locking down the guest
profile and the integration user's permission set is `dya-sf-permissions`. Follow every rule below.

References:

- `references/shared/sharing-and-access.md` — the permission model boundary classes now run under, and the guest user.
- `references/shared/platform-deltas.md` — release-coupled facts, including the security defaults that hit boundary classes hardest.
- `references/shared/metadata-and-api-versions.md` — what version retirement does and does not touch.
- `references/apex-rest-service.md` — the full `@RestResource` service across all HTTP verbs, request and response handling, error contracts, and a worked transactional endpoint.

---

## Platform Context — Winter '27 / API v68.0

Winter '27 adds nothing to Apex REST but changes what reaches it: the OAuth **username-password flow
is retired, enforced 20 February 2027**, so every caller using `grant_type=password` stops working
that day. Inventory them now — `dya-sf-integration-auth`.

- **`@RestResource` is GA, recommended and not deprecated.** Version retirement targets the version
  number in *standard endpoint URLs* and the SOAP `login()` method, and **excludes**
  custom Apex REST and SOAP web services, Apex classes, triggers and Visualforce. Full status in
  `references/shared/metadata-and-api-versions.md`.
- **Apex SOAP web services (`webservice`) are legacy but supported.** Prefer Apex REST for anything
  new. Its legacy status is unrelated to the SOAP `login()` retirement, which concerns authentication.
- **The API 67.0 security defaults hit boundary classes hardest.** An `@RestResource` class compiled
  at 67.0 or above with no sharing keyword defaults to `with sharing`, and its SOQL and DML default
  to `USER_MODE`. An endpoint relying on system-mode access returns fewer rows, silently, or throws.
  Audit **before** raising the version. `WITH SECURITY_ENFORCED` no longer compiles.
- **Serve every inbound endpoint over HTTPS**; it is mandatory.

---

## 1. `@RestResource` vs `@InvocableMethod`

| | `@RestResource` | `@InvocableMethod` |
|---|---|---|
| Purpose | Expose Apex as an **HTTP REST endpoint** | Make a method callable by **Flow / Agentforce / Process** |
| Surface | `/services/apexrest/...` | declarative tools + external systems via the Invocable Actions REST API |
| Caller | An external system over HTTP | A Flow, an agent action, or automation |
| Inbound integration? | **Yes** — this is the inbound endpoint | No — it's an action building block |

**Agents do not enter through `@RestResource`.** Build agent capabilities with `@InvocableMethod`
(`dya-sf-agentforce`). As a secondary path, surface an existing Apex REST class as an agent action
through a generated OpenAPI document.

---

## 2. When to Build a Custom Endpoint

Stop at the first that fits.

1. **Standard REST / Composite / Bulk** (`dya-sf-integration-inbound-apis`) — plain CRUD/query,
   multi-op, or bulk. **Default.**
2. **Apex REST (`@RestResource`)** — bespoke contract: custom request/response shapes, a
   transactional unit of work across objects, validation at the boundary, or a payload the
   standard API cannot express.
3. **Apex SOAP (`webservice`)** — only when a consumer mandates SOAP/WSDL and REST is not an option.

---

## 3. Apex REST Service — Essentials

```apex
@RestResource(urlMapping='/orders/*')
global with sharing class OrderApi {

    @HttpPost
    global static ResponseDto createOrder(RequestDto payload) {
        // user mode enforced from API 67.0; validate, then do a transactional unit of work
        // ... build records, single bulk DML with AccessLevel.USER_MODE ...
        RestContext.response.statusCode = 201;
        return new ResponseDto(/* ... */);
    }

    @HttpGet
    global static ResponseDto getOrder() {
        String id = RestContext.request.requestURI.substringAfterLast('/');
        // ... query WITH USER_MODE ...
        return new ResponseDto(/* ... */);
    }
}
```

- Make the class `global` and its methods `global static`, annotated
  `@HttpGet/@HttpPost/@HttpPut/@HttpPatch/@HttpDelete`, one of each per class.
- Declare sharing explicitly — `with sharing` unless justified — query `WITH USER_MODE`, and run DML
  with `AccessLevel.USER_MODE`.
- Read headers, URI, status codes and raw bodies from `RestContext.request` / `RestContext.response`.
- Bulkify and bound everything.
- Return a **stable, versioned response contract**. Catch and translate to an error DTO plus the
  right HTTP status; a leaked stack trace is information disclosure.

Full multi-verb service, error contract and transactional pattern: `references/apex-rest-service.md`.

---

## 4. Sites & Experience Cloud as Integration Surfaces

Public **Salesforce Sites** and **Experience Cloud** sites host guest-accessible Apex REST endpoints:
webhook receivers or public APIs with no OAuth handshake.

- The endpoint runs as the **guest user**: no role, a restricted class of sharing rules, and
  whatever the guest profile grants. Scope that profile as a functional requirement
  (`dya-sf-permissions`); under the API 67.0 user-mode defaults it governs what the code can see and do.
- Validate and sanitise every input. Treat all guest traffic as hostile.
- Prefer authenticated OAuth (`dya-sf-integration-auth`) whenever the caller can authenticate.

---

## 5. Decision Matrix

| Need | Use | Inbound endpoint you author? |
|---|---|---|
| Plain CRUD/query for an external app | Standard REST | No |
| Multi-op / bulk | Composite / Bulk 2.0 | No |
| Bespoke contract / transactional unit of work | Apex REST (`@RestResource`) | Yes |
| Custom payload the standard API can't express | Apex REST | Yes |
| Consumer mandates SOAP/WSDL | Apex SOAP (`webservice`) | Yes (legacy) |
| Make a method callable from Flow/Agentforce | `@InvocableMethod` (not an inbound endpoint) | No |
| Public webhook receiver, no auth handshake | Apex REST on a Site (guest user) | Yes (lock down) |

---

## 6. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| `@RestResource` for plain CRUD | Standard REST API |
| Confusing `@RestResource` with `@InvocableMethod` | REST endpoint vs Flow/agent action — different jobs |
| New Apex SOAP web service | Apex REST (`@RestResource`) |
| An endpoint class with no sharing keyword | Explicit `with sharing` plus `WITH USER_MODE` |
| `WITH SECURITY_ENFORCED` in a boundary class | `WITH USER_MODE` — the old form does not compile from 67.0 |
| Not knowing which callers still use the username-password flow | Inventory them before 20 February 2027 |
| Returning raw exceptions/stack traces to callers | Error DTO + correct HTTP status code |
| Broad guest profile on a Site endpoint | Least-privilege guest profile; validate all input |
| Non-bulkified boundary logic | Bulkify; assume volume and concurrency |
| Unversioned response contract | Stable, explicitly versioned contract |

---

## Summary — The Five Commandments

1. **Use the standard API first** — author an endpoint only when the contract needs it.
2. **Use `@RestResource`, GA and recommended, for custom REST**; `@InvocableMethod` is a *different thing* (Flow/agent actions), and Apex SOAP is legacy.
3. **Treat boundary classes as security-critical** — explicit `with sharing` and `USER_MODE`, audited before you raise the version, never `WITH SECURITY_ENFORCED`.
4. **Keep contracts stable and errors clean** — versioned DTOs, proper HTTP status codes, never raw stack traces.
5. **Treat guest/Site endpoints as hostile** — minimal profile, validate everything, prefer authenticated OAuth.
