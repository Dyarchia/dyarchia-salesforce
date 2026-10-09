# Troubleshooting — Reference (Winter '27 / API v68.0)

Symptom, cause and fix for every phase of an agent's life, from a blank org to a live conversation.

Read the row for the phase you are in; when two rows match, apply the cheaper fix first. Syntax rules
are in `references/agent-script.md`, constructs that compile and misbehave in
`references/agent-control-flow-pitfalls.md`, and the deploy model in
`references/agent-lifecycle-metadata.md`.

## How to read an opaque failure

Work this ladder before changing the script; most "the agent ignores me" reports stop at step 3.

1. **Reproduce in preview with traces.** `sf agent preview start` → `send` → `end`, then
   `sf agent trace read --session-id <id> --format summary`.
2. **Drill into one dimension.** `--format detail --dimension routing | actions | grounding | errors`.
   `routing` answers "which subagent ran", `actions` gives name, inputs, output and latency per
   action, `errors` aggregates every failure of the session.
3. **Locate the break in the chain** `configured → available → invoked → executed → effected`
   (`references/agent-control-flow-pitfalls.md`). Each link has its own rows below.
4. **Capture the trace id.** Platform errors carry it in the `instance` field as `urn:trace:...`;
   Salesforce Support needs it together with the error code.
5. **Retry only what the code says is transient.** Every `*_TIMEOUT`, `*_RATE_LIMIT`,
   `*_SERVICE_UNAVAILABLE`, `*_NETWORK_ERROR` and `*_STREAM_ERROR` is transient; every `*_BAD_REQUEST`,
   `*_NOT_FOUND`, `*_VALIDATION_ERROR` and `*_SECURITY_ERROR` fails identically on retry.

## Environment and org setup

| Symptom | Cause | Fix |
|---|---|---|
| `sf agent` commands fail with `This feature is not currently enabled for this user type or org` | Einstein or Agentforce is off | Setup › Einstein Setup › Turn on Einstein; Setup › Agentforce Agents › enable Agentforce |
| The **New Agent** button is missing right after enabling Agentforce | The page caches the pre-enable state | Refresh the page |
| A scratch org has no agent features | The definition file lacks them | Add the `AgentforceStandardAgents` feature, `agentPlatformSettings.enableAgentPlatform: true` and `einsteinGptSettings.enableEinsteinGptPlatform: true`, or generate the project with `sf template generate project --template agent`, which ships an Agentforce-ready `config/project-scratch-def.json` |
| A grounded agent cannot be built in a scratch org | Data libraries need a Data 360-connected org | Develop grounded agents in a Developer or Developer Pro sandbox connected to Data 360 |
| Data 360 features error minutes after enabling | Data 360 provisioning runs up to 60 minutes | Wait for the completion message on Data Cloud Setup Home before any agent step |
| `D360_TENANT_NOT_FOUND` | The org is not provisioned in Data 360 | Provision Data 360, then retry |
| `PROD_ORG_ID_NOT_AVAILABLE` | A sandbox is not linked to its production org | Repair the sandbox-to-production link before using Data 360 features |
| `TENANT_NOT_PROVISIONED` or `INVALID_TENANT_STATUS` | The org is still provisioning, or suspended | Wait for provisioning; a suspended org needs an admin, not a retry |
| A non-admin cannot publish | Publishing needs `Modify All Data` and `Manage AI Agents` | Assign both through a permission set |
| A non-admin cannot preview | Previewing needs `Agent Platform Builder` | Assign it through a permission set; generating and validating a bundle need no extra permission |
| CI cannot authorise the org | Web login is unavailable in CI | Use the JWT flow through an external client app with a certificate (`dya-sf-cli`) |

## Authoring and validation

`sf agent validate authoring-bundle --api-name <Name> --target-org <alias>` compiles the script and
prints each error with its location. It needs an org; a local compile is in
`references/agent-lifecycle-metadata.md`.

| Symptom | Cause | Fix |
|---|---|---|
| Syntax error with a line number | Wrong indentation, a block name without its colon (`config` for `config:`), an undeclared variable, or an unsupported expression | Fix the line; the Agentforce DX VS Code extension highlights the same errors inline |
| Parse error on a line that looks correct | Tabs and spaces mixed in one file | Re-indent the file with one style |
| Error on `elif` or on an `if` inside an `if` | Neither exists | `else if`, compound predicates, or sequential `if` statements |
| Action or subagent name rejected | Developer-name rules: start with a letter, alphanumerics and underscores only, no trailing or doubled underscore, 80 characters at most | Rename in `snake_case` |
| A subagent or action called `escalate` is rejected | `escalate` is reserved | Choose another name |
| A linked variable fails to compile | Linked variables take no default, cannot be set by the agent, and cannot be a list or an object | Drop the default and the `set`; keep collections in `mutable` variables |
| `id`-typed parameter warns | `id` is deprecated | Type Salesforce Ids as `string` |
| A `modality voice` block fails | Legacy flat keys and nested `outbound` / `inbound` keys in one block | Rewrite the whole block in one format (`references/voice.md`) |
| `default_agent_user` is flagged in `config` | The key moved | Put it in the `access` block |
| `generate authoring-bundle` yields bare boilerplate | No spec was passed | Pass `--spec <file>`; `--no-spec` is the boilerplate path by design |
| The generated subagents are generic | The spec's role and company descriptions are vague | Enrich the spec and regenerate (`references/agent-design.md`) |
| `generate authoring-bundle` refuses the API name | The API name already exists in the org | Pick another `--api-name`; `--force-overwrite` only replaces a local bundle |

## Deploy, retrieve and moving between orgs

| Symptom | Cause | Fix |
|---|---|---|
| A retrieve returns one bundle version | `AiAuthoringBundle:My_Agent` names the draft only | Retrieve `"AiAuthoringBundle:My_Agent*"` for every version |
| A retrieve returns runtime metadata and no `.agent` file | `Agent:My_Agent` is a pseudo-type for the runtime graph plus its Apex and flows | Request `AiAuthoringBundle` explicitly as well |
| Deploy at 67.0 fails with missing `Bot` / `BotVersion` | A committed agent needs the bundle and its runtime metadata together | Use a manifest listing every agent type (`references/agent-lifecycle-metadata.md`) |
| Deploy at 68.0 fails on `AiAgentDefinitionVersion` | The `AiAgentDefinition` is neither in the target nor in the package, or no version is included | Deploy the definition with at least one version (`MyAgent#2`, `MyAgent#*`) |
| Deploy at 68.0 rejects a version | It travels in the same package as its matching legacy `BotVersion` | Split the package; never pair a version with its legacy twin |
| A 68.0 manifest deploys nothing useful into production | Production is still on 67.0 | Both orgs must be on 68.0; until then use the 67.0 manifests |
| A 68.0 deploy misses the agent's Apex, flows or templates | The dependency flag was omitted | Pass `--root-type-with-dependencies AiAgentDefinitionVersion` to both retrieve and deploy |
| A 68.0 deploy of a script agent loses its source | The bundle is not auto-included | Add `AiAuthoringBundle` to the manifest |
| Deploying one agent version fails in a fresh org | Single-version manifests assume the agent exists | Deploy the full agent first, then single versions |
| The `AiAuthoringBundle` and `BotVersion` numbers disagree | More versions were saved than committed | Read the version pairing from the `<target>` element of the versioned `bundle-meta.xml` |
| Retrieve or deploy runs for an hour or times out | `*` wildcards on `ApexClass`, `Flow` or `GenAiPromptTemplate` pull the whole org | Name the members the agent uses |
| The agent is deployed but cannot run in the target | The agent user's username belongs to the source org | String replacement at deploy (`references/agent-lifecycle-metadata.md`), or set the user on a new version |
| Future deploys to an org are blocked | A version was created in the target that the source lacks | Recreate the matching version in the source org; keep both in step |
| An org breaks after deploying hand-edited agent metadata | Editing retrieved agent metadata other than the username is unsupported | Restore from source control; change behaviour in the `.agent` file and republish |
| `sf agent generate template` fails on a script agent | Template packaging does not support Agent Script agents | No workaround exists yet; distribute by metadata deploy |
| `sf agent create` produced an agent with no `.agent` file, and some DX commands ignore it | That legacy path creates a scriptless agent | Rebuild through `generate authoring-bundle` and `publish authoring-bundle` |

## Publish

| Symptom | Cause | Fix |
|---|---|---|
| Publish stops with compilation errors | Publish validates first | Run `validate authoring-bundle` until clean |
| Publish errors on a `My_Agent_3` bundle | Only the unversioned draft is publishable | Edit and publish the naked `My_Agent` bundle |
| Publish succeeds; the agent is not in Builder | Wrong default org, or a stale page | `sf org display` to confirm the org; refresh Builder |
| Apex or Flow edits do not show after publish | Publish does not deploy Apex or flows | `sf project deploy start --metadata ApexClass:<Name>` (and the flow) **before** publishing |
| Publish fails with a bare internal error | The message names no cause | Rerun with `--verbose`; confirm every `apex://`, `flow://` and `prompt://` target exists **in the org** and the flow is active; confirm `access.default_agent_user` names an active user; validate again; keep the `urn:trace` id for Support |
| The DX project lacks the new version after publish | Publish retrieves runtime metadata but not the versioned bundle | `sf project retrieve start --metadata "AiAuthoringBundle:My_Agent*"` |
| Publish overwrote local runtime files unexpectedly | Publish retrieves by default | Pass `--skip-retrieve` when the local runtime files must stay untouched |

## Preview

| Symptom | Cause | Fix |
|---|---|---|
| Validation passes; the preview session never initialises | `access.default_agent_user` is missing, wrong, or names an inactive user; live mode and Apex debugging need it | Set it to an active agent user in that org |
| `preview start --authoring-bundle` refuses to start | A bundle preview needs an explicit mode | Pass `--use-live-actions` or `--simulate-actions` on `start`; `send` takes no mode |
| Interactive `sf agent preview` runs mocked actions | Simulation is that command's default | Add `--use-live-actions`; the interactive command has no `--simulate-actions` flag |
| Simulated preview passes; live preview fails | Simulation invents action output from descriptions | Deploy the Apex, flows and templates, then preview live |
| Breakpoints are never hit | The Replay Debugger needs live mode | Live mode plus `--apex-debug` (`-x`), or VS Code **Start Debug Mode** |
| Previewing a published agent fails | `--api-name` targets an **active** published agent | Activate a version first, or preview the bundle |
| "Multiple active sessions" | More than one session is open for the agent | Pass `--session-id`; `sf agent preview sessions` lists them; `sf agent preview end --all` closes them |
| Edits to the `.agent` file have no effect mid-session | The session runs the compiled script it started with | Validate, end the session, start a new one |
| A Boolean-gated route never opens in preview | `--context-variables` sends every value as text | `--context-variables-json '[{"name":"x","type":"Boolean","value":true}]'` (CLI 2.151.7+) |
| Escalation does nothing in preview | Preview does not support escalation or honour connection endpoint settings | Publish, activate and test escalation on the real channel |

## Activation

| Symptom | Cause | Fix |
|---|---|---|
| Activating version 3 deactivates version 2 | One version is active at a time | Expected; plan cutovers per version |
| A CI job activated the wrong version | `sf agent activate --json` without `--version` activates the **latest** | Always pass `--api-name` and `--version` in automation |
| Users lose an in-flight conversation | Deactivation ends open interactions | Deactivate outside service hours, or activate the replacement version instead |
| `--version` value rejected | It is the number in `vN.botVersion-meta.xml`, not the bundle suffix | Read N from the runtime file, not from `My_Agent_N` |

## Testing

| Symptom | Cause | Fix |
|---|---|---|
| `agent test create` says the agent is not in the org | Tests target a published agent | Publish first |
| `agent test run --api-name` cannot find the test | The flag names the `AiEvaluationDefinition`, not the agent | Pass the test's API name |
| Tests pass locally and fail in CI | JWT auth missing, agent not active, or results read before the run ends | Authenticate with JWT; activate before running; `--wait`, or `test resume --job-id` |
| `--wait` expires and reports in progress | The run outlived the wait (CLI 2.149.9+) | `sf agent test resume --job-id <id>` |
| Exit code `1` with no failed assertion visible | Exit `1` means test cases hit **execution errors**, not failed expectations | Read the result output to tell the two apart |
| A run is refused | Ten runs may be `IN-PROGRESS` at once | Wait or serialise runs |
| A test definition is refused | One `AiEvaluationDefinition` holds 1,000 test cases at most | Split the suite |
| Low `coherence` and similar scores | Vague instructions or action descriptions | Tighten `system.instructions` and action descriptions; read the routing trace |
| Results shift between identical reruns | The testing service changes over time, and generation is non-deterministic | Assert on outcomes and actions, not on wording; set thresholds, not exact matches |
| `sf agent generate test-spec` hangs in a pipeline | It is an interactive prompt per case | Write the spec YAML directly (`references/testing-and-evaluation.md`) |

## Runtime — routing and behaviour

| Symptom | Cause | Fix |
|---|---|---|
| The wrong subagent answers | Overlapping or terse transition descriptions | Make each `go_to_*` description specific and disjoint; fewer subagents route better |
| The router ignores a `setVariables` tool or a `before_reasoning` block | The router runs on Einstein HyperClassifier, which allows only `@utils.transition` and no `before_reasoning` / `after_reasoning` | Move that logic into a subagent, or set another `model_config.model` on the router |
| A sensitive feature is reached without verification | `available when` hides options but never forces a step; the model chooses an unguarded path | Put a conditional `transition to` at the top of the router's `->` instructions (`references/agent-design.md`) |
| Instructions before a transition have no effect | A transition discards the prompt resolved so far | Place deterministic transitions first in the instructions |
| The agent bounces between two subagents | Conditions on both sides transition to each other | Make the conditions mutually exclusive; add a counter or a step variable |
| The agent hangs or answers erratically in one subagent | Agent-level `system.instructions` contradict that subagent's instructions | Add a `system` override in that subagent |
| The model never calls an action defined in the subagent | Actions defined under `actions:` are invisible to the model until listed under `reasoning.actions` | Expose it as a tool in `reasoning.actions`, or `run` it deterministically |
| An action is called with the wrong arguments | Required, unbound inputs are slot-filled by the model | Bind inputs from variables where the value is known; describe each input precisely |
| An action is chosen inconsistently | Too many inputs bound to variables delays availability until all are set | Bind only the inputs the logic needs; let the model fill the rest |
| The agent re-asks for values it was given | Values were never stored | Capture with `@utils.setVariables` (`with x = ...`) and give each variable a default that means "not captured" |
| A record is created twice | The create action stayed available after success | `available when @variables.record_id == ""` on the capture and create tools |
| The agent confirms an action that never ran | Generated text is not evidence | Gate the confirmation on the action's returned Id; transition to a confirmation subagent only when it is set |
| A flow returns an Id after a DML failure | The fault path did not clear the output | Clear the output variable on the fault path so the gate stays closed |
| Hidden data leaks into answers | Action outputs stay in context for the whole session | `filter_from_agent: True` on outputs the model must not see |
| An `object` output will not bind to its target's complex type | `complex_data_type_name` is required on complex outputs | Set it to the target's type, for example `lightning__recordInfoType` |
| Escalation fails on the live channel | No `connection messaging` block, or a wrong `outbound_route_name` | Configure `outbound_route_type: "OmniChannelFlow"` with a valid route (`dya-sf-omni-channel`) |
| Multilingual voice agent speaks the default locale | Adaptive language mode is ignored on voice | Set an explicit `default_locale` (`references/voice.md`) |
| Answers slow down as subagents grow | More tools enlarge every request | Trim `reasoning.actions` per subagent; gate the rest with `available when` |

## Runtime — agent user and silent permission failures

An agent runs as a user. When that user cannot see a record or field, user-mode queries return
fewer rows or blank fields instead of an error, so the agent answers confidently from nothing.

| Symptom | Cause | Fix |
|---|---|---|
| An action succeeds and returns nothing | The agent user lacks object, field or record access; user-mode SOQL filters silently | Grant the minimum through a permission set (`dya-sf-permissions`); never widen a profile to silence it |
| A field is always blank in answers | FLS strips it for the agent user | Grant read on that field to the agent user's permission set |
| Data-library calls fail with `PERMISSION_DENIED` | The permission is checked against the acting user, not the org | Grant it to that user; sessions opened before the grant keep the old permissions |
| Behaviour differs between Agent API and Builder | `bypassUser: true` runs as the agent user, `false` as the token's user | Pick the identity deliberately and test with that one |
| The agent user cannot be found to log in as | `sf org create agent-user` creates a passwordless user that cannot log in, visible to admins only | Inspect its permission set assignments from Setup or by SOQL on `PermissionSetAssignment` |
| A committed agent needs a different user | Committed versions are read-only | Create a new version, set `access.default_agent_user`, publish |
| `A2A_SECURITY_ERROR` | The caller lacks the permission set for the target agent | Grant access to the agent; check delegated access when acting for another user |
| `PLANNER_AGENT_NOT_FOUND` with a correct Id | The agent is not visible to the caller, still provisioning, or in another environment | Confirm caller access and environment; wait for provisioning |

## Grounding and data libraries

Depth on libraries, retrievers and indexing: `references/knowledge-and-data-libraries.md`.

| Symptom | Cause | Fix |
|---|---|---|
| Grounded answers are empty right after setup | The library is still provisioning or indexing (`PROVISIONING_IN_PROGRESS`, `UPLOAD_NOT_READY`) | Poll `sf agent adl status -i <id>` until ready |
| `DC_CONNECTION_MISSING` | Data 360's connection is still being set up or dropped | Wait for Data 360 provisioning, then retry |
| `RETRIEVER_NOT_ACTIVE` | The retriever was never activated or was deactivated | Activate it in Agentforce |
| `NON_DEFAULT_DATASPACE` | Data libraries work only in the default dataspace | Use the default dataspace; no setting changes this |
| `DC1_NOT_SUPPORTED` | A Data 360 companion org cannot host a data library | Use a custom retriever (`dya-sf-data360`) |
| `FEATURE_NOT_ENABLED` / `MISSING_ORG_PREREQUISITE` | Data libraries or a dependency are off | Enable the feature and its prerequisites in Setup |
| `SEARCH_INDEX_QUOTA_EXCEEDED` | The org holds its maximum number of search indexes | Delete unused indexes |
| `UNSUPPORTED_FILE_TYPE` | The extension is unsupported or misrepresents the content | Convert the file to a supported format |
| `FILES_NOT_UPLOADED` | The upload URL was obtained but the upload never completed | Request a fresh upload URL and upload again; do not retry the reference |
| `PRIMARY_FIELDS_IMMUTABLE` | Primary fields are fixed when a source is created | Delete and recreate the source |
| `DELETE_IN_USE` | Another resource references the one being deleted | Remove the references first |
| `INDEXING_FAILED`, `RETRIEVER_FAILED`, `SEARCH_INDEX_FAILED`, `DC_ASSET_FAILED` | Transient provisioning failure | Retry after a short wait |
| The answer is fluent but unsupported by the sources | The groundedness check was disabled | Keep `config.runtime.groundedness: True` for knowledge agents |
| Citations never appear | Citation enrichment is off, or the channel cannot render it | Keep `config.runtime.citation: True` on channels that render citations |

## Agent API and headless calls

| Symptom | Cause | Fix |
|---|---|---|
| HTTP 400, `{VALUE} is not a valid agent ID` | Wrong or truncated agent Id | Use the 18-character Id of that org's agent |
| HTTP 401 | Token problem | Rebuild the external client app: scopes `api`, `refresh_token offline_access`, `chatbot_api`, `sfap_api`; client credentials enabled; JWT-based tokens enabled; a Run As user with API Only access |
| HTTP 404 | Wrong token or wrong host | `api.salesforce.com`, or `api.gov.salesforce.com` on Government Cloud |
| HTTP 423 | A second request hit a session that is still processing | Send one request per session at a time |
| HTTP 500, `Unsupported Media Type` | Missing JSON content type | `Content-Type: application/json` |
| HTTP 500, `EngineConfigLookupException` | `instanceConfig.endpoint` is not the My Domain URL | Copy Setup › My Domain › Current My Domain URL |
| HTTP 500, `HttpServerErrorException` | Wrong agent Id in the path | Correct the Id |
| HTTP 500 after about two minutes | The call hit the 120-second timeout | Shorten the turn: fewer actions, smaller outputs, async work |
| The API refuses one specific agent | Agents of type "Agentforce (Default)" are not supported | Use a service or employee agent |
| `PLANNER_SESSION_NOT_FOUND` | The session expired, was ended, or is from another environment | Start a new session; expire cached session Ids when a session ends |
| `PLANNER_REQUEST_VALIDATION_ERROR` | The body breaks the schema | Fix every field in the `errors` array; they are reported together |
| `PLANNER_MISSING_REQUIRED_HEADER` | A proxy stripped or emptied an identity header | Forward identity headers unchanged; empty counts as missing |

## Multi-agent orchestration errors

| Code | Cause | Fix |
|---|---|---|
| `A2A_CONFLICT` | A message arrived while the conversation's previous task was running | Serialise turns per conversation |
| `A2A_PAYLOAD_TOO_LARGE` | Input variables carry embedded files or accumulated history | Pass references, not file bodies; drop history the session already holds |
| `A2A_BAD_REQUEST` / `A2A_DESERIALIZATION_ERROR` | Input variables do not match the connected subagent's declared inputs | Align names and types with the connected agent's variables |
| `A2A_NOT_FOUND` | Agent, task or session Id expired, wrong, or owned by another user | Correct the Id; confirm ownership |
| `A2A_UNAUTHORIZED` | Credentials missing, stale, or stripped by a gateway | Re-authenticate; stop the gateway stripping auth headers |
| `A2A_TIMEOUT` | A reasoning step or model call ran too long | Retry; then fewer inputs and a shorter prompt |
| Data set by a connected agent never reaches the orchestrator | Variables flow one way, orchestrator to connected agent | Read results from the connected agent's response, not from variables |

## Model gateway errors

| Code | Cause | Fix |
|---|---|---|
| `PLANNER_LLM_GATEWAY_TIMEOUT` | Large prompt, slow provider, or many actions exposed | Retry; then expose fewer actions per subagent and shorten inputs |
| `PLANNER_LLM_GATEWAY_RATE_LIMIT` | The org's model quota is exhausted by bursts or competing agents | Back off at least 5 seconds; spread batch workloads |
| `PLANNER_LLM_GATEWAY_EMPTY_GENERATION` | Safety filters suppressed the output, or the prompt left nothing actionable | Retry once; if reproducible, rewrite the instruction to ask for a concrete output |
| `PLANNER_LLM_GATEWAY_SERVICE_UNAVAILABLE` / `_NETWORK_ERROR` | Provider outage or network blip | Retry; check trust.salesforce.com; switch the subagent's model if an alternative is configured |
| `PLANNER_LLM_GATEWAY_STREAM_ERROR` | The stream dropped mid-answer | Retry; ask for shorter answers if long ones keep failing |
| `RATE_LIMIT_EXCEEDED` (any service) | Too many requests in the window | Wait 10 seconds, then back off progressively |
| `NOT_IMPLEMENTED` | Unsupported operation or parameter value, or an optional capability is off | Correct the value or enable the capability; retrying cannot help |
| `INTERNAL_ERROR` | Platform fault, not configuration | Retry once; then open a case with the `urn:trace` id |

## Hosted MCP servers used by an agent

| Symptom | Cause | Fix |
|---|---|---|
| A client cannot connect | Wrong URL shape, or the server is not enabled | `https://api.salesforce.com/platform/mcp/v1/[sandbox/]platform/<server>` or `.../custom/<server>`; enable it in Setup › API Catalog › MCP Servers |
| A former beta integration stopped working | GA changed the URL, made servers opt-in, and replaced the scopes | Enable the servers; use scopes `mcp_api` and `refresh_token`; update URLs; reauthorise every user |
| Sign-in fails | Callback URL mismatch, or a client without a compatible OAuth flow | Match the callback exactly; the server requires authorisation code with PKCE |
| Isolate client versus server | — | Connect to `sobject-all` with Postman or MCP Inspector; if that works, the client is misconfigured |
| A tool runs and returns nothing | The authorising user lacks access; every call runs as that user | Fix the user's permissions, not the server |
