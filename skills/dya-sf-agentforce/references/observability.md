# Agent Observability — Reference (Winter '27 / API v68.0)

How to see what an agent did, in a preview and in production, and turn what you see into a fix.

Use what the platform records: preview traces, Agentforce Session Tracing in Data 360, the Trust Layer
audit trail and the OpenTelemetry export. Query mechanics for Data 360 (SQL, `__dlm` SOQL, paging,
credits) are in `dya-sf-data360`; this file names the objects and what to look for.

## 1. Preview sessions

A preview is the cheapest reproduction: one command, one trace per turn, no deployment of tests.

| Mode | How | Actions | Use |
|---|---|---|---|
| Simulated | `--authoring-bundle <Bundle> --simulate-actions` | LLM-mocked from the Agent Script | Routing and conversation shape before actions exist; adversarial probes with no side effects |
| Live, bundle | `--authoring-bundle <Bundle> --use-live-actions` | Real Apex, flows, prompt templates in the org | Reproducing a defect before publishing |
| Published | `--api-name <Agent>` | Always live | Reproducing what users get from the active version |

```bash
sf agent preview start --authoring-bundle Bike_Repair_Concierge --use-live-actions \
    --context-variables '$Context.EndUserLanguage=Spanish' -o <alias>
sf agent preview send --authoring-bundle Bike_Repair_Concierge --session-id <id> \
    --utterance "¿Dónde está mi pedido 88412?" -o <alias>
sf agent preview sessions
sf agent preview end --authoring-bundle Bike_Repair_Concierge --session-id <id> -o <alias>
```

- Pass a mode flag on `start` whenever you pass `--authoring-bundle`; it is required there, ignored for
  published agents, and not accepted by `send` or `end`.
- Name the agent on `send` and `end` with the same `--authoring-bundle` or `--api-name` used on
  `start`; `--session-id` may be omitted only while the agent has exactly one open session.
- End every session; `end` prints where its traces are. `end --all` (with `-p` to skip the prompt)
  closes every open session for an agent or the whole project.
- For live mode, set `default_agent_user` in the Agent Script `access` block to a real org user and deploy changed
  Apex, flows and templates first; the preview runs what is in the org, not in the project.
- Expect a preview to ignore connection endpoint configuration and escalation; test escalation through
  the real channel after publishing.
- Add `-x/--apex-debug` to the interactive `sf agent preview` to write Apex debug logs to the output
  directory (default `./temp/agent-preview`, override with `-d`), then replay them in the Apex Replay
  Debugger.

### Context variables in a preview

| Kind | Name shape | Example |
|---|---|---|
| Linked context variable (externally provided, read as `$Context.Name`) | `$Context.` prefix | `$Context.CaseId=500xx0000012345` |
| State variable (mutable agent state) | Bare developer name | `retryCount=0` |
| Typed value (Boolean, Number, Date, Object, List, Json…) | `--context-variables-json` | `'[{"name":"isMember","type":"Boolean","value":true}]'` |

- Quote the whole value in single quotes so the shell does not expand `$Context`.
- Prefix linked variables; a bare name becomes a state variable and the live action reading
  `$Context.Name` sees null.
- Send a Boolean that gates `available when` as typed JSON; `--context-variables` always sends Text.
- When a name appears in both flags, the JSON value wins.

## 2. Preview traces

Every turn of every preview (interactive or programmatic, VS Code or CLI) records a trace in the DX
project. The CLI stores a session under `.sfdx/agents/<agentId>/sessions/<sessionId>/` with
`transcript.jsonl`, `metadata.json`, a turn index, and `traces/<planId>.json`, one file per turn.
Saving a session with `--output-dir` or **Save Chat History** writes `transcript.json` and the trace
JSON under the chosen directory.

```bash
sf agent trace list --agent Bike_Repair_Concierge --since 2026-10-01
sf agent trace read --session-id <id>
sf agent trace read --session-id <id> --turn 2 --format detail --dimension routing
sf agent trace read --session-id <id> --format detail --dimension errors
sf agent trace read --session-id <id> --format raw --json
sf agent trace delete --agent Bike_Repair_Concierge --older-than 7d --no-prompt
```

| Question | Read |
|---|---|
| What happened, turn by turn? | `--format summary` (default): subagent, actions, response |
| Why did it pick that subagent, or switch? | `--format detail --dimension routing` |
| What did each action receive and return, and how long did it take? | `--dimension actions` |
| How did the model reason toward its plan? | `--dimension grounding` |
| What failed anywhere in the session? | `--dimension errors` |
| Something the formatter does not show | `--format raw` |

- `--dimension` is required with `--format detail`; `--turn` counts from 1.
- `--since` takes ISO 8601 (`2026-10-01`, read as UTC midnight, or a full timestamp); `--older-than`
  takes `m`, `h`, `d` or `w`.
- `trace delete` with no filter deletes every trace of every agent. Always filter.
- Keep `.sfdx/` out of version control and purge live-mode traces regularly; they hold real record
  data, prompts and action payloads.
- Fall back to `--format raw` when a newer org changes the schema; the formatter lags the payload.

### Trace JSON structure

A trace file is the planner response the Agent API returned for one turn (the preview runs on the
Agent API).

| Path | Meaning |
|---|---|
| `type` | `PlanSuccessResponse` for a completed plan |
| `planId`, `sessionId` | Turn and session identifiers; the file is named after `planId` |
| `intent`, `topic` | Classified intent and the subagent that handled the turn |
| `plan[]` | Ordered steps, each with a `type` |

| Step `type` | Fields | Read it for |
|---|---|---|
| `UserInputStep` | `message` | The utterance as the planner received it |
| `UpdateTopicStep` | `topic`, `description`, `job`, `instructions[]`, `availableFunctions[]` | Which subagent was entered, its instructions, and the actions it could choose from |
| `EventStep` | `eventName`, `isError`, `payload.oldTopic`, `payload.newTopic` | Subagent switches and runtime errors |
| `LLMExecutionStep` | `promptName`, `promptContent`, `promptResponse`, `executionLatency`, `startExecutionTime`, `endExecutionTime` | The exact prompt the model saw and what it answered |
| `ReasoningStep` | `reason` | The planner's stated reason for a decision |
| `FunctionStep` | `function.name`, `function.input`, `function.output`, `executionLatency` | Action calls, their parameters, results and latency |
| `PlannerResponseStep` | `message`, `responseType`, `isContentSafe`, `safetyScore.safety_score`, `safetyScore.category_scores` | The reply and its safety verdict |

Safety category scores: `toxicity`, `hate`, `identity`, `violence`, `physical`, `sexual`, `profanity`,
`biased`.

```bash
jq -r '.plan[] | select(.type == "FunctionStep") | "\(.function.name)\t\(.executionLatency) ms"' traces/<planId>.json
jq '.plan[] | select(.type == "UpdateTopicStep") | {topic, availableFunctions}' traces/<planId>.json
jq '.plan[] | select(.type == "PlannerResponseStep") | {isContentSafe, safetyScore}' traces/<planId>.json
```

- Check `availableFunctions` before blaming the model for not calling an action; if the action is
  absent, a gate or the subagent's action list removed it.
- Compare `function.input` with what the user said; a wrong parameter is an extraction problem in the
  action's input descriptions, not a routing problem.
- Read `promptContent` to confirm that variables were substituted; a literal variable reference there
  is a wiring bug (`references/agent-control-flow-pitfalls.md`).

## 3. Turn on production telemetry

Production behaviour lives in Data 360, so Data 360 must be provisioned.

- In Setup › Einstein Generative AI › **Einstein Audit, Analytics, and Monitoring Setup**, turn on
  **Agentforce Session Tracing** (how the agent ran) and **Audit and Feedback** (what was sent to and
  returned from the model, with masking, toxicity and feedback).
- Install the **Salesforce Standard Data Model** managed package before using agent optimization on
  session data.
- Give analysts Data 360 query access and keep the data in the dataspace they can read; queries and the
  OTel API enforce dataspace and governance rules for the calling user.
- For agents created from an agent spec, set `enrichLogs: true` (or `--enrich-logs true` on
  `sf agent generate agent-spec`) to add conversation data to the event logs; it defaults to false.
- From an Agent API client, send a fresh `externalSessionKey` per conversation and store it on your
  side; it is your join key into the agent's event logs. Post thumbs up or down to
  `/sessions/{id}/feedback`; it lands in the feedback DMOs (`references/lifecycle-and-api.md`).
- For agents reached through Salesforce Hosted MCP Servers, every tool call runs as the authorising
  user and appears in the API logs with `API_CLIENT_CATEGORY = SALESFORCE_HOSTED_MCP`.

## 4. The Session Tracing data model (STDM)

One session holds participants and ordered interactions (turns); each interaction holds ordered steps
and messages. All objects are Data 360 DMOs.

```text
ssot__AiAgentSession__dlm
├── ssot__AiAgentSessionParticipant__dlm
├── ssot__AiAgentInteraction__dlm                (turn, PrevInteractionId chain)
│   ├── ssot__AiAgentInteractionStep__dlm        (PrevStepId chain)
│   └── ssot__AiAgentInteractionMessage__dlm
├── ssot__AiAgentMoment__dlm ── ssot__AiAgentMomentInteraction__dlm ── interaction
├── AiAgentSessionLog_std__dlm
└── AiAgentGenerativeAiUsage_std__dlm
```

| DMO | Grain | Fields to know |
|---|---|---|
| `ssot__AiAgentSession__dlm` | One conversation | `ssot__StartTimestamp__c`, `ssot__EndTimestamp__c`, `ssot__AiAgentChannelType__c`, `ssot__AiAgentSessionEndType__c` (resolved, escalated, deflected, other), `ssot__RelatedMessagingSessionId__c`, `ssot__RelatedVoiceCallId__c`, `ssot__PreviousSessionId__c`, `ssot__VariableText__c` |
| `ssot__AiAgentSessionParticipant__dlm` | User or agent in a session | `ssot__AiAgentApiName__c`, `ssot__AiAgentVersionApiName__c`, `ssot__AiAgentType__c`, `ssot__AiAgentSessionParticipantRole__c` |
| `ssot__AiAgentInteraction__dlm` | One turn | `ssot__AiAgentSessionId__c`, `ssot__AiAgentInteractionType__c` (e.g. Turn), `ssot__TopicApiName__c`, `ssot__TelemetryTraceId__c`, `ssot__PrevInteractionId__c` |
| `ssot__AiAgentInteractionStep__dlm` | One step in a turn | `ssot__AiAgentInteractionStepType__c` (`UserInputStep`, `LLMExecutionStep`, `FunctionStep`), `ssot__Name__c` (action name for actions), `ssot__InputValueText__c`, `ssot__OutputValueText__c`, `ssot__ErrorMessageText__c`, `ssot__PreStepVariableText__c`, `ssot__PostStepVariableText__c`, `ssot__TopicApiName__c`, `ssot__GenAiGatewayRequestId__c`, `ssot__GenerationId__c`, timestamps |
| `ssot__AiAgentInteractionMessage__dlm` | One message | `ssot__AiAgentInteractionMessageType__c` (Input, Output), `ssot__ContentText__c`, `ssot__AiAgentInteractionMsgContentType__c`, `ssot__Modality__c` (voice or text), `ssot__MessageSentTimestamp__c` |
| `ssot__AiAgentMoment__dlm` | A summarised stretch of a session | `ssot__RequestSummaryText__c`, `ssot__ResponseSummaryText__c`, `ssot__AiAgentApiName__c`, `ssot__AiAgentVersionApiName__c` |
| `AiAgentSessionLog_std__dlm` | Structured runtime log line | `Category__c` (Tool, LLM, Retrieval, Guardrail, Auth, HTTP…), `Code__c`, `LogLevelType__c` (DEBUG to FATAL), `Description__c`, `DetailedDescription__c` (JSON), `CauseLogId__c`, `RootCauseLogId__c` |
| `AiAgentGenerativeAiUsage_std__dlm` | One model call's usage | `AiAgentSessionId__c`, `AiAgentInteractionId__c`, `AiAgentToolName__c`, `PromptTemplateDeveloperName__c`, `ModelProviderModelName__c`, `PromptInputTokenCount__c`, `PromptCompletionTokenCount__c`, `PromptTotalTokenCount__c` |
| `ssot__TelemetryTraceSpan__dlm` | One span | `ssot__TelemetryTrace__c`, `ssot__TelemetryParentSpanId__c`, `ssot__OperationName__c`, `ssot__DurationNumber__c` (nanoseconds), `ssot__StatusCode__c` |

- Read the subagent from the **step's** `ssot__TopicApiName__c` in multi-agent setups; it reads
  `NOT_SET` when an orchestrator's router coordinates several subagents in one interaction.
- Diff `ssot__PreStepVariableText__c` against `ssot__PostStepVariableText__c` to find the step that
  corrupted state.
- Follow `RootCauseLogId__c` on an ERROR or FATAL log line to the deepest known cause; it can point into
  another session.
- `ssot__AiAgentSession__dlm.ssot__Id__c` is documented as at most 15 characters; normalise 18-character
  IDs before joining from outside Data 360.
- Expect partial population for some agent types: for Agentforce Coworker, interactions and steps are
  not populated and participants carry no agent IDs. Check row counts per DMO before concluding that
  nothing happened.

### Trust Layer audit DMOs

These record each model request, independently of the agent graph; join from a step through
`ssot__GenAiGatewayRequestId__c` and `ssot__GenerationId__c`.

| DMO (reference name) | Holds |
|---|---|
| `GenAiGatewayRequest_std__dlm` | Prompt (`PromptText__c`, `MaskedPromptText__c`), model and provider, prompt template, token counts, `IsPiiMaskingEnabled__c`, input and output safety-scoring flags |
| `GenAiGatewayResponse_std__dlm` | Response envelope, linked by `AiGatewayRequestId__c` |
| `GenAiResponseGeneration_std__dlm` | `GeneratedResponseText__c`, `MaskedGeneratedResponseText__c` |
| `GenAiContentQuality_std__dlm`, `GenAiContentQualityCategory_std__dlm` | `IsToxicityDetected__c` and per-category values |
| `GenAiFeedback_std__dlm` | Thumbs feedback tied to a generation |

The Audit and Feedback data model also appears under the names `GenAIGatewayRequest__dlm`,
`GenAIGatewayResponse__dlm` and `GenAIGeneration__dlm` (fields such as `prompt__c`, `feature__c`,
`gatewayRequestId__c`). List the DMOs present in the org's data space and use the family it has; do
not mix field names across families.

- Turn on Audit and Feedback together with Session Tracing; tracing alone gives the agent graph without
  the prompts.
- With masking on, the masked response text is not stored in the generation DMO.

### Scorer results

Custom scorers (`references/testing-and-evaluation.md` §7) write to the AI Agent Tag DMOs:
`ssot__AiAgentTagDefinition__dlm` (the scorer and version), `ssot__AiAgentTag__dlm` (its allowed values)
and `ssot__AiAgentTagAssociation__dlm` (one score on a session, moment or interaction:
`ssot__ValueText__c`, `ssot__IsPassed__c`, `ssot__OutcomeType__c`, `ssot__SourceType__c`,
`ssot__AssociationReasonText__c`). Track pass rate per scorer per agent version from the associations.

### Queries

Run these through the Data 360 Query API or Query Editor (`dya-sf-data360`).

```sql
SELECT st.ssot__Name__c                 AS action_name,
       COUNT(*)                         AS failures,
       MIN(st.ssot__ErrorMessageText__c) AS sample_error
FROM ssot__AiAgentInteractionStep__dlm st
JOIN ssot__AiAgentSession__dlm s ON s.ssot__Id__c = st.ssot__SessionId__c
WHERE st.ssot__AiAgentInteractionStepType__c = 'FunctionStep'
  AND st.ssot__ErrorMessageText__c IS NOT NULL
  AND s.ssot__StartTimestamp__c >= CURRENT_DATE - INTERVAL '7' DAY
GROUP BY st.ssot__Name__c
ORDER BY failures DESC
```

```sql
SELECT i.ssot__TopicApiName__c               AS subagent,
       s.ssot__AiAgentSessionEndType__c      AS end_type,
       COUNT(DISTINCT s.ssot__Id__c)          AS sessions
FROM ssot__AiAgentSession__dlm s
JOIN ssot__AiAgentInteraction__dlm i ON i.ssot__AiAgentSessionId__c = s.ssot__Id__c
WHERE s.ssot__StartTimestamp__c >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY i.ssot__TopicApiName__c, s.ssot__AiAgentSessionEndType__c
```

- Always bound by `ssot__StartTimestamp__c`; unbounded scans of session data are slow and billed.
- Read message text from `ssot__AiAgentInteractionMessage__dlm`, not from step inputs; steps carry
  planner payloads, messages carry what the user saw.
- Treat every query result as personal data; never paste it into a test spec, ticket or prompt
  unscrubbed.

## 5. OpenTelemetry export (Beta)

The Agentforce Session Trace OTel API returns one session, pre-joined from Session Tracing and Audit
and Feedback, as OTLP v1.0 `ResourceSpans`: turns, messages, LLM calls, action executions, metric
scores and feedback.

```http
GET /services/data/v68.0/einstein/audit/otel/{sessionId}
Authorization: Bearer <token>
```

- Turn on Session Tracing and Audit and Feedback first; the API reads Data 360 and needs it provisioned.
- Authenticate with an External Client App OAuth token, as for the Agent API; no extra permission
  beyond standard Agentforce access is needed in the Beta.
- Request one session per call; there is no bulk endpoint, and only sessions that **started within the
  last 72 hours** are returned. Export continuously, not on demand weeks later.
- Stay within Connect REST API rate limits; throttle the loop.
- Use it for pipelines and debugging outside Salesforce; it does not replace the STDM DMOs, which keep
  powering Agentforce Studio analytics.
- Expect no stock collector receiver for Salesforce: write a small poller that lists recent session IDs
  (a Data 360 query), fetches each trace, and posts it to your collector's OTLP/HTTP endpoint.

```bash
#!/usr/bin/env bash
set -euo pipefail
for id in $(cat session-ids.txt); do
    sf api request rest "/services/data/v68.0/einstein/audit/otel/$id" -o "$ORG" > "otel-$id.json"
    curl --fail -sS -X POST "$OTLP_ENDPOINT/v1/traces" \
        -H 'Content-Type: application/json' --data-binary "@otel-$id.json"
    sleep 1
done
```

Confirm the top-level shape your collector expects (`resourceSpans`) on one file before pointing the
loop at production; the Beta format can change.

## 6. Diagnose, reproduce, improve

Run this loop for every production defect. Each step names where to look; none needs custom logging.

1. **Detect.** Watch, per agent version: session end type mix (escalated, deflected), failing
   `FunctionStep`s, ERROR and FATAL session log lines, scorer pass rates, negative feedback, toxicity
   detections, token usage per session.
2. **Locate.** Find the sessions, then the interaction and step where behaviour diverged.
3. **Classify** with the table below before touching the agent.
4. **Reproduce** in a sandbox with a live preview of the same version, the same context variables and an
   equivalent (scrubbed) utterance; read the trace dimension that matches the class.
5. **Encode** the reproduction as a test case that fails today (`references/testing-and-evaluation.md`).
6. **Fix** in a new agent version in the sandbox; review the diff of the Agent Script, never apply
   generated edits unread.
7. **Gate** on the full suite, including cases that passed before.
8. **Promote, then re-measure** after 24 to 48 hours of traffic. If the issue rate did not fall or a new
   one appeared, reactivate the previous version (`sf agent activate --api-name <Agent> --version <N>`)
   and repeat with the new evidence.

| Symptom | Evidence | Likely cause | Fix location |
|---|---|---|---|
| Wrong subagent | Interaction or step `TopicApiName`; trace `routing` | Overlapping subagent descriptions or scope | Subagent descriptions and boundaries |
| Right subagent, no action | No `FunctionStep`; action absent from `availableFunctions` | Gate false, action not attached, missing input | `available when`, subagent action list, variable seeding |
| Action called with wrong inputs | `function.input` / `ssot__InputValueText__c` | Vague input descriptions, value not in context | Action input descriptions, context variables |
| Action error | `ssot__ErrorMessageText__c`, session log `Category__c` Tool or HTTP | Implementation, permissions of the agent user, callout | Apex or flow (`dya-sf-apex`), agent user access (`dya-sf-permissions`) |
| Empty or partial action output | `function.output` empty under the agent user, full as admin | Sharing or FLS for the agent user | `dya-sf-permissions`, never a wider profile |
| Plausible but wrong answer | LLM step output not supported by action output or retrieval | Missing or stale grounding content | Knowledge or data library (`references/knowledge-and-data-libraries.md`) |
| State lost between turns | Pre/post step variable text | Reinitialisation, unguarded assignment | `references/agent-control-flow-pitfalls.md` |
| Slow turns | Step timestamps, `executionLatency`, span durations | Slow action or callout, oversized prompt | The action; grounding size |
| Unsafe reply | `isContentSafe` false, content quality toxicity | Prompt or grounding content | Instructions, content; add a safety test |

Escalate to `references/troubleshooting.md` when the evidence points at org setup rather than agent
design.

## 7. Anti-Patterns

| Anti-pattern | Do instead |
|---|---|
| A custom logging object or logger class for agent activity | Session Tracing, Audit and Feedback, preview traces |
| Debugging production from memory of the conversation | The session's interactions, steps and messages in Data 360 |
| Starting analysis at `ssot__TelemetryTraceSpan__dlm` | Session → interaction → step, then spans for timing |
| `sf agent trace delete` with no filter in a shared project | `--agent`, `--session-id` or `--older-than` |
| Committing `.sfdx/` traces or saved transcripts | Ignore them; purge live-mode traces |
| Expecting the OTel API to backfill last month | Export within the 72-hour window |
| Fixing before reproducing | Preview reproduction and a failing test first |
| Validating a fix on the one failing conversation | The full regression suite |
| Pasting session data into tests or tickets | Scrubbed, synthesised equivalents |
