# Mistral Vibe (Vibe CLI) — Full Command Catalog

Verified against the official docs (`docs.mistral.ai/vibe/code/cli/`: work-with-cli, commands-shortcuts, agents). Vendor: Mistral AI (France). Binary / trigger: `vibe`. Open-source (Apache 2.0), powered by the Devstral 2 model family. Renamed from Le Chat's coding agent (May 2026). Config root: `~/.vibe/`. Available on Le Chat Pro/Team with pay-as-you-go credits beyond included limits, or BYOK.

## Two modes

- **Interactive** (default): `vibe`, or `vibe "initial prompt"`. Terminal chat for exploration, multi-step work, review and follow-up.
- **Programmatic**: `vibe --prompt "task"` runs a single task and exits. No chat UI, interactive tools disabled, and it defaults to the `auto-approve` agent.

## Input prefixes (interactive)

| Prefix | Effect |
|--------|--------|
| `@path` | Attach a file to the prompt (with path autocomplete) |
| `/` | Open the slash-command picker |
| `!cmd` | Run a shell command directly, bypassing the agent |
| `&prompt` | Send the prompt to a Vibe Code Web cloud sandbox; returns a session link |

## Slash commands (full)

| Command (alias) | Purpose |
|-----------------|---------|
| `/help` | Show help for the current CLI session |
| `/config` | Edit config settings |
| `/model` | Select the active model |
| `/thinking` | Select the thinking (reasoning) level |
| `/reload` | Reload configuration, agent instructions and skills from disk |
| `/clear` | Clear conversation history |
| `/copy` | Copy the last agent message to the clipboard |
| `/log` | Show the path to the current interaction log file |
| `/debug` | Toggle the debug console |
| `/compact` | Compact history by summarizing it (optional guiding instructions) |
| `/exit` | Exit the application |
| `/status` | Display agent statistics |
| `/teleport` | Teleport the session to Vibe Code Web |
| `/proxy-setup` | Configure proxy and SSL certificate settings |
| `/resume` (`/continue`) | Browse and resume past sessions |
| `/rename` | Rename the current session |
| `/mcp` (`/connectors`) | Display MCP servers and connectors; pass a name to list its tools |
| `/voice` | Configure voice settings |
| `/leanstall` | Install `leanstral`, the Lean 4 proof-assistant agent |
| `/unleanstall` | Uninstall the Lean 4 agent |
| `/rewind` | Rewind to a previous message |
| `/loop` | Recurring prompt: `/loop interval prompt`, `/loop list`, `/loop cancel id\|all` |
| `/data-retention` | Show data retention information |

Skills can also expose themselves as slash commands; a `/` command not in this list likely comes from a local skill in `~/.vibe/skills/` or `.vibe/skills/`.

## Programmatic flags

| Flag | Purpose |
|------|---------|
| `--prompt "q"` | Run one task non-interactively and exit |
| `--max-turns N` | Cap assistant turns (recommended to bound run length) |
| `--enabled-tools TOOL` | Restrict tools; exact names, glob (`bash*`), or regex (`re:^serena_.*$`) |
| `--output text\|json\|streaming` | Output format |
| `--max-price DOLLARS` | Budget cap — **indicative only**, values come from config and can be stale; do not rely on it |
| `--agent NAME` | Pick a built-in or custom agent |
| `--trust` | Grant temporary trust for the current invocation (programmatic) |
| `--continue` / `-c` | Resume the most recent session |
| `--resume SESSION_ID` | Resume a specific session (partial IDs supported) |

## Agents (approval model)

Agents are config overrides bundling a system prompt, compaction prompt, model, tool set and approval rules. Pick with `--agent`; cycle in-session with `Shift+Tab`; set `default_agent` in `config.toml` (interactive only — programmatic falls back to `auto-approve`).

| Agent | Behavior |
|-------|----------|
| `default` | General-purpose; asks for approval before running tools |
| `plan` | Read-only exploration/planning; auto-approves safe read tools |
| `accept-edits` | Auto-approves file edits in the working dir; still asks for other actions |
| `auto-approve` | Auto-approves all tools — use only in a trusted sandbox (can run `rm -rf`) |
| `lean` | Lean 4 proof-assistant agent (install via `/leanstall`) |

Built-in subagent `explore` (read-only codebase exploration) is model-spawned and not selectable with `--agent`.

Custom agents/subagents are `.toml` files in `~/.vibe/agents/` (user) or `./.vibe/agents/` (project), declaring `agent_type = "agent"` (user-selectable) or `"subagent"` (delegation-only via the `task` tool). The `safety` field (`safe`/`neutral`/`destructive`/`yolo`) only tints the input border — it does not enforce permissions. `system_prompt_id` points to a file in `~/.vibe/prompts/`.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+C` | Copy selection, else clear input, else quit/interrupt on empty |
| `Ctrl+D` | Delete char to the right, or quit on empty input |
| `Ctrl+Z` | Suspend the CLI |
| `Escape` | Interrupt the current operation |
| `Ctrl+O` | Toggle tool output |
| `Ctrl+Y` / `Ctrl+Shift+C` | Copy the current selection |
| `Shift+Tab` | Cycle available modes/agents |
| `Shift+Up` / `Shift+Down` | Scroll the chat up/down |
| `Ctrl+G` | Edit the current plan in an external editor |
| `Ctrl+\` | Toggle the debug console |
| `Alt+Up` / `Ctrl+P` | Rewind to the previous message |
| `Alt+Down` / `Ctrl+N` | Move to the next rewound message |

Some shortcuts misbehave under tmux/SSH; Mistral recommends Ghostty, Kitty, WezTerm or iTerm2.

## Config, trust & project rules

- Settings: `~/.vibe/config.toml` (keys like `default_agent`, `active_model`, `log_interactions = true`). Session resume requires logging on.
- Trust folders: the CLI confirms a new directory before loading project config/skills/agents; remembered in `~/.vibe/trusted_folders.toml`. Use `vibe --trust` for temporary programmatic trust.
- Skills: `~/.vibe/skills/`, `.vibe/skills/` (`SKILL.md`).
- Project rules: `AGENTS.md` — user-level `~/.vibe/AGENTS.md` plus the first project-level `AGENTS.md` found walking up from cwd, only inside trusted folders.
- Auth: `MISTRAL_API_KEY` / BYOK, or a Le Chat Pro/Team plan with PAYG credits.

## Notes

- Trust model: previews a diff before applying changes and confirms before edits or shell commands unless the agent auto-approves. MCP via HTTP, streamable-HTTP and stdio; per-tool permission levels from "always allow" to "always ask".
- Distinctive vs the others: open-source (Apache 2.0); Lean 4 integration (`/leanstall`); cloud hand-off (`&`, `/teleport`); agent-based approval model rather than permission flags; no `/fork`.
- Known friction: opaque `rate limit exceeded` errors on the coding agent that do not state which limit was hit; paying users hit them mid-session. Beyond included plan limits, usage continues PAYG at API rates, or BYOK.
