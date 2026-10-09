# Agent Metadata and the Deploy/Publish Lifecycle

What an agent is on disk, what a deploy moves, and the CLI surface around it. The authoring
walkthrough is in `references/building-an-agent.md`.

## The bundle is a pair of files

```text
force-app/main/default/aiAuthoringBundles/
    Travel_Advisor/
        Travel_Advisor.agent              ← the Agent Script
        Travel_Advisor.bundle-meta.xml    ← required sibling
```

- Make the directory name, the `.agent` filename and the `.bundle-meta.xml` filename **all match**.
- Match `developer_name` inside the script to the directory name. A mismatch causes deploy failures
  that name neither file usefully.
- Name the metadata file `<ApiName>.bundle-meta.xml`. **A literal `bundle-meta.xml` is not
  deployable** — the API name is part of the filename, not a placeholder.

Mind the capital **B** in `aiAuthoringBundles/`. A wrong case survives a case-insensitive filesystem
on Windows or macOS, then fails on a Linux CI runner.

## Deploy is not publish

Publish after every deploy that must serve conversations.

```text
sf project deploy start        stages the AiAuthoringBundle into the authoring domain.
                               Creates NO runtime entity. Nothing serves a conversation.

sf agent publish               compiles the Agent Script to Agent DSL and creates the runtime
   authoring-bundle            graph: Bot, BotVersion, GenAiPlannerBundle, GenAiPlugins.
```

A deploy alone leaves an agent that exists in source and cannot be talked to. At **API 68.0** the
runtime side deploys and retrieves as `AiAgentDefinition` and `AiAgentDefinitionVersion`, which
makes an agent source-controllable like any other metadata.

## Naked versus version-suffixed bundles

Always author against the naked name.

| Bundle | Meaning | Writable |
|---|---|---|
| `Local_Info_Agent` | Always points at the highest DRAFT | **Yes — the only writable surface** |
| `Local_Info_Agent_1` | A published snapshot, locked by a `<target>` element in its `bundle-meta.xml` | **No** |

**Deploying an unmodified version-suffixed bundle succeeds as a no-op.** The command reports
success, the org is unchanged, and nothing shows which of the two you edited.

## Retrieval leaves the bundle behind

```bash
sf project retrieve start --metadata Agent:Local_Info_Agent --target-org <alias>          # ❌ no bundle
sf project retrieve start --metadata AiAuthoringBundle:Local_Info_Agent --target-org <a>  # ✅
```

Always request the `AiAuthoringBundle` explicitly; `Agent:X` does **not** include it, so you
retrieve the runtime metadata and none of the source you edit. The command in `references/building-an-agent.md` passes
both types for this reason; trimming it to one loses the source silently.

## Validate locally, without an org

Compile locally, then validate against the org, then publish.

AgentScript has a public open-source SDK and compiler: the npm package
**`@sf-agentscript/agentforce`**, source at `https://github.com/salesforce/agentscript.git`. A
`.agent` file compiles and lints **offline**.

A local compile catches syntax and structural errors in seconds; org validation is a round-trip
whose errors are further from the cause.

## CLI surface

```bash
sf agent generate authoring-bundle --name "<Label>" --api-name <ApiName> --spec <path> | --no-spec
sf agent validate authoring-bundle --api-name <ApiName>
sf agent publish  authoring-bundle --api-name <ApiName>
sf agent activate   --api-name <ApiName> --version <N>
sf agent deactivate --api-name <ApiName>

sf agent preview start --authoring-bundle <ApiName>     # preview the bundle, pre-publish
sf agent preview start --api-name <ApiName>             # preview the published, active agent
sf agent preview send  --session-id <id> --utterance "<text>"
sf agent preview … --use-live-actions | --simulate-actions
sf agent trace list | read | delete                     # trace files from preview sessions

sf agent test create --spec <path>
sf agent test run --api-name <AiEvaluationDefinition> --wait <minutes>
sf agent test list | results --job-id <id> | resume --job-id <id>
sf agent test run-eval --spec <path>                    # same YAML, richer evaluation framework
```

```bash
sf agent adl create | get | list | update | delete | status    # Agentforce Data Libraries
sf agent adl upload --source-type sfdrive --library-id <id>
sf agent adl file add | list | delete -i <id>

sf agent mcp create | get | list | update | delete | fetch     # MCP servers
sf agent mcp asset list | replace -i <id>
```

Use `sf agent generate template` only to package an agent for managed-package or AppExchange
distribution, not to scaffold one you are about to author. Roll out Agent Script bundles through the
publish workflow above.

Use `sf` **2.139.6 or newer**.

**Do not run `sf agent generate test-spec` under automation**: it is an interactive REPL that prompts
per case and stalls with no output. Write the spec YAML directly or copy one from an existing agent.
