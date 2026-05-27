# decimatio-skills

> A collection of Claude Skills by Decimatio Dev, published openly under MIT.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v67.0-00A1E0.svg)
![Claude Skills](https://img.shields.io/badge/Claude-Compatible-D97757.svg)

Claude Skills are reusable instruction packs that customise how Claude approaches specific domains. They are becoming a cross-vendor standard for AI assistants, so the contents of this repo should be portable in spirit even where the loading mechanics differ.

---

## Available skills

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
    Root([decimatio-skills/])
    Root --> README[README.md]
    Root --> Changelog[CHANGELOG.md]
    Root --> License[LICENSE]
    Root --> Gitignore[.gitignore]
    Root --> Apex[decimatio-apex/]
    Root --> LWC[decimatio-lwc/]
    Root --> Flow[decimatio-flow/]

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

    classDef root fill:#D97757,stroke:#8B4513,color:#fff,stroke-width:2px
    classDef skillFolder fill:#00A1E0,stroke:#005F8A,color:#fff,stroke-width:2px
    classDef skillFile fill:#1a4f6b,stroke:#005F8A,color:#fff,stroke-width:2px
    classDef refsFolder fill:#7FB3D5,stroke:#2E86AB,color:#fff
    classDef refFile fill:#E8F4F8,stroke:#2E86AB,color:#1a1a1a
    classDef meta fill:#F4F4F4,stroke:#999,color:#555

    class Root root
    class Apex,LWC,Flow skillFolder
    class ApexSkill,LWCSkill,FlowSkill skillFile
    class ApexRefs,LWCRefs,FlowRefs refsFolder
    class R1,R2,R3,R4,R5,R6,R7 refFile
    class README,Changelog,License,Gitignore meta
```

Each skill folder contains its `SKILL.md` (the load-bearing instructions) plus a `references/` subfolder with verbatim implementations and large code examples that Claude loads on demand. Repo-level files (`README.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`) live at the root and never get bundled into the installable skill.

---

## Install in Claude.ai

A `.skill` file is just a ZIP archive of the skill folder with the extension renamed. Build it once, upload it once.

```mermaid
flowchart LR
    A[Clone or<br/>download repo] --> B[Zip the<br/>skill folder]
    B --> C[Rename<br/>.zip → .skill]
    C --> D[Upload in<br/>Claude.ai]

    classDef step fill:#D97757,stroke:#8B4513,color:#fff,stroke-width:2px
    class A,B,C,D step
```

Upload location in Claude.ai: **Settings → Capabilities → Skills → Upload skill**.

### Terminal — macOS, Linux, WSL

```bash
zip -r decimatio-apex.skill decimatio-apex/
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

## Install in Claude Code

Claude Code reads skills directly from a folder on disk — no zipping needed. Copy the skill folder into the directory matching the scope you want:

```mermaid
flowchart LR
    A[Clone repo] --> B{Scope?}
    B -->|All your projects| C["cp -r skill ~/.claude/skills/"]
    B -->|Just this project| D["cp -r skill .claude/skills/"]
    C --> E[Restart<br/>Claude Code]
    D --> E

    classDef step fill:#D97757,stroke:#8B4513,color:#fff,stroke-width:2px
    classDef decision fill:#00A1E0,stroke:#005F8A,color:#fff,stroke-width:2px
    classDef cmd fill:#2d2d2d,stroke:#666,color:#f0f0f0

    class A,E step
    class B decision
    class C,D cmd
```

After copying, restart Claude Code and verify with `claude doctor` — the skill should appear under **Loaded Skills**.

---

## License

[MIT](LICENSE)
