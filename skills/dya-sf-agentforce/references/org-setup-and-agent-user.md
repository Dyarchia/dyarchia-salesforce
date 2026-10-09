# Org Setup and the Agent User — Reference (Winter '27 / API v68.0)

Everything that must be true in the org, and of the user an agent runs as, before the agent works.

The general access model (profiles, permission sets, sharing, FLS) is `dya-sf-permissions`; this
file covers only what is specific to agents.

## 1. Pick the environment

| Agent needs | Use | Fact that decides it |
|---|---|---|
| No Data Library, no Data 360 grounding | Scratch org from an Agentforce definition file | Empty and fast; ideal for source-driven work on one feature |
| A Data Library or any Data 360 feature | Developer or Developer Pro sandbox connected to Data 360 | Salesforce recommends a sandbox for Data Library work; refreshes often |
| Integration or user testing on real data | Partial or Full Copy sandbox | Carries production data; refresh is rationed |
| Learning, no Dev Hub | Developer Edition signed up with Agentforce and Data 360 | Free and permanent |

- A sandbox copies production's metadata, **not** a working Agentforce setup. Run §3 after every
  create and every refresh.
- A scratch org needs a Dev Hub that holds Data 360 licences.
- Data 360 is what the Einstein Trust Layer, agent event logs and consumption tracking run on.
  Skip it only in throwaway development orgs whose agents are not grounded.

## 2. Scratch org definition

Generate the project from the `agent` template; it writes a working definition to
`config/project-scratch-def.json`. Start from that file rather than writing one.

```json
{
    "orgName": "Agent Dev",
    "edition": "Developer",
    "features": ["EnableSetPasswordInApi", "Einstein1AIPlatform"],
    "settings": {
        "agentPlatformSettings": { "enableAgentPlatform": true },
        "einsteinGptSettings": { "enableEinsteinGptPlatform": true }
    }
}
```

- `Einstein1AIPlatform` gives the generative AI platform; it is supported in Developer and Enterprise
  editions.
- `agentPlatformSettings.enableAgentPlatform` and `einsteinGptSettings.enableEinsteinGptPlatform`
  switch Agentforce and Einstein on at creation, so no Setup clicks follow. Omit them and every
  `sf agent` command fails with *feature is not currently enabled for this user type or org*.

```bash
sf org login web --set-default-dev-hub --alias DevHub
sf org create scratch --definition-file config/project-scratch-def.json --alias afdx \
    --set-default --target-dev-hub DevHub --duration-days 7
sf org open --target-org afdx
```

## 3. Enable the platform in Setup

Sandboxes, Developer Edition and production orgs need these steps by hand, **in this order**.

| # | Step | Setup path | Done when |
|---|---|---|---|
| 1 | Provision Data 360 (if grounded, and always in production) | Data Cloud Setup Home › Get Started | The page shows a home org ID, instance and tenant endpoint. **Allow up to 60 minutes; do not continue before it finishes** |
| 2 | Turn on Einstein | Einstein Setup › Turn on Einstein | Toggle on; refresh. Einstein and Data 360 take a few minutes to sync |
| 3 | Configure the Einstein Trust Layer | Einstein Trust Layer settings | Only after steps 1 and 2; the Trust Layer depends on Data 360 |
| 4 | Turn on Agentforce | Agentforce Agents › Agentforce toggle | **Refresh the page**, or the New Agent button stays hidden |
| 5 | Confirm Agentforce Data Library is available, if used | Agentforce Data Library | A library can be created; otherwise every call answers `FEATURE_NOT_ENABLED` and an admin must enable the feature |

- If **Agentforce Agents** is missing from Setup, Einstein is off.
- Turn on Lightning Knowledge before building a Knowledge library; see
  `references/knowledge-and-data-libraries.md`.
- Data 360 setup and its permission sets: `dya-sf-data360`.

## 4. DX project and authorisation

```bash
sf template generate project --name agentforcedx --template agent
cd agentforcedx
sf org login web --alias agentforce --set-default
```

- The `agent` template ships a sample `Local_Info_Agent` with Apex, Flow and prompt-template actions,
  its permission sets and permission set groups, and the scratch definition above.
- Install VS Code with the Salesforce Extension Pack: it carries Agentforce DX, the Agent Script
  Language Server and the Apex Replay Debugger.
- For CI, authorise with the JWT flow through an external client app holding a certificate; the
  agent commands need nothing beyond standard DX authorisation. See `dya-sf-cli`.
- Keep `sf` current (`sf update`); the agent command family changes with the CLI's weekly releases.

## 5. Permissions the developer needs

| Task | System permissions on the developer's user |
|---|---|
| `sf agent generate authoring-bundle`, `sf agent validate authoring-bundle` | None |
| `sf agent preview` | Agent Platform Builder |
| `sf agent publish authoring-bundle` | Modify All Data **and** Manage AI Agents |
| Create or edit a Data Library | Agentforce Data Library access; a refused call returns `PERMISSION_DENIED`, checked against the acting user. Re-authenticate after a grant |

A System Administrator already holds all of them. Grant the others through a permission set, never
by changing the profile.

## 6. The agent type decides who the agent runs as

Set `agent_type` in the script's `config` block; a template sets it for you.

| `agent_type` | Serves | Runs as | `access.default_agent_user` |
|---|---|---|---|
| `AgentforceServiceAgent` (default) | Customers on a channel: Enhanced Chat, messaging, voice, Agent API | A dedicated **agent user** | **Required.** Publish fails if the username does not exist in the org |
| `AgentforceEmployeeAgent` | Employees inside Salesforce or an embedded client | The **employee in the conversation** | **Omit.** Setting it makes publish and preview fail with an uninformative internal error |

- **A service agent gives every customer the same identity.** Whatever the agent user can read, any
  visitor can ask the agent to reveal. Separate one customer's data from another's in the script and
  the actions, not with sharing; see §10.
- **An employee agent sees what the employee sees.** Grant its actions' Apex classes, flows and
  objects to the employees, through permission sets or permission set groups.
- The Agent API does not serve agents of type "Agentforce (Default)". See
  `references/lifecycle-and-api.md`.

## 7. Create the agent user

Create it in Setup, from Agentforce Builder (**New User** when creating from the Service Agent
template), or from the CLI:

```bash
sf org create agent-user --target-org my-org
sf org create agent-user --first-name Service --last-name Agent \
    --base-username service-agent@corp.com --target-org my-org
```

| What the command does | Detail |
|---|---|
| Name | "Agent User", or `--first-name` / `--last-name` |
| Username | `agent.user.<12-char GUID>@<org domain>`; with `--base-username` the GUID is inserted before the `@` |
| Email | Set to the username |
| Profile | Einstein Agent User |
| Permission sets | `AgentforceServiceAgentBase`, `AgentforceServiceAgentUser`, `EinsteinGPTPromptTemplateUser` |
| Licences | Checks that the licences the profile and permission sets need are available; fails otherwise |
| Output | The username, user ID, available Einstein Agent licences and the assignments it made |

- The user has **no password** and cannot log in. Only admins can view or edit it in Setup.
- The command grants the platform baseline only. **It grants nothing your actions touch**; §8 does.
- Find an existing agent user before creating another:

```bash
sf data query --target-org my-org \
    --query "SELECT Username FROM User WHERE UserType = 'EinsteinAgent' AND IsActive = true"
```

### Wire it into the script

```agentscript
access:
    default_agent_user: "agent.user.a1b2c3d4e5f6@example.com"   # ✅ the access block

config:
    developer_name: "Order_Help"
    default_agent_user: "agent.user.a1b2c3d4e5f6@example.com"   # ❌ deprecated in config
```

`sf org create agent-user --help` and the `agent` project template still place the property in
`config`; the Agent Script reference deprecates that location. Write it in `access`.

- Preview in live mode and Apex debug mode both run as this user. A script that validates but whose
  preview fails to start almost always names a missing or inactive user.
- **A committed agent version cannot be edited.** To change its user, create a new version and set
  the user there.

### Moving an agent between orgs

The username carries a per-org GUID, so it differs in every org. Replace it at deploy time with
string replacement in `sfdx-project.json`:

```json
{
    "replacements": [
        {
            "glob": "force-app/**/*.agent",
            "stringToReplace": "agent.user.a1b2c3d4e5f6@example.com",
            "replaceWithEnv": "TARGET_AGENT_USER"
        },
        {
            "glob": "force-app/**/*-meta.xml",
            "stringToReplace": "agent.user.a1b2c3d4e5f6@example.com",
            "replaceWithEnv": "TARGET_AGENT_USER"
        }
    ]
}
```

```bash
TARGET_AGENT_USER="agent.user.f6e5d4c3b2a1@example.com" sf project deploy start \
    --source-dir force-app --target-org uat
```

- Replacement works on **draft** agents only; a committed version needs the manual new-version route.
- Do not edit any other retrieved agent metadata by hand; a deploy of edited metadata can corrupt
  the org.
- After the first deploy, keep agent versions matched between source and target org, or later
  deploys are blocked.
- Lifecycle detail: `references/agent-lifecycle-metadata.md`.

## 8. Grant the agent user what its actions touch

An action executes with the agent user's access. Grant exactly what each action reads or writes,
read-only unless the action writes.

| Layer | Grant | Symptom when missing |
|---|---|---|
| Object | Object permission (Read; Create or Edit only where an action writes) | The action finds no records or errors |
| Field | Field permission for **every** field the action reads or writes. Object access does not imply field access | The field arrives empty; the agent answers as if the data does not exist |
| Apex | Class access for every invocable class and the classes it calls | The action fails at runtime |
| Flow | The **Run Flows** user permission | The flow action fails |
| Prompt template | `EinsteinGPTPromptTemplateUser`, assigned by `sf org create agent-user` | The template action fails |
| Knowledge | Read on `Knowledge__kav`, field access on the indexed fields, and the **Allow View Knowledge** app permission. The agent user cannot hold a Knowledge licence | Knowledge answers come back empty |
| Data 360 | A Data 360 permission set or permission set licence (§9) | Retrievers return nothing for the agent while they work for you |

- Builder creates a per-agent permission set, named like **Agentforce Agent \<AgentName\>
  Permissions**, assigned to the agent user. It starts empty: put the agent's object and field
  grants there.
- A permission set you write for an agent user declares the **Einstein Agent** licence:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Order Help Agent</label>
    <license>Einstein Agent</license>
    <classAccesses>
        <apexClass>OrderStatusAction</apexClass>
        <enabled>true</enabled>
    </classAccesses>
    <fieldPermissions>
        <field>Order.Delivery_Window__c</field>
        <readable>true</readable>
        <editable>false</editable>
    </fieldPermissions>
    <objectPermissions>
        <object>Order</object>
        <allowRead>true</allowRead>
        <allowCreate>false</allowCreate>
        <allowEdit>false</allowEdit>
        <allowDelete>false</allowDelete>
        <viewAllRecords>false</viewAllRecords>
        <modifyAllRecords>false</modifyAllRecords>
    </objectPermissions>
    <userPermissions>
        <enabled>true</enabled>
        <name>RunFlow</name>
    </userPermissions>
</PermissionSet>
```

- Never add a field permission for a master-detail field; the deploy is rejected.
- Deploy in dependency order: Apex and flows, then the permission set, then the authoring bundle.
- Assign with the CLI. `--on-behalf-of` takes a username or a CLI alias, never the User record's
  Alias field:

```bash
sf org assign permset --name Order_Help_Agent --on-behalf-of agent.user.a1b2c3d4e5f6@example.com \
    --target-org my-org
sf org assign permsetlicense --name <LicenceDeveloperName> \
    --on-behalf-of agent.user.a1b2c3d4e5f6@example.com --target-org my-org
```

- Prove a flow's access as the agent user before blaming the script: enable **Let admins debug
  flows as other users** in Process Automation Settings, then **Debug › Run automation as another
  user**. If it succeeds as you and fails as the agent user, the gap is a permission.
- Apex actions run `with sharing` in user mode by default at 67.0+, so the agent user's sharing
  applies too; see `references/agent-actions.md` and `dya-sf-apex`.

## 9. Data 360 access for grounding

- Agentforce Data Library works **only in the default data space**; a non-default one fails with
  `NON_DEFAULT_DATASPACE`, and no setting changes that.
- A Data 360 **companion org** (Data 360 provisioned in a different org) cannot host a Data Library
  (`DC1_NOT_SUPPORTED`). Ground through a custom retriever instead.
- `DC_CONNECTION_MISSING` means Data 360 is still provisioning or lost its connection. Wait; do not
  rebuild the library.
- `MISSING_ORG_PREREQUISITE` means a licence, org permission or dependent feature is absent. Fix the
  org; retrying does nothing.
- **The agent user needs Data 360 access to run retriever queries.** The permission set or licence
  that grants it varies by org shape and release; look it up in the target org instead of
  hardcoding one name. Names in use include the `GenieDataPlatformStarterPsl` permission set licence
  and the `GenieUserEnhancedSecurity` ("Data Cloud User") and `DataCloudUser` permission sets:

```bash
sf data query --target-org my-org \
    --query "SELECT Name, Label FROM PermissionSet WHERE Label LIKE '%Data Cloud%'"
sf data query --target-org my-org \
    --query "SELECT DeveloperName, MasterLabel FROM PermissionSetLicense WHERE MasterLabel LIKE '%Data%'"
```

- The person who builds search indexes, retrievers and unstructured data objects needs Data 360
  administration rights such as the Data Cloud Architect permission set. That is a builder grant;
  never give it to the agent user.
- Data spaces, permission sets and Data 360 setup: `dya-sf-data360`.

## 10. Customers, guests and other external callers

A service agent's customer is usually not a Salesforce user, or is a site guest. Every turn runs as
the agent user regardless.

- Keep the agent user read-only on the minimum set of objects and fields.
- Verify identity before any customer-specific action, with a **conditional transition** at the top
  of the router's instructions. `available when` only hides actions; it does not force the step.
  Pattern: `references/agent-script-patterns.md`.
- Pass the verified customer's ID into every action and filter by it in Apex or Flow. Never let the
  model choose whose record to read.
- Restrict a customer-facing Knowledge library to public articles:
  `sf agent adl update --library-id <id> --restrict-to-public-articles`.
- Return only fields the customer may see; anything an action outputs can reach the conversation.
- The Agent API authenticates through an external client app whose client-credentials **Run As**
  user needs at least API Only access. See `references/lifecycle-and-api.md`.
- An agent exposed as an MCP tool runs in the authenticated caller's context; see
  `dya-sf-headless360`.

## 11. How missing access shows up

Most gaps are silent: the agent says it has no information, which reads like a grounding or
instruction problem. Rule out access first, and test in **live** preview: simulated mode mocks
actions, so no permission gap can appear there.

| Symptom | Cause | Check |
|---|---|---|
| No **New Agent** button | Page not refreshed after enabling, or Einstein off | §3 steps 2 and 4 |
| *Feature is not currently enabled for this user type or org* from `sf agent` | Einstein or Agentforce off; scratch definition lacks the settings | §2, §3 |
| Script validates, preview never starts | `default_agent_user` missing, misspelled or inactive | §7 query |
| Employee agent fails to publish with an internal error | `access.default_agent_user` set on an employee agent | §6 |
| Publish fails after a cross-org deploy | Source org's agent username | §7 string replacement |
| `sf org create agent-user` fails its licence check | No Einstein Agent licences available | Org licences |
| Action answers "no records" in live mode | Agent user lacks object access or sharing | §8 object layer; debug as the user |
| Agent behaves as if a field is blank | Field permission missing | §8 field layer |
| Knowledge answers are always empty | Allow View Knowledge, `Knowledge__kav` read, or field access missing | §8 Knowledge layer |
| Grounded answers work for you, not for the agent | Agent user lacks Data 360 access | §9 |
| `PERMISSION_DENIED` from a Data Library call | Acting user lacks Data Library rights | §5; re-authenticate |
| `FEATURE_NOT_ENABLED` from a Data Library call | Data Library not enabled | §3 step 5 |

## 12. Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Building in a scratch org when the agent needs a Data Library | A Developer or Developer Pro sandbox connected to Data 360 |
| Refreshing a sandbox and expecting Agentforce to work | Re-run the Setup sequence after every create and refresh |
| Enabling Einstein before Data 360 finishes | Wait for Data 360 completion, then Einstein, Trust Layer, Agentforce |
| `default_agent_user` in the `config` block | The `access` block |
| `default_agent_user` on an employee agent | Omit it; the employee's own access applies |
| One catch-all permission set for every agent | One permission set per agent, holding only that agent's grants |
| Granting the agent user System Administrator or Modify All Data | A licence-scoped permission set with only what the actions touch |
| Object access without field access | Explicit field permissions for every field read or written |
| Hardcoding the source org's agent username | String replacement with `replaceWithEnv` |
| Testing access in simulated preview | Live preview, and flow debug as the agent user |
| Relying on sharing to separate customers of a service agent | Identity verification plus actions filtered by the verified ID |
| Hardcoding one Data 360 permission set name in automation | Query which one the org has, then assign it |
