# Knowledge and Data Libraries — Reference (Winter '27 / API v68.0)

How to ground an agent: Agentforce Data Libraries, retrievers and search indexes, prompt-template
RAG, citations, and the external MCP tools an agent consumes.

Org prerequisites and the agent user's grants are `references/org-setup-and-agent-user.md`; Data 360
itself is `dya-sf-data360`.

## 1. Pick the grounding path

| Source of truth | Mechanism | Use when |
|---|---|---|
| PDFs, documents, text files | Data Library, **file** source (`sfdrive`) | Answers come from documents nobody wants to rewrite as articles |
| Salesforce Knowledge articles | Data Library, **knowledge** source | Articles already exist and business users maintain them |
| Website pages, other Data 360 unstructured data, custom chunking | Data 360 search index plus a custom **retriever**, wrapped in a Data Library (`retriever` source) or called from a prompt template | You need control over parsing, chunking, filters or returned fields |
| Data 360 hosted in a companion org | Custom retriever | Data Libraries do not support companion orgs |
| Structured records (orders, cases, balances) | An Apex or Flow action that queries them | Exact values, not passages; see `references/agent-actions.md` |
| A short, frequently changing lookup (product renames, acronyms) | An action that loads it once into a variable (§7) | Re-indexing for a rename is overkill |
| Tools in an external system | An MCP server registered in the API Catalog (§9) | The capability lives outside Salesforce |

Prefer grounding over model knowledge for anything factual; ground every factual answer the agent
gives.

## 2. What a Data Library is

A library (ID prefix `1JD`) provisions a Data 360 pipeline and reports each stage:

```text
DATA_STREAM → DATA_LAKE_OBJECT → DATA_MODEL_OBJECT → SEARCH_INDEX → RETRIEVER
```

- **`READY`** means chunking and embedding finished and the retriever exists. Wire the library into
  an agent only when it is `READY`.
- **Every stage `SUCCESS` while the status is not `READY`** means the pipeline is done but the search
  index may still be processing. You may add files; do not judge answer quality yet.
- The agent references a library through its **`rag_feature_config_id`, which is `ARFPC_` followed
  by the library ID**: not the library ID itself, not the retriever ID. `sf agent adl get` prints
  it once a retriever exists.
- The library's unstructured data model object carries an `ADL_` prefix; look for it when building a
  custom search index or retriever on top of library content.
- Prerequisites: Data 360 provisioned and connected, the **default** data space, Agentforce Data
  Library available in the org. Develop in a sandbox, not a scratch org.
- Setup UI: Setup › Agentforce Data Library.

## 3. The `sf agent adl` command family

Every command takes `-o/--target-org` and `--json`. Library IDs are 18-character IDs starting `1JD`.

| Command | Flags | Notes |
|---|---|---|
| `create` | `-n/--name` (≤ 80), `--developer-name` (≤ 80, letters, digits, underscores, starts with a letter), `--source-type sfdrive\|knowledge\|retriever`, `--description` (≤ 255), `-w/--wait` | Creates the library; for `sfdrive` it provisions the pipeline |
| | `--index-mode basic\|enhanced` | `sfdrive` only |
| | `--primary-index-field1`, `--primary-index-field2` | `knowledge`: **required and immutable** |
| | `--content-fields` | `knowledge`: optional, comma-separated, mutable |
| | `--data-category-ids` **or** `--data-category-names` | `knowledge`: mutually exclusive; names as `Group.Category` |
| | `--retriever-id` | `retriever`: required, must be an **active** custom retriever |
| `upload` | `-i/--library-id`, `-f/--file` (repeatable), `-w/--wait` | `sfdrive` only. First load: checks readiness, uploads, triggers indexing and full provisioning |
| `file add` | `-i/--library-id`, `-f/--path` (repeatable) | Day-2: appends to a **READY** library and re-indexes; no duplicate names in one batch |
| `file list` | `-i`, `--page-size` (1–200, default 50), `--offset`, `--status uploaded\|indexing\|indexed\|index_failed\|deleting\|delete_failed` | Per-file state |
| `file delete` | `-i`, `--file-id` (the `AiGroundingFileRef` ID from `file list`) | Removes the file and re-indexes |
| `get` | `-i` | Configuration, status, retriever, `rag_feature_config_id` |
| `list` | `--source-type sfdrive\|knowledge\|retriever` | All libraries with IDs and status |
| `status` | `-i`, `--include-artifacts` | Stage detail and errors; the flag resolves the Data 360 asset IDs and is slower |
| `update` | `-i`, `-n/--name`, `--description`, `--content-fields`, `--[no-]restrict-to-public-articles`, `--[no-]data-category-rule`, `--retriever-id` | Content fields and public-article restriction trigger re-indexing |
| `delete` | `-i` | Permanent, files and index included. Refused while an agent references the library |

`upload` has no `--source-type` flag, and the file flag is `--file` on `upload` but `--path` on
`file add`.

### File library

```bash
sf agent adl create --name "Product Manuals" --developer-name Product_Manuals \
    --source-type sfdrive --target-org dev
sf agent adl upload --library-id 1JDxx0000000001AAA --file ./docs/setup.pdf \
    --file ./docs/warranty.pdf --wait 15 --target-org dev       # ✅ first load
sf agent adl get --library-id 1JDxx0000000001AAA --target-org dev   # status and rag_feature_config_id

sf agent adl file add --library-id 1JDxx0000000001AAA --path ./docs/recall.pdf \
    --target-org dev                                             # ✅ later additions
sf agent adl upload --library-id 1JDxx0000000001AAA --file ./docs/recall.pdf \
    --target-org dev                                             # ❌ upload is the first load, not day-2
```

- A library holds at most **1,000 files**.
- Without `--wait`, `upload` returns once indexing starts; poll `status` before wiring the library.
- A rejected file type fails with `UNSUPPORTED_FILE_TYPE`; convert it rather than renaming it.

### Knowledge library

```bash
sf agent adl create --name "Support Articles" --developer-name Support_Articles \
    --source-type knowledge --primary-index-field1 Title --primary-index-field2 Summary \
    --content-fields Answer__c --data-category-names Products.Hardware,Products.Software \
    --wait 20 --target-org dev
sf agent adl update --library-id 1JDxx0000000002AAA --restrict-to-public-articles --target-org dev
```

- Lightning Knowledge must be on and the articles **published**.
- Every index and content field must exist on the Knowledge object and be a text type (string or
  text area).
- **Pick the two primary index fields once**: they cannot change. A wrong choice means a new library.
- A knowledge library indexes on creation; no upload step.
- Data category names and IDs cannot be mixed in one call; duplicates are dropped silently.
- No update is accepted while indexing runs (`UPDATE_IN_PROGRESS`).
- Restrict customer-facing libraries to public articles.

### Retriever library

```bash
sf agent adl create --name "Help Site" --developer-name Help_Site --source-type retriever \
    --retriever-id 0ppxx0000000001AAA --target-org dev
sf agent adl update --library-id 1JDxx0000000003AAA --retriever-id 0ppxx0000000002AAA --target-org dev
```

- Ready immediately; there are no files. Activate the retriever first (`RETRIEVER_NOT_ACTIVE`).
- Swap the retriever with `update`; build and test the new one before swapping.

### The REST surface underneath

The CLI drives Connect REST resources under `/services/data/vXX.X/einstein/data-libraries`:
`upload-readiness`, `file-upload-urls` (pre-signed storage URLs valid 15 minutes), `indexing`,
`files` and `status`. Call them directly only from an integration, through an external client app
with the client-credentials flow and JWT-based access tokens. A `file-upload-urls` call before the
library is ready returns 400; a `filePath` that was never uploaded fails with `FILES_NOT_UPLOADED`,
and retrying the same request never fixes it: request a fresh URL and upload again.

## 4. Wire a library into an agent

**Builder:** Explorer › Data › Data Library, select the library, save. **Show Sources** turns on
citations for every answer from the library.

**Agent Script:** declare the library once in a top-level `knowledge` block, then give the subagents
that answer questions the standard knowledge action, whose inputs default from `@knowledge`.

```agentscript
knowledge:
    rag_feature_config_id: "ARFPC_1JDxx0000000001AAA"   # ✅ ARFPC_ + library ID
    citations_enabled: True
    citations_url: ""

subagent product_help:
    label: "Product Help"
    description: "Answers setup, warranty and troubleshooting questions from the product manuals."
    reasoning:
        instructions: ->
            | Search the manuals with AnswerQuestionsWithKnowledge before any factual answer.
            | Answer only from knowledgeSummary. If it is empty, say the manuals do not cover it.
        actions:
            AnswerQuestionsWithKnowledge: @actions.AnswerQuestionsWithKnowledge
                with query = ...
                with ragFeatureConfigId = ...
                with citationsEnabled = ...
                with citationsUrl = ...

    actions:
        AnswerQuestionsWithKnowledge:
            label: "Answer Questions with Knowledge"
            description: "Searches the product manuals and returns a cited summary."
            target: "standardInvocableAction://streamKnowledgeSearch"
            source: "EmployeeCopilot__AnswerQuestionsWithKnowledge"
            inputs:
                query: string
                    description: "Search text built from the customer's question."
                    is_required: True
                    is_user_input: True
                ragFeatureConfigId: string = @knowledge.rag_feature_config_id
                citationsEnabled: boolean = @knowledge.citations_enabled
                citationsUrl: string = @knowledge.citations_url
            outputs:
                knowledgeSummary: object
                    complex_data_type_name: "lightning__richTextType"
                    is_displayable: True
                citationSources: object
                    complex_data_type_name: "@apexClassType/AiCopilot__GenAiCitationInput"
                    is_displayable: False
```

```agentscript
knowledge:
    rag_feature_config_id: "1JDxx0000000001AAA"   # ❌ the bare library ID
```

- `citations_url` stays empty unless citations must resolve under a known public base URL.
- Point a different library at the agent by changing `rag_feature_config_id`, then validate and
  republish. The library must be `READY` first.
- Copy the action definition from a Builder-created agent retrieved into the project when in doubt;
  the Builder writes the full input and output contract. Action grammar:
  `references/agent-actions.md`.
- Grounded answers only come back when the agent user can read the source; see
  `references/org-setup-and-agent-user.md` §8–9.

## 5. Citations

| Layer | Setting | Effect |
|---|---|---|
| Agent runtime | `config.runtime.citation` (on unless `False`) | Runs citation enrichment on knowledge-based answers. Turn it off for channels that cannot render citations |
| Knowledge block | `knowledge.citations_enabled` | Passed into the knowledge action |
| Builder | **Show Sources** on the Data Library | Shows sources for every library answer |
| Retriever | **Citation Settings**, plus URL and Title among the returned fields | Gives the agent something to cite |
| Custom Apex action | `AiCopilot.GenAiCitationInput` or `AiCopilot.GenAiCitationOutput` output variable | Supplies sources from your own retrieval |

- Platform-generated citations exist only for agents created **after 26 May 2025**, and appear only
  once the agent is **active**.
- The end user must be able to open each cited URL; a citation to a page they cannot reach is worse
  than none.
- Employee agents and the Agent API both carry citations; see `references/lifecycle-and-api.md`.
- Keep `config.runtime.groundedness` on for knowledge-heavy agents: it checks the response against
  the retrieved content. Turn it off only after measuring that it adds nothing.

### Citations from a custom Apex action

| Class | Use when |
|---|---|
| `AiCopilot.GenAiCitationInput(inputText, sources)` | The action hands sources to the reasoning engine, which decides what to cite |
| `AiCopilot.GenAiCitationOutput` | The action dictates exactly which references are cited |

A source is a `GenAiSourceReference(id, contents, metadata)`: `contents` is a list of
`GenAiSourceContentInfo(fieldName, objectName, content)` and `metadata` a list of
`GenAiSourceReferenceInfo(link, sourceObjectRecordId, sourceObjectApiName)`, each with an optional
`label`.

```apex
public with sharing class PolicySourcesAction {
    public class Request {
        @InvocableVariable(required=true description='Knowledge article record IDs to cite')
        public List<Id> articleIds;
    }

    public class Response {
        @InvocableVariable(description='Article text the agent answers from')
        public String content;
        @InvocableVariable(description='Citation sources for the article text')
        public AiCopilot.GenAiCitationInput sources;
    }

    @InvocableMethod(label='Get Policy Sources' description='Returns policy article text with citation sources.')
    public static List<Response> getSources(List<Request> requests) {
        Set<Id> allIds = new Set<Id>();
        for (Request req : requests) {
            allIds.addAll(req.articleIds);
        }
        Map<Id, Knowledge__kav> articles = new Map<Id, Knowledge__kav>(
            [SELECT Id, Title, Summary FROM Knowledge__kav WHERE Id IN :allIds WITH USER_MODE]   // ✅ one query
        );

        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            List<AiCopilot.GenAiSourceReference> refs = new List<AiCopilot.GenAiSourceReference>();
            List<String> texts = new List<String>();
            for (Id articleId : req.articleIds) {
                Knowledge__kav article = articles.get(articleId);
                if (article == null) {
                    continue;
                }
                texts.add(article.Summary);
                refs.add(new AiCopilot.GenAiSourceReference(
                    article.Id,
                    new List<AiCopilot.GenAiSourceContentInfo>{
                        new AiCopilot.GenAiSourceContentInfo('Summary', 'Knowledge__kav', article.Summary)
                    },
                    new List<AiCopilot.GenAiSourceReferenceInfo>{
                        new AiCopilot.GenAiSourceReferenceInfo('/' + article.Id, article.Id, 'Knowledge__kav')
                    }
                ));
            }
            Response res = new Response();
            res.content = String.join(texts, '\n\n');
            res.sources = new AiCopilot.GenAiCitationInput(null, refs);
            responses.add(res);
        }
        return responses;
    }
}
```

- To cite a prompt template's retrieval, call it with `citationMode = 'post_generation'` and map
  the `ConnectApi` citation output onto the `AiCopilot` classes. Calling templates from Apex:
  `references/prompt-templates.md`.

## 6. RAG with a search index, a retriever and a prompt template

Choose this over a plain Data Library when you need control of chunking, filters or fields.

| Stage | Where | Rules |
|---|---|---|
| Ingest | Data 360 connector, or a Data Library's `ADL_` data model object | Use the default data space for anything a Data Library touches |
| Search index | Data 360 › Search Index, or Intelligent Context for LLM-based parsing of visual content | Hybrid search for mixed keyword and semantic questions. Keep the chunk size within the embedding model's sequence length (Salesforce Embedding V2 Small takes 1,200-token chunks). Prepend the title to chunks. Check chunk records in Data Explorer before going further |
| Retriever | Agentforce Studio › Data › Retrievers › New › Individual Retriever | Pick data space, data model object and search index; filter to the relevant documents; return only fields that help the answer (chunk, title, URL for citations); enable Citation Settings; **activate**. Each save is a new version; one version is active |
| Prompt template | Flex template with a free-text input | Bind the retriever's search text to the input; insert `{!$EinsteinSearch:<RetrieverApiName>.results}`; state the allowed sources, the fallback reply when nothing matches, and the citation format |
| Agent | Prompt-template action on a subagent | `references/agent-actions.md`, `references/prompt-templates.md` |

- Test the template in Prompt Builder preview with real questions before wiring it: relevant
  results, grounded answer, correct format, citations, and the fallback when nothing matches.
- Weak answers come from the index or retriever far more often than from the prompt. Fix chunking
  and filters first.
- An org has a quota of search indexes (`SEARCH_INDEX_QUOTA_EXCEEDED`); delete unused ones.
- Data 360 SQL, data spaces and index internals: `dya-sf-data360`.

## 7. Grounding patterns

**Load a small lookup once, before reasoning.** For a terminology map that business users maintain
(old and new product names, slang, acronyms), keep it in a Knowledge article or record, fetch it with
a Flow action once per session, and tell the agent to translate the customer's term before searching.

```agentscript
variables:
    term_map: mutable string = "not_loaded"

subagent product_help:
    reasoning:
        instructions: ->
            if @variables.term_map == "not_loaded":
                run @actions.get_term_map
                    with articleNumber = "000001042"
                    set @variables.term_map = @outputs.termMap
            | Customers may use new product names. Before searching, translate any name found in
              {!@variables.term_map} to the name the manuals use.
```

- The sentinel default makes the fetch run once per session.
- **Reproduce the failure first**: ask with the new term before adding the map, so a passing test
  proves the map works and not the model's general knowledge.
- Stop using this pattern when the map grows large enough to crowd the context; re-index instead.

**Answer only from evidence.** Instruct every grounded subagent to call its knowledge action before
answering, answer only from what it returns, and say so when nothing comes back. Pair this with a
grounding test: `references/testing-and-evaluation.md`.

## 8. When grounding returns nothing

| Symptom | Cause | Fix |
|---|---|---|
| Library stuck before `READY` | Data 360 still provisioning (`PROVISIONING_IN_PROGRESS`, `DC_CONNECTION_MISSING`) | Wait and poll `sf agent adl status` |
| A stage fails (`INDEXING_FAILED`, `SEARCH_INDEX_FAILED`, `DC_ASSET_FAILED`) | Pipeline error | `sf agent adl status --include-artifacts`, then fix the named asset |
| `NON_DEFAULT_DATASPACE` | Library targeted at another data space | Default data space only |
| `DC1_NOT_SUPPORTED` | Companion org | Custom retriever |
| `DELETE_IN_USE` | An agent references the library | Remove it from the agent first |
| Answers fine for you, empty for the agent | Agent user lacks Data 360 or Knowledge access | `references/org-setup-and-agent-user.md` §8–9 |
| Knowledge library finds nothing | Articles unpublished, wrong primary fields, category filter too narrow, public-only restriction | `sf agent adl get`; check article status and categories |
| Agent never calls the knowledge action | Wrong `rag_feature_config_id`, missing `knowledge` block, or instructions that let the model answer from memory | §4; instruct "search before answering" |
| Citations missing | Agent predates 26 May 2025, is inactive, or `runtime.citation` is `False` | §5 |

Server errors carry a trace ID (`urn:trace:...`) in the `instance` field; quote it when escalating to
Salesforce Support.

## 9. External tools over MCP (consumer side)

An agent can call tools that an **external** MCP server advertises. Register the server in the API
Catalog, allowlist the assets the agent may use, then add them to the agent as actions.

**The `sf agent mcp` commands are Developer Preview**: subject to change and not for functionality
you ship. Use the API Catalog in Setup for anything that must last.

| Command | Flags | Notes |
|---|---|---|
| `create` | `-n/--name`, `--server-url`, `--label`, `--description`, `--auth-type OAUTH\|NO_AUTH` (default `NO_AUTH`), `--identity-provider`, `--client-id`, `--client-secret`, `--scope` | `OAUTH` requires all four OAuth flags. Registers the server and discovers its assets |
| `list` | `--label`, `--type EXTERNAL`, `--status ACTIVE\|DISCONNECTED` | `DISCONNECTED`: check URL, auth and network |
| `get` | `-i/--mcp-server-id` | Name, label, type, status, URL |
| `update` | `-i`, any of the `create` fields | Changes only what you pass; switching to `OAUTH` needs all four OAuth flags |
| `delete` | `-i`, `--no-prompt` | Prompts unless `--no-prompt` |
| `fetch` | `-i` | Live read of the tools, prompts and resources the server advertises now |
| `asset list` | `-i` | Catalog view: each asset's kind (`MCP_TOOL`, `MCP_PROMPT`, `MCP_RESOURCE`), whether active, whether available as an agent action |
| `asset replace` | `-i`, `--assets <json\|->` **or** `--assets-file <path>` | **Full replacement** of the allowlist: an asset left out is removed |

```bash
sf agent mcp create --name ShippingTools --server-url https://mcp.shipper.example.com \
    --auth-type OAUTH --identity-provider ShipperIdp --client-id 3MVG9example \
    --client-secret - --scope "tracking.read" --target-org dev < shipper-secret.txt   # ✅ secret on stdin
sf agent mcp fetch --mcp-server-id 0XSxx0000000001 --target-org dev
sf agent mcp asset list --mcp-server-id 0XSxx0000000001 --target-org dev
sf agent mcp asset replace --mcp-server-id 0XSxx0000000001 --assets-file ./mcp-allowlist.json \
    --target-org dev
```

```json
{
    "assets": [
        { "name": "McpTool__getTrackingStatus", "kind": "MCP_TOOL", "active": true },
        { "name": "McpTool__listCarrierDelays", "kind": "MCP_TOOL", "active": true }
    ]
}
```

- Pass `--client-secret -` and pipe the secret in; a secret on the command line lands in shell
  history.
- Read the current set with `asset list` or `fetch` before every `asset replace`, then send the
  complete desired set.
- Allowlist only the tools the agent needs; review every tool that writes or deletes before
  activating it.
- An asset becomes callable only when it is active and reported as available as an agent action;
  then add it to a subagent like any other action (`references/agent-actions.md`).
- The agent picks an MCP tool by its name and description, exactly as it picks any action. Rewrite
  a vague server-supplied description in the agent's action definition.
- After the server changes its tools, run `fetch` to see what it advertises now, then update the
  allowlist with `asset replace`.

**Serving the other direction is out of scope here.** Exposing Salesforce data, actions or agents to
external AI clients through Salesforce-hosted MCP servers (disabled by default; an admin enables each
one under Setup › API Catalog › MCP Servers, active within about two minutes) is
`dya-sf-headless360`; MCP connectivity patterns are `dya-sf-integration-connectors-mcp`.

## 10. Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Wiring a library before it is `READY` | Poll `sf agent adl status`; wire only at `READY` |
| The bare library ID as `rag_feature_config_id` | `ARFPC_` + library ID, as `sf agent adl get` prints it |
| `sf agent adl upload` to add files to a live library | `sf agent adl file add` |
| Guessing a knowledge library's primary index fields | Choose them deliberately; they are immutable |
| A customer-facing Knowledge library over internal articles | `--restrict-to-public-articles` and data-category scoping |
| Building a Data Library in a non-default data space or a companion org | Default data space; a custom retriever for companion orgs |
| Tuning the prompt when retrieval returns the wrong chunks | Fix chunking, filters and returned fields first |
| A grounded subagent allowed to answer from memory | "Search before answering; answer only from the result; say when nothing is found" |
| Citations switched on for a channel that cannot render them | `config.runtime.citation: False` for that agent |
| Re-indexing thousands of articles for a product rename | A small term map loaded once into a variable |
| `asset replace` with only the new tool | Read the current set, send the full allowlist |
| Every MCP tool a server offers, activated | Only the tools the agent needs, reviewed |
| OAuth client secret on the command line | `--client-secret -` with the secret on stdin |
| Building on `sf agent mcp` for production | Developer Preview; use the API Catalog in Setup |
