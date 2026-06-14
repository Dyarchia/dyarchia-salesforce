# Grok Build (Grok CLI) — Full Command Catalog

From xAI's in-tool `/help` and `~/.grok/docs/user-guide/` index. Vendor: xAI. Binary: `grok`. Config root: `~/.grok/`. Modes: interactive TUI, headless (`grok -p`) for scripts/CI, and ACP agent for editors.

## Quick start

```powershell
irm https://x.ai/cli/install.ps1 | iex   # install (PowerShell on Windows)
```

```bash
grok --version
grok update
grok                                   # launch TUI
grok -p "Explain this project"         # initial prompt
grok -p "Review the changes" --output-format json --always-approve   # headless
```

Auth: opens the browser on first use, caches creds at `~/.grok/auth.json`. CI uses `XAI_API_KEY`.

## Slash commands

Sessions & context:
`/new` (alias `/clear`), `/resume` (alias `/load`), `/compact [context]`, `/context`, `/session-info`, `/rewind`, `/fork`.

Model & mode:
`/model grok-build` (alias `/m`), `/always-approve` (alias `/yolo`), `/multiline` (alias `/ml`), `/plan [description]`, `/vim-mode`.

Memory (requires `--experimental-memory` or env):
`/memory`, `/flush`, `/dream`, `/remember`.

Extensions:
`/skills`, `/plugins`, `/marketplace`, `/hooks`, `/mcps`.

Other:
`/theme` (alias `/t`), `/settings` (alias `/config`), `/feedback`, `/loop 30m <prompt>` (recurring task), `/goal <…>` (autonomous objective), `/terminal-setup`, `/quit`, `/exit`.

Skills with `user-invocable: true` also appear as `/<skill-name>`.

## Essential keybindings

| Action | Keys |
|--------|------|
| Send prompt | `Enter` |
| Newline | `Shift+Enter` / `Alt+Enter` |
| Toggle multiline | `Ctrl+M` |
| Toggle always-approve (YOLO) | `Ctrl+O` |
| Cancel current turn | `Ctrl+C` / `Esc` |
| Toggle TODO panel | `Ctrl+T` |
| Search prompt history | `Ctrl+R` |
| Move task to background | `Ctrl+G` |
| Switch focus prompt ↔ scrollback | `Tab` / `Esc` |
| Command palette | `Ctrl+P` (or `?`) |

In scrollback: `j`/`k` or arrows; `h`/`l` collapse/expand (some require Vim mode); `Enter` opens fullscreen viewer.

## Config

`~/.grok/config.toml`. Precedence: CLI flags > environment variables > `config.toml`. Example structure:

```toml
[cli]
installer = "internal"

[ui]
max_thoughts_width = 120
fork_secondary_model = "grok-build"
yolo = false
compact_mode = false

[marketplace]
official_marketplace_auto_installed = true

[[marketplace.sources]]
name = "xAI Official"
git = "https://github.com/xai-org/plugin-marketplace.git"
```

## Skills & project rules

- Skills: `~/.grok/skills/<name>/SKILL.md` (also `.grok/skills/` local or repo). Frontmatter + tool-use patterns; many surface as `/` commands. See `08-skills.md` and `create-skill`.
- Project rules: `AGENTS.md` / `CLAUDE.md` (`12-project-rules.md`) — Grok reads both; it did not rename `CLAUDE.md`.
- MCP servers: configured via `07-mcp-servers.md`; managed in-tool with `/mcps`.
- Custom models / BYOK: Ollama, OpenAI-compatible endpoints (`11-custom-models.md`).

## Local docs (`~/.grok/docs/user-guide/`)

`01-getting-started`, `02-authentication`, `03-keyboard-shortcuts`, `04-slash-commands`, `05-configuration`, `06-theming`, `07-mcp-servers`, `08-skills`, `09-plugins`, `10-hooks`, `11-custom-models`, `12-project-rules`, `13-memory`, `14-headless-mode`, `15-agent-mode`, `16-subagents`, `17-sessions`, `18-sandbox`, `19-plan-mode`, `20-background-tasks`, `21-terminal-support`, `22-permissions-and-safety`. Full `README.md` at `~/.grok/README.md`.

## Notes

- Surface closely mirrors Claude Code: `SKILL.md` skills, `CLAUDE.md` rules, `/compact`, `/rewind`, `/fork`, MCP, subagents, hooks, plan mode, headless `-p`, sandbox.
- A leading `!` for inline shell is not documented for the interactive TUI in `/help` (verify in-tool).
