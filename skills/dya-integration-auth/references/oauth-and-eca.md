# OAuth Flows & External Client Apps — Reference (Winter '27 / API v68.0)

Load from `dya-integration-auth` for inbound authentication detail. External Client Apps (ECAs) are the new default container for OAuth client configuration.

## The Flows, Decisively

### JWT Bearer (server-to-server — the backend default)
No user, no interactive step. The client signs a JWT with a private key; Salesforce trusts the matching certificate on the ECA.

1. Create an **External Client App**, enable OAuth, upload the **digital certificate**, set scopes (e.g. `api`, `refresh_token` as needed), and pre-authorise the integration user via a permission set/profile.
2. The client builds a JWT (`iss` = consumer key, `sub` = integration username, `aud` = login URL, short `exp`), signs it with the private key.
3. POST to the token endpoint with `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` and the assertion → receive an access token.
4. Call the API with `Authorization: Bearer <token>`.

Best for: ETL, middleware, backend services. No stored password; rotate by swapping the certificate.

### Web Server (authorization code + PKCE)
A user authorises a web app. Use PKCE (code challenge/verifier) — mandatory for public clients, recommended for all. Returns an authorization code exchanged for access + refresh tokens.

### Client Credentials
Pure machine-to-machine bound to a single **run-as user** configured on the ECA. Simpler than JWT (shared secret), but pick a least-privilege integration user. Good when certificate management is undesirable and a secret is acceptable.

### Refresh Token
Pairs with the web-server flow to obtain long-lived access without re-prompting. Store refresh tokens securely; they're high-value credentials.

### Device
For input-constrained devices (kiosks, IoT): the device shows a code the user enters on another screen.

### Username-Password — DO NOT USE
Not supported by ECAs, blocked by default in new orgs, and retired for connected apps by a Winter '27
Release Update **enforced on 20 February 2027**. On that date an integration posting
`grant_type=password` stops receiving a token.

Migrating: **client credentials** is the smallest change — the app runs as one designated integration
user and no password is stored. **JWT bearer** replaces the shared secret with a signed certificate
and is the better answer for anything high value. **Web server plus PKCE** where a human is actually
authorising. Never migrate to another scheme that carries a password.

## External Client Apps vs Connected Apps

| Dimension | External Client App | Connected App |
|---|---|---|
| Creation | The default going forward | New-creation disabled by default (Spring '26) |
| Structure | Developer settings separated from admin **policies** (packageable cleanly, 2GP) | Monolithic |
| Default posture | **Closed by default**; legacy password flows blocked | Historically open |
| Secret rotation | **Staged Credentials API** (stage new secret, cut over, retire old — zero downtime) | Manual, disruptive |
| Canvas | Supported (added Spring '26) | Supported |

Migration guidance: build all new identities as ECAs; when revisiting a Connected App, recreate it as an ECA; inventory and migrate username-password integrations before **20 February 2027** and SOAP `login()` before its **Summer '27** retirement (the **"Any API Auth"** permission already gates SOAP `login()` in new orgs).

## MCP / Agent Auth

Hosted MCP servers (and external AI clients) authenticate with **OAuth + PKCE** through an ECA configured with the **`mcp_api`** and **`refresh_token`** scopes; tokens must be JWT-shaped. Every MCP call then runs as the authenticated user with full CRUD/FLS/sharing — so scope the user tightly. See `dya-integration-connectors-mcp`.

## Token Hygiene

- Short-lived access tokens; refresh rather than long sessions.
- Store refresh tokens/private keys in a secret manager, never in code or config files.
- Scope minimally (`api`, `refresh_token`, `mcp_api`, …) — request only what's needed.
- Rotate via Staged Credentials; monitor with Login History / API usage event logs.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Username-Password flow | JWT Bearer / Web Server + PKCE |
| SOAP `login()` | OAuth via ECA |
| New Connected App | External Client App |
| Storing private key/secret in code | Secret manager + ECA |
| Over-broad scopes | Minimal scope set |
| Long-lived access tokens | Short tokens + refresh |
| Manual disruptive secret swap | Staged Credentials API |
