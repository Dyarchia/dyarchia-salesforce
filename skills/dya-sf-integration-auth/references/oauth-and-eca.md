# OAuth Flows & External Client Apps — Reference (Winter '27 / API v68.0)

Load from `dya-sf-integration-auth` for inbound authentication detail.

## The Flows

### JWT Bearer
The client signs a JWT with a private key; Salesforce trusts the matching certificate on the ECA.

1. Create an **External Client App**, enable OAuth, upload the **digital certificate**, set scopes (e.g. `api`, `refresh_token` as needed), and pre-authorise the integration user via a permission set/profile.
2. The client builds a JWT (`iss` = consumer key, `sub` = integration username, `aud` = login URL, short `exp`) and signs it with the private key.
3. POST to the token endpoint with `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` and the assertion → receive an access token.
4. Call the API with `Authorization: Bearer <token>`.

Use it for ETL, middleware and backend services. Rotate by swapping the certificate.

### Web Server (authorization code + PKCE)
PKCE uses a code challenge and verifier. The flow returns an authorization code, exchanged for access + refresh tokens.

### Client Credentials
Use it when certificate management is undesirable and a secret is acceptable; it is simpler than JWT but uses a shared secret. Configure the **run-as user** on the ECA.

### Refresh Token
Gives long-lived access without re-prompting. Treat refresh tokens as high-value credentials.

### Device
The device shows a code the user enters on another screen.

## External Client Apps vs Connected Apps

| Dimension | External Client App | Connected App |
|---|---|---|
| Secret rotation | **Staged Credentials API**: stage new secret, cut over, retire old | Manual, disruptive |
| Canvas | Supported (added Spring '26) | Supported |

## MCP / Agent Auth

Scope the user tightly: every MCP call runs as the authenticated user with full CRUD/FLS/sharing. External AI clients authenticate like hosted MCP servers; tokens must be JWT-shaped. See `dya-sf-integration-connectors-mcp`.

## Token Hygiene

- Use short-lived access tokens; refresh rather than holding long sessions.
- Store refresh tokens/private keys in a secret manager, never in code or config files.
- Request only the scopes needed (`api`, `refresh_token`, `mcp_api`, …).
- Rotate via Staged Credentials; monitor with Login History / API usage event logs.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Over-broad scopes | Minimal scope set |
| Long-lived access tokens | Short tokens + refresh |
