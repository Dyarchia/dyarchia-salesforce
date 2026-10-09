# Agent Metadata and Lifecycle — Reference (Winter '27 / API v68.0)

What an agent is on disk, how drafts become versions, what a deploy moves, and what can change after publish.

The authoring walkthrough is in `references/building-an-agent.md`; failures at each step are in
`references/troubleshooting.md`.

## 1. The bundle is a pair of files

```text
force-app/main/default/aiAuthoringBundles/
    Travel_Advisor/
        Travel_Advisor.agent              ← the Agent Script
        Travel_Advisor.bundle-meta.xml    ← required sibling
```

- Make the directory name, the `.agent` filename and the `.bundle-meta.xml` filename **all match**.
- Match `config.developer_name` inside the script to the directory name. A mismatch causes deploy
  failures that name neither file usefully.
- Name the metadata file `<ApiName>.bundle-meta.xml`. **A literal `bundle-meta.xml` is not
  deployable**; the API name is part of the filename, not a placeholder.
- `developer_name` holds at most 80 characters, starts with a letter, uses alphanumerics and
  underscores, never ends with or doubles an underscore, and is unique in the org.

Mind the capital **B** in `aiAuthoringBundles/`. A wrong case survives a case-insensitive filesystem
on Windows or macOS, then fails on a Linux CI runner.

## 2. The metadata types

| Type | Represents | API |
|---|---|---|
| `AiAuthoringBundle` | The blueprint: the `.agent` file plus its XML | 67.0 and 68.0 |
| `AiAgentDefinition` | The agent: type, context variables, conversation settings | 68.0+ |
| `AiAgentDefinitionVersion` | One version: dialogs, conversation variables, planner configuration, behaviour | 68.0+ |
| `GenAiPlugin` | A subagent | Both |
| `GenAiFunction` | An action | Both |
| `Bot` / `BotVersion` | The agent and its versions at 67.0; at 68.0 used only by Einstein Bots | 67.0 and earlier for agents |
| `GenAiPlannerBundle` | The planner mapping subagents to actions at 67.0 | Does not exist at 68.0 |
| `Agent` | A CLI pseudo-type for the whole runtime graph, not real metadata | CLI only |

`GenAiFunctionDefinition` and `GenAiPlannerDefinition` are the Tooling API objects for actions and
planners. The `sf` CLI help and the publish guide still describe publish output as `Bot`,
`BotVersion` and `GenAi*`; on an org at 68.0, source-control the agent as `AiAgentDefinition` and
`AiAgentDefinitionVersion`.

## 3. Draft, committed, active

| State | Represented by | Editable |
|---|---|---|
| Draft | `AiAuthoringBundle` only | **Yes**; the only writable state |
| Committed (published) version | `AiAuthoringBundle` plus the runtime metadata | **No**; create a new version and edit that |
| Active version | A committed version serving users | No; one active version per agent at a time |
| Legacy agent (no Agent Script) | `Bot` / `BotVersion` only | Inactive versions yes, the active one no |

- **Publishing is committing.** `sf agent publish authoring-bundle` is the pro-code equivalent of
  Builder's **Commit Version** button.
- **Change a committed agent by publishing a new version**, never by editing its files: the agent
  user, an instruction, an action target. A committed version's `default_agent_user` cannot be
  changed in place.
- **Saving and committing count separately.** Builder saves more `AiAuthoringBundle` versions than it
  commits, so bundle version 9 can map to runtime version 7. The versioned bundle's
  `bundle-meta.xml` `<target>` element names the runtime version it belongs to.

## 4. Deploy is not publish

Publish after every deploy that must serve conversations.

```text
sf project deploy start        stages the AiAuthoringBundle as a draft.
                               Creates no runtime version. Nothing serves a conversation.

sf agent publish               compiles the Agent Script and creates the runtime metadata,
   authoring-bundle            a new agent or a new version of an existing one.
```

Publish runs these steps in order:

1. Validates the script compiles; any error stops it.
2. Creates the runtime metadata, or a new version of it.
3. Retrieves the new runtime metadata into the DX project, unless `--skip-retrieve`.
4. Writes the `<target>` element into the local `bundle-meta.xml`, tying the bundle to that version.
5. Deploys the `AiAuthoringBundle` and creates a new versioned bundle in the org, **which it does not
   retrieve**.

- **Deploy Apex, flows and prompt templates before publishing.** Publish does not deploy them, and
  live preview runs whatever the org holds.
- **Publish only the naked draft.** Publishing a version-suffixed bundle is an error.
- Pass `--verbose` to list every component retrieved and deployed, `--concise` for a summary.

## 5. Naked versus version-suffixed bundles

Always author against the naked name.

| Bundle | Meaning | Writable |
|---|---|---|
| `Local_Info_Agent` | Always points at the highest draft | **Yes; the only writable surface** |
| `Local_Info_Agent_1` | A published snapshot, locked by a `<target>` element in its `bundle-meta.xml` | **No** |

**Deploying an unmodified version-suffixed bundle succeeds as a no-op.** The command reports
success, the org is unchanged, and nothing shows which of the two you edited.

## 6. Retrieve, sync and delete

```bash
sf project retrieve start --metadata AiAuthoringBundle:Local_Info_Agent --target-org dev     # ✅ draft only
sf project retrieve start --metadata "AiAuthoringBundle:Local_Info_Agent*" --target-org dev  # ✅ every version
sf project retrieve start --metadata Agent:Local_Info_Agent --target-org dev                  # ❌ alone: no bundle
```

- **`Agent:X` retrieves** the runtime metadata **plus** the Apex and flows behind its actions, and no
  `AiAuthoringBundle`. **`Agent:X` deploys** the runtime metadata only, not the Apex or flows.
  Always request `AiAuthoringBundle` too; `references/building-an-agent.md` passes both for this
  reason.
- With source tracking on, `sf project retrieve preview` / `deploy preview` show agent changes like
  any other metadata.
- `sf project delete source --metadata AiAuthoringBundle:X` deletes the bundle and its runtime
  metadata; `--metadata Agent:X` deletes the runtime metadata of an inactive or half-created agent.
  Neither deletes Apex or flows.

## 7. Move an agent between orgs at 68.0

Both orgs must be on 68.0. While production is on 67.0, use §8.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Warranty_Agent</members>
        <name>AiAgentDefinition</name>
    </types>
    <types>
        <members>Warranty_Agent#*</members>
        <name>AiAgentDefinitionVersion</name>
    </types>
    <types>
        <members>Warranty_Agent</members>
        <name>AiAuthoringBundle</name>
    </types>
    <version>68.0</version>
</Package>
```

```bash
sf project retrieve start --manifest manifest/package.xml --root-type-with-dependencies AiAgentDefinitionVersion --target-org sandbox
sf project deploy start   --manifest manifest/package.xml --root-type-with-dependencies AiAgentDefinitionVersion --target-org prod
```

- Name versions as `Agent#N`, every version as `Agent#*`, everything as `*`.
- `--root-type-with-dependencies AiAgentDefinitionVersion` pulls the exact versions of the flows,
  Apex and prompt templates each agent version uses; do not list them.
- List everything else the agent needs: custom objects, fields, and the `AiAuthoringBundle` of every
  Agent Script agent.
- Deploy `AiAgentDefinition` in the same package unless it already exists in the target, with at
  least one `AiAgentDefinitionVersion`.
- Never deploy a version in the same package as its matching legacy `BotVersion`.

## 8. Move an agent between orgs at 67.0 and earlier

| Manifest | Contents | Rule |
|---|---|---|
| All agents | `Bot`, `BotVersion`, `GenAiPlannerBundle`, `AiAuthoringBundle`, `GenAiPlugin`, `GenAiFunction`, `GenAiPromptTemplate`, `ApexClass`, `Flow` | Replace `*` on Apex, Flow and templates with named members; wildcards cause very long deploys or timeouts |
| One version | `BotVersion` `Agent.v2`, `GenAiPlannerBundle` `Agent_v2`, `AiAuthoringBundle` `Agent_2`, plus its actions | Deploy the full agent to the target first |
| Mismatched numbers | `BotVersion` `Agent.v7`, `GenAiPlannerBundle` `Agent_v7`, `AiAuthoringBundle` `Agent_9` | Read the pairing from the versioned bundle's `<target>` |

## 9. Rules for every move

- **Swap the agent username at deploy.** Usernames differ per org. Add `replacements` in
  `sfdx-project.json` for the `default_agent_user` value in `aiAuthoringBundles/**/*.agent` (and in
  `bots/**/*-meta.xml` at 67.0), fed by an environment variable such as `TARGET_AGENT_USER`. A
  committed version cannot be edited afterwards; set the user on a new version instead.
- **Edit nothing else in retrieved agent metadata.** Deploying hand-edited agent metadata can corrupt
  the target org. Change behaviour in the `.agent` file and republish.
- **Keep source and target in step.** After a deploy, a version created only in the target blocks
  future deployments; create the matching version in the source.
- **Grant the agent user the access its actions need** in the target org (`dya-sf-permissions`).
- **Publish needs** `Modify All Data` and `Manage AI Agents`; preview needs `Agent Platform Builder`;
  generating and validating a bundle need neither.

## 10. Activation

```bash
sf agent activate   --api-name Warranty_Agent --version 3 --target-org prod
sf agent deactivate --api-name Warranty_Agent --target-org prod
```

- Activation makes a version available on the agent's channels immediately; **one version is active
  at a time**, so activating version 3 retires version 2.
- `--version` is N from `vN.botVersion-meta.xml`. **With `--json` and no `--version`, the latest
  version activates**; always pass both flags in automation.
- **Deactivation ends open conversations** and makes the agent unreachable on every connection.
- Previewing a published agent with `--api-name` requires an active version; some agent tests do too.
- Roll back by activating the previous version; keep it published.

## 11. Packaging

`sf agent generate template` builds a `BotTemplate` and `GenAiPlannerBundle` from a `Bot` file and
version, from a **namespaced scratch org**, for a second-generation managed package:

```bash
sf agent generate template --agent-file force-app/main/default/bots/Warranty_Agent/Warranty_Agent.bot-meta.xml --agent-version 2 --source-org pkg-scratch --output-dir pkg
```

**It does not work for Agent Script agents**, which cannot be packaged as templates yet; move them
by metadata deploy (§7). It never scaffolds a new agent: the sample Local Info Agent comes from
`sf template generate project --template agent`.

## 12. Validate before you publish

```bash
sf agent validate authoring-bundle --api-name Warranty_Agent --target-org dev
```

Org validation needs `--target-org` and reports each error with its location.

For an offline compile and lint, the npm package **`@sf-agentscript/agentforce`** (Apache-2.0) parses,
lints and emits Agent Script without an org. Compile locally, validate against the org, then publish.

## 13. CLI surface

```bash
sf agent generate agent-spec --type customer|internal --role "<text>" --output-file <path>
sf agent generate authoring-bundle --name "<Label>" --api-name <ApiName> --spec <path> | --no-spec
sf agent validate authoring-bundle --api-name <ApiName>
sf agent publish  authoring-bundle --api-name <ApiName> [--skip-retrieve] [--verbose | --concise]
sf agent activate   --api-name <ApiName> --version <N>
sf agent deactivate --api-name <ApiName>
sf org open agent   --api-name <ApiName> | --authoring-bundle <ApiName> [--version <N>]

sf agent preview start --authoring-bundle <ApiName> --use-live-actions | --simulate-actions
sf agent preview start --api-name <ApiName>          # published and active; always live
sf agent preview send  --session-id <id> --utterance "<text>"
sf agent preview end   --session-id <id> | --all
sf agent trace list | read --session-id <id> | delete

sf agent test create --spec <path> --api-name <TestName>
sf agent test run --api-name <AiEvaluationDefinition> --wait <minutes>
sf agent test list | results --job-id <id> | resume --job-id <id>
sf agent test run-eval --spec <path>
```

`--context-variables-json` on `sf agent preview` and `preview start` sends typed values; it needs
CLI 2.151.7 or newer, the baseline for this skill.

Data libraries and MCP servers have their own command groups; options and workflows are in
`references/knowledge-and-data-libraries.md`.

```bash
sf agent adl create --name "<Label>" --developer-name <Name> --source-type sfdrive|knowledge|retriever
sf agent adl upload   -i <libraryId> -f <file>          # SFDRIVE libraries; -w waits for indexing
sf agent adl file add -i <libraryId> -f <path>
sf agent adl file delete -i <libraryId> --file-id <id>
sf agent adl status -i <libraryId>

sf agent mcp list | get | create | update | delete | fetch    # Developer Preview
```

**The `sf agent mcp` commands are Developer Preview**, so never use them in production pipelines.

**Do not run `sf agent generate test-spec` under automation**: it is an interactive prompt per case
and stalls with no output. Write the spec YAML directly or copy one from an existing agent.

Do not use `sf agent create --spec`: it builds a legacy agent with no Agent Script.
