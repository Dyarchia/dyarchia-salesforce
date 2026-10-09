# Building an Agent, End to End — Reference (Winter '27 / API v68.0)

The order in which you build an agent's parts.

## 0. Prerequisites

Complete these steps before building anything; until Agentforce is on, the symptom is a missing
button rather than an error.

1. **Pick an environment.** A **sandbox** copies production's metadata, so it tests against real
   configuration; Developer and Developer Pro refresh often. A **scratch org** is empty and fast to
   create, suiting source-driven work on one feature. A **Developer Edition** org is the free
   permanent option for learning.
2. **Turn on Data 360 first, if the agent will be grounded in it.** Setup › Data Cloud Setup Home.
   **This can take up to 60 minutes**; proceed only once it finishes — see `dya-sf-data360`.
3. **Enable Einstein.** Setup › Einstein Setup › *Turn on Einstein*.
4. **Enable Agentforce.** Setup › Agentforce Agents. After enabling it the first time, refresh the
   page or the **New Agent** button will not appear.
5. **Create a Salesforce DX project** and authorise the org. Keep agents in a DX project under
   version control; they are metadata.

## 1. Two workflows, and which to choose

**Author in DX** — script first, org second. Choose it when the agent is a code artefact from the
start.

**Build in Builder, then retrieve** — click first, code second. Choose it when a non-developer shapes
the agent's behaviour and a developer then takes it into version control.

Both end with an **authoring bundle** in the DX project that you code, preview and publish. Use the
**new** Agentforce Builder, not the legacy one — only the new builder produces an Agent Script file.

## 2. Authoring from scratch

### Generate an agent spec (optional, recommended)

```bash
sf agent generate agent-spec --type customer --output-file specs/agentSpec.yaml --target-org <alias>
```

Write this small YAML capturing the agent's purpose; without it the generated bundle is
boilerplate.

### Generate the authoring bundle

```bash
sf agent generate authoring-bundle --spec specs/agentSpec.yaml --name "My Agent" --api-name My_Agent --target-org <alias>
```

`--name` is the label and `--api-name` the API name, derived from the label when omitted. Pass
`--no-spec` instead of `--spec` for the default boilerplate. Without `--spec`, `--no-spec` or
`--name` the command prompts, and stalls under automation.

An **`AiAuthoringBundle`** is the metadata component you author against. Inside it, a **`.agent`**
file is the Agent Script — the agent's blueprint — beside a `<ApiName>.bundle-meta.xml` whose name
must match the directory. Bundles land in `aiAuthoringBundles/` in your package directory; the
capital **B**; a Linux CI runner will not find `aiAuthoringbundles/`.

**Deploying stages the bundle into the authoring domain and creates no runtime entity**;
`sf agent publish authoring-bundle` compiles the Agent Script and creates the `Bot`, `BotVersion`,
`GenAiPlannerBundle` and `GenAiPlugin` records that serve conversations. At **API 68.0** those
runtime components deploy and retrieve as `AiAgentDefinition` and `AiAgentDefinitionVersion`, so an
agent is source-controllable like other metadata. Below 68.0 you move the bundle and republish
instead.

Do not use `sf agent create --spec …`: it creates an agent without Agent Script, and Salesforce
recommends against it because script-based agents are more flexible and easier to modify and
maintain.

### Code the script

Edit the `.agent` file in VS Code. The Agentforce DX extension gives syntax highlighting, linting and
validation, and Agentforce Vibes can write script for you. Validate after every edit so the script
compiles.

> Syntax: `references/agent-script.md`.

### Preview while you build

```bash
sf agent preview start --authoring-bundle My_Local_Agent
sf agent preview send  --authoring-bundle My_Local_Agent --utterance "What can you help me with?"
sf agent preview sessions
sf agent preview end   --authoring-bundle My_Local_Agent

# or an interactive chat with a published, active agent, capturing transcripts
sf agent preview --api-name My_Agent --output-dir ./transcripts
```

A published agent must be **active** before you can preview it. `sf agent trace list | read |
delete` reads the trace files every preview session records.

**Unimplemented actions return mocked responses**, so you can test routing and conversation shape
before writing any Apex. The Apex Replay Debugger works during a preview, and the transcripts show how the agent classified and routed.

### Publish

```bash
sf agent publish authoring-bundle --api-name My_Agent
```

Creates the underlying agent metadata in the org and syncs it with the DX project.

## 3. Retrieving an agent someone built in Builder

```bash
sf project retrieve start --metadata AiAuthoringBundle --metadata Agent --target-org <alias>

# one bundle and all its versions
sf project retrieve start --metadata "AiAuthoringBundle:Local_Info_Agent*" --target-org <alias>
```

Then code, preview and publish as above.

## 4. Test before activating

```bash
sf agent test create --spec test-specs/resort-manager-tests.yaml --target-org <alias>
sf agent test run --api-name Resort_Manager_Tests --wait 10 --target-org <alias>
sf agent test list --target-org my-dev-org
sf agent test results --job-id 4KBed00fakeahmPGAQ
sf agent test resume  --job-id 4KBed00fakeahmPGAQ

# the same YAML spec, run through the richer evaluation framework
sf agent test run-eval --spec test-specs/resort-manager-tests.yaml --target-org <alias>
```

`--api-name` on `test run` names the **test**, the `AiEvaluationDefinition` that `test create`
deployed, not the agent. Without `--wait` the command returns at once and prints the `test resume`
command to collect results.

**Do not use `sf agent generate test-spec` here.** It is an interactive REPL prompting for each case,
so it stalls under automation with no output. Write the spec YAML directly, or copy and edit one from
an existing agent.

Test three things separately, because they fail for different reasons: **subagent classification**
(does the right subagent fire, and *not* fire when out of scope), **action selection** (right action,
right parameters), and **grounding accuracy** (is the answer supported by retrieved data).

## 5. Activate

```bash
sf agent activate --api-name My_Agent --version 2 --target-org my-org
```

Without `--api-name` and `--version` the command prompts for both. `--version` is the number in the
`vN.botVersion-meta.xml` file name.

## 6. Provision the agent user

```bash
sf org create agent-user --target-org my-org
```

It creates "Agent User" with the Einstein Agent User profile and the `AgentforceServiceAgentBase`,
`AgentforceServiceAgentUser` and `EinsteinGPTPromptTemplateUser` permission sets; name it in the
script's `config` block as `default_agent_user`. Add access with `sf org assign permset`. Scope the
agent user before activation; it is the security boundary. An agent runs as a user, and
**that user's permissions decide what the agent can reach and surface**. See `dya-sf-permissions`.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Building before enabling Einstein and Agentforce | Do the Setup steps first; the symptom is a missing button, not an error |
| Enabling Data 360 and continuing immediately | It can take an hour; wait for the completion message |
| Using the Legacy Agentforce Builder for new work | The new builder, which produces an Agent Script file |
| `sf agent create` without Agent Script | Generate an authoring bundle — Salesforce recommends against the scriptless path |
| Skipping the agent spec | Ten minutes there yields a bundle shaped around your agent instead of boilerplate |
| Waiting until actions exist before previewing | Unimplemented actions are mocked — preview routing on day one |
| Testing with one conversation | `sf agent test` over a spec; classification, action selection and grounding are separate failures |
| Treating the agent user as setup paperwork | It is the security boundary — scope it before activation |
