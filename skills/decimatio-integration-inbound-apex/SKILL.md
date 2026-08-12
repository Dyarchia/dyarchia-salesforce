---
name: decimatio-integration-inbound-apex
description: Salesforce custom inbound endpoints (Summer '26 / API v67.0) — exposing your own APIs. Apex REST services (@RestResource, GA and recommended), Apex SOAP web services (webservice keyword, legacy), the @RestResource-vs-@InvocableMethod distinction, and Sites/Experience Cloud as integration surfaces with guest-user security. Load only when the user explicitly invokes this skill by name (`decimatio-integration-inbound-apex`); do NOT auto-trigger on generic Apex or API questions.
---

# Salesforce Custom Inbound Endpoints (Apex)

You are an expert at exposing custom inbound endpoints on Salesforce. Use this when the standard APIs (`decimatio-integration-inbound-apis`) can't express the contract — you need bespoke payloads, transactional units of work, or business logic at the boundary. Authentication is in `decimatio-integration-auth`; deep Apex rules in `decimatio-apex`. Follow every rule below.

References:
- `references/apex-rest-service.md` — full `@RestResource` service (all HTTP verbs), request/response handling, error contracts, and a worked transactional endpoint.

---

## Platform Context — Summer '26 / API v67.0

- **`@RestResource` (Apex REST) is GA and the recommended way** to build a custom REST endpoint. It is **not deprecated**. The API-version retirement (31.0–40.0) targets *standard-endpoint versions* and SOAP `login()`, and **explicitly excludes** custom Apex REST/SOAP web services, Apex classes, triggers, and Visualforce.
- **Apex SOAP web services (`webservice` keyword) remain supported but legacy** — prefer Apex REST for new endpoints. (This is a style recommendation, not a retirement; and it is unrelated to the SOAP `login()` retirement, which is about authentication.)
- **v67 security defaults hit boundary classes hardest.** An `@RestResource` class compiled at 67.0 with no sharing keyword defaults to `with sharing`, and its SOQL/DML default to `USER_MODE`. A boundary endpoint that historically relied on system-mode access can suddenly return fewer rows or throw. Declare sharing and access level explicitly; audit before bumping. `WITH SECURITY_ENFORCED` no longer compiles.
- **HTTPS is mandatory** for all inbound endpoints.

---

## 1. The Distinction That Causes Confusion — `@RestResource` vs `@InvocableMethod`

These are different annotations for different jobs. Do not conflate them:

| | `@RestResource` | `@InvocableMethod` |
|---|---|---|
| Purpose | Expose Apex as an **HTTP REST endpoint** | Make a method callable by **Flow / Agentforce / Process** |
| Surface | `/services/apexrest/...` | declarative tools + external systems via the Invocable Actions REST API |
| Caller | An external system over HTTP | A Flow, an agent action, or automation |
| Inbound integration? | **Yes** — this is the inbound endpoint | No — it's an action building block |

So: **agents do not "enter" via `@RestResource`.** Agent capabilities are built with `@InvocableMethod` (see `decimatio-agentforce`). You *can* expose an existing Apex REST class as an agent action by generating an OpenAPI document, but that is a secondary path, not how `@RestResource` itself works. When the requirement is "an external system calls a custom HTTP endpoint," that's `@RestResource`.

---

## 2. When to Build a Custom Endpoint at All

Reach for Apex REST only when the standard APIs can't do it. Stop at the first that fits:

1. **Standard REST / Composite / Bulk** (`decimatio-integration-inbound-apis`) — plain CRUD/query, multi-op, or bulk. **Default.**
2. **Apex REST (`@RestResource`)** — bespoke contract: custom request/response shapes, a transactional unit of work spanning multiple objects, validation/business logic at the boundary, or a payload the standard API can't express.
3. **Apex SOAP (`webservice`)** — only when a consumer specifically mandates SOAP/WSDL and REST is not an option (legacy).

If you're just doing CRUD, don't write an endpoint — use the standard API.

---

## 3. Apex REST Service — Essentials

```apex
@RestResource(urlMapping='/orders/*')
global with sharing class OrderApi {

    @HttpPost
    global static ResponseDto createOrder(RequestDto payload) {
        // user-mode enforced at v67; validate, then do a transactional unit of work
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
- The class is `global`; methods are `global static` and annotated `@HttpGet/@HttpPost/@HttpPut/@HttpPatch/@HttpDelete` (one of each per class).
- Declare sharing explicitly (`with sharing` unless justified); query `WITH USER_MODE`, DML with `AccessLevel.USER_MODE`.
- Use `RestContext.request` / `RestContext.response` for headers, URI, status codes, and raw bodies.
- Bulkify and bound everything — a boundary endpoint can be called hard; assume volume and concurrency.
- Return a **stable, versioned response contract** with clear error shapes; never leak raw stack traces. Catch and translate to an error DTO + appropriate HTTP status.

Full multi-verb service, error contract, and transactional pattern: `references/apex-rest-service.md`.

---

## 4. Sites & Experience Cloud as Integration Surfaces

Public **Salesforce Sites** and **Experience Cloud** sites can host guest-accessible Apex REST endpoints — useful as lightweight inbound webhook receivers or public APIs without a full OAuth handshake.

- The endpoint runs as the **guest user**. Under v67 user-mode defaults, the guest profile's object/field permissions and sharing now govern what the code can see and do — scope the guest profile to the absolute minimum.
- Validate and sanitise every input; treat all guest traffic as hostile.
- Prefer authenticated OAuth access (`decimatio-integration-auth`) over guest endpoints whenever the caller can authenticate.

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
| Endpoint class with no sharing keyword at v67 | Explicit `with sharing` + `WITH USER_MODE` |
| `WITH SECURITY_ENFORCED` in a boundary class | `WITH USER_MODE` (removed in API 67+) |
| Returning raw exceptions/stack traces to callers | Error DTO + correct HTTP status code |
| Broad guest profile on a Site endpoint | Least-privilege guest profile; validate all input |
| Non-bulkified boundary logic | Bulkify; assume volume and concurrency |
| Unversioned response contract | Stable, explicitly versioned contract |

---

## Summary — The Five Commandments

1. **Standard API first** — only author an endpoint when the contract genuinely needs it.
2. **`@RestResource` is GA and recommended** for custom REST; `@InvocableMethod` is a *different thing* (Flow/agent actions), and Apex SOAP is legacy.
3. **Boundary classes are security-critical at v67** — explicit `with sharing` + `USER_MODE`, audit before bumping, never `WITH SECURITY_ENFORCED`.
4. **Stable contracts, clean errors** — versioned DTOs, proper HTTP status codes, never raw stack traces.
5. **Treat guest/Site endpoints as hostile** — minimal profile, validate everything, prefer authenticated OAuth.
