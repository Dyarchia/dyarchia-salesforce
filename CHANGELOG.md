# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-28

### Added

- Initial public release of the repository under the MIT license.
- Three skills published, all targeting Salesforce Summer '26 / API v67.0:
  - **`decimatio-apex`** — Apex syntax, security, SOQL/DML, triggers, async patterns, testing, observability.
  - **`decimatio-lwc`** — LWC template syntax, Lightning Data Service, GraphQL, state management, dev tooling.
  - **`decimatio-flow`** — Flow types, bulkification, screen reactivity, security, Apex integration, HTTP callouts, AI-assisted authoring, testing.
- Repository documentation: `README.md` with install paths for Claude.ai and Claude Code, `LICENSE` (MIT), and this `CHANGELOG.md`.
- `.gitignore` excluding build artifacts (`*.skill` bundles), OS metadata, editor folders, and local Claude Code configuration.

### Notes

- All skills load only on explicit invocation by name. They do not auto-trigger on generic Apex, LWC, or Flow questions.
- The canonical form in the repository is the unpacked skill folder. `.skill` files are build artifacts produced on demand and are not tracked in version control.

[Unreleased]: https://github.com/Decimatio-Dev/decimatio-skills/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Decimatio-Dev/decimatio-skills/releases/tag/v0.1.0
