# Prompt Templates — Reference (Winter '27 / API v68.0)

Load from `dya-agentforce` when an agent action generates or transforms text, or when you need to
call a prompt template from code.

## What they are, and where the line falls

A **prompt template** is a reusable, parameterised prompt built in **Prompt Builder**. It merges CRM
data — record fields, related lists, Flow output, Apex — into a prompt and calls the LLM. It is the
right action type whenever the job is *produce text grounded in records*: a summary, a draft email, a
field value, a classification.

Authoring a template is a Prompt Builder task, done in the UI and documented in Salesforce Help. What
belongs to a developer, and what this reference covers, is **calling one from code**, **running one
over many records**, and **moving one between orgs**.

In Agent Script an action reaches a template with the `prompt://` target — see
`references/agent-script.md`:

```agentscript
check_bookings:
    description: "Summarise the customer's current bookings."
    target: "prompt://check_bookings"
```

## Calling a template programmatically

Three surfaces, chosen by where the caller lives:

| Caller | Surface |
|---|---|
| A third-party web application | **Connect REST API** — the Prompt Template Generations resource |
| Apex | **Connect in Apex** — resolve the template; the `EinsteinLLM` class carries the static methods |
| Flow, or anywhere on the platform | The **Generate Prompt Response** invocable action |

The invocable action is the one to reach for by default: it works from Flow, from an agent, and from
anywhere an action can be called, without you writing an integration.

## Batch processing — many records, no user waiting

For generating output over a large set of records — a nightly summarisation of a case backlog — do
not loop synchronous calls. Two standard objects drive an asynchronous batch: **`AiJobRun`** (the job)
and **`AiJobRunItem`** (one per input record).

### Step 1 — create the job

```apex
AiJobRun jobRun = new AiJobRun(
    JobType = 'PromptTemplate',
    Target  = 'Summarize_Case',   // template DeveloperName; an Id is accepted but is org-specific
    Status  = 'New'
);
insert as user jobRun;
```

`Target` takes the template's **DeveloperName or its record Id** — prefer the DeveloperName, because
it is stable across orgs and an Id is not. `Status` is required on insert; start at `New` so the
items can be added before anything runs.

### Step 2 — one item per record

```apex
List<Case> cases = [SELECT Id FROM Case LIMIT 200];

List<AiJobRunItem> items = new List<AiJobRunItem>();
for (Case c : cases) {
    Map<String, Object> payload = new Map<String, Object>{
        'Input:Case' => new Map<String, Object>{ 'id' => c.Id }
    };
    items.add(new AiJobRunItem(
        AiJobRunId = jobRun.Id,
        Status     = 'Ready',
        Input      = JSON.serialize(payload)
    ));
}
insert as user items;
```

`Input` is a JSON string whose keys use the `Input:` prefix, and the value is a record pointer with
an `id`. Every item goes in at `Status = 'Ready'`.

For a run approaching the item cap, wrap this step in a `Database.Batchable` so each execute scope
gets fresh governor limits — see `dya-apex`.

### Step 3 — hand it to the platform

```apex
jobRun.Status = 'ReadyToStart';
update as user jobRun;
```

**Nothing changes after this point.** Once the job reaches `InProgress`, `AiJobRunId` and `Input`
become immutable, non-null schema fields are frozen, and neither the job nor its items can be
deleted. The `InProgress`, `Completed` and `Failed` statuses cannot be set by you at all. Build the
whole batch before flipping the switch.

### Limits worth knowing before you design

| | Standard models | Models with native batch support |
|---|---|---|
| Items per `AiJobRun` | 1,000 | 10,000 |
| Recommended daily volume from Apex | 5,000 | 50,000 |

You may create as many jobs as you need; extras sit in `Queued` and are picked up as capacity frees.
Exceeding the recommended daily volume does not fail — jobs simply take longer than 24 hours, which
is worse, because it looks like a hang. Native-batch completion time is set by the model provider,
typically 24 hours.

Jobs at `ReadyToStart` process in `CreatedDate` order, though several flipped within a few seconds of
each other may not strictly hold that order — do not depend on sequencing between jobs.

`JobType` differs by initiator: `PromptTemplate` for an Apex-created run, `GeneratePromptAsyncIA` when
Flow's Prompt Template Batch Generation action starts it.

## Moving templates between orgs

Metadata API types: **`GenAiPromptTemplate`** and **`GenAiPromptTemplateActv`**. Deploy them like any
other metadata, from a DX project under version control — see `references/shared/org-model.md`.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Apex string-building a prompt by hand | A prompt template — it merges record data and is manageable by an admin |
| Looping synchronous generations over many records | `AiJobRun` + `AiJobRunItem` batch |
| Referencing a template by record Id across orgs | `DeveloperName` — the Id does not survive a deployment |
| Editing job items after flipping to `ReadyToStart` | Build the batch fully first; the fields become immutable |
| Pushing past the recommended daily volume | Jobs stretch beyond 24 hours rather than failing — plan the volume |
| Assuming jobs run in the order you started them | `CreatedDate` order is approximate within a few seconds |
| Click-deploying templates between orgs | `GenAiPromptTemplate` metadata from version control |
