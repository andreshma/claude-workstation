# Usage

How to install the workstation and use it day to day. For how the pieces fit see [architecture.md](architecture.md);
for what goes wrong and how to recover see [runbook.md](runbook.md).

The interface is in English. Menu labels and status labels are quoted exactly as the screen shows them. Command names,
flags and some stored values are still Spanish words (`tmux-nivel completo`, `--todas`) and are written as you type
them. `Ctrl+b` is the tmux prefix: press it, release, then press the key.

On the workstation itself, two things are always up to date because they read what is installed:

| What | How |
|---|---|
| Cheat sheet of daily shortcuts | `Ctrl+b h` |
| Full manual generated from the installed menus, key bindings and commands | `ws-menus --ver` |

## Contents

- [1. Requirements](#1-requirements)
- [2. Install](#2-install)
- [3. First run](#3-first-run)
- [4. Opening repositories](#4-opening-repositories)
- [5. Key bindings](#5-key-bindings)
- [6. The menu](#6-the-menu)
- [7. Status bar legend](#7-status-bar-legend)
- [8. Finding the tab that needs you](#8-finding-the-tab-that-needs-you)
- [9. Working with Claude in a tab](#9-working-with-claude-in-a-tab)
- [10. Accounts](#10-accounts)
- [11. Protection levels](#11-protection-levels)
- [12. Reports and telemetry](#12-reports-and-telemetry)
- [13. Notifications and Telegram](#13-notifications-and-telegram)
- [14. Appearance and screensaver](#14-appearance-and-screensaver)
- [15. Backups and restore](#15-backups-and-restore)
- [16. Updating from the kit](#16-updating-from-the-kit)
- [17. Command reference](#17-command-reference)
- [18. Troubleshooting](#18-troubleshooting)
- [19. Known limitations](#19-known-limitations)

## 1. Requirements

| Requirement | Detail |
|---|---|
| Operating system | Windows 11 with WSL2 (Ubuntu 24.04) |
| tmux | 3.3 or newer |
| Claude Code | Installed and logged in |
| Base packages | `tmux git jq fzf gh bubblewrap socat rsync shellcheck` |
| Optional: `python3-numpy` | 12 of the 25 screensaver scenes use a numpy shading engine |
| Optional: `chafa` | The `galeria` screensaver scene |

`ws-tools install numpy chafa` installs both optional packages once the kit is installed.

## 2. Install

1. Install the base packages:

   ```bash
   sudo apt-get install -y tmux git jq fzf gh bubblewrap socat rsync shellcheck
   ```

2. Clone the kit, test it and install it:

   ```bash
   git clone https://github.com/andreshma/claude-workstation ~/code/claude-workstation
   cd ~/code/claude-workstation
   bash tests/run.sh            # installer tests in temporary homes; they do not touch your machine
   bash install.sh --dry-run    # shows new / changed / same without writing
   bash install.sh              # detects your Windows user; otherwise pass --win-user
   ```

3. Install the tools and check the health of the workstation:

   ```bash
   ws-tools install base nube calidad
   ws-check && ws-health
   ```

4. On Windows, run `windows\instalar.ps1` from PowerShell to add the terminal profile and shortcuts.

`install.sh` backs up every file it changes as `*.bak.<date>`. It also points git at the kit hooks (commit gate)
unless you already use another hooks path.

`install.sh` options:

| Option | Use |
|---|---|
| `--dry-run` | Print what would change without writing |
| `--win-user USER` | Windows user name, when it cannot be detected |
| `--repos PATH` | Folder that holds your repositories (default: `source/repos` under the Windows profile) |
| `--no-plugins` | Skip the tmux plugins |
| `--no-mcp` | Skip MCP server registration |
| `--no-git-hooks` | Do not set git's global hooks path |

## 3. First run

1. Start the session with `dev` in PowerShell, the desktop shortcut, or the Ubuntu profile of Windows Terminal.
2. Press `Ctrl+b I` once to install the tmux plugins.
3. Press `Ctrl+b m` to open the menu.

### Entering and leaving

| Action | How |
|---|---|
| Enter the session | `dev` in PowerShell, the desktop shortcut, or the Ubuntu profile of Windows Terminal. It attaches to the tmux session `dev`, creating it if needed; saved tabs are restored |
| Leave without closing anything | `Ctrl+b d` (detach). Tabs and their Claude sessions keep running |
| Save now | `Ctrl+b Ctrl+s`, or `devsave` in PowerShell before restarting WSL |
| Reload the tmux configuration | `Ctrl+b r` |

PowerShell helpers installed by `windows\instalar.ps1`:

| Command | What it does |
|---|---|
| `dev` | Enters the `dev` session |
| `devo <repo>` | Opens a repository in a new tab with Claude |
| `devdash`, `devagents` | Tab dashboard; live subagents |
| `devsave` | Saves the tmux session now |
| `devcheck` | Runs `ws-check` and `ws-health` |
| `devsnapshot`, `devrestoretest` | Full export of the Ubuntu distro as `.vhdx` (stops WSL for a few minutes); imports the latest snapshot as a throwaway distro, checks it and deletes it |

Sessions survive closing the terminal and restarting WSL: tmux-continuum saves every minute, `tmux-save-now` saves
when a tab or pane is created, closed or renamed, and each restored tab resumes its Claude conversation.

## 4. Opening repositories

| Action | How |
|---|---|
| Pick a folder and open it with Claude | `Ctrl+b o`. Enter opens; `→` enters the subfolders of the highlighted entry; `←` goes up. If a tab for that folder already exists, it jumps there |
| Open from the shell | `tw <folder> [name]` |
| Open with Opus | `two <folder>`, or Menu → "Open a folder with Opus" |
| Open a worktree | `twt <repo> <branch>`, or Menu → "New worktree of this repo" |
| Add a folder as a pane of the current tab | `tp <folder>` |
| Open with a pane layout (Claude + tests + git) | Menu → "Open a folder with a template (Claude + tests + git)". Templates: `node-api`, `dotnet`, `python`, `terraform`, `qa` |
| Open a favorite folder | `Ctrl+b F`, or Menu → "Favorites ★". Enter goes to the tab or opens the folder with Claude in its group; `Ctrl+X` removes it from the list |
| Bring recent conversations that have no tab | Menu → "Tabs and session" → "Bring recent conversations into tmux" (`tmux-traer`) |

The picker lists the folders under the roots in `~/.config/tmux-claude/roots.txt`, one per line as
`label|depth|path`. The label is also the **group**: each group is its own tmux session, and a new tab is created in
the session of its group. `Alt+↑/↓` switches group and `Ctrl+b S` lists all groups with their tabs. To keep everything
in one session, set `grupos=off` in `~/.config/tmux-claude/ajustes`.

A tab opens Claude with `claude --continue` when the folder already has conversations, and plain `claude` otherwise.

Favorites belong to the folder, not to the tab: `Ctrl+b *` adds or removes the current tab's folder, the tab shows a
★ in the status bar, and the mark survives closing the tab and restarting tmux. The list is kept in
`~/.config/tmux-claude/favoritos`. `tmux-open --dir <folder>` opens a folder without asking.

## 5. Key bindings

### Without prefix

| Keys | Action |
|---|---|
| `Alt+1` … `Alt+9` | Go to tab 1–9 |
| `Alt+←` / `Alt+→` | Previous / next tab |
| `Alt+0` | Last used tab |
| `Alt+s` | Search tabs by name |
| `Alt+Shift+←` / `Alt+Shift+→` | Move the tab left / right |
| `Alt+↑` / `Alt+↓` | Previous / next group |
| Click on `≡ menu` in the bar | Open the menu |
| Right click on a tab | Rename, close, move, save session, live subagents |
| Double click on a tab | Tab summary |

### With prefix `Ctrl+b`

| Key | Action |
|---|---|
| `m` | Main menu |
| `Space` | Command palette: search any menu option by typing |
| `h` | Shortcut cheat sheet |
| `o` | Open a folder or repository |
| `f` | Search tabs by name |
| `a` | "Active now": tabs that are active now, across groups |
| `D` | Tab dashboard |
| `A` | Live subagents (`v` shows a subagent's transcript) |
| `i` | Summary of the tab: where it is, what it is doing, where it stopped |
| `S` | All groups with their tabs |
| `*` | Add the tab's folder to the favorites, or remove it |
| `F` | Favorites list |
| `e` | Paste the output of the side pane into Claude's prompt (redacted, without Enter) |
| `?` | Quick question to Claude in a popup, outside the tab's context |
| `N` | Notify me when the command in this pane finishes (again: cancel) |
| `u` | Extract URLs, paths, hashes, IDs and tickets from the screen |
| `E` | Label for the tab (Blocked, In review, Waiting on someone, Testing, Ready) |
| `v` | Show or hide the compute monitor (second status line) |
| `g` | Persistent floating shell in the tab's folder |
| `P` | Floating PowerShell |
| `G` | lazygit in the tab's folder |
| `K` | CI checks of the pull request (`gh pr checks`), or recent runs |
| `Y` | Copy the last 200 lines of the pane to the clipboard |
| `H` | Start or stop logging the pane to `~/logs` |
| `M` / `T` | Layout: main pane at 65 % / tiled |
| `c`, `"`, `%` | New tab / split below / split to the side, in the current folder |
| `r` | Reload `~/.tmux.conf` |
| `d` | Detach |
| `Ctrl+s` / `Ctrl+r` | Save / restore the session (tmux-resurrect) |
| `Ctrl+b` | Send `Ctrl+B` to Claude (move a task to the background) |

Standard tmux keys still apply: `'` go to a tab by number, `,` rename, `&` close the tab, `z` zoom, `x` close the
pane, `[` scroll and copy (`v` marks, `y` copies, `q` leaves), `Tab` extrakto.

### Inside Claude Code

| Keys | Action |
|---|---|
| `Esc`, `Esc Esc` | Interrupt; go back to an earlier point |
| `Shift+Tab` | Permission modes (plan, auto) |
| `Alt+P` | Model picker |
| `Ctrl+O` | Transcript with reasoning |
| `Ctrl+T`, `Ctrl+R`, `Ctrl+G` | Task list; history; edit the prompt in the editor |
| `Shift+Enter` | New line |
| `!` | Run a command yourself (outside the sandbox) |
| `claude -c`, `claude -r` | Resume the last conversation; choose one |

### In the shell

The interactive shell loads tab completion, fzf (`Ctrl+R` history, `Ctrl+T` file, `Alt+C` folder), grey suggestions
(ble.sh, `→` accepts) and an optional terminal copilot that never executes anything: `Alt+a` turns a request written in
natural language into a command, `Alt+e` explains the command on the line, `Alt+x` proposes a fix for the last failed
command. `AI_SHELL_GHOST=0` turns the grey AI suggestion off.

## 6. The menu

`Ctrl+b m` opens the main menu; each `›` opens a submenu and `Backspace` goes back. The key after each label selects
it. The title shows the group, the tab, Claude's state and the context percentage.

### Main menu

| Section | Key | Label | Action |
|---|---|---|---|
| Go to | `a` | Active now, from all groups | Active tabs across groups |
| | `g` | Go to the next one waiting for you or stalled for a while | Jump to the next tab that waits for you or is stalled |
| | `F` | Favorites ★ | Favorite folders, open or not |
| | `f` | Find a tab by name | Search tabs |
| | `D` | Tab dashboard | Dashboard |
| | `o`, `O` | Open a folder or repo; Open a folder with Opus | Open a folder |
| | `T` | Open a folder with a template (Claude + tests + git) | Open with a pane template |
| | `w` | New worktree of this repo | New worktree (asks for the branch) |
| This tab | `c` | Claude in this tab › | Submenu, enabled when the tab has Claude |
| | `s` | Tabs and session › | Tabs and session |
| | `l` | Panes, copy and notifications › | Panes, copy and notifications |
| Tools | `p` | Command palette | Command palette |
| | `?` | Quick question to Claude | Quick question |
| | `x` | Views: monitor, focus, popups, history › | Views |
| | `r` | Usage and reports › | Usage and reports |
| | `e` | Workstation: health, backups, notifications › | Health, backups, notifications |
| | `v` | Appearance and screensaver › | Appearance and screensaver |
| Help | `m` | Full manual (everything installed) | Full generated manual |
| | `h` | Keyboard shortcuts | Shortcuts |

### "Claude in this tab" (`c`)

| Section | Key | Label |
|---|---|---|
| Conversation | `c` `k` `b` `t` `T` `e` `B` | View context; Compact conversation; Go back to an earlier point; Transcript and reasoning; Tasks and subagents; Interrupt; Send to background |
| Model and mode | `9` | Model › (Fable, Opus, Sonnet, Haiku, Claude's own picker, and the automatic-routing switch) |
| | `p` | Permission mode / plan |
| | `S` | Protection › (see [Protection levels](#11-protection-levels)) |
| With other tabs | `x` | Send the neighboring pane to Claude |
| | `D` | Same text to several Claude tabs (broadcast) |
| | `Z` | Swarm: several Claudes in parallel on one goal (one worktree and branch per subtask) |
| | `E` | Export my work for another Claude (handoff package, `ws-traspaso`) |
| | `s`, `w` | Solo Claude in a new tab; Solo Claude in a new worktree |
| Account | `a` | Switch this tab to the personal / work account (same conversation) |
| | `n` | New tabs use: … (default account for new tabs) |
| | `f` | Always use the account of this tab for this project (pin the project) |
| | `L` | Log in to the personal account |
| | `+` | More Claude commands › (task list, editor, draft, fast mode, stop background subagents, redraw, `/status`, `/usage`, `/mcp`, `/effort`) |

### "Tabs and session" (`s`)

| Key | Label |
|---|---|
| `N` | Go by number… |
| `S` | Groups and tabs |
| `i` | Summary: what, where and where it left off |
| `*` | Add to favorites ★ / Remove from favorites ☆ |
| `E` | Tab label |
| `r`, `x` | Rename tab; Close tab |
| `s`, `R` | Save session now; Restore saved session |
| `u` | Recover tabs from an earlier save (`tmux-recuperar`) |
| `t` | Bring recent conversations into tmux |
| `G` | Save this tab as a template |

### "Panes, copy and notifications" (`l`)

| Key | Label |
|---|---|
| `v`, `h` | Split side by side; Split top and bottom |
| `z` | Zoom the pane |
| `M`, `T` | Main layout 65 %; Tiled |
| `!`, `x` | Move the pane to its own tab; Close this pane |
| `c`, `Y` | Scroll and copy; Copy the last 200 lines |
| `u` | Extract URLs, paths, IDs… |
| `N` | Notify me when it finishes |
| `L` | Live logs with alarm (Kubernetes, App Service, Docker, a file, your own command) |

### "Views" (`x`)

| Key | Label |
|---|---|
| `v` | Show / Hide compute monitor |
| `A` | Live subagents |
| `f` | Focus mode: 25/50/90 min, no notifications |
| `m`, `e` | Second monitor (same group, independent); Read-only mirror (screen sharing) |
| `g`, `P` | Persistent floating shell; Floating PowerShell |
| `h`, `y` | Search the history of all panes; Searchable history: turn on / turn off (off by default) |
| `r`, `V` | Record this pane / Stop recording; Open the recordings folder |

### "Usage and reports" (`r`)

| Key | Label | Command |
|---|---|---|
| `i` | Full report with Claude findings (usage, agents, MemPalace, recall) | `ws-informe --ia --ia-memoria --abrir` |
| `j` | Quick report, without Claude | `ws-informe --abrir` |
| `a` | Learn from me: facts for MemPalace (you choose) | `ws-aprender hechos` |
| `k` | Create "/" commands from what you repeat | `ws-aprender comandos` |
| `c` | Usage dashboard (browser) | `ws-telemetria abrir` |
| `r` | Tools: timings, errors and cost (7 days) | `ws-telemetria trazas` |
| `t` | Estimate per ticket (90 days) | `ws-telemetria estimar` |
| `s` | Report for last week | `ws-telemetria semana` |
| `p` | Budgets for the month | `ws-telemetria presupuestos` |
| `x` | Export CSV for Excel or Power BI | `ws-telemetria exportar` |

### "Workstation" (`e`)

| Key | Label | Command |
|---|---|---|
| `v` | Workstation check | `ws-check`, `ws-health` |
| `b`, `B` | Back up Claude now; Test the latest backup | `ws-backup-lite`; `ws-restore-lite` |
| `P` | Your personal configuration: sync | `ws-personal sync` |
| `R` | Restart Claude in all idle tabs (picks up the new configuration) | `tmux-claude-restart --todas` |
| `U` | Update the workstation from the kit | `ws-actualizar` |
| `Q` | Repo quality and security | `ws-gate repo-view` |
| `u` | Claude audit | `claude-report` |
| `z` | Switch Azure subscription | `tmux-az-sub` |
| `I` | Installed tools | `ws-tools` |
| `n` | Windows notifications: on / off | toggles `@cnotify` |
| `g`, `G` | Telegram: turn notifications on or off; Telegram: text replies on/off (PIN) | `ws-telegram alternar`; `ws-telegram texto alternar` |

### "Appearance and screensaver" (`v`)

| Key | Label |
|---|---|
| `o`, `c`, `a` | Dark theme; Light theme; Automatic: follows Windows |
| `t` | Claude theme in this tab (`/theme`) |
| `s` | Pick a scene from a list |
| `p`, `n` | Start it now; Next scene |
| `e` | Screensaver: on / off |

## 7. Status bar legend

The bar is at the top. On the left, the group name (hidden for `dev`) and the tabs; on the right, the menu button, the
watcher's traffic light, the Azure subscription, the git branch and the time.

### On each tab

| Mark | Meaning |
|---|---|
| `●` (colored) | Claude's state: blue thinking, orange tool, red needs you, green done, purple subagents. The current tab also shows the label |
| `◆3` | Three subagents running |
| `ctx 62%` / `62%` | Context used |
| `⏳` | No Claude activity for a while |
| `!` | Bell: something in the tab asked for attention |
| `[Z]` | A pane is zoomed |
| 🔒 / 🔓 | Protection level `completo` / `puro` |
| 🤖 before the name | Solo mode |
| `·P` after the name | The tab was switched to the personal account |
| `⏺` | The pane is being recorded |
| ✔ ✖ ●, `#12` ✓ ✎ 📝, `ABC-123` | CI passed / failed / running; pull request number, approved / changes requested / draft; ticket taken from the branch name |
| A label word | The tab's label (`Ctrl+b E`) |
| ★ | The tab's folder is a favorite (`Ctrl+b *` toggles it, `Ctrl+b F` lists them) |

### State labels

| Label | Meaning |
|---|---|
| 🧠 thinking 42s | Thinking |
| 🔧 Bash 2m | Running a tool, with its name |
| ✋ approve Bash 5m | A permission dialog is open: Claude waits for your approval |
| ❓ asking you 1m | Claude opened a question dialog |
| 👉 waiting for you 3m | The turn ended and Claude's last message asks you something or asks you to do something |
| 📦 compacting | Compacting the conversation |
| 🐝 3 agents 4m | Subagents working |
| ✔ done 12m ago | Finished, nothing pending |
| ⏳ stalled 11m | Thinking or running a tool with no events for 10 minutes |
| ⛔ interrupted | You pressed `Esc` |
| ✖ API error | The turn ended with an API error |

"waiting for you" is decided from the text of Claude's last message when the turn ends: it ends in a question, or it
asks you to run a command, decide, confirm or provide a value. `WS_TETOCA=0` turns it off, and those tabs then show
"done".

### Right side

| Segment | Meaning |
|---|---|
| `≡ menu` | Click to open the menu |
| `⚠ 2,5` | Tabs 2 and 5 wait for you: a permission or question dialog, "waiting for you", or an API error |
| `⏳ 3(12m)` | Tab 3 has had no activity for 12 minutes |
| `◉ $4.1/h` | Estimated spend of all sessions over the last 10 minutes, at API-equivalent prices. Green, yellow from 5 USD/h, red from 15 |
| `5h 82%` | Usage limit, when the plan exposes it |
| Subscription, branch, time | Active Azure subscription, branch of the tab's folder, clock |

Thresholds are tmux options: `@cwatch_remind` (3 min), `@cwatch_stall` (10 min), `@cburn_warn` (5), `@cburn_crit`
(15). Example: `tmux set -g @cwatch_stall 20`.

`Ctrl+b v` adds a second line with CPU, RAM and network sparklines, free space on `C:`, spend per hour and the count of
working, waiting and finished Claude sessions.

## 8. Finding the tab that needs you

| Tool | Shows |
|---|---|
| `⚠` in the bar | The tab numbers that wait for you |
| `Ctrl+b m`, then `g` | Jumps to the **next** tab that waits or is stalled, changing group if needed. Repeating it cycles through them |
| `Ctrl+b a` | "Active now": first what waits for you (✋ ❓ 👉 ✖), then what is working, then what finished in the last 15 minutes; all groups. Enter goes to the tab |
| `Alt+s` or `Ctrl+b f` | Tab search, ordered with the waiting tabs first |
| `Ctrl+b D` | Dashboard of every tab: state with its time, what it is doing, turn duration, model, context, cost, branch, uncommitted changes, label |
| Windows notification | Sent when a tab you are not looking at needs you or finishes a turn of at least 20 seconds. A tab with an open dialog is reminded every `@cwatch_remind` minutes; a "waiting for you" tab gets a single reminder |

## 9. Working with Claude in a tab

| Task | How |
|---|---|
| Give Claude the output of your tests or build | Run them in a side pane, then `Ctrl+b e` in Claude's pane. The last lines are redacted and pasted into the prompt without sending |
| Ask something without polluting the context | `Ctrl+b ?`. End the line with `+p` to include the last 60 lines of the pane. No tools, no saved session |
| Choose the model for a task | `cr "task"` classifies it, says which tier and why, and sends it after you confirm. `cr -t sonnet "task"` forces a tier; `cr --dry-run` only classifies |
| Change the tab's model | Menu → "Claude in this tab" → "Model". Only this tab changes |
| Be asked before a mismatched model is used | Automatic routing: when a rule in `~/.config/ws-ruteo/reglas.conf` says the task belongs to another tier, a popup offers `y` switch and send, `n` send as is, `x` return the text. No answer in 30 seconds sends with the current model. Toggle it in the "Model" submenu |
| Leave Claude working alone | Menu → "Claude in this tab" → "Solo Claude in a new tab" or "Solo Claude in a new worktree" |
| Run several Claudes on one goal | Menu → "Claude in this tab" → "Swarm: several Claudes in parallel on one goal". Claude proposes 2–6 independent subtasks, you edit and confirm, each gets its worktree, branch and tab. `tmux-enjambre integrar <id>` merges them into an integration branch; it never pushes |
| Send the same text to several tabs | Menu → "Claude in this tab" → "Same text to several Claude tabs" |
| Hand the work to another Claude | `ws-traspaso` (menu key `E`): a Markdown package with a summary, branch, changes, commits, diff, task list and touched files, saved and copied to the clipboard. `--conversacion` adds the transcript |
| Restart Claude so it picks up new settings | Menu → "Claude in this tab" → "Protection" → "Restart without changing the protection (resumes the conversation)", or for every tab `tmux-claude-restart --todas` |
| Be told when a long command ends | `Ctrl+b N` on the pane |

The routing rules match prompts typed in Spanish and in English; the Spanish expressions in `reglas.conf` are there on
purpose.

Documents: when Claude reads a PDF, Office file, `.csv`, `.rtf`, `.odt` or `.epub`, a hook converts it to Markdown
first (`ws-tomd`), in a sandbox without network.

Restart all tabs:

```bash
tmux-claude-restart --todas --lista             # shows what it would do: restart / busy / solo
tmux-claude-restart --todas                     # restarts idle tabs; each resumes its conversation
tmux-claude-restart --todas --tambien-ocupadas  # also interrupts tabs that are working
```

Tabs that are thinking, running a tool, compacting or showing a dialog are skipped by default. Each tab keeps its
protection level; tabs in solo mode are left as they are.

## 10. Accounts

The workstation runs two Claude accounts: `trabajo` (work, in `~/.claude`) and `personal` (in `~/.claude-personal`).
Each has its own login. Settings, hooks, agents and conversations are shared, so switching a tab continues the same
conversation.

### First-time setup of the personal account

```bash
claude-cuenta setup            # prepares ~/.claude-personal; does not touch ~/.claude
claude-cuenta login personal   # switch claude.ai to your personal organization in the browser first
claude-cuenta estado           # default account, organization of each login, pinned projects
```

### Daily use

The menu keys are in "Claude in this tab", section "Account".

| Task | Command | Menu key |
|---|---|---|
| Switch this tab to the other account | `claude-cuenta pestaña` | `a` |
| Choose the account for new tabs | `claude-cuenta usar trabajo`, `claude-cuenta usar personal` | `n` |
| Pin a project to an account | `claude-cuenta proyecto personal [folder]` | `f` (pins the project to this tab's account) |
| Unpin | `claude-cuenta proyecto quitar [folder]` | None |
| List pinned projects | `claude-cuenta proyectos` | None |
| Close only the personal session | `claude-cuenta logout personal` | None |
| Start one Claude with a given account | `claude-trabajo`, `claude-personal` (shell aliases) | None |

Rules:

- A pinned project covers its repository root, every subfolder and its `<repo>.wt/…` worktrees. Every new tab opened
  there uses the pinned account, whatever the default is.
- Without a pin, new tabs use the default account.
- A tab that was switched by hand keeps its account in that pane's shell; it shows `·P` after its name when it is on
  the personal account.
- The switch is refused when both logins belong to the same organization, because the usage would be charged to the
  wrong one.
- A tab in solo mode stays in solo mode after switching.

## 11. Protection levels

Each tab has its own level. Changing it restarts Claude in that tab and resumes the conversation; anything half done
in that turn is lost.

| Level | Menu key | What changes |
|---|---|---|
| Full (`completo`) 🔒 | `c` | Sandbox on with no way out: no unsandboxed commands and no excluded commands, so `az`, `gh`, `git push`, `kubectl` and similar run inside the sandbox, without network or credentials, and mostly fail. All kit rules stay |
| Normal (`normal`) | `n` | Your `~/.claude/settings.json` as it is: sandbox on, with the excluded commands that need network and credentials |
| Pure (`puro`) 🔓 | `p` | No sandbox and none of the kit's `allow`/`ask` rules: Claude asks as it would without the kit |
| Solo mode 🤖 | `s` | Claude in `auto` permission mode without the sandbox, to work alone. The `ask` rules still ask you |

In every level, including `puro` and solo mode, two things stay on: the `deny` rules (credential files, printing
secrets, bypassing the git gate) and the `guard.sh` hook (forced pushes, pushes to `main`, `--no-verify`, production
changes, secrets written to files). State, traces and notifications also keep working.

```bash
tmux-nivel completo            # current tab
tmux-nivel normal %12          # a given pane
tmux-nivel --comando puro      # prints the command Claude would be started with
tmux-solo esta | normal        # this tab into / out of solo mode
tmux-solo nueva [folder]       # new tab in solo mode
tmux-solo worktree [folder]    # new tab in a fresh worktree <repo>.wt/solo-<date>
```

In the "Protection" submenu, "Active rules (/permissions)" and "Sandbox status (/sandbox)" show what Claude actually
loaded. After a restart of the workstation, restored tabs are started again with `claude-resume`, that is, with your
normal settings.

When Claude reports a read-only file system or a blocked command, that is the sandbox or the guard working. Run the
command yourself with `!` or in a floating shell (`Ctrl+b g`).

Telegram never offers to run commands in a `puro` or solo-mode tab.

## 12. Reports and telemetry

Everything is computed and stored locally under `~/.local/share/ws-telemetria`. Costs are API-equivalent prices; a
subscription plan is not billed per token.

### Dashboard

```bash
ws-telemetria abrir      # regenerates and opens the dashboard in the Windows browser
ws-telemetria resumen    # today and 7 days, per project, in the terminal
```

The dashboard is regenerated about once a minute while tmux is running. It shows today, 7 and 30 days; trends over the
whole history; per project, model, session and tool; machine resources and network; the OpenTelemetry section "API,
permissions and active time" (API calls with typical duration, p95 and time to first token; errors by code; who decides
each permission; your active time and Claude's; hook time; compactions; subagents; MCP and skills); and the estimation
ratios.

### Report

```bash
ws-informe                  # last 30 days, HTML and Markdown
ws-informe --dias 14 --abrir
ws-informe --ia             # adds findings written by Claude from the aggregated metrics only
ws-informe --ia-memoria     # also reviews the memory store through its MCP server
ws-informe --json           # the measured data
```

Reports are written to `~/.local/share/ws-telemetria/informes/` and copied to `%UserProfile%\ws-telemetria\`.

**Estimation ratios** ("Ratios for estimating" in the dashboard, 30 days) appear in both the dashboard and the report:
your words and Claude's per turn, tokens per word, model and tool calls per turn, output speed, cost per turn, per
thousand words, per million tokens and per active hour, and CPU, disk and RAM per token and per turn. Each states its
sample size. The report also has an **estimation baseline** per project: active hours, turns, tokens, words, lines, CPU
and cost, with cost per hour and per 100 lines.

### Per ticket, per week, budgets

```bash
ws-telemetria estimar                       # active hours, turns, cost, lines, commits per ticket (90 days)
ws-telemetria estimar --por rama|proyecto   # grouped by branch or project
ws-telemetria estimar --csv ABC             # CSV, filtered
ws-telemetria semana                        # last week against the one before, Markdown
ws-telemetria presupuestos                  # month to date against ~/.config/ws-telemetria/presupuestos.conf
ws-telemetria trazas --dias 7               # tools: uses, time, errors, approximate cost
ws-telemetria exportar                      # CSV of turns, traces and estimation
ws-telemetria sql                           # DuckDB with the views `turnos` and `trazas`
```

The ticket comes from the branch name (`feature/ABC-123-…`).

### OpenTelemetry collector and hook timing

```bash
ws-otel estado               # running or not, port, signals stored today, folder
ws-otel resumen --dias 7     # counts per signal type and per event
ws-otel iniciar | detener    # start in the background / stop
ws-hooks                     # time in hooks per event, as measured by Claude Code
ws-hooks lista SessionStart  # configured hooks for an event
ws-hooks tiempo SessionStart -n 3   # runs each hook of the event separately, three times, and times it
```

Notes:

- The watcher starts the collector whenever tmux is running; you rarely need `iniciar`.
- A tab starts exporting when its Claude starts. After installing or changing the telemetry settings, restart the tabs
  (`tmux-claude-restart --todas`).
- The collector stores prompt, response and tool text with recognizable secrets masked. To store counts, timings and
  names only, the collector process must start with `WS_OTEL_CONTENIDO=0`: `ws-otel detener`, then
  `WS_OTEL_CONTENIDO=0 ws-otel iniciar`. The watcher restarts the collector from tmux's environment, so also set it
  there (`tmux set-environment -g WS_OTEL_CONTENIDO 0`) and in `~/.bashrc`.
- `ws-hooks tiempo` really executes the hooks, with a test session id and without a tmux pane. Events that block or
  modify tools are not run.

### Other

| Command | What it shows |
|---|---|
| `claude-report [days]` | Summary of the audit log: sessions, prompts, actions per repository and tool, blocked and denied actions |
| `ws-auditoria` | Read-only audit of the workstation by pillar, with a report |
| `tmux-enfoque 25` | Focus mode for 25 minutes: minimal bar, no Windows notifications |

## 13. Notifications and Telegram

Windows notifications are on by default; clicking one brings Windows Terminal to the front on that tab. Toggle them in
Menu → "Workstation" → "Windows notifications", or `tmux set -g @cnotify off`.

Telegram is optional:

```bash
ws-telegram configurar     # once: links your bot; the token goes to the Windows Credential Manager
ws-telegram estado         # configuration, service and recent events
ws-telegram prueba         # sends a test message
ws-telegram encender | apagar
ws-telegram texto on       # free-text replies, protected by a 4–6 digit PIN (off by default)
ws-telegram olvidar        # deletes token, chat and state
```

| From the phone | How |
|---|---|
| Answer a permission or question dialog | Tap one of the buttons (the dialog's options, or "⎋ Cancel"). Codes are single-use and expire in 10 minutes |
| Reply with text to an open question | Reply to the message starting with your PIN, then a space and the answer. Requires `ws-telegram texto on` |
| Run a command Claude proposed | Tap "▶ Run" under the command, then reply with your PIN. Dangerous commands arrive as text only, to be run at the PC |

See the [threat model](THREAT_MODEL.md#telegram-remote-control) for what this channel does and does not protect.

## 14. Appearance and screensaver

```bash
tmux-theme oscuro | claro | auto    # dark, light; auto follows Windows
tmux-saver --escena oceano          # show a scene now; any key returns
tmux-saver --fijar oceano           # keep one scene; `aleatoria` picks a different one each time
tmux-saver --toggle                 # turn the screensaver on or off
tmux-escena                         # pick from a list (Menu → "Appearance and screensaver" → s)
tmux-arte --lista                   # scenes this machine can draw (--todas: all)
```

The screensaver (`tmux-saver`) appears after 10 minutes without touching the terminal (`minutos=` in
`~/.config/tmux-claude/apariencia`) and any key dismisses it; tabs keep working behind it. It does not appear while a
permission dialog is open. All scenes are drawn by `tmux-arte`.

| Scenes | Names | Needs |
|---|---|---|
| ASCII art (13) | `cumbres`, `aurora`, `nevada`, `velero`, `peces`, `tuberias`, `batalla`, `fogata`, `cerezo`, `lluvia`, `galaxia`, `nebulosa`, `hiperespacio` | Nothing extra |
| Shading engine (12) | `oceano`, `planeta`, `dona`, `lava`, `vuelo`, `boreal`, `nubes`, `agujero`, `estanque`, `fuego`, `tunel`, `fractal` | `python3-numpy`; without it they are left out of the random choice |
| `galeria` | Your images and animated GIFs (`png`, `jpg`, `gif`, `webp`) | `chafa`, and files in `~/.config/tmux-claude/galeria` |

```bash
ws-tools install numpy chafa
```

## 15. Backups and restore

Nothing here needs to be run by hand in normal use; these are the commands for checking and recovering.

| What | Where it goes | Command |
|---|---|---|
| tmux session (tabs, panes) | `~/.local/share/tmux/resurrect`, copied to `%UserProfile%\.tmux-resurrect-backup` | automatic; `Ctrl+b Ctrl+s` to force |
| Conversations and audit log | `%UserProfile%\.claude-wsl-backup` | automatic (`ws-backup`) |
| Light backup of Claude data, tmux saves and an inventory for reinstalling; never credentials | `%UserProfile%\WSL-Backups\lite` (14 kept) | `ws-backup-lite` |
| Encrypted copy of the light backup | OneDrive | `ws-respaldo-nube configurar` once, then automatic |
| Personal configuration | Your private repository | `ws-personal sync` |

```bash
ws-restore-lite                 # tests the latest backup in a temporary folder; does not touch $HOME
ws-restore-lite --restaurar     # restores into $HOME (asks; refuses with Claude open; keeps differing files)
ws-respaldo-nube probar         # decrypts the latest cloud copy into a temporary folder and checks it
ws-respaldo-nube bajar          # decrypts a cloud copy to restore it with ws-restore-lite
tmux-recuperar                  # lists tmux saves and restores the one you choose
```

Recovering a machine: new Ubuntu → `bash install.sh` → `ws-restore-lite --restaurar` → `ws-personal restaurar` →
logins (`claude auth login`, `az login`, `gh auth login`). The step-by-step version is in the
[runbook](runbook.md#17-recovery).

## 16. Updating from the kit

```bash
ws-update            # Claude Code, tmux plugins, system packages
ws-actualizar        # the workstation itself, from the kit's repository
ws-actualizar --revisar   # only says whether there is a new version
```

`ws-actualizar` pulls with `--ff-only`, runs `install.sh` (every changed file is backed up as `*.bak.<date>`) and then
`ws-test`. If the tests fail it goes back to the previous commit and reinstalls. It does nothing when the kit folder
has uncommitted changes or unpushed commits.

After an update:

```bash
tmux source-file ~/.tmux.conf     # or Ctrl+b r
tmux-claude-restart --todas       # running Claude sessions pick up new settings, hooks and telemetry
```

Restarting Claude in all tabs skips the tabs that are working or have a dialog open, keeps each tab's protection
level and leaves solo-mode tabs alone; `--lista` shows what it would do and `--tambien-ocupadas` includes busy tabs.

If you maintain the kit, the reverse direction is `bash export.sh` (captures what is installed into `files/`), review
the diff, `ws-verify`, commit.

## 17. Command reference

### Commands by task

| Task | Commands | Section |
|---|---|---|
| Open folders and tabs | `tw`, `two`, `twt`, `tp`, `tmux-open`, `tmux-traer`, `tmux-favoritos` | [4](#4-opening-repositories) |
| Model per task | `cr` | [9](#9-working-with-claude-in-a-tab) |
| Restart Claude | `tmux-claude-restart` | [9](#9-working-with-claude-in-a-tab) |
| Swarm and handoff | `tmux-enjambre`, `ws-traspaso` | [9](#9-working-with-claude-in-a-tab) |
| Accounts | `claude-cuenta`, `claude-trabajo`, `claude-personal` | [10](#10-accounts) |
| Protection | `tmux-nivel`, `tmux-solo` | [11](#11-protection-levels) |
| Dashboard and reports | `ws-telemetria`, `ws-informe`, `ws-otel`, `ws-hooks`, `claude-report`, `ws-auditoria` | [12](#12-reports-and-telemetry) |
| Focus mode | `tmux-enfoque` | [12](#12-reports-and-telemetry) |
| Telegram | `ws-telegram` | [13](#13-notifications-and-telegram) |
| Theme and screensaver | `tmux-theme`, `tmux-saver`, `tmux-escena`, `tmux-arte` | [14](#14-appearance-and-screensaver) |
| Backups | `ws-backup-lite`, `ws-restore-lite`, `ws-respaldo-nube`, `tmux-recuperar`, `ws-personal` | [15](#15-backups-and-restore) |
| Updates and health | `ws-update`, `ws-actualizar`, `ws-check`, `ws-health`, `ws-verify`, `ws-test`, `ws-tools` | [16](#16-updating-from-the-kit) |
| Manual and shortcuts | `ws-menus --ver`, `Ctrl+b h` | [5](#5-key-bindings) |
| PowerShell | `dev`, `devo`, `devdash`, `devagents`, `devsave`, `devcheck`, `devsnapshot`, `devrestoretest` | [3](#3-first-run) |

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `WS_TETOCA` | `1` | `0` disables the "waiting for you" state |
| `WS_OTEL_CONTENIDO` | `1` | `0` makes the collector store no text or identity |
| `WS_OTEL_PUERTO` | `14318` | Collector port (the endpoints in `settings.json` must match) |
| `WS_OTEL_RETENCION_DIAS` | `395` | Days the collector keeps its files |
| `WS_GALERIA` | `~/.config/tmux-claude/galeria` | Folder for the `galeria` scene |
| `WS_GALERIA_SEG` | `25` | Seconds per image |
| `WS_GALERIA_SIMBOLOS` | Not set | `ascii` to use letters and signs only |
| `WS_ARTE_COLOR` | auto | `24` or `256` forces the color depth of the scenes |
| `WS_PREGUNTA_MODELO` | Haiku | Model for the quick question (`sonnet`, `opus`) |
| `GUARD_PROD_REGEX` | `prod\|prd\|produccion` | What the guard treats as a production subscription or context |
| `CLAUDE_NOTIFY_MIN_SECS` | `20` | Minimum turn length for a "finished" notification |
| `AI_SHELL_GHOST` | `1` | `0` turns off the grey AI suggestion in the shell |

### tmux options

| Option | Default | Effect |
|---|---|---|
| `@cwatch_remind` | 3 (minutes) | Interval between reminders for a tab with an open dialog |
| `@cwatch_stall` | 10 (minutes) | Time without events after which a tab counts as stalled |
| `@cburn_warn` | 5 (USD per hour) | Spend rate shown in yellow |
| `@cburn_crit` | 15 (USD per hour) | Spend rate shown in red |
| `@cnotify` | on | `off` turns Windows notifications off |
| `@cruteo` | on | `off` turns automatic model routing off in all tabs |
| `@rama_barra` | on | `off` hides CI, pull request and ticket in the bar |

## 18. Troubleshooting

| Symptom | Action |
|---|---|
| Tabs are missing after a restart | Menu → "Tabs and session" → "Recover tabs from an earlier save" (`tmux-recuperar`) |
| Claude does not resume the conversation | In the tab: `claude -c` or `claude -r` |
| Something broke after `install.sh` | Restore the file's `*.bak.<date>` |
| `export.sh` refuses because of "possible secrets" | Move the secret to a vault; a detection pattern goes in `secrets-allow.txt` after review |
| The gate blocks a commit | Fix what is marked; per repository, from your own shell: `git config ws.gate.skip …` |
| Claude reports a read-only file system | That is the sandbox; run the command yourself or add a justified exclusion |
| Open tabs do not send OpenTelemetry data | Export starts when Claude starts: restart the tab (`tmux-claude-restart --todas`) |
| WSL is damaged | New Ubuntu → `install.sh` → `ws-restore-lite --restaurar` → logins |

The full step-by-step guide, with causes, is [runbook.md](runbook.md).

## 19. Known limitations

- Windows with WSL2 only.
- Command names, flags and some stored values are still Spanish words, pending a rename.
- Hook-based traces and OpenTelemetry data exist only from the day the workstation is installed; cost and token
  history is rebuilt from the transcripts Claude Code keeps.
- OpenTelemetry traces are a beta feature of Claude Code and may change.
- A tab that was already open when the telemetry settings changed emits nothing until its Claude is restarted.
- Changing a tab's protection level restarts Claude; anything half done in that turn is lost.
- After a restart of the workstation, restored tabs start with your normal settings, whatever level they had.
- The lock icon in the bar comes from a tmux option set when the level is applied; a Claude started by hand in a pane
  does not update it.
- Costs are API-equivalent prices, not what a subscription plan bills.
