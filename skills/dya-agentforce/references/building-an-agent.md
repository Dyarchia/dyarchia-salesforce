# Building an Agent, End to End — Reference (Winter '27 / API v68.0)

Load from `dya-agentforce` when you are actually building an agent rather than reasoning about one.
The rest of the skill explains the parts; this is the order you touch them in.

## 0. Prerequisites — the step people skip

None of this works in an org where Agentforce has not been switched on, and the failure looks like
"the button isn't there" rather than an error.

1. **Pick an environment.** A **sandbox** is a copy of production and carries its metadata, so it is
   the realistic place to test against real configuration; Developer and Developer Pro refresh often.
   A **scratch org** is empty and fast to create, which suits source-driven work on one feature. A
   **Developer Edition** org is the free permanent option for learning.
2. **Turn on Data 360 first, if the agent will be grounded in it.** Setup › Data Cloud Setup Home.
   **This can take up to 60 minutes** and nothing else should proceed until it finishes — see
   `dya-data360`.
3. **Enable Einstein.** Setup › Einstein Setup › *Turn on Einstein*.
4. **Enable Agentforce.** Setup › Agentforce Agents. After enabling it the first time, refresh the
   page or the **New Agent** button will not appear.
5. **Create a Salesforce DX project** and authorise the org. Agents are metadata like anything else,
   so they live in a DX project under version control. See `references/shared/org-model.md`.

## 1. Two workflows, and which to choose

**Author in DX** — script first, org second. Best when the agent is a code artefact from the start.

**Build in Builder, then retrieve** — click first, code second. Best when a non-developer shapes the
agent's behaviour and a developer then takes it into version control.

They converge: both end with an **authoring bundle** in the DX project that you code, preview and
publish. Use the **new** Agentforce Builder, not the legacy one — only the new builder produces an
Agent Script file.

## 2. Authoring from scratch

### Generate an agent spec (optional, recommended)

```bash
sf agent generate agent-spec --type customer --spec specs/agentSpec.yaml
```

A small YAML capturing what the agent is for. Skipping it is allowed, but then the generated bundle
is boilerplate rather than shaped around your agent — the ten minutes here save an hour later.

### Generate the authoring bundle

```bash
sf agent generate authoring-bundle --spec specs/agentSpec.yaml
```

An **`AiAuthoringBundle`** is the metadata component you author against. Inside it, a file with the
**`.agent`** extension is the Agent Script — the agent's blueprint — beside a
`<ApiName>.bundle-meta.xml` whose name must match the directory. Bundles land in
`aiAuthoringBundles/` in your package directory; the capital **B** matters, because a Linux CI
runner will not find `aiAuthoringbundles/`.

The authoring bundle is not what a running agent is made of. **Deploying stages the bundle into the
authoring domain and creates no runtime entity**; `sf agent publish authoring-bundle` compiles the
Agent Script and creates the `Bot`, `BotVersion`, `GenAiPlannerBundle` and `GenAiPlugin` records
that serve conversations. At **API 68.0** those runtime components deploy and retrieve as
`AiAgentDefinition` and `AiAgentDefinitionVersion`, which is what makes an agent source-controllable
like any other metadata — and why both orgs must be on 68.0 for a deploy to carry anything. Below
68.0 you are moving the bundle and republishing instead.

There is a path that creates an agent directly without Agent Script (`sf agent create --spec …`).
Salesforce explicitly recommends against it: script-based agents are more flexible and easier to
modify and maintain.

### Code the script

Edit the `.agent` file in VS Code. The Agentforce DX extension gives syntax highlighting, linting and
validation, and Agentforce Vibes can write script for you. Validate as you go so it compiles.

> Syntax: `references/agent-script.md`.

### Preview while you build

```bash
sf agent preview start --authoring-bundle My_Local_Agent
sf agent preview send  --authoring-bundle My_Local_Agent
sf agent preview sessions
sf agent preview end   --authoring-bundle My_Local_Agent

# or against a published agent, capturing transcripts
sf agent preview --api-name My_Agent --output-dir ./transcripts
```

**Actions you have not implemented yet return mocked responses**, so you can test routing and
conversation shape before writing a line of Apex. That is the point of previewing early. The Apex
Replay Debugger works during a preview, and the transcripts show how the agent classified and routed.

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

Then code, preview and publish exactly as above.

## 4. Test before activating

```bash
sf agent test create --spec test-specs/resort-manager-tests.yaml --target-org <alias>
sf agent test list --target-org my-dev-org
sf agent test results --job-id 4KBed00fakeahmPGAQ
sf agent test resume  --job-id 4KBed00fakeahmPGAQ
```

**Do not reach for `sf agent generate test-spec` here.** It is an interactive REPL that prompts for
each case, so it stalls under automation with no output. Write the spec YAML directly, or copy one
from an existing agent and edit it.

Test the three things separately, because they fail for different reasons: **subagent
classification** (does the right subagent fire, and does it *not* fire when out of scope), **action
selection** (right action, right parameters), and **grounding accuracy** (is the answer supported by
retrieved data).

## 5. Activate

```bash
sf agent activate --target-org my-org
```

## 6. Provision the agent user

```bash
sf agent generate agent-user
```

An agent runs as a user, and **that user's permissions decide what the agent can reach and surface**.
This is the security boundary, not an administrative afterthought — scope it deliberately before
activation. See `dya-permissions`.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Starting to build before enabling Einstein and Agentforce | Do the Setup steps first; the symptom is a missing button, not an error |
| Enabling Data 360 and continuing immediately | It can take an hour; wait for the completion message |
| Using the Legacy Agentforce Builder for new work | The new builder, which produces an Agent Script file |
| `sf agent create` without Agent Script | Generate an authoring bundle — Salesforce recommends against the scriptless path |
| Skipping the agent spec | Ten minutes there produces a bundle shaped around your agent instead of boilerplate |
| Waiting until actions exist before previewing | Unimplemented actions are mocked — preview routing on day one |
| Testing by having one conversation | `sf agent test` over a spec; classification, action selection and grounding are separate failures |
| Treating the agent user as setup paperwork | It is the security boundary — scope it before activation |
