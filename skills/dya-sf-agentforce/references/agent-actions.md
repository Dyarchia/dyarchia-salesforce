# Agent Actions — Reference (Winter '27 / API v68.0)

Every way to implement an agent action, declare it in Agent Script, wire it into reasoning, secure it
and debug it. Apex-specific depth: `references/apex-actions.md`.

## 1. Definition versus tool

An action lives in two places, and the two do different jobs.

| Block | Holds | Who calls it |
|---|---|---|
| `subagent.actions` | The **definition**: `target`, `inputs`, `outputs`, display flags | Your `->` logic, with `run` |
| `subagent.reasoning.actions` | A **tool**: a pointer to a definition, a `@utils` function or a subagent, with `with` / `set` bindings | The LLM, at its discretion |

- An action defined but never listed under `reasoning.actions` is invisible to the LLM; it runs only
  where your logic says `run`.
- Actions are not shared between subagents. Importing an action from the asset library gives each
  subagent its own copy; define it again in every subagent that runs it.
- An action created in Agentforce Builder and exposed as a tool gets the same name in both blocks.
  In hand-written script the two names may differ (`send_code_action` defined, `send_code_tool`
  exposed); reference the tool name from prompts.

### When each invocation runs

| How | Where | When it executes | Inputs |
|---|---|---|---|
| `run @actions.x` | `reasoning.instructions: ->` | Every time the subagent is parsed, **before** the prompt reaches the LLM | Bind every input with `with`; no slot-filling |
| `run @actions.x` | `before_reasoning` / `after_reasoning` | Before reasoning starts / after the reasoning loop exits, every request; `after_reasoning` is skipped when the subagent transitions away mid-run | Bind every input |
| Tool | `reasoning.actions` | Only if the LLM chooses it, when it receives the resolved prompt | `with p = ...` or unbound required inputs are slot-filled |
| Chained `run` under a tool | Indented under the tool entry | Immediately after the LLM-chosen tool, deterministically | Bind every input; slot-filling is not available |

```agentscript
subagent order_help:
    description: "Looks up and schedules customer orders."

    reasoning:
        instructions: ->
            if @variables.order_summary == "":
                run @actions.get_current_order
                    with email = @variables.member_email
                    set @variables.order_summary = @outputs.order_summary
            | Greet the member and show {!@variables.order_summary}.
              To look up an older order, use {!@actions.find_order}.

        actions:
            find_order: @actions.get_order_by_number
                with order_number = ...
                set @variables.order_details = @outputs.order_details
                run @actions.get_delivery_slot
                    with order_details = @variables.order_details
                    set @variables.delivery_date = @outputs.delivery_date
```

Reference a tool from a `|` prompt with `{!@actions.<tool>}` when the LLM must call it at a specific
point; the LLM already sees every tool's name and description, so add the reference for ordering,
not for discovery.

## 2. Choosing the implementation

Pick the least-code option that fits.

| Need | Implementation | How it reaches Agent Script |
|---|---|---|
| Declarative orchestration, record DML, approvals, reuse of an existing automation | **Autolaunched Flow** | `target: "flow://<FlowApiName>"` |
| Deterministic logic, callouts, cross-object work, complex inputs/outputs, custom UI, citations | **Apex `@InvocableMethod`** | `target: "apex://<ClassName>"` |
| Text generated or transformed by an LLM, grounded in records or a retriever | **Prompt template** | `target: "prompt://<TemplateApiName>"` |
| A read-only SOQL query exposed as-is | **Named Query API** | Builder: Reference Action Type **API** › **Salesforce Named Query API** (§9) |
| An existing `@RestResource` class | **Apex REST action** via OpenAPI + API Catalog | Builder: Apex reference action type (§10) |
| An existing `@AuraEnabled` controller method | **AuraEnabled action** via OpenAPI + API Catalog | Builder: Apex reference action type (§10) |
| An external HTTP API described by OpenAPI | **External Service** operation | Builder; see `dya-sf-integration-outbound` |
| Tools of an MCP server | MCP server registered in the **API Catalog** | Builder; see `dya-sf-integration-connectors-mcp` |
| Delegate to another whole Agentforce agent | **Connected subagent** | `connected_subagent` block, `target: "agentforce://..."` (§11) |
| Delegate to another subagent of this agent and come back | Subagent as a tool | `tool_name: @subagent.<name>` |
| Store what the user said into variables | Utility | `@utils.setVariables` with `...` bindings |

**Agent Script documents exactly three action target schemes: `apex://`, `flow://` and `prompt://`.**
For every other reference action type, create the action in Agentforce Builder, then read the
`.agent` file the builder writes (retrieve the authoring bundle; see `dya-sf-cli`) and keep the
target string it generated. Never hand-write a scheme you have not seen the builder emit.

One official example writes a prompt template target as `generatePromptResponse://<Template>`; the
Agent Script reference and the CLI's agent template use `prompt://`. Use `prompt://`.

Grounding in knowledge and data libraries: `references/knowledge-and-data-libraries.md`.

## 3. Action definition properties

| Property | Required | Meaning |
|---|---|---|
| action name | Yes | Starts with a letter; letters, digits and single underscores; no trailing underscore; max 80 characters. Use `snake_case` |
| `target` | Yes | `{TYPE}://{DEVELOPER_NAME}` of the executable |
| `description` | No | What the action does and when to use it. The LLM reads it to decide whether to call the action; when omitted, one is generated from the name. Multiline with `\|` |
| `label` | No | Name shown to the user; generated from the name (`check_weather` → "Check Weather") |
| `inputs` | No | Input parameters (§4) |
| `outputs` | No | Output parameters (§5) |
| `require_user_confirmation` | No | `True` makes the user confirm before the action runs |
| `include_in_progress_indicator` | No | `True` shows a progress indicator while it runs |
| `progress_indicator_message` | No | The text of that indicator, e.g. `"Checking your order..."` |

A tool entry under `reasoning.actions` takes its own `description`, `available when`, `with`, `set`,
and chained `run` / `transition to`.

- **Write the description as routing copy:** what it does, when to use it, what it returns. Name the
  trigger situation, not the implementation.
- **Set `require_user_confirmation: True` on every action that changes data or spends money.** It is
  a platform-level gate, independent of what the prompt tells the LLM.
- **Gate tools with `available when`** on deterministic state (`@variables.verified == True`); the
  LLM cannot call a tool whose condition is false.

## 4. Inputs

```agentscript
inputs:
    order_number: string
        label: "Order Number"
        description: "The order number the customer gives, e.g. 00012345"
        is_required: True
        is_user_input: True
```

| Input property | Meaning |
|---|---|
| `description` | What the value is and its format; the LLM fills the input from it |
| `label` | Display label |
| `is_required` | `True` when the target cannot run without it |
| `is_user_input` | `True` when the value is collected from the user in the conversation |
| `complex_data_type_name` | The Lightning type, required when the type is `object` (§6) |

Slot-filling rules:

- The LLM fills an input only when it is **required and unbound**, or bound to `...` on a tool.
- Chained actions and `run` statements are deterministic: bind every input to a variable or literal.
- **Bind tool inputs to variables sparingly.** A tool is offered once the agent holds all its
  relevant inputs, so over-binding makes the LLM select tools inconsistently. Bind only values the
  LLM must not choose (an Id, a verified email), and confirm the choice in testing.
- For values the LLM must never invent (record Ids, amounts), resolve them with a deterministic
  `run` first and bind the variable.

## 5. Outputs

By default the agent keeps every output in context **for the rest of the session** and may use it to
answer later questions.

```agentscript
outputs:
    risk_score: number
        label: "Risk Score"
        description: "Internal fraud score, 0 to 100"
        filter_from_agent: True
    refund_reference: string
        label: "Refund Reference"
        description: "Reference number to give the customer"
        is_displayable: True
```

| Output property | Meaning |
|---|---|
| `description` | What the value means; also tells the LLM how to use it ("if empty, tell the customer...") |
| `label` | Display label |
| `filter_from_agent` | `True` excludes the value from the agent's context; default `False` |
| `is_displayable` | Whether the value is shown to the user in the action's rendered output |
| `is_used_by_planner` | Whether the reasoning engine uses the value; Salesforce's own CLI template pairs `True` with `is_displayable: False` on a prompt response |
| `complex_data_type_name` | The Lightning type, required for `object` / `list[object]` (§6) |
| `developer_name` | Overrides the parameter's developer name; the official examples omit it |

- **Set `filter_from_agent: True` on internal values** the logic needs and the model must never
  repeat (scores, internal codes, other customers' data); capture them with `set @variables.x` and
  branch on them in `->` logic.
- **Capture an output in a variable** with `set @variables.x = @outputs.y` whenever a condition, a
  later action or another subagent needs it.
- Declare only the outputs you use; the official examples declare a subset of the target's outputs.

## 6. Types

Agent Script parameter types: `string`, `number` (floating point), `integer`, `long`, `boolean`,
`object`, `date` (YYYY-MM-DD), `datetime`, `time`, `currency`, and `list[<type>]`. **`id` is
deprecated: declare Salesforce Ids as `string`.**

Complex values use `object` (or `list[object]`) plus `complex_data_type_name`:

| Value the target exchanges | Declare |
|---|---|
| A record, e.g. a Flow `lightning__recordInfoType` output | `object` + `complex_data_type_name: "lightning__recordInfoType"` |
| A list of records | `list[object]` + `"lightning__recordInfoType"` |
| An Apex `Date` input | `object` + `"lightning__dateType"` |
| Plain text | `string` (the CLI template also adds `"lightning__textType"` to prompt I/O) |
| An Apex-defined class | `object` + `"@apexClassType/c__<ClassName>"` |
| A list of an Apex-defined class | `list[object]` + `"@apexClassType/c__<ClassName>"` |

- **Copy `complex_data_type_name` from the action Agentforce Builder generates** rather than
  guessing; the type comes from the target's signature.
- Run `sf agent validate authoring-bundle --api-name <Bundle>` after every action edit.

### Lightning types and custom UI

Agent action inputs and outputs map to **standard Lightning types** (`lightning__dateType`,
`lightning__numberType`, `lightning__multilineTextType`, `lightning__listType`, ...). The type picks
the generated input widget and output renderer: a date picker for a date, a list for a list.

To brand the UI, build a **custom Lightning type** (`LightningTypeBundle` metadata, with
`editor.json` / `renderer.json` pointing at Lightning web components) and select it as the action
parameter's **Input Rendering** or **Output Rendering**. A custom UI applies **only to actions whose
inputs or outputs are Apex classes**. Component side: `dya-sf-lwc`. A custom component that exposes
a public `getFormattedValue()` method gets the global copy button in agent responses.

## 7. Parameter names bind by exact API name

The keys under `inputs:` and `outputs:` are the target's parameter API names, case-sensitive.

| Target | Input / output key |
|---|---|
| `apex://` | The `@InvocableVariable` field name of the request / response class (`order_number`, `dateToCheck`) |
| `flow://` | The Flow variable API name marked *Available for input* / *Available for output* |
| `prompt://` | Inputs: `"Input:<InputApiName>"`, quoted; output: `promptResponse` |

```agentscript
check_events:
    description: "Find local events matching the guest's interests."
    target: "prompt://Get_Event_Info"
    inputs:
        "Input:Event_Type": string
            description: "Kind of event the guest wants, e.g. live music"
            is_required: True
    outputs:
        promptResponse: string
            description: "Generated event suggestions"
```

- **Quote a key that is not a plain identifier** (`"Input:Event_Type"`, `"FirstName"` as the Flow
  names it), both in the definition and in `with "Input:Event_Type" = @variables.interest`.
- **Rename the Apex field or Flow variable and the script key together**; the key is the binding.
- The tool name and the definition name are yours to choose; only parameter keys are bound.

## 8. Wiring patterns

| Goal | Pattern |
|---|---|
| Data ready before the LLM speaks | Guarded `run` at the top of `->`: `if @variables.x == "":` then `run`, `set` |
| Never re-fetch | The same guard; it also stops repeated calls on every turn |
| Fixed sequence | Consecutive `run` statements, the first output fed into the second through a variable |
| Follow-up after an LLM choice | Chained `run` under the tool |
| Move on after an action | `transition to @subagent.<next>` under the tool |
| Branch on a result | `run`, `set`, then `if` / `else` in `->` |
| Expose only when valid | `available when` on the tool |
| Run once the subagent finishes | `run` in `after_reasoning` |

```agentscript
reasoning:
    instructions: ->
        run @actions.check_eligibility
            with customer_id = @variables.customer_id
            set @variables.is_eligible = @outputs.eligible
        if @variables.is_eligible == True:
            | Offer the upgrade using {!@actions.apply_upgrade}.
        else:
            | Explain that the account is not eligible for an upgrade.

    actions:
        apply_upgrade: @actions.apply_upgrade
            available when @variables.is_eligible == True
            with customer_id = @variables.customer_id
            set @variables.upgrade_status = @outputs.status
            transition to @subagent.confirmation
```

Control-flow traps (`run` inside `|`, re-entry, transitions): `references/agent-control-flow-pitfalls.md`.
Fuller patterns: `references/agent-script-patterns.md`.

## 9. Named Query API actions

A Named Query API is a SOQL query saved in Setup and exposed as an API; it needs no code.

1. Setup › **User Interface** › enable **Salesforce Platform REST API, Named Query for Agent
   Actions**.
2. Create and save the Named Query API (REST API Developer Guide, *Named Query API*).
3. Setup › **API Catalog**: **activate** the named query; until activated it is not offered as an
   action.
4. Setup › **Agentforce Assets** › Actions › **New Agent Action** › Reference Action Type **API** ›
   Category **Salesforce Named Query API** › pick the query.

| Who | Permission |
|---|---|
| Author | *Allows users to create, read, update and delete Named Query API records* |
| Agent's running user | **View Developer Name** or **View Setup and Configuration**, plus read access to every queried object and field |

Use a named query for a fixed, read-only lookup. Switch to Apex or Flow when the query needs
branching, writes, more than one object round trip, or a shaped result.

## 10. Apex REST and `@AuraEnabled` actions through OpenAPI

Both routes turn existing Apex into agent actions by describing it in an OpenAPI 3.0 document,
deploying it as `ExternalServiceRegistration` metadata into the **API Catalog**, activating its
operations, and creating an action from the resulting Apex reference action type.

### Prerequisites

| Requirement | Apex REST | `@AuraEnabled` |
|---|---|---|
| Class annotation | `@RestResource(urlMapping=...)` with at least one `@HttpGet`/`@HttpPost`/`@HttpPut`/`@HttpPatch`/`@HttpDelete` method | `@AuraEnabled` methods |
| Sharing keyword | Explicit `with sharing`, `without sharing` or `inherited sharing` | Same |
| Managed-package classes | Not eligible | Not eligible |
| Tooling | Agentforce Vibes Extension (Salesforce Extension Pack in VS Code / Open VSX, or Agentforce Vibes IDE) | Same; the commands are **Beta** |
| Validation | MuleSoft for Agentforce Extension Pack governance rulesets (recommended) | Same |

### Generate, verify, deploy

1. Retrieve the class (Org Browser or `sf project retrieve start`), then run **SFDX: Refresh SObjects
   Definitions**.
2. Decompose ESR metadata so the spec is an editable YAML file:

   ```bash
   sf project convert source-behavior --behavior decomposeExternalServiceRegistrationBeta
   ```

3. Run **SFDX: Create OpenAPI Document from this Class** (`(Beta)` for `@AuraEnabled`). It writes
   `<Class>.yaml` and `<Class>.externalServiceRegistration-meta.xml` under
   `externalServiceRegistration/`.
4. Verify the YAML against the class (checklist below), fix the Problems panel, then run **SFDX:
   Validate OpenAPI Document** or the MuleSoft governance validation (the SFDX command disappears
   when the MuleSoft pack is installed).
5. Deploy the Apex class first; deploying the ESR does not deploy the class. Then deploy the
   `.externalServiceRegistration-meta.xml`.
6. Setup › **API Catalog** › **Apex** (or the **AuraEnabled** source list): activate the operations.
7. Create the action: Agentforce Assets › **New Agent Action**, using the Apex reference action type.

After changing the class, rerun the generate command and choose **Overwrite** (irreversible) or
**Manually merge with existing ESR** (timestamped files in `esr_files_for_merge/`), then validate and
redeploy.

The catalog description comes from the YAML's top-level `info.description`, not the XML
`<description>`.

### Verification checklist

- `openapi: 3.0.0`, a single server `url: /services/apexrest` (Apex REST), and `paths` that match
  `urlMapping` exactly.
- A path parameter (`/Cases/{caseId}`) for every Id read from the URI, declared `in: path`,
  `required: true`; query-string values declared `in: query`.
- Request body shape matches what the method reads; responses in the 2xx range match the return
  type.
- Security: OAuth2, or HTTP bearer.
- Media types: `application/json` for request bodies and parameters; responses `application/json`
  for `type: object`, `text/plain` for `type: string`.
- Leave out: path-level `servers`, `options`, `head`, `trace`; operation-level `callbacks`,
  `deprecated`, `security`, `servers`; parameter `deprecated`, `explode`, `allowReserved`, `in:
  cookie`; response `headers`; media-type `encoding`; `not` in schemas.
- Never declare the headers `cookie`, `set-cookie`, `set-cookie2`, `content-length`,
  `Authorization`.
- Add `example` / `examples` to parameters and headers.
- Write a detailed `description` on every path, operation and parameter (Markdown allowed).

### Extensions that create actions on deploy

| Extension | Meaning |
|---|---|
| `x-sfdc/agent/action/publishAsAgentAction` | `true` creates an agent action for the operation on deploy |
| `x-sfdc/agent/action/isUserInput` | Required with the above: `true` collects the field from the user |
| `x-sfdc/agent/action/isDisplayable` | Required with the above: `true` shows the field to the user |
| `x-sfdc/privacy/isPii` | Optional: `true` routes the operation's queries through the PII service |

```yaml
paths:
  /orders/{orderId}:
    get:
      operationId: getOrder
      description: Returns status and delivery date for one order. Use when the customer asks where an order is.
      x-sfdc:
        agent:
          action:
            publishAsAgentAction: true
components:
  schemas:
    Order:
      x-sfdc:
        agent:
          action:
            isDisplayable: true
```

Put field-level extensions inside an inline schema, never in one reached through `$ref`.

### ESR metadata for an Apex REST registration

| Field | Value |
|---|---|
| `registrationProvider` | The Apex REST class name |
| `registrationProviderType` | `ApexRest` |
| `schemaType` | `OpenApi3` |
| `namedCredential` | Null: the service runs in the org |
| `schema` | The YAML; empty in source when the project decomposes ESRs |

Apex REST registrations do not appear under External Services in Setup; find them in the API
Catalog.

### Limits

API Catalog limits cap active operations and objects. At the cap, deactivate or delete unused
operations. **Remove a registration from every agent action that uses it before deactivating or
deleting it.**

## 11. Other agents, MCP and External Services

### Connected subagent

```agentscript
connected_subagent billing_agent:
    label: "Billing Agent"
    target: "agentforce://<target filled in by Agentforce Builder>"
    description: "Answers invoice, payment and refund questions."
    loading_text: "Checking billing..."
    inputs:
        customer_id: string = @variables.customer_id
```

- Let Agentforce Builder fill `target` when you connect the agent; do not compose it by hand.
- Route with `@utils.transition to @connected_subagent.billing_agent` (handoff) or list
  `@connected_subagent.billing_agent` as a tool (supervisor).
- Inputs flow one way: orchestrator to connected agent. Nothing comes back as a variable.
- `after_response` runs after the connected agent answers (`if`, `set`, `transition`);
  `delegate_escalation: True` lets a handoff-mode connected agent escalate to a human.

### MCP tools

Register the MCP server in the **API Catalog**; its tools, prompts and resources then become
available as agent actions. Server registration and auth: `dya-sf-integration-connectors-mcp`.

### External Services

An External Service registered from an OpenAPI spec exposes its operations as reference actions.
Named credentials and the callout side: `dya-sf-integration-outbound`.

## 12. Security

An agent runs in the context of a user, and that user's permissions grant or deny every action.

- **Service agents run as `default_agent_user`**, set in the `access` block. Create it with
  `sf org create agent-user`; it gets the Einstein Agent User profile and cannot log in. Setup and
  permission set design: `references/org-setup-and-agent-user.md` and `dya-sf-permissions`.
- **Grant the running user, per action:**

  | Action type | Grant |
  |---|---|
  | Apex | Apex class access to the invocable class and every class it calls |
  | Flow | The **Run Flows** user permission, plus the flow's object and field access |
  | Named Query | View Developer Name or View Setup and Configuration, plus read on the queried data |
  | Any | Object CRUD and FLS for every record the action reads or writes |

- **Enforce access inside the implementation.** Apex: `with sharing`, `WITH USER_MODE`,
  `AccessLevel.USER_MODE` (`references/apex-actions.md`). Flow: run the flow in user context
  (`dya-sf-flow`).
- **Never trust an LLM-filled input as authorization.** Re-derive ownership server-side ("does this
  order belong to the verified contact?") before reading or writing.
- **Gate state-changing actions** with `available when` on verification state and
  `require_user_confirmation: True`.
- **Keep sensitive outputs out of context** with `filter_from_agent: True`; mark PII operations
  with `x-sfdc/privacy/isPii` on the OpenAPI route.
- Simulated preview mocks every action and never exercises permissions: test live, as the real
  agent user.

## 13. Errors the model can act on

- **Return failure as output, do not throw.** Give every action a status output and a
  human-readable message; describe in the output `description` what the agent must do with an empty
  or failed result.
- **Make "nothing found" a value**, e.g. `"No products match those filters."`, so the LLM does not
  improvise one.
- **Instruct the subagent to call the action** when it must always be used; an agent can skip an
  action the instructions never mention.
- Customise the generic failure text with `system.messages.error`; see `references/agent-script.md`.
- `PLANNER_LLM_GATEWAY_TIMEOUT` grows with the number of actions offered: keep each subagent's tool
  list short and gate the rest with `available when`.
- Runtime diagnosis (traces, session data): `references/observability.md` and
  `references/troubleshooting.md`.

## 14. Deploy, preview, test

- **Deploy the Apex, Flow or template before publishing the agent.** Publishing an authoring bundle
  does not deploy them, and an agent whose `flow://` target is missing does not publish.

  ```bash
  sf project deploy start --metadata "ApexClass:GetOrderAction" --metadata "Flow:Get_Order"
  sf agent validate authoring-bundle --api-name Order_Agent
  sf agent publish authoring-bundle --api-name Order_Agent
  ```

- **Preview simulated first, then live.** Simulated mode mocks every action from its description;
  live mode runs the real targets as `default_agent_user`. Published agents always run live.

  ```bash
  sf agent preview --authoring-bundle Order_Agent
  sf agent preview --authoring-bundle Order_Agent --use-live-actions --apex-debug
  sf agent preview start --authoring-bundle Order_Agent --use-live-actions
  ```

  `sf agent preview` is simulated unless `--use-live-actions` is passed; `sf agent preview start`
  requires `--use-live-actions` or `--simulate-actions` with `--authoring-bundle`.
- Assert action selection in tests with `expectedActions` (action API names) in the test spec:
  `references/testing-and-evaluation.md`.

## 15. Anti-Patterns — NEVER Do These

| Anti-Pattern | Correct Approach |
|---|---|
| Defining an action and expecting the LLM to call it | List it under `reasoning.actions` as a tool, or `run` it in logic |
| Hand-writing an undocumented target scheme | Create the action in Builder, keep the target it writes |
| Script keys that differ from Apex field / Flow variable names | Use the exact, case-sensitive API names |
| Binding every tool input to a variable | Bind only values the LLM must not choose; slot-fill the rest |
| LLM-chosen record Ids or amounts | Resolve them with a deterministic `run`, bind the variable |
| Internal scores left in context | `filter_from_agent: True`, branch in `->` logic |
| Write actions with no gate | `available when` plus `require_user_confirmation: True` |
| Re-running a lookup every turn | Guard the `run` with an emptiness check |
| Throwing to the agent | A status and message output with a described meaning |
| One action doing everything | Several narrow actions with sharp descriptions |
| Publishing before deploying the target | Deploy Apex / Flow / template, validate, then publish |
| Deactivating a catalog operation still in use | Remove it from every agent action first |
| `id` parameter type | `string` |
