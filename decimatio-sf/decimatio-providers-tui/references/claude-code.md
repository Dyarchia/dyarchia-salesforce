# Claude Code — Full Command Catalog

Verified against the official CLI reference (`code.claude.com/docs/en/cli-reference`) and current cheat-sheets, June 2026. Version line `2.1.x`. Vendor: Anthropic. Binary: `claude`. Config root: `~/.claude/`.

## CLI commands

| Command | Description |
|---------|-------------|
| `claude` | Start interactive session |
| `claude "query"` | Start interactive session with an initial prompt |
| `claude -p "query"` | Query via SDK, then exit (headless/print) |
| `cat f \| claude -p "query"` | Process piped content |
| `claude -c` | Continue most recent conversation in current dir |
| `claude -c -p "query"` | Continue via SDK |
| `claude -r "<session>" "query"` | Resume session by id or name |
| `claude update` | Update to latest version |
| `claude install [version]` | Install/reinstall native binary (`stable`, `latest`, or e.g. `2.1.118`) |
| `claude auth login` / `logout` / `status` | Account auth (`--console` for API billing) |
| `claude agents` | Open agent view; `--json` for scripting |
| `claude attach <id>` / `respawn <id>` / `stop <id>` / `rm <id>` / `logs <id>` | Manage background sessions |
| `claude mcp` | Configure MCP servers |
| `claude plugin` (alias `plugins`) | Manage plugins |
| `claude setup-token` | Long-lived OAuth token for CI |
| `claude remote-control` | Control Claude Code from claude.ai / app |
| `claude project purge [path]` | Delete local project state |
| `claude ultrareview [target]` | Run ultrareview non-interactively |

## Key CLI flags

| Flag | Purpose |
|------|---------|
| `--print`, `-p` | Headless/print mode |
| `--continue`, `-c` | Load most recent conversation in dir |
| `--resume`, `-r` | Resume by id/name or interactive picker |
| `--fork-session` | New session id on resume (use with `-r`/`-c`) |
| `--model` | `sonnet` / `opus` / `haiku` / `fable` or full id |
| `--effort` | `low` / `medium` / `high` / `xhigh` / `max` |
| `--permission-mode` | `default` / `acceptEdits` / `plan` / `auto` / `dontAsk` / `bypassPermissions` |
| `--dangerously-skip-permissions` | Skip permission prompts (= `bypassPermissions`) |
| `--allowedTools` / `--disallowedTools` | Permission rule lists |
| `--tools` | Restrict built-in tools (e.g. `"Bash,Edit,Read"`) |
| `--add-dir` | Add working directories |
| `--mcp-config` / `--strict-mcp-config` | Load MCP servers from JSON; restrict to those |
| `--agents` | Define subagents via JSON |
| `--append-system-prompt` / `--system-prompt` (+ `-file` variants) | Customize system prompt |
| `--bare` | Skip auto-discovery for faster scripted calls |
| `--safe-mode` | Start with all customizations disabled (troubleshooting) |
| `--output-format` | `text` / `json` / `stream-json` (print mode) |
| `--input-format` | `text` / `stream-json` (print mode) |
| `--max-turns` / `--max-budget-usd` | Print-mode limits |
| `--worktree`, `-w` | Isolated git worktree; pair with `--tmux` |
| `--verbose`, `-v` | Verbose / version |

`claude --help` does not list every flag; absence from `--help` does not mean unavailable.

## In-session slash commands (selection)

`/help`, `/clear`, `/compact`, `/plan`, `/resume`, `/rewind` (checkpoints), `/rename`, `/cost`, `/stats`, `/usage`, `/model`, `/cd`, `/add-dir`, `/theme`, plus bundled skill-commands like `/code-review`. Custom commands live in `.claude/commands/` and appear under `/help`.

## Conventions

- File references: `@filename` includes file contents; `@` triggers path autocomplete.
- Shell: a leading `!` runs a terminal command.
- Plan mode and permission modes cycle with `Shift+Tab`.

## Config & memory

- Settings: `~/.claude/settings.json` (user), `.claude/settings.json` (project), `.claude/settings.local.json` (local). Precedence: flags > env > local > project > user.
- Project rules / memory: `CLAUDE.md` (and auto-memory).
- Skills: `~/.claude/skills/<name>/SKILL.md` and `.claude/skills/`; model-invoked via the Skill tool, frontmatter `name` + `description`.
- Hooks: lifecycle events configured in `settings.json`.
- Themes: `~/.claude/themes/<name>.json`.
- MCP: `claude mcp add …`, `claude mcp list`; project `.mcp.json`.

## Install

```bash
curl -fsSL https://claude.ai/install.sh | bash   # native binary (recommended)
brew install --cask claude-code                  # macOS Homebrew
npm install -g @anthropic-ai/claude-code         # npm (deprecated path)
```
