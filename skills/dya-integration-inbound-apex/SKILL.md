---
name: dya-integration-inbound-apex
description: Salesforce custom inbound endpoints (Winter '27 / API v68.0) — exposing your own APIs. Apex REST services (@RestResource, GA and recommended), Apex SOAP web services (webservice keyword, legacy), the @RestResource-vs-@InvocableMethod distinction, and Sites/Experience Cloud as integration surfaces with guest-user security. Load only when the user explicitly invokes this skill by name (`dya-integration-inbound-apex`); do NOT auto-trigger on generic Apex or API questions.
---

# Salesforce Custom Inbound Endpoints (Apex)

You are an expert at exposing custom inbound endpoints on Salesforce. Author one only when the
standard APIs (`dya-integration-inbound-apis`) cannot express the contract: bespoke payloads,
transactional units of work, or logic at the boundary. Authentication is `dya-integration-auth`;
deep Apex rules are `dya-apex`. Follow every rule below.

References:

- `references/shared/sharing-and-access.md` — the permission model a boundary class now runs under, and the guest user.
- `references/shared/platform-deltas.md` — the release-coupled facts, including the security defaults that hit boundary classes hardest.
- `references/shared/metadata-and-api-versions.md` — what version retirement does and does not touch.
- `references/apex-rest-service.md` — the full `@RestResource` service across all HTTP verbs, request and response handling, error contracts, and a worked transactional endpoint.

Locking down the guest profile and choosing the integration user's permission set belong to
`dya-permissions`.

---

## Platform Context — Winter '27 / API v68.0

Winter '27 adds nothing to Apex REST. It changes what reaches it: the OAuth **username-password flow
is retired, enforced 20 February 2027**, so every caller arriving with `grant_type=password` stops
working that day. Inventory them now — `dya-integration-auth`.

Four standing facts, the third of which catches people:

- **`@RestResource` is GA, recommended and not deprecated.** Version retirement targets the version
  number in *standard endpoint URLs* and the SOAP `login()` method, and **explicitly excludes**
  custom Apex REST and SOAP web services, Apex classes, triggers and Visualforce. Full status in
  `references/shared/metadata-and-api-versions.md`.
- **Apex SOAP web services (`webservice`) are legacy but supported.** Prefer Apex REST for anything
  new. That is style, not retirement, and unrelated to the SOAP `login()` retirement, which is
  authentication.
- **The API 67.0 security defaults hit boundary classes hardest.** An `@RestResource` class compiled
  at 67.0 or above with no sharing keyword defaults to `with sharing`, and its SOQL and DML default
  to `USER_MODE`. An endpoint that relied on system-mode access starts returning fewer rows or
  throwing — silently, in the query's case. Declare sharing and access level explicitly, and audit
  **before** raising the version. `WITH SECURITY_ENFORCED` no longer compiles.
- **HTTPS is mandatory** on every inbound endpoint.

---

## 1. The Distinction That Causes Confusion — `@RestResource` vs `@InvocableMethod`

Different annotations, different jobs. Do not conflate them.

| | `@RestResource` | `@InvocableMethod` |
|---|---|---|
| Purpose | Expose Apex as an **HTTP REST endpoint** | Make a method callable by **Flow / Agentforce / Process** |
| Surface | `/services/apexrest/...` | declarative tools + external systems via the Invocable Actions REST API |
| Caller | An external system over HTTP | A Flow, an agent action, or automation |
| Inbound integration? | **Yes** — this is the inbound endpoint | No — it's an action building block |

**Agents do not enter through `@RestResource`.** Agent capabilities are built with
`@InvocableMethod` (`dya-agentforce`). An existing Apex REST class can be surfaced as an agent
action through a generated OpenAPI document, but that is a secondary path. An external system
calling a custom HTTP endpoint is `@RestResource`.

---

## 2. When to Build a Custom Endpoint at All

Stop at the first that fits.

1. **Standard REST / Composite / Bulk** (`dya-integration-inbound-apis`) — plain CRUD/query,
   multi-op, or bulk. **Default.**
2. **Apex REST (`@RestResource`)** — bespoke contract: custom request/response shapes, a
   transactional unit of work across objects, validation at the boundary, or a payload the
   standard API cannot express.
3. **Apex SOAP (`webservice`)** — only when a consumer mandates SOAP/WSDL and REST is not an option.

Plain CRUD never justifies an endpoint.

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

Rules:
- The class is `global`; methods are `global static` and annotated
  `@HttpGet/@HttpPost/@HttpPut/@HttpPatch/@HttpDelete`, one of each per class.
- Declare sharing explicitly — `with sharing` unless justified — query `WITH USER_MODE`, and run DML
  with `AccessLevel.USER_MODE`.
- Read headers, URI, status codes and raw bodies from `RestContext.request` / `RestContext.response`.
- Bulkify and bound everything: a boundary endpoint gets called hard.
- Return a **stable, versioned response contract**. Catch and translate to an error DTO plus the
  right HTTP status; a leaked stack trace is information disclosure.

Full multi-verb service, error contract and transactional pattern: `references/apex-rest-service.md`.

---

## 4. Sites & Experience Cloud as Integration Surfaces

Public **Salesforce Sites** and **Experience Cloud** sites host guest-accessible Apex REST endpoints
— webhook receivers or public APIs with no OAuth handshake.

- The endpoint runs as the **guest user**: no role, a deliberately weak class of sharing rules, and
  whatever the guest profile grants. Under the API 67.0 user-mode defaults that profile governs what
  the code can see and do, so scoping it is a functional requirement, not hardening advice.
  `dya-permissions`.
- Validate and sanitise every input. Treat all guest traffic as hostile.
- Prefer authenticated OAuth (`dya-integration-auth`) whenever the caller can authenticate.

---

## 5. Decision Matrix — Quick Reference

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

1. **Standard API first** — only author an endpoint when the contract genuinely needs it.
2. **`@RestResource` is GA and recommended** for custom REST; `@InvocableMethod` is a *different thing* (Flow/agent actions), and Apex SOAP is legacy.
3. **Boundary classes are security-critical** — explicit `with sharing` and `USER_MODE`, audited before you raise the version, never `WITH SECURITY_ENFORCED`.
4. **Stable contracts, clean errors** — versioned DTOs, proper HTTP status codes, never raw stack traces.
5. **Treat guest/Site endpoints as hostile** — minimal profile, validate everything, prefer authenticated OAuth.
