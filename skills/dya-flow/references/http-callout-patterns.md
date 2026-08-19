# HTTP Callout in Flow — Reference Setup

Full implementation of the Flow HTTP Callout pattern referenced from SKILL.md §8. Load this file when adding a new REST integration to a flow, or when reviewing why an existing HTTP Callout action is failing.

The pattern was introduced as Beta in Spring '23 (GET only) and went GA with POST/PUT/DELETE/PATCH in Summer '23. It is now the default mechanism for REST integration that does not need custom marshalling — no Apex required.

## Architecture

```
Flow ── invokes ──► HTTP Callout Action
                          │
                          ├── reads ──► Named Credential (URL + auth)
                          │
                          └── conforms to ──► External Service (auto-generated)
                                                  │
                                                  └── exposes ──► Apex Types (auto-generated request/response DTOs)
```

You build the Named Credential once. The first time you create an HTTP Callout in Flow Builder pointing at it, the platform generates the External Service and the Apex types from your sample request/response payloads. Subsequent callouts in any flow reuse them.

## Step 1 — The Named Credential

Setup → Security → Named Credentials → New Legacy Named Credential (or new External Credential + Named Credential pair for OAuth flows).

**For a simple API-key REST service:**

- **Label** — `Pricing Engine`
- **Name** — `Pricing_Engine` (the API name)
- **URL** — `https://api.pricing.example.com`
- **Identity Type** — Anonymous (the API key travels in a custom header)
- **Authentication Protocol** — No Authentication
- **Generate Authorization Header** — unchecked
- **Allow Formulas in HTTP Header** — checked
- **Custom Headers** — add a header `X-Api-Key` with value `{!$Credential.PricingEngine.ApiKey}` (the credential value lives in a Custom Setting or Named Credential parameter, never inline in metadata).

**For OAuth 2.0 (Client Credentials, Authorization Code, JWT):**

- Create an **External Credential** with the auth protocol and principal.
- Create a **Named Credential** referencing the External Credential.
- The platform handles token acquisition, refresh, and header injection.

**Never** hardcode API endpoints, API keys, or tokens in Flow metadata or Apex strings. Named Credentials are the only correct location.

## Step 2 — Create the HTTP Callout Action in Flow Builder

In Flow Builder → New Action → "Create HTTP Callout" or open the Flow → Toolbox → Actions → "Create HTTP Callout".

**Fields:**

- **Label** — `Fetch Pricing Quote` (appears in the Action picker afterwards)
- **API Name** — `Fetch_Pricing_Quote`
- **Named Credential** — `Pricing_Engine`
- **URL Path** — `/v2/quote` (appended to the Named Credential's base URL)
- **Method** — `POST`
- **Sample Request Body** — paste a real JSON request payload:

  ```json
  {
    "productCode": "SKU-12345",
    "quantity": 10,
    "currency": "USD"
  }
  ```

- **Sample Response Body** — paste a real JSON response payload:

  ```json
  {
    "quoteId": "Q-7891011",
    "unitPrice": 99.99,
    "totalPrice": 999.90,
    "validUntil": "2026-06-01T00:00:00Z"
  }
  ```

  The platform parses both samples and generates two Apex types: `FetchPricingQuoteRequest` and `FetchPricingQuoteResponse`, with strongly-typed fields matching the JSON structure.

- **Headers** — add per-request headers if needed (e.g., `Content-Type: application/json` is added automatically; add `X-Idempotency-Key` if the API supports it).

Save. The action now appears in the Action picker for any flow type.

## Step 3 — Invoke the Action in a Flow

### GET — Simple Case

For a GET request, you usually have only URL parameters. Add them as query parameters in the action configuration. The action returns the response variable; reference it as `{!Fetch_Pricing_Quote.response}`.

### POST/PUT — Body Required

POST and PUT requests need a request body of the generated type. Build it with Assignment elements:

1. **Create a Record Variable** of type `FetchPricingQuoteRequest`.
2. **Assignment** — populate its fields: `quoteRequest.productCode = {!productSku}`, `quoteRequest.quantity = {!quantity}`, etc.
3. **Action: Fetch Pricing Quote** — pass `quoteRequest` as the `Body` input.
4. After the action, `{!Fetch_Pricing_Quote.response.quoteId}` and other response fields are available.

## Step 4 — Error Handling Is Mandatory

The HTTP Callout action does NOT throw on a non-2xx response. It returns the response with the status code populated. You MUST check it explicitly.

### Pattern

After the action:

1. **Decision element** — branch on `{!Fetch_Pricing_Quote.statusCode}`:
   - `>= 200 AND < 300` → success path
   - `>= 400 AND < 500` → client error path (log and surface to user)
   - `>= 500` → server error path (log, retry, or fail gracefully)
   - else → unknown status path
2. **Fault Path** — handles platform-level failures (network unreachable, Named Credential misconfigured). Connect the action's Fault Path to a logging element.

Both paths must exist. The status-code decision handles HTTP-level errors; the Fault Path handles platform-level errors. Skipping either creates silent failures in production.

## Step 5 — Asynchronous Path Requirement

HTTP Callouts CANNOT run on a record-triggered flow's synchronous path (the platform forbids callouts after uncommitted DML).

**Always place HTTP Callouts on:**

- The **Asynchronous Path** of a record-triggered flow, OR
- An **autolaunched flow** invoked from elsewhere, OR
- A **screen flow** (synchronous is fine — there is no committed DML preceding it), OR
- A **scheduled flow**.

Placing a callout on the main path of a record-triggered flow surfaces an error at activation time. Do not work around it; restructure the flow.

## Pagination Pattern

Many REST APIs paginate responses. The standard pattern uses a Loop:

1. **Variable**: `nextCursor` (Text, default empty).
2. **Variable**: `allRecords` (Record Collection of the response item type).
3. **Loop**:
   - **Action: Fetch Page** with `cursor = {!nextCursor}`.
   - **Decision**: if the response has results, append to `allRecords` and update `nextCursor`; if not, exit loop.
4. After the loop, `allRecords` holds the full result set.

Beware of governor limits — the **synchronous Apex CPU limit applies to flows** even though there is no visible Apex. For very large result sets, paginate across multiple invocations on an async path or move to scheduled-flow + cursor pattern.

## Reusable HTTP Callout for Multiple Flows

The External Service generated from one HTTP Callout is a metadata component (`ExternalServiceRegistration`). It can be exposed to:

- Other Flow Builder actions (automatically).
- Apex (via the generated `ExternalService.<name>` namespace).
- LWC (via Apex wrapper, or via the GraphQL adapter if it is a Salesforce object proxy).

Define the integration once; reuse it across the stack.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Hardcoded URL in the URL Path field | Put it in the Named Credential's base URL; only the path goes in the action |
| API key inline in a custom header value | `{!$Credential.<NCName>.<paramName>}` referencing a Named Credential parameter |
| HTTP Callout on a record-triggered flow's main path | Move to Asynchronous Path |
| No Decision element after the action checking `statusCode` | Always branch on status; never assume success |
| No Fault Path on the action | Always connect to a logging element |
| Writing Apex to do a callout that has no custom marshalling | Use Flow HTTP Callout — no Apex needed |
| Building the callout per record inside a flow loop | Build the request once, invoke once per logical operation |
| Logging callout errors only via `System.debug` | Route through Platform Event logger (see `dya-apex` §11) |
