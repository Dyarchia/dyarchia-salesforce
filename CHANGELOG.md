# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Twenty-two skills under `skills/`, all targeting Summer '26 / API v67.0:
  - **`decimatio-aura`** — Aura components: when (not) to use, events, server/LDS, LWC interop.
  - **`decimatio-visualforce`** — Visualforce controller patterns and JavaScript Remoting.
  - **`decimatio-lwr`** — Lightning Web Runtime component development: runtime differences vs Lightning Experience, navigation, Lightning Web Security/CSP, guest context.
  - **`decimatio-lwr-sites`** — Experience Cloud LWR sites: enhanced sites, the Grid/CMS, guest-user hardening, SEO, partial deployment.
  - **`decimatio-lightning-out`** — Lightning Out 2.0: embedding LWCs in non-Salesforce apps.
  - **`decimatio-agentforce`** — Agentforce: agent anatomy (Topics/Instructions/Actions), Agent Script, Apex/Flow/Prompt-Template actions, Data 360 grounding, Agent API, testing and evals, the Trust Layer.
  - **`decimatio-data360`** — Data 360 (formerly Data Cloud): the ingest→DLO→DMO→identity→insights→activation pipeline, ingestion and zero-copy, SOQL on DMOs, Query/Connect API, segments, credit governance.
  - **`decimatio-headless360`** — Headless 360: the API/MCP/CLI surfaces, the MCP server taxonomy, building custom MCP tools, the Headless/Agentforce Experience Layer (HXL/AXL), headless DevOps, the Trust Layer.
  - **`decimatio-integration-overview`** — integration decision hub: the six integration patterns, sync vs async, idempotency/retry/governor concerns, the master decision matrix, the authoring-surface map, and API-version-retirement facts.
  - **`decimatio-integration-inbound-apis`** — standard inbound APIs: REST and the composite family, SOAP, Bulk API 2.0, GraphQL, and the Connect/UI/Metadata/Tooling APIs.
  - **`decimatio-integration-inbound-apex`** — custom inbound endpoints: Apex REST services (`@RestResource`), Apex SOAP web services (legacy), and Sites/Experience Cloud as integration surfaces with guest-user security.
  - **`decimatio-integration-outbound`** — outbound integration: Apex HTTP callouts and limits, async callout patterns, the callout-after-DML rule, Flow HTTP Callout, External Services, Outbound Messages (legacy), Salesforce Connect, and calling external APIs from LWC.
  - **`decimatio-integration-events`** — event-driven integration: Platform Events, Change Data Capture, the Pub/Sub API (gRPC), publish/subscribe from Apex and Flow, replay/retention, and webhook patterns.
  - **`decimatio-integration-auth`** — integration authentication and identity: inbound OAuth 2.0 flows, External Client Apps vs Connected Apps, JWT/mTLS, and outbound Named/External Credentials.
  - **`decimatio-integration-connectors-mcp`** — connectors and agentic integration: MuleSoft (Anypoint, for Flow), Heroku/AppLink, AppExchange/ISV connectors, Data 360 as an integration path, and Hosted MCP servers / Agent API.
  - **`decimatio-b2b-commerce`** — B2B (and D2C) Commerce on core: the CartExtension framework, `ConnectApi.BaseEndpointExtension` endpoint extensions, the `ConnectApi.CommerceCart` Apex API, buyer groups and entitlements, Storefront/LWR.
  - **`decimatio-b2c-commerce`** — B2C Commerce (Demandware lineage): the `dw.*` Script API, SFRA cartridges/controllers/ISML/hooks/jobs, the Composable Storefront (PWA Kit + Managed Runtime), SCAPI with mandatory SLAS auth, Shopper Context personalization.
  - **`decimatio-field-service`** — Field Service: the FSL Apex namespace, the scope-1 + DML-before-callout scheduling pattern, Salesforce Scheduler REST candidates/slots and Appointment Bundling, the ServiceAppointment lifecycle, Field Service Mobile.
  - **`decimatio-omnistudio`** — OmniStudio: OmniScripts, FlexCards, Integration Procedures, DataRaptors/Data Mappers, Apex Remote Actions (the `Callable` vs `VlocityOpenInterface2` contract), Standard vs Managed Package.
  - **`decimatio-revenue-cloud`** — Revenue Cloud Advanced / RLM: Product Catalog Management, Salesforce Pricing (Pricing Procedures + Context Service + Decision Tables), Transaction Management, Product Configurator Business APIs, Asset Lifecycle, Billing.
  - **`decimatio-permissions`** — the permissions and sharing model: profiles, permission sets and groups with muting, OWD/role hierarchy/sharing rules/manual and Apex sharing, restriction and scoping rules, field-level security, and how it interacts with Apex user mode.
  - **`decimatio-sf-cli`** — the `sf` command catalog: the command model and topics, authentication, metadata deploy/retrieve, scratch orgs and sandboxes, Apex/data/sobject, Agentforce DX, packaging, flag conventions.
- `references/solid-principles.md` in `decimatio-apex` (SRP/OCP/LSP/ISP/DIP applied to Apex).
- `references/jest-testing.md` in `decimatio-lwc`.
- **`CLAUDE.md`** at the repo root: the frontmatter contract, skill body conventions, bundle packaging rules, commit conventions, and the architecture status — what is implemented and what is reserved by convention.
- **`scripts/build-skill.ps1` and `scripts/build-skill.sh`** — bundle packaging, replacing the copy-paste snippets that used to live in the README. Both root the archive at the skill folder and force forward-slash ZIP entry names. Output is reproducible: entries are emitted in sorted order with a fixed 1980-01-01 timestamp, so rebuilding an unchanged skill yields a byte-identical bundle. Without that, any rebuild dirtied all 25 binaries in the diff regardless of what actually changed.
- **`scripts/validate-skills.ps1` and `scripts/validate-skills.sh`** — deterministic pre-commit checks: frontmatter parses, `name` matches the folder, the explicit-invocation clause is present, every skill is listed in the README, every bundle exists, entries are rooted and forward-slashed, and each bundle's contents match its source file by file via SHA-256. Warns when a `SKILL.md` exceeds 20 KB. Exits non-zero on any mismatch.
- **`.claude/skills/decimatio-skill-authoring/SKILL.md`** — the prescriptive procedure for adding, editing, splitting and removing a skill in this repo.
- **`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`** — the repository is now a Claude Code plugin and its own marketplace, so all 25 skills install in one step from `skills/`. No MCP servers are declared: third-party servers are not vendored here, and only servers written in this repo would ship.

### Changed

- **`decimatio-permissions`**: added the "Any API Auth" permission (v67) to Platform Context — it gates legacy SOAP `login()` and is enforced by default in new orgs, so the skill now names SOAP `login()` as end-of-life and points at OAuth + External Client Apps. Closes an asymmetry with `decimatio-integration-auth`, which already declared the permission in its own description.
- **`.skill` bundles are now committed to the repository.** A `decimatio-<name>.skill` is generated for every skill under `skills/` and placed in `dist/`. The `.skill` entry has been removed from `.gitignore`. The README leads with the plugin install, then the pre-built bundles, and moves the per-OS zip instructions under a *Rebuilding a bundle* subsection. Trade-off: any change to a `SKILL.md` must regenerate its bundle in the same commit to keep them in sync — now enforced by `scripts/validate-skills`.
- **`.skill` ZIP entry names now use forward slashes.** The first commit of the pre-built bundles used PowerShell's `Compress-Archive`, which writes Windows backslashes (`decimatio-apex\SKILL.md`) into the entry names. The ZIP spec mandates forward slashes, and strict parsers (Claude Desktop's skill import) reject the backslash variant with *"Zip file contains path with invalid characters"*. Bundles have been rebuilt with `System.IO.Compression.ZipArchive` using explicit `decimatio-<name>/<inner>` entry names.
- **`decimatio-apex`**: the Tony Scott trigger framework is now the default for greenfield orgs only (ask in existing orgs); added a per-object hierarchical trigger kill-switch (`Trigger_Settings__c`).
- **`decimatio-lwc`**: refreshed for Summer '26 / API v67.0 — `@lwc/state` State Manager (GA), grouped `<details>` accordions, `lightning/accApi`, `blob:` downloads (Lightning Web Security blocks `data:` URIs), Component Preview and SLDS Flow-screen hooks GA.
- **`decimatio-flow`**: documented the v67 `InvocableActionExtension` Apex Action configuration (per-input editors, picklist values, custom header) and the no-argument-constructor requirement for invocable action input types.
- **`README.md`**: the catalogue is now a grouped vertical list covering all 25 skills — the previous wide table went unreadable past a dozen entries and had fallen seven skills behind the repo. The layout diagram was redrawn around the actual tree, and the packaging section now points at the scripts instead of inlining shell snippets.
- **`.gitignore`**: stopped ignoring `.claude/` wholesale so repo-level skills and configuration are versioned (only `settings.local.json` stays local); added secret exclusions (`.env*`, `*.pem`, `*.key`, `*.p12`, `*.jks`, `credentials*`, `.sf/`, `.sfdx/`), which were absent from a public repo whose skills document OAuth, JWT and Named Credentials.
- **Repository renamed to `decimatio-salesforce` and restructured as a Claude Code plugin.** The umbrella is now the GitHub organisation, not this repo: one repo per domain, one plugin per repo. `decimatio-sf/` became `skills/` (one nesting level removed), the root `.skill` bundles moved to `dist/`, and `decimatio-sf-sources/` became `sources/`. The packaging and validation scripts take `SourceRoot` and `OutputRoot` overrides, defaulting to the new paths.
- **`docs/`**: `TODO.md` moved out of `.gitignore` and into version control, so postponed work is tracked with the repo rather than in a local-only file.
- Made repository documentation provider-agnostic: removed vendor-specific branding
  in favour of neutral "agent skills" terminology, since the skill format is a
  cross-vendor standard.

### Removed

- **`decimatio-providers-tui`** — the cross-provider terminal-agent reference (Claude Code, Antigravity CLI, Grok Build, Mistral Vibe, opencode) and its five `references/` files. It is not a Salesforce domain skill and sits outside the scope of this library; its `.skill` bundle is no longer published. The skill was never part of a tagged release.

## [0.1.0] - 2026-05-28

### Added

- Initial public release of the repository under the MIT license.
- Three skills published, all targeting Salesforce Summer '26 / API v67.0:
  - **`decimatio-apex`** — Apex syntax, security, SOQL/DML, triggers, async patterns, testing, observability.
  - **`decimatio-lwc`** — LWC template syntax, Lightning Data Service, GraphQL, state management, dev tooling.
  - **`decimatio-flow`** — Flow types, bulkification, screen reactivity, security, Apex integration, HTTP callouts, AI-assisted authoring, testing.
- Repository documentation: `README.md` with `.skill` bundle and on-disk install paths, `LICENSE` (MIT), and this `CHANGELOG.md`.
- `.gitignore` excluding build artifacts (`*.skill` bundles), OS metadata, editor folders, and local agent configuration.

### Notes

- All skills load only on explicit invocation by name. They do not auto-trigger on generic Apex, LWC, or Flow questions.
- The `[0.1.0]` release shipped under the repository's former name; the comparison links below now resolve to the renamed repository.
- The canonical form in the repository is the unpacked skill folder. `.skill` files are build artifacts produced on demand and are not tracked in version control.

[Unreleased]: https://github.com/decimatio-dev/decimatio-salesforce/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/decimatio-dev/decimatio-salesforce/releases/tag/v0.1.0
