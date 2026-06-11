# decimatio-legio

> A collection of agent skills by Decimatio Dev, published openly under MIT.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v67.0-00A1E0.svg)
![Agent Skills](https://img.shields.io/badge/Agent%20Skills-Compatible-5B5BD6.svg)

Agent skills are reusable instruction packs that customise how an AI coding agent approaches specific domains. They are becoming a cross-vendor standard for AI assistants, so the contents of this repo should be portable in spirit even where the loading mechanics differ.

---

## Available skills

The catalogue is organised by domain. Today every skill targets Salesforce, so it lives under `decimatio-salesforce/`; future domains get sibling folders at the repo root.

| Skill | Domain | Target |
|---|---|---|
| **`decimatio-apex`** | Salesforce Apex — syntax, security, SOQL/DML, triggers, async, testing, observability | Summer '26 / API v67.0 |
| **`decimatio-lwc`** | Salesforce LWC — template syntax, LDS, GraphQL, state management, dev tooling | Summer '26 / API v67.0 |
| **`decimatio-flow`** | Salesforce Flow — flow types, bulkification, screen reactivity, security, Apex integration, HTTP callouts, testing | Summer '26 / API v67.0 |

Each skill loads **only on explicit invocation by name** (slash-command pattern) — they do not auto-trigger on generic Apex, LWC, or Flow questions.

---

## Repository layout

```mermaid
graph TD
    Root([decimatio-legio/])
    Root --> README[README.md]
    Root --> Changelog[CHANGELOG.md]
    Root --> License[LICENSE]
    Root --> Gitignore[.gitignore]
    Root --> SF[decimatio-salesforce/]

    SF --> Apex[decimatio-apex/]
    SF --> LWC[decimatio-lwc/]
    SF --> Flow[decimatio-flow/]

    Apex --> ApexSkill[SKILL.md]
    Apex --> ApexRefs[references/]
    ApexRefs --> R1[trigger-framework.md]
    ApexRefs --> R2[async-patterns.md]
    ApexRefs --> R3[observability-patterns.md]

    LWC --> LWCSkill[SKILL.md]
    LWC --> LWCRefs[references/]
    LWCRefs --> R4[graphql-patterns.md]
    LWCRefs --> R5[state-management.md]

    Flow --> FlowSkill[SKILL.md]
    Flow --> FlowRefs[references/]
    FlowRefs --> R6[invocable-apex-patterns.md]
    FlowRefs --> R7[http-callout-patterns.md]

    classDef root fill:#5B5BD6,stroke:#3B3B8F,color:#fff,stroke-width:2px
    classDef domainFolder fill:#6E56CF,stroke:#3B3B8F,color:#fff,stroke-width:2px
    classDef skillFolder fill:#00A1E0,stroke:#005F8A,color:#fff,stroke-width:2px
    classDef skillFile fill:#1a4f6b,stroke:#005F8A,color:#fff,stroke-width:2px
    classDef refsFolder fill:#7FB3D5,stroke:#2E86AB,color:#fff
    classDef refFile fill:#E8F4F8,stroke:#2E86AB,color:#1a1a1a
    classDef meta fill:#F4F4F4,stroke:#999,color:#555

    class Root root
    class SF domainFolder
    class Apex,LWC,Flow skillFolder
    class ApexSkill,LWCSkill,FlowSkill skillFile
    class ApexRefs,LWCRefs,FlowRefs refsFolder
    class R1,R2,R3,R4,R5,R6,R7 refFile
    class README,Changelog,License,Gitignore meta
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
zip -r decimatio-apex.skill decimatio-salesforce/decimatio-apex/
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
