# decimatio-legio

> A collection of agent skills by Decimatio Dev, published openly under MIT.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v67.0-00A1E0.svg)
![Agent Skills](https://img.shields.io/badge/Agent%20Skills-Compatible-5B5BD6.svg)

Agent skills are reusable instruction packs that customise how an AI coding agent approaches specific domains. They are becoming a cross-vendor standard for AI assistants, so the contents of this repo should be portable in spirit even where the loading mechanics differ.

---

## Available skills

The catalogue is organised by domain. Today every skill targets Salesforce, so it lives under `decimatio-sf/`; future domains get sibling folders at the repo root.

| Skill | Domain | Target |
|---|---|---|
| **`decimatio-apex`** | Apex — syntax, security, SOQL/DML, triggers, async, testing, observability, SOLID | Summer '26 / API v67.0 |
| **`decimatio-lwc`** | LWC — template syntax, LDS, GraphQL, `@lwc/state`, dev tooling | Summer '26 / API v67.0 |
| **`decimatio-flow`** | Flow — flow types, bulkification, screen reactivity, security, Apex integration, callouts, testing | Summer '26 / API v67.0 |
| **`decimatio-aura`** | Aura components — when (not) to use, events, server/LDS, LWC interop | Summer '26 / API v67.0 |
| **`decimatio-visualforce`** | Visualforce — controller patterns, JavaScript Remoting | Summer '26 / API v67.0 |
| **`decimatio-lwr`** | Lightning Web Runtime — component portability, navigation, LWS/CSP, guest context | Summer '26 / API v67.0 |
| **`decimatio-lwr-sites`** | Experience Cloud LWR sites — enhanced sites, Grid/CMS, guest hardening, SEO | Summer '26 / API v67.0 |
| **`decimatio-lightning-out`** | Lightning Out 2.0 — embedding LWCs in non-Salesforce apps | Summer '26 / API v67.0 |

Each skill loads **only on explicit invocation by name** (slash-command pattern) — none auto-trigger on generic Salesforce questions.

---

## Repository layout

```mermaid
graph TD
    Root([decimatio-legio/])
    Root --> Meta["README · CHANGELOG · LICENSE · .gitignore"]
    Root --> SF[decimatio-sf/]

    SF --> Apex[decimatio-apex/]
    SF --> LWC[decimatio-lwc/]
    SF --> Flow[decimatio-flow/]
    SF --> Aura[decimatio-aura/]
    SF --> VF[decimatio-visualforce/]
    SF --> LWR[decimatio-lwr/]
    SF --> LWRS[decimatio-lwr-sites/]
    SF --> LO[decimatio-lightning-out/]

    classDef root fill:#5B5BD6,stroke:#3B3B8F,color:#fff,stroke-width:2px
    classDef domainFolder fill:#6E56CF,stroke:#3B3B8F,color:#fff,stroke-width:2px
    classDef skillFolder fill:#00A1E0,stroke:#005F8A,color:#fff,stroke-width:2px
    classDef meta fill:#F4F4F4,stroke:#999,color:#555

    class Root root
    class SF domainFolder
    class Apex,LWC,Flow,Aura,VF,LWR,LWRS,LO skillFolder
    class Meta meta
```

Each skill folder contains its `SKILL.md` (the load-bearing instructions) plus a `references/` subfolder with verbatim implementations and large code examples that the agent loads on demand. Repo-level files (`README.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`) live at the root and never get bundled into the installable skill.

---

## Install as a `.skill` bundle

A `.skill` file is just a ZIP archive of the skill folder with the extension renamed. Build it once, upload it once into whichever assistant supports the format.

```mermaid
flowchart LR
    A[Clone or<br/>download repo] --> B[Zip the<br/>skill folder]
    B --> C[Rename<br/>.zip → .skill]
    C --> D[Upload in<br/>your assistant]

    classDef step fill:#5B5BD6,stroke:#3B3B8F,color:#fff,stroke-width:2px
    class A,B,C,D step
```

### Terminal — macOS, Linux, WSL

```bash
zip -r decimatio-apex.skill decimatio-sf/decimatio-apex/
```

The `zip` command is preinstalled on macOS and almost every Linux distro.

### macOS Finder

Right-click the skill folder → **Compress [folder name]** → rename the resulting `.zip` to `.skill`.

> If Finder hides extensions, enable them first: **Finder → Settings → Advanced → Show all filename extensions**.

### Linux file manager (GNOME Files, KDE Dolphin, others)

Right-click the skill folder → **Compress…** / **Create archive…** → choose ZIP format → rename the resulting `.zip` to `.skill`.

### Windows Explorer

Right-click the skill folder → **Compress to ZIP file** → rename the resulting `.zip` to `.skill`.

---

## Install from disk

Agents that read skills directly from a folder on disk need no zipping — copy the skill folder into the directory matching the scope you want:

```mermaid
flowchart LR
    A[Clone repo] --> B{Scope?}
    B -->|All your projects| C["cp -r skill ~/.../skills/"]
    B -->|Just this project| D["cp -r skill .../skills/"]
    C --> E[Restart<br/>the agent]
    D --> E

    classDef step fill:#5B5BD6,stroke:#3B3B8F,color:#fff,stroke-width:2px
    classDef decision fill:#00A1E0,stroke:#005F8A,color:#fff,stroke-width:2px
    classDef cmd fill:#2d2d2d,stroke:#666,color:#f0f0f0

    class A,E step
    class B decision
    class C,D cmd
```

After copying, restart the agent and verify the skill appears under its loaded-skills list.

---

## License

[MIT](LICENSE)
