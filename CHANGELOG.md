# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Eight skills under `decimatio-sf/`, all targeting Summer '26 / API v67.0:
  - **`decimatio-aura`** — Aura components: when (not) to use, events, server/LDS, LWC interop.
  - **`decimatio-visualforce`** — Visualforce controller patterns and JavaScript Remoting.
  - **`decimatio-lwr`** — Lightning Web Runtime component development: runtime differences vs Lightning Experience, navigation, Lightning Web Security/CSP, guest context.
  - **`decimatio-lwr-sites`** — Experience Cloud LWR sites: enhanced sites, the Grid/CMS, guest-user hardening, SEO, partial deployment.
  - **`decimatio-lightning-out`** — Lightning Out 2.0: embedding LWCs in non-Salesforce apps.
  - **`decimatio-agentforce`** — Agentforce: agent anatomy (Topics/Instructions/Actions), Agent Script, Apex/Flow/Prompt-Template actions, Data 360 grounding, Agent API, testing and evals, the Trust Layer.
  - **`decimatio-data360`** — Data 360 (formerly Data Cloud): the ingest→DLO→DMO→identity→insights→activation pipeline, ingestion and zero-copy, SOQL on DMOs, Query/Connect API, segments, credit governance.
  - **`decimatio-headless360`** — Headless 360: the API/MCP/CLI surfaces, the MCP server taxonomy, building custom MCP tools, the Headless/Agentforce Experience Layer (HXL/AXL), headless DevOps, the Trust Layer.
- `references/solid-principles.md` in `decimatio-apex` (SRP/OCP/LSP/ISP/DIP applied to Apex).

### Changed

- **`decimatio-apex`**: the Tony Scott trigger framework is now the default for greenfield orgs only (ask in existing orgs); added a per-object hierarchical trigger kill-switch (`Trigger_Settings__c`).
- **`decimatio-lwc`**: refreshed for Summer '26 / API v67.0 — `@lwc/state` State Manager (GA), grouped `<details>` accordions, `lightning/accApi`, `blob:` downloads (Lightning Web Security blocks `data:` URIs), Component Preview and SLDS Flow-screen hooks GA.
- **`decimatio-flow`**: documented the v67 `InvocableActionExtension` Apex Action configuration (per-input editors, picklist values, custom header) and the no-argument-constructor requirement for invocable action input types.
- **`README.md`**: list the full eight-skill catalogue and simplify the repository-layout diagram.
- Renamed the repository to **`decimatio-legio`**.
- Grouped the Salesforce skills under a `decimatio-sf/` domain folder; the
  repo root is now reserved for future non-Salesforce domains.
- Made repository documentation provider-agnostic: removed vendor-specific branding
  in favour of neutral "agent skills" terminology, since the skill format is a
  cross-vendor standard.

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

[Unreleased]: https://github.com/decimatio-dev/decimatio-legio/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/decimatio-dev/decimatio-legio/releases/tag/v0.1.0
