# Named Credentials & External Credentials — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-auth` for outbound authentication.

## The Two-Part Model

| Piece | Holds | Answers |
|---|---|---|
| **Named Credential** | Base URL + which External Credential + callout options (HTTP headers, allow formulas, generate auth header) | *Where* do I call? |
| **External Credential** | Auth protocol + **Principals** (+ custom headers via formula) | *How* do I authenticate? |

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Payments_API/v1/charge');  // resolves base URL + injects auth
req.setMethod('POST');
// No hand-set Authorization header, no secret in code, no Remote Site Setting.
HttpResponse res = new Http().send(req);
```

## Principal Types

A user or integration user may use a Principal once assigned the **permission set** that references the External Credential Principal.

## Auth Protocols

| Protocol | Use |
|---|---|
| **OAuth 2.0 — Browser/Web Server** | User-delegated outbound access |
| **OAuth 2.0 — Client Credentials (secret)** | Machine-to-machine with a shared secret |
| **OAuth 2.0 — Client Credentials (JWT assertion)** | Machine-to-machine, certificate-based (no shared secret) |
| **JWT** | Token-signing scenarios |
| **AWS Signature v4** | Calling AWS services (SigV4 signing handled for you) |
| **Basic** | Legacy username/password to the *external* system (avoid where possible) |
| **Custom** | Set the auth header yourself via a formula (API keys, bespoke schemes) |

Prefer **OAuth Client Credentials with JWT** for modern machine-to-machine; **Custom** for simple API-key headers; reserve **Basic** for legacy targets.

## Setup Outline

1. Create an **External Credential**; pick the protocol; add a **Principal** (Named or Per-User) and its parameters (token URL, scope, certificate/secret).
2. Create a **Named Credential** pointing at the base URL and the External Credential; configure callout options (generate authorization header, allowed formulas in headers, etc.).
3. Create/assign a **permission set** granting access to the External Credential Principal; assign it to the running/integration user.
4. In code/Flow, call `callout:Named_Credential/path`.

## Custom Headers via Formula

External Credentials support **custom headers** computed with formulas (e.g. an API key, a computed signature, a tenant id), so you don't hand-build them in Apex. Keep secrets in the credential and reference them in the formula.

## Why Not Remote Site Settings / Hard-Coding

- Remote Site Settings only allowlist a URL; they manage no auth, secrets or rotation.
- Hard-coded tokens leak in code, version control, and logs, and can't be rotated centrally.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Secret/token in a custom setting | External Credential (encrypted, principal-scoped) |
| Setting the `Authorization` header by hand | Let the Named/External Credential inject it |
| Legacy Named Credential (pre-External-Credential) | Migrate to Named + External Credential |
| One Named Principal where attribution matters | Per-User Principal |
| Basic auth where OAuth is available | OAuth Client Credentials (JWT) |
| API key pasted into code | Custom header via External Credential formula |
