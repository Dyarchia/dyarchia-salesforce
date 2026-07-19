# opencode — Full Command Catalog

From the official CLI reference (`opencode.ai/docs/cli`). Vendor: opencode / SST. Binary: `opencode`. Config root: `~/.config/opencode/`, data root: `~/.local/share/opencode/`. Open-source TUI + headless agent with a plugin marketplace, MCP, ACP, GitHub Actions integration, attachable headless server and an agent Client Protocol endpoint.

## Two top-level modes

- **TUI (default)** — `opencode` with no args starts the terminal user interface. Equivalent to `opencode tui [project]`.
- **Non-interactive** — `opencode run "prompt"` executes one task and exits; supports streaming JSON and attaching to a running `serve` instance.

The rest of the CLI is organized as subcommands: `agent`, `attach`, `auth`, `github`, `mcp`, `models`, `run`, `serve`, `session`, `stats`, `export`, `import`, `web`, `acp`, `plugin`, `pr`, `db`, `debug`, `uninstall`, `upgrade`. Every subcommand also accepts the global flags (`--help`, `--version`, `--print-logs`, `--log-level`, `--pure`).

## TUI flags (`opencode [project]`)

| Flag | Short | Purpose |
|------|-------|---------|
| `--continue` | `-c` | Continue the last session |
| `--session` | `-s` | Session ID to continue |
| `--fork` | | Fork the session when continuing (with `--continue` / `--session`) |
| `--prompt` | | Prompt to use |
| `--model` | `-m` | Model in `provider/model` form |
| `--agent` | | Agent to use |
| `--auto` | | Auto-approve permissions not explicitly denied |
| `--port` | | Port to listen on (server-backed mode) |
| `--hostname` | | Hostname to listen on |
| `--mdns` | | Enable mDNS discovery |
| `--mdns-domain` | | Custom mDNS domain |
| `--cors` | | Additional browser origin(s) to allow CORS |

The TUI is a frontend; long-lived state and MCP servers live in a `serve` backend. The `attach` subcommand connects a TUI to an already-running `serve` or `web` instance.

## Subcommand catalog

### `opencode agent`

Manage agents. Agents are first-class config objects with a system prompt and permission set.

| Subcommand | Purpose |
|------------|---------|
| `opencode agent create` | Create a new agent (interactive unless all of `--path`, `--description`, `--mode`, `--permissions` are supplied) |
| `opencode agent list` | List all available agents |

`create` flags:

| Flag | Short | Purpose |
|------|-------|---------|
| `--path` | | Directory to write the agent file (defaults to global or `.opencode/agent` based on the prompt) |
| `--description` | | What the agent should do |
| `--mode` | | `all` / `primary` / `subagent` |
| `--permissions` | | Comma-separated allow list. Available: `bash`, `read`, `edit`, `glob`, `grep`, `webfetch`, `task`, `todowrite`, `websearch`, `lsp`, `skill`. Anything omitted is denied. Alias: `--tools` |
| `--model` | `-m` | `provider/model` |

### `opencode attach [url]`

Attach a TUI to an already-running `serve` or `web` backend (defaults to `http://localhost:4096` when omitted).

```bash
opencode web --port 4096 --hostname 0.0.0.0          # in terminal 1
opencode attach http://10.20.30.40:4096              # in terminal 2
```

| Flag | Short | Purpose |
|------|-------|---------|
| `--dir` | | Working directory to start TUI in |
| `--continue` | `-c` | Continue the last session |
| `--session` | `-s` | Session ID to continue |
| `--fork` | | Fork the session when continuing |
| `--password` | `-p` | Basic-auth password (defaults to `OPENCODE_SERVER_PASSWORD`) |
| `--username` | `-u` | Basic-auth username (defaults to `OPENCODE_SERVER_USERNAME` or `opencode`) |

### `opencode auth`

Manage provider credentials. Providers come from Models.dev; keys land in `~/.local/share/opencode/auth.json` (plus any env or project `.env` at startup).

| Subcommand | Purpose |
|------------|---------|
| `opencode auth login` | Configure an API key (interactive; `--provider` and `--method` skip the prompts) |
| `opencode auth list` (alias `ls`) | List authenticated providers |
| `opencode auth logout` | Clear a provider from the credentials file |

`login` flags:

| Flag | Short | Purpose |
|------|-------|---------|
| `--provider` | `-p` | Provider ID or name to log in to |
| `--method` | `-m` | Login method label, skipping the method selection |

### `opencode github`

Manage the GitHub agent for repository automation (GitHub Actions).

| Subcommand | Purpose |
|------------|---------|
| `opencode github install` | Install the agent in the repo, set up the workflow, walk through config |
| `opencode github run` | Run the agent (typical CI use) |

`run` flags:

| Flag | Purpose |
|------|---------|
| `--event` | GitHub mock event to run the agent for |
| `--token` | GitHub personal access token |

### `opencode mcp`

Manage Model Context Protocol servers. Servers are configured via the `mcp add` wizard (local or remote).

| Subcommand | Purpose |
|------------|---------|
| `opencode mcp add` | Add an MCP server (interactive wizard) |
| `opencode mcp list` (alias `ls`) | List configured servers and their connection status |
| `opencode mcp auth [name]` | OAuth with an OAuth-capable server (prompts if no name) |
| `opencode mcp auth list` (alias `ls`) | List OAuth-capable servers and their status |
| `opencode mcp logout [name]` | Remove OAuth credentials for a server |
| `opencode mcp debug <name>` | Debug OAuth connection issues for a server |

### `opencode models [provider]`

List available models in `provider/model` form. Pass a provider ID to filter; `--refresh` to fetch fresh from Models.dev; `--verbose` to include cost metadata.

```bash
opencode models
opencode models anthropic
opencode models --refresh --verbose
```

### `opencode run [message..]`

Non-interactive one-shot. Use it for scripting, automation, or one-off questions without launching the TUI.

```bash
opencode run Explain async/await in JavaScript
opencode run --attach http://localhost:4096 "Explain async/await in JavaScript"
```

| Flag | Short | Purpose |
|------|-------|---------|
| `--command` | | The command to run, use message for args |
| `--continue` | `-c` | Continue the last session |
| `--session` | `-s` | Session ID to continue |
| `--fork` | | Fork the session when continuing |
| `--share` | | Share the session |
| `--model` | `-m` | `provider/model` |
| `--agent` | | Agent to use |
| `--file` | `-f` | File(s) to attach to the message |
| `--format` | | `default` (formatted) or `json` (raw JSON events) |
| `--title` | | Title for the session (truncated prompt if no value) |
| `--attach` | | Attach to a running `opencode serve` instance |
| `--password` | `-p` | Basic-auth password (defaults to `OPENCODE_SERVER_PASSWORD`) |
| `--username` | `-u` | Basic-auth username (defaults to `OPENCODE_SERVER_USERNAME` or `opencode`) |
| `--dir` | | Directory to run in (or path on the remote server when attaching) |
| `--port` | | Port for the local server (random if omitted) |
| `--variant` | | Provider-specific reasoning effort |
| `--thinking` | | Show thinking blocks |
| `--auto` | | Auto-approve permissions not explicitly denied |

### `opencode serve`

Start a headless HTTP server. See the server docs for the full HTTP interface. Set `OPENCODE_SERVER_PASSWORD` to enable basic auth; username defaults to `opencode`.

| Flag | Purpose |
|------|---------|
| `--port` | Port to listen on |
| `--hostname` | Hostname to listen on |
| `--mdns` | Enable mDNS discovery |
| `--mdns-domain` | Custom mDNS domain |
| `--cors` | Additional browser origin(s) to allow CORS |

### `opencode session`

Manage sessions. Sessions are persistent; `run` and `serve` reuse them, and `export` / `import` move them between machines.

| Subcommand | Purpose |
|------------|---------|
| `opencode session list` | List all sessions |
| `opencode session delete <sessionID>` | Delete a session |

`list` flags:

| Flag | Short | Purpose |
|------|-------|---------|
| `--max-count` | `-n` | Limit to N most recent sessions |
| `--format` | | `table` (default) or `json` |

### `opencode stats`

Token usage and cost statistics.

| Flag | Purpose |
|------|---------|
| `--days` | Show stats for the last N days (default: all time) |
| `--tools` | Number of tools to show (default: all) |
| `--models` | Show model usage breakdown (hidden by default; pass N for top N) |
| `--project` | Filter by project (all projects by default, empty string: current project) |

### `opencode export [sessionID]`

Export a session as JSON. If no session ID is given, an interactive picker is shown.

| Flag | Purpose |
|------|---------|
| `--sanitize` | Redact sensitive transcript and file data |

### `opencode import <file>`

Import a session from a local JSON file or an opencode share URL.

```bash
opencode import session.json
opencode import https://opncd.ai/s/abc123
```

### `opencode web`

Start a headless server with a web UI (opens the browser by default). Same `--port` / `--hostname` / `--mdns` / `--cors` flags as `serve`. Basic auth via `OPENCODE_SERVER_PASSWORD` (username `opencode`).

### `opencode acp`

Start an Agent Client Protocol server on stdin/stdout using nd-JSON. Same `--cwd` / `--port` / `--hostname` / `--mdns` / `--cors` / `--mdns-domain` shape as `serve` plus `--cwd`.

### `opencode plugin <module>` (alias `plug`)

Install a plugin and update the config.

| Flag | Short | Purpose |
|------|-------|---------|
| `--global` | `-g` | Install in global config |
| `--force` | `-f` | Replace existing plugin version |

### `opencode pr <number>`

Fetch a GitHub PR branch, check it out locally, then run opencode in it.

### `opencode db [query]`

Database tools; `opencode db path` prints the database path. `--format json|tsv` controls output.

### `opencode debug [command]`

Debugging and troubleshooting tools. No subcommands documented in the public surface beyond the entry point.

### `opencode uninstall`

| Flag | Short | Purpose |
|------|-------|---------|
| `--keep-config` | `-c` | Keep configuration files |
| `--keep-data` | `-d` | Keep session data and snapshots |
| `--dry-run` | | Show what would be removed without removing |
| `--force` | `-f` | Skip confirmation prompts |

### `opencode upgrade [target]`

```bash
opencode upgrade            # latest
opencode upgrade v0.1.48    # specific
```

| Flag | Short | Purpose |
|------|-------|---------|
| `--method` | `-m` | Installation method that was used: `curl`, `npm`, `pnpm`, `bun`, `brew` |

## Global flags

| Flag | Short | Purpose |
|------|-------|---------|
| `--help` | `-h` | Display help |
| `--version` | `-v` | Print version |
| `--print-logs` | | Print logs to stderr |
| `--log-level` | | `DEBUG` / `INFO` / `WARN` / `ERROR` |
| `--pure` | | Run without external plugins |

## Environment variables (selection)

The most load-bearing ones. Full list in the official docs.

| Variable | Type | Purpose |
|----------|------|---------|
| `OPENCODE_AUTO_SHARE` | boolean | Automatically share sessions |
| `OPENCODE_GIT_BASH_PATH` | string | Path to Git Bash on Windows |
| `OPENCODE_CONFIG` | string | Path to config file |
| `OPENCODE_TUI_CONFIG` | string | Path to TUI config file |
| `OPENCODE_CONFIG_DIR` | string | Path to config directory |
| `OPENCODE_CONFIG_CONTENT` | string | Inline JSON config content |
| `OPENCODE_PERMISSION` | string | Inlined JSON permissions config |
| `OPENCODE_CLIENT` | string | Client identifier (defaults to `cli`) |
| `OPENCODE_ENABLE_EXA` | boolean | Enable Exa web search tools |
| `OPENCODE_SERVER_PASSWORD` | string | Enable basic auth for `serve` / `web` |
| `OPENCODE_SERVER_USERNAME` | string | Override basic auth username (default `opencode`) |
| `OPENCODE_MODELS_URL` | string | Custom URL for fetching models config |
| `OPENCODE_DISABLE_AUTOUPDATE` | boolean | Disable automatic update checks |
| `OPENCODE_DISABLE_PRUNE` | boolean | Disable pruning of old data |
| `OPENCODE_DISABLE_TERMINAL_TITLE` | boolean | Disable automatic terminal title updates |
| `OPENCODE_DISABLE_DEFAULT_PLUGINS` | boolean | Disable default plugins |
| `OPENCODE_DISABLE_LSP_DOWNLOAD` | boolean | Disable automatic LSP server downloads |
| `OPENCODE_ENABLE_EXPERIMENTAL_MODELS` | boolean | Enable experimental models |
| `OPENCODE_DISABLE_AUTOCOMPACT` | boolean | Disable automatic context compaction |
| `OPENCODE_DISABLE_CLAUDE_CODE` | boolean | Disable reading from `.claude` (prompt + skills) |
| `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT` | boolean | Disable reading `~/.claude/CLAUDE.md` |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` | boolean | Disable loading `.claude/skills` |
| `OPENCODE_DISABLE_MODELS_FETCH` | boolean | Disable fetching models from remote sources |
| `OPENCODE_DISABLE_MOUSE` | boolean | Disable mouse capture in the TUI |
| `OPENCODE_FAKE_VCS` | string | Fake VCS provider for testing |

### Experimental

| Variable | Type | Purpose |
|----------|------|---------|
| `OPENCODE_EXPERIMENTAL` | boolean | Umbrella flag for the experimental set |
| `OPENCODE_EXPERIMENTAL_PLAN_MODE` | boolean | Enable plan mode |
| `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS` | boolean | Enable background subagent tasks |
| `OPENCODE_EXPERIMENTAL_WORKSPACES` | boolean | Enable workspace support |
| `OPENCODE_EXPERIMENTAL_FILEWATCHER` | boolean | Enable file watcher for an entire dir |
| `OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER` | boolean | Disable the file watcher |
| `OPENCODE_EXPERIMENTAL_LSP_TOOL` | boolean | Enable the experimental LSP tool |
| `OPENCODE_EXPERIMENTAL_LSP_TY` | boolean | Enable TY LSP for Python files |
| `OPENCODE_EXPERIMENTAL_NATIVE_LLM` | boolean | Enable the native LLM request path |
| `OPENCODE_EXPERIMENTAL_PARALLEL` | boolean | Enable parallel web search |
| `OPENCODE_EXPERIMENTAL_SCOUT` | boolean | Enable the Scout subagent |
| `OPENCODE_EXPERIMENTAL_EVENT_SYSTEM` | boolean | Enable the experimental event system |
| `OPENCODE_EXPERIMENTAL_OXFMT` | boolean | Enable the oxfmt formatter |
| `OPENCODE_EXPERIMENTAL_EXA` | boolean | Enable experimental Exa features |
| `OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX` | number | Max output tokens for LLM responses |
| `OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS` | number | Default timeout for bash commands in ms |
| `OPENCODE_EXPERIMENTAL_DISABLE_COPY_ON_SELECT` | boolean | Disable copy-on-select in the TUI |
| `OPENCODE_EXPERIMENTAL_ICON_DISCOVERY` | boolean | Enable icon discovery |

## Quick start

```bash
opencode                                # launch TUI in current dir
opencode run "Explain this project"     # one-shot, headless
opencode serve --port 4096              # headless server
opencode web --port 4096                # headless server + browser
opencode attach http://localhost:4096   # TUI attached to a server
opencode models                         # list configured provider/model ids
opencode auth login                     # configure provider API keys
opencode upgrade                        # update to latest
```

Auth: providers are read from Models.dev at startup. Keys live in `~/.local/share/opencode/auth.json`, or come from env / project `.env`. `OPENCODE_SERVER_PASSWORD` (and optionally `OPENCODE_SERVER_USERNAME`) enable basic auth for `serve` and `web`.

## Notes

- Surface sits squarely in the Claude Code / Grok orbit: `SKILL.md` skills, MCP, subagents, plan mode, hooks, headless `-p`-style invocation (`opencode run`), and attachable headless server.
- Distinctive vs the others: the `web` subcommand opens a browser against a local headless server; `acp` exposes an Agent Client Protocol endpoint; `pr` automates the checkout-and-run flow on top of GitHub PRs; `mcp auth` and `mcp debug` exist as first-class concerns rather than a single subcommand; `uninstall` and `upgrade` ship as CLI subcommands rather than external scripts.
- `opencode` reads `.claude/CLAUDE.md` and `.claude/skills` by default; all of it is gated behind `OPENCODE_DISABLE_CLAUDE_CODE*` env vars. This is the canonical "pick up the existing Claude Code project setup and run on it" path.
