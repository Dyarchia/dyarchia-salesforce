# Antigravity CLI (AGY) — Full Command Catalog

From Google's Antigravity CLI documentation ("Using AGY CLI" settings page and keybindings page). Vendor: Google. Binary: `agy` (some third-party sources also cite `av` — confirm with `--version`). Config root: `~/.gemini/antigravity-cli/`. Successor to Gemini CLI; consumer cutover 2026-06-18.

## Settings

- **Configuration file**: plain JSON at `~/.gemini/antigravity-cli/settings.json`.
- **Settings panel**: `/config` or `/settings` opens a full-screen overlay of all options. Selecting a setting opens its options or a text input; selections save to disk immediately.
- **Overrides**: some settings can be overridden at launch via flags (e.g. `--sandbox`, `--dangerously-skip-permissions`). The panel shows an indicator of where an override came from; the on-disk setting can still be edited but the session enforces the launch override until restart.

## Quick tips

| Action / feature | Tip / command |
|------------------|---------------|
| Auto-complete file paths | `@` triggers path suggestions |
| Clear prompt | `esc esc` (when no streaming active) |
| Terminal commands | leading `!` runs a terminal command directly |
| Help | `?` lists all slash commands |
| Reduce tool-call noise | set verbosity `low` in `/config` |
| Manage permissions | `/config` or `/permissions` |
| Go back in conversation | `/rewind` or `/undo` |
| Fork conversation | `/fork` spins up a separate workspace and branches from an earlier point |
| Clear conversation | `/clear` starts a new session |
| Resume conversation | `/resume` lists and resumes previous logs |
| Auto-save resume | on close, prints the exact command to resume that session |

## Slash commands (full `/help`)

The complete in-tool command set (richer than the quick-tips page).

| Command (aliases) | Purpose |
|-------------------|---------|
| `/add-dir` | Add a directory to the workspace |
| `/agents` | List available custom agents |
| `/artifact` | View and review artifacts |
| `/btw` | Ask a side question without interrupting the current task |
| `/changelog` | Show release notes and changes |
| `/clear` (`new`) | Clear conversation and start a new one |
| `/config` (`settings`) | Open settings panel |
| `/context` | Visualize current context usage |
| `/copy` | Copy the last planner response to the clipboard |
| `/credits` | Show remaining G1 credits and purchase link |
| `/diff` | View uncommitted changes and per-turn diffs |
| `/exit` (`quit`) | Exit the CLI |
| `/fast` | Execute tasks directly (simple tasks, faster) |
| `/feedback` | Submit qualitative feedback |
| `/fork` (`branch`) | Branch the conversation at this point |
| `/help` | Show commands and keybindings |
| `/hooks` | Manage hook configs for tool events |
| `/keybindings` | Set custom keybindings |
| `/logout` | Log out |
| `/mcp` | Manage MCP servers |
| `/model` | Set a model |
| `/open` | Open a file or view opened/edited files |
| `/permissions` | Manage tool permissions |
| `/planning` | Plan before executing (deep research, complex/collaborative work) |
| `/rename` | Rename the current conversation |
| `/resume` (`switch`, `conversation`) | Browse and resume past conversations |
| `/rewind` (`undo`) | Rewind conversation to a previous message |
| `/skills` | List available skills |
| `/statusline` | Toggle the statusline |
| `/tasks` | View background tasks |
| `/title` | Toggle custom terminal window title |
| `/usage` (`quota`) | View model quota usage |
| `/goal` | Run until the specified goal is completely finished |
| `/schedule` | Run an instruction on a recurring schedule or one-time timer |
| `/grill-me` | Interview me to align on a plan |
| `/teamwork-preview` | Invoke a team of agents for large projects autonomously |

Notable vs the rest: AGY has no `/compact` (uses `/context` to visualize usage), splits execution into `/fast` (direct) and `/planning` (plan-first), and exposes a G1-credit balance via `/credits`. Autonomous surface: `/goal`, `/schedule`, `/teamwork-preview`, `/grill-me`, `/btw`.

## Keybindings

Custom keybindings via `/keybindings` or by editing `~/.gemini/antigravity-cli/keybindings.json`. Reset by deleting the file.

| Action | Keys | Purpose |
|--------|------|---------|
| Clear TUI screen | `Ctrl+L` | Clear terminal output |
| Enter / submit | `Enter` | Submit prompts or choices |
| Escape / cancel | `Ctrl+C`, `Esc` | Stop stream, close menus, clear prompt |
| Exit CLI | `Ctrl+D` | Terminate the TUI session |
| Suspend CLI | `Ctrl+Z` | Push session to terminal background |
| Edit command | `e` | Open editor to edit a proposed terminal command |
| Confirm no / yes | `n` / `y` | Decline / approve terminal command execution |
| Open editor | `Ctrl+G` | Edit prompt in default shell editor |
| Paste text | `Ctrl+V` | Paste from clipboard |
| Redo / undo text edit | `Ctrl+Shift+Z` / `Ctrl+_`, `Ctrl+Shift+-` | Redo / undo last text change |
| Yank (copy) | `Ctrl+Y` | Copy selected text |
| Navigate down / up | `Down` / `Up` | Scroll in menu lists |
| Go to bottom / top | `Ctrl+End` / `Ctrl+Home` | Jump TUI view |
| Navigate left / right | `Left` / `Right` | Move prompt cursor |
| Page down / up | `PgDn`, `Shift+Down` / `PgUp`, `Shift+Up` | Scroll TUI page |
| Tab / focus | `Tab` | Auto-complete choices or switch component focus |
| Insert newline | `Alt+Enter`, `Ctrl+J`, `Shift+Enter` | Newline without submitting |

## Notes

- Config lives under `~/.gemini/` despite the Antigravity name — a rebrand over the Gemini stack.
- `--dangerously-skip-permissions` and `@`/`!` conventions mirror Claude Code.
- Headless/CI flags are not covered in the published quick-start; verify in-tool.
