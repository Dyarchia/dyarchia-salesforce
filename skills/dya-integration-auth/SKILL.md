---
name: dya-integration-auth
description: Salesforce integration authentication & identity (Winter '27 / API v68.0) — inbound OAuth 2.0 flows, External Client Apps vs Connected Apps, the username-password flow retirement, the "Any API Auth" permission and SOAP login() retirement, JWT/mTLS/session auth; and outbound Named Credentials + External Credentials (principals, protocols). The one home for "how do I authenticate an integration." Load only when the user explicitly invokes this skill by name (`dya-integration-auth`); do NOT auto-trigger on generic auth or OAuth questions.
---

# Salesforce Integration Authentication & Identity

You are an expert on authenticating Salesforce integrations in **both** directions: how external
systems authenticate *into* Salesforce, and how Salesforce authenticates *out* to external systems.
This is the cross-cutting identity skill every other integration skill defers to. Follow every rule
below.

References:

- `references/shared/platform-deltas.md` — the release-coupled facts, including the retirements below.
- `references/shared/metadata-and-api-versions.md` — endpoint version retirement, and where SOAP `login()` sits in it.
- `references/oauth-and-eca.md` — the OAuth 2.0 flows in depth, External Client Apps vs Connected Apps, JWT bearer setup, MCP and agent auth.
- `references/named-external-credentials.md` — the Named Credential + External Credential model, principal types, auth protocols, and the `callout:` pattern.

Who can *do* what once authenticated is a different question and belongs to `dya-permissions`.
Routing between integration patterns is `dya-integration-overview`.

---

## Platform Context — Winter '27 / API v68.0

Two retirements dominate this release for authentication. Both are **dated**, and the dates are what
make them actionable — an integration that works today stops working on a specific day.

| Change | When | What breaks |
|---|---|---|
| **OAuth 2.0 username-password flow retired for connected apps** | Release Update in Winter '27, **enforced 20 February 2027** | Anything posting `grant_type=password` with a username, password and security token stops receiving a token. Not at the release upgrade — on that date |
| **SOAP `login()` retirement** for API 31.0–64.0 | Summer '27; already unavailable at 65.0+ | Username/password SOAP authentication. The **"Any API Auth"** user permission already gates who may use it, enforced by default in new orgs |
| **Update Instanced URLs in API Traffic** | Postponed to **Spring '27** | API calls to instance-based endpoints rather than the org's My Domain URL |

If an org does not see the username-password Release Update in Setup, the flow is already blocked
there and it is unaffected. New orgs block it by default.

**Migrating off username-password.** The **client credentials flow** is the smaller change: the
external client app runs as one designated integration user and no password is stored anywhere.
**JWT bearer** uses a signed certificate instead of any shared secret, and is the better answer for
anything high value. The **web server flow with PKCE** is the answer when a real human is
authorising. Do not migrate to another password-carrying scheme.

**Update Instanced URLs in API Traffic** can be tested now: Setup › My Domain › Redirections ›
*Block API traffic that uses an incorrect instanced URL*. Turn it on in a sandbox and see what
breaks before the date chooses for you.

Standing context: **External Client Apps are the default** for inbound integration identity, and new
Connected App creation has been disabled by default since Spring '26. **Named Credentials plus
External Credentials** are the outbound model; legacy Named Credentials are deprecated. **Hosted MCP
servers** authenticate with OAuth plus PKCE through an ECA carrying the `mcp_api` and `refresh_token`
scopes — see `dya-integration-connectors-mcp`. HTTPS is mandatory everywhere.

---

## 1. Two Directions, One Discipline

```text
INBOUND   external authenticates INTO Salesforce
          → OAuth 2.0 flow + External Client App

OUTBOUND  Salesforce authenticates OUT to an external system
          → Named Credential (the endpoint) + External Credential (the authentication)
```

Never hard-code a secret in either direction. Inbound identity lives in an **External Client App**;
outbound credentials live in **External Credentials**, encrypted and principal-scoped. Both exist so
that secrets are absent from code *and* from metadata — a secret in a `.cls` file is a secret in
version control.

## 2. Inbound — Choosing the OAuth Flow

| Flow | Use it for | Notes |
|---|---|---|
| **JWT Bearer** | Server-to-server, no human involved | Certificate-based, no stored secret. The modern default for system integrations |
| **Client Credentials** | Server-to-server tied to one run-as user | Simplest migration off username-password. Pick a least-privilege integration user deliberately — everything the integration can do, it does as them |
| **Web Server (authorization code + PKCE)** | A human authorises an application | PKCE is required for public clients and harmless for confidential ones — always use it |
| **Refresh Token** | Long-lived access after an interactive grant | Pairs with the web server flow; store the refresh token as a secret |
| **Device** | Input-constrained devices | Kiosks, IoT |
| **Username-Password** | Nothing | Retired, enforced 20 February 2027, and already blocked in new orgs and by every ECA |

Default to **JWT Bearer** for backend integrations and **web server plus PKCE** for user-facing apps.

> Full setup for each: `references/oauth-and-eca.md`.

## 3. Inbound — External Client Apps vs Connected Apps

| | External Client App | Connected App (legacy) |
|---|---|---|
| Status | The default — create these | Supported; new creation disabled by default since Spring '26 |
| Model | Developer settings separated from admin policy; metadata-clean; second-generation-packaging friendly | Monolithic, awkward to package cleanly |
| Security posture | **Closed by default**; blocks legacy password flows outright | Historically open by default |
| Secret rotation | Staged Credentials API — rotate with no downtime | Manual, with a gap |

Build new integration identities as ECAs. Keep existing Connected Apps running, but migrate when you
touch one — and **inventory everything using username-password or SOAP `login()` now**, because both
have dates attached.

## 4. Inbound — Other Mechanisms

- **Session-based** — for a caller already in session, such as Visualforce or Aura calling Apex REST. A harvested session id is not a long-lived API credential and must never be treated as one.
- **Mutual TLS** — certificate-based transport authentication where the counterparty requires it. Configured for inbound traffic in Setup.
- **"Any API Auth"** — the user permission gating SOAP `login()` eligibility, enforced by default in new orgs.
- **Guest access** — an unauthenticated endpoint on a Site or Experience Cloud page runs as the guest user. Lock that profile down; see `dya-integration-inbound-apex` and `dya-permissions`.

## 5. Outbound — Named Credentials and External Credentials

The only correct way to authenticate an outbound callout. Two pieces of metadata:

- **Named Credential** — the **endpoint**: base URL, which External Credential to use, callout options.
- **External Credential** — the **authentication**: protocol plus **principals**. Tokens are stored encrypted in `UserExternalCredential`.

Reference it from Apex or Flow as `callout:My_Named_Credential/path`. No secret in code, no Remote
Site Setting.

**Principal types** decide whose identity the external system sees:

- **Named Principal** — one shared identity for every user. The usual choice for a system integration.
- **Per-User Principal** — each user authenticates individually, mapped through a permission set. Use it when the external system must know *which* user acted, for its own audit or authorisation.

**Protocols**: OAuth 2.0 (browser flow, web server, client credentials with a secret, client
credentials with a JWT assertion), JWT, **AWS Signature v4**, Basic (legacy), and Custom (a header
built from a formula).

> Setup, principal mapping and the `callout:` pattern in full: `references/named-external-credentials.md`.

## 6. Decision Matrix

| Need | Use |
|---|---|
| A backend system authenticates into Salesforce, no human | JWT Bearer + External Client App |
| Migrating an existing username-password integration, minimal change | Client Credentials + ECA, with a purpose-built integration user |
| A human authorises an application | Web Server flow + PKCE + ECA |
| Long-lived access after an interactive login | Refresh token, paired with the web server flow |
| The counterparty requires certificate transport auth | Mutual TLS |
| An AI or MCP client connects to the org | OAuth + PKCE + ECA with the `mcp_api` scope |
| Salesforce calls an external system under one shared identity | Named Credential + External Credential, Named Principal |
| Salesforce calls an external system as the acting user | External Credential, Per-User Principal |
| Salesforce calls AWS | External Credential, AWS Signature v4 |
| Anything still on SOAP `login()` or username-password | Migrate to OAuth + ECA, before the dates above |

## 7. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct approach |
|---|---|
| The username-password OAuth flow | Client credentials, or JWT bearer |
| Migrating off username-password to another password-carrying scheme | Certificate or client-credential based auth |
| SOAP `login()` for new authentication | OAuth with an External Client App |
| A new Connected App for a new integration | External Client App |
| A client secret or token hard-coded in code or metadata | External Client App / External Credential |
| A hard-coded endpoint plus a Remote Site Setting | Named Credential, referenced as `callout:` |
| Storing a harvested session id as an API key | A proper OAuth token lifecycle |
| An over-scoped integration user or permission set | Purpose-built and least-privilege — see `dya-permissions` |
| A broad guest profile on a Site endpoint | A minimal guest profile |
| Editing a secret by hand and accepting the downtime | Staged Credentials API rotation |
| Assuming an integration user escapes user-mode enforcement | From API 67.0 their object and field access governs what the code can read |
| Waiting for an enforcement date to find out what breaks | Test in a sandbox with the blocking setting on |

## Summary — The Five Commandments

1. **External Client Apps plus OAuth inbound; Named and External Credentials outbound.** Secrets never live in code or metadata.
2. **JWT Bearer is the backend default**, web server plus PKCE for user-facing. Username-password is retired — enforced 20 February 2027 — and SOAP `login()` follows in Summer '27.
3. **ECAs over Connected Apps** — closed by default, packageable, and rotatable without downtime.
4. **Least privilege everywhere.** Purpose-built integration users and principals; from API 67.0 their own object and field access governs what the code can read.
5. **Pick the principal type on purpose** — Named Principal for a shared system identity, Per-User when the external system must know who acted.
