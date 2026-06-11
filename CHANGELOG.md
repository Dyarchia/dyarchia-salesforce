# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Renamed the repository to **`decimatio-legio`**.
- Grouped the Salesforce skills under a `decimatio-salesforce/` domain folder; the
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
