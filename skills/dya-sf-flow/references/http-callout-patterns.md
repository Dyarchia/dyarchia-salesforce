# HTTP Callout in Flow — Reference Setup

Full implementation of SKILL.md §7. Load when adding a REST integration to a flow, or when diagnosing a failing HTTP Callout action.

Beta in Spring '23 (GET only), GA with POST/PUT/DELETE/PATCH in Summer '23.

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

The first HTTP Callout created against a Named Credential generates the External Service and the Apex types from your sample payloads; later callouts in any flow reuse them.

## Step 1 — The Named Credential

Setup → Security → Named Credentials → New Legacy Named Credential (or a new External Credential + Named Credential pair for OAuth flows).

**Simple API-key REST service:**

- **Label** — `Pricing Engine`
- **Name** — `Pricing_Engine` (the API name)
- **URL** — `https://api.pricing.example.com`
- **Identity Type** — Anonymous (the API key travels in a custom header)
- **Authentication Protocol** — No Authentication
- **Generate Authorization Header** — unchecked
- **Allow Formulas in HTTP Header** — checked
- **Custom Headers** — header `X-Api-Key` with value `{!$Credential.PricingEngine.ApiKey}` (the value lives in a Custom Setting or Named Credential parameter, never inline in metadata).

**OAuth 2.0 (Client Credentials, Authorization Code, JWT):**

- Create an **External Credential** with the auth protocol and principal.
- Create a **Named Credential** referencing the External Credential.
- The platform handles token acquisition, refresh, and header injection.

## Step 2 — Create the HTTP Callout Action in Flow Builder

Flow Builder → New Action → "Create HTTP Callout", or open the Flow → Toolbox → Actions → "Create HTTP Callout".

**Fields:**

- **Label** — `Fetch Pricing Quote` (shown in the Action picker)
- **API Name** — `Fetch_Pricing_Quote`
- **Named Credential** — `Pricing_Engine`
- **URL Path** — `/v2/quote` (appended to the Named Credential's base URL)
- **Method** — `POST`
- **Sample Request Body** — a real JSON payload:

  ```json
  {
    "productCode": "SKU-12345",
    "quantity": 10,
    "currency": "USD"
  }
  ```

- **Sample Response Body** — a real JSON payload:

  ```json
  {
    "quoteId": "Q-7891011",
    "unitPrice": 99.99,
    "totalPrice": 999.90,
    "validUntil": "2026-06-01T00:00:00Z"
  }
  ```

  The platform generates two Apex types from the samples, `FetchPricingQuoteRequest` and `FetchPricingQuoteResponse`, with strongly-typed fields matching the JSON structure.

- **Headers** — per-request headers if needed (`Content-Type: application/json` is added automatically; add `X-Idempotency-Key` if the API supports it).

Save. The action now appears in the Action picker for any flow type.

## Step 3 — Invoke the Action in a Flow

### GET — Simple Case

Add URL parameters as query parameters in the action configuration. Reference the response as `{!Fetch_Pricing_Quote.response}`.

### POST/PUT — Body Required

1. **Create a Record Variable** of type `FetchPricingQuoteRequest`.
2. **Assignment** — populate its fields: `quoteRequest.productCode = {!productSku}`, `quoteRequest.quantity = {!quantity}`, etc.
3. **Action: Fetch Pricing Quote** — pass `quoteRequest` as the `Body` input.
4. After the action, `{!Fetch_Pricing_Quote.response.quoteId}` and the other response fields are available.

## Step 4 — Error Handling Is Mandatory

After the action:

1. **Decision element** — branch on `{!Fetch_Pricing_Quote.statusCode}`:
   - `>= 200 AND < 300` → success path
   - `>= 400 AND < 500` → client error path (log and surface to user)
   - `>= 500` → server error path (log, retry, or fail gracefully)
   - else → unknown status path
2. **Fault Path** — handles platform-level failures (network unreachable, Named Credential misconfigured). Connect it to an error-handling element.

Skipping either creates silent failures in production.

## Step 5 — Asynchronous Path Requirement

The synchronous path of a record-triggered flow forbids callouts after uncommitted DML. **Place HTTP Callouts on:**

- The **Asynchronous Path** of a record-triggered flow, OR
- An **autolaunched flow** invoked from elsewhere, OR
- A **screen flow** (synchronous is fine — no uncommitted DML precedes it), OR
- A **scheduled flow**.

A callout on the main path of a record-triggered flow errors at activation time. Restructure the flow.

## Pagination Pattern

Paginate with a Loop:

1. **Variable**: `nextCursor` (Text, default empty).
2. **Variable**: `allRecords` (Record Collection of the response item type).
3. **Loop**:
   - **Action: Fetch Page** with `cursor = {!nextCursor}`.
   - **Decision**: if the response has results, append to `allRecords` and update `nextCursor`; otherwise exit the loop.
4. After the loop, `allRecords` holds the full result set.

For very large result sets, paginate across multiple invocations on an async path, or move to a scheduled-flow + cursor pattern; the **synchronous Apex CPU limit applies to flows** even with no visible Apex.

## Reusable HTTP Callout for Multiple Flows

The generated External Service is a metadata component (`ExternalServiceRegistration`), exposed to:

- Other Flow Builder actions (automatically).
- Apex (via the generated `ExternalService.<name>` namespace).
- LWC (via an Apex wrapper, or the GraphQL adapter if it is a Salesforce object proxy).

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Hardcoded URL in the URL Path field | Put it in the Named Credential's base URL; only the path goes in the action |
| API key inline in a custom header value | `{!$Credential.<NCName>.<paramName>}` referencing a Named Credential parameter |
| HTTP Callout on a record-triggered flow's main path | Move to Asynchronous Path |
| No Decision element after the action checking `statusCode` | Always branch on status; never assume success |
| No Fault Path on the action | Always connect to an error-handling element |
| Writing Apex to do a callout that has no custom marshalling | Use Flow HTTP Callout — no Apex needed |
| Building the callout per record inside a flow loop | Build the request once, invoke once per logical operation |
| A callout error that reaches nobody | Surface it where the org already looks (see `dya-sf-apex` §11) |
