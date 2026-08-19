---
name: dya-integration-auth
description: Salesforce integration authentication & identity (Summer '26 / API v67.0) — inbound OAuth 2.0 flows, External Client Apps vs Connected Apps, the "Any API Auth" permission and SOAP login() retirement, JWT/mTLS/session auth; and outbound Named Credentials + External Credentials (principals, protocols). The one home for "how do I authenticate an integration." Load only when the user explicitly invokes this skill by name (`dya-integration-auth`); do NOT auto-trigger on generic auth or OAuth questions.
---

# Salesforce Integration Authentication & Identity

You are an expert on authenticating Salesforce integrations in **both** directions: how external systems authenticate *into* Salesforce, and how Salesforce authenticates *out* to external systems. This is the cross-cutting identity skill every other integration skill defers to. Follow every rule below.

References:
- `references/oauth-and-eca.md` — the OAuth 2.0 flows in depth, External Client Apps vs Connected Apps, JWT bearer setup, and MCP/agent auth.
- `references/named-external-credentials.md` — Named Credential + External Credential model, principal types, auth protocols, and the `callout:` pattern.

---

## Platform Context — Summer '26 / API v67.0

- **External Client Apps (ECAs) are the new default** for inbound integration identity. New **Connected App** creation is disabled by default from Spring '26; ECAs are the metadata-clean, closed-by-default, 2GP-friendly successor and **block legacy username/password OAuth flows**.
- **SOAP `login()` retires Summer '27** (API 31.0–64.0; already gone in 65.0+). The new **"Any API Auth"** user permission gates who may authenticate via SOAP `login()` and is enforced by default in new orgs. Migrate to OAuth.
- **Named Credentials + External Credentials** are the standard outbound model; legacy Named Credentials are deprecated.
- **Hosted MCP servers** authenticate via OAuth + **PKCE** with an ECA carrying `mcp_api` + `refresh_token` scopes (JWT-shaped tokens). See `dya-integration-connectors-mcp`.
- **HTTPS mandatory**; **My Domain** login-URL enforcement for API traffic postponed to Winter '27 — build against My Domain now.

---

## 1. Two Directions, One Discipline

```
INBOUND  (external authenticates INTO Salesforce)
  → OAuth 2.0 flow + External Client App
OUTBOUND (Salesforce authenticates OUT to external)
  → Named Credential (endpoint) + External Credential (auth)
```

Never hard-code secrets in either direction. Inbound identity lives in an **External Client App**; outbound credentials live in **External Credentials** (encrypted, principal-scoped). Both keep secrets out of code and metadata.

---

## 2. Inbound — Choose the OAuth Flow

| Flow | Use | Notes |
|---|---|---|
| **JWT Bearer** | Server-to-server backend, no user interaction | Certificate-based; the **modern default** for system integrations |
| **Web Server (auth code + PKCE)** | A user authorises a web app | Interactive; PKCE required for public clients |
| **Client Credentials** | Server-to-server tied to one run-as user | Simple machine-to-machine; pick a least-privilege integration user |
| **Refresh Token** | Long-lived access after an initial interactive grant | Pair with web-server flow |
| **Device** | Input-constrained devices | Kiosks/IoT |
| **Username-Password** | — | **Eliminated / not supported by ECAs.** Never use. |

Default to **JWT Bearer** for backend integrations and **Web Server + PKCE** for user-facing apps. Full setup: `references/oauth-and-eca.md`.

---

## 3. Inbound — External Client Apps vs Connected Apps

| | External Client App (ECA) | Connected App (legacy) |
|---|---|---|
| Status | **New default**; create these | Supported, but new-creation disabled by default (Spring '26) |
| Model | Separates developer settings from admin policy; metadata-clean; 2GP-friendly | Monolithic, harder to package cleanly |
| Security posture | **Closed by default**; blocks legacy password flows | Open-by-default historically |
| Secret rotation | Staged Credentials API (zero-downtime rotation) | Manual |

Build new integration identities as **ECAs**. Keep existing Connected Apps working, but migrate when you touch them — and inventory anything using SOAP `login()` / username-password before Summer '27.

---

## 4. Inbound — Other Mechanisms

- **Session-based** — for same-context callers (e.g. Visualforce/Aura calling Apex REST in-session). Don't use a harvested session id as a long-lived API credential.
- **Mutual TLS (mTLS)** — certificate-based transport auth where required by the counterparty; configure inbound mTLS in Setup.
- **"Any API Auth" permission** — controls SOAP `login()` eligibility; enforced by default in new orgs. Treat SOAP `login()` as end-of-life.
- **Guest/Site access** — unauthenticated endpoints on Sites/Experience Cloud run as the guest user; lock the guest profile down (see `dya-integration-inbound-apex`).

---

## 5. Outbound — Named Credentials + External Credentials

The modern, only-correct way to authenticate an outbound callout. Two metadata pieces:

- **Named Credential** = the **endpoint** (base URL + which External Credential to use, callout options).
- **External Credential** = the **authentication** (protocol + **Principals**). Tokens are stored encrypted in `UserExternalCredential`.

Reference it in code/Flow with `callout:My_Named_Credential/path` — no secrets, no Remote Site Setting.

### Principal types
- **Named Principal** — one shared identity for all users (typical for system integrations).
- **Per-User Principal** — each user authenticates individually (mapped to a permission set); use when the external system must know *which* user acted.

### Protocols
OAuth 2.0 (Browser/Web Server, **Client Credentials with secret**, **Client Credentials with JWT assertion**), JWT, **AWS Signature v4**, Basic (legacy), and Custom (header via formula).

Full setup, principal mapping, and the `callout:` pattern: `references/named-external-credentials.md`.

---

## 6. Decision Matrix — Quick Reference

| Need | Use |
|---|---|
| Backend system authenticates into SF, no user | JWT Bearer + External Client App |
| User authorises a web app to access SF | Web Server flow + PKCE + ECA |
| Machine-to-machine tied to one run-as user | Client Credentials flow + ECA |
| Long-lived access after interactive login | Refresh Token (+ web-server) |
| Certificate transport auth required | Mutual TLS |
| AI/MCP client connects to the org | OAuth + PKCE + ECA (`mcp_api` scope) |
| SF calls external, shared identity | Named Credential + External Credential, Named Principal |
| SF calls external, per-user identity | External Credential, Per-User Principal |
| SF calls AWS | External Credential, AWS Signature v4 |
| Legacy SOAP login()/username-password | Migrate to OAuth + ECA before Summer '27 |

---

## 7. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Username-Password OAuth flow | JWT Bearer / Web Server + PKCE |
| SOAP `login()` for new auth | OAuth + External Client App |
| New Connected App for a new integration | External Client App |
| Hard-coded client secret / token in code | External Client App / External Credential |
| Hard-coded endpoint + Remote Site Setting | Named Credential (`callout:`) |
| Storing a harvested session id as an API key | Proper OAuth token lifecycle |
| Over-scoped integration user/permission set | Least-privilege, purpose-built |
| Broad guest profile on Site endpoints | Minimal guest profile |
| Manual secret edits with downtime | Staged Credentials API rotation |
| Ignoring the v67 user-mode effect on integration users | Scope the integration user's FLS/objects correctly |

---

## Summary — The Five Commandments

1. **External Client Apps + OAuth inbound; Named/External Credentials outbound** — secrets never in code or metadata.
2. **JWT Bearer is the backend default**; Web Server + PKCE for user-facing; **never username/password or SOAP `login()`** (retiring Summer '27).
3. **ECAs over Connected Apps** — closed-by-default, packageable, with staged secret rotation.
4. **Least privilege everywhere** — purpose-built integration users/principals; v67 user-mode means their FLS/objects govern access.
5. **Pick the principal type on purpose** — Named Principal for shared system identity, Per-User when the external system must know who acted.
