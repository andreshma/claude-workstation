# Usage

How to install the workstation and use it day to day. For how the pieces fit see [architecture.md](architecture.md);
for what goes wrong and how to recover see [runbook.md](runbook.md).

The interface and every command, option and stored value are in English. Menu labels and status labels are quoted
exactly as the screen shows them; commands are written as you type them. If you come from a version before 3.0, whose
commands had Spanish names, read [Upgrading from 2.x names](#18-upgrading-from-2x-names). `Ctrl+b` is the tmux prefix:
press it, release, then press the key.

On the workstation itself, two things are always up to date because they read what is installed:

| What | How |
|---|---|
| Cheat sheet of daily shortcuts | `Ctrl+b h` |
| Full manual generated from the installed menus, key bindings and commands | `ws-menus --show` |

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
- [15. Language](#15-language)
- [16. Backups and restore](#16-backups-and-restore)
- [17. Updating from the kit](#17-updating-from-the-kit)
- [18. Upgrading from 2.x names](#18-upgrading-from-2x-names)
- [19. Command reference](#19-command-reference)
- [20. Troubleshooting](#20-troubleshooting)
- [21. Known limitations](#21-known-limitations)

## 1. Requirements

| Requirement | Detail |
|---|---|
| Operating system | Windows 11 with WSL2 (Ubuntu 24.04) |
| tmux | 3.3 or newer |
| Claude Code | Installed and logged in |
| Base packages | `tmux git jq fzf gh bubblewrap socat rsync shellcheck` |
| Optional: `python3-numpy` | 12 of the 25 screensaver scenes use a numpy shading engine |
| Optional: `chafa` | The `gallery` screensaver scene |

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
   ws-tools install base cloud quality
   ws-check && ws-health
   ```

4. On Windows, run `windows\install.ps1` from PowerShell to add the terminal profile and shortcuts.

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
| `--remove-shims` | Only delete the wrappers left under the command names used before 3.0, then exit (see [Upgrading from 2.x names](#18-upgrading-from-2x-names)) |

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

PowerShell helpers installed by `windows\install.ps1`:

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
| Open a favorite folder | `Ctrl+b F` (the finder on its favorites view). Enter goes to the tab or opens the folder with Claude in its group; `Ctrl+X` removes it from the list |
| Resume a recent conversation of any project | `Ctrl+b j` (the finder on its recent view). Enter goes to its tab, or opens one in its group and resumes that conversation |
| Bring recent conversations that have no tab | Menu → "Tabs and session" → "Bring recent conversations into tmux" (`tmux-bring`) |

The picker lists the folders under the roots in `~/.config/tmux-claude/roots.txt`, one per line as
`label|depth|path`. The label is also the **group**: each group is its own tmux session, and a new tab is created in
the session of its group. `Alt+↑/↓` switches group and `Ctrl+b S` lists all groups with their tabs. To keep everything
in one session, set `groups=off` in `~/.config/tmux-claude/settings`.

`roots.txt` comes from the kit and is replaced on every install. Put your own roots in
`~/.config/ws-local/roots.txt`, in the same format; the kit never touches that file. A folder outside every root
opens in the group `other`.

A tab opens Claude with `claude --continue` when the folder already has conversations, and plain `claude` otherwise.

Favorites belong to the folder, not to the tab: `Ctrl+b *` adds or removes the current tab's folder, the tab shows a
★ in the status bar, and the mark survives closing the tab and restarting tmux. The list is kept in
`~/.config/tmux-claude/favorites`. `tmux-open --dir <folder>` opens a folder without asking.

## 5. Key bindings

### Without prefix

| Keys | Action |
|---|---|
| `Alt+1` … `Alt+9` | Go to tab 1–9 |
| `Alt+←` / `Alt+→` | Previous / next tab |
| `Alt+0` | Last used tab |
| `Alt+s` | Finder: tabs, active, favorites, recent |
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
| `f` | Finder: every open tab, with the ones that wait for you first (see [8](#8-finding-the-tab-that-needs-you)) |
| `a` | Finder on the active view: tabs that are active now, across groups |
| `j` | Finder on the recent view: recent Claude conversations of all projects, open or not |
| `D` | Tab dashboard |
| `A` | Live subagents (`v` shows a subagent's transcript) |
| `i` | Summary of the tab: where it is, what it is doing, where it stopped |
| `S` | All groups with their tabs |
| `*` | Add the tab's folder to the favorites, or remove it |
| `F` | Finder on the favorites view: favorite folders, open or not |
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
| Go to | `g` | Go to the next one waiting for you or stalled for a while | Jump to the next tab that waits for you or is stalled |
| | `f` | Find: tabs, active, favorites, recent | The finder (`tmux-find`); its views are also on `Ctrl+b a`, `F` and `j` |
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
| Conversation | `c` `k` `b` `t` `e` `B` | View context; Compact conversation; Go back to an earlier point; Transcript and reasoning; Interrupt; Send to background |
| Tasks and subagents | `T` `d` `A` `K` | Tasks and subagents (`/tasks`); Claude task list (`Ctrl+T`); Live subagents (`Ctrl+b A`); Stop background subagents |
| Model and mode | `9` | Model › (Fable, Opus, Sonnet, Haiku, Claude's own picker, and the automatic-routing switch) |
| | `p` | Permission mode / plan |
| | `S` | Protection › (levels and solo mode: this tab, a new tab, a new worktree; see [Protection levels](#11-protection-levels)) |
| With other tabs | `x` | Send the neighboring pane to Claude |
| | `D` | Same text to several Claude tabs (broadcast) |
| | `Z` | Swarm: several Claudes in parallel on one goal (one worktree and branch per subtask) |
| | `E` | Export my work for another Claude (handoff package, `ws-handoff`) |
| Account | `a` | Switch this tab to the personal / work account (same conversation) |
| | `n` | New tabs use: … (default account for new tabs) |
| | `f` | Always use the account of this tab for this project (pin the project) |
| | `L` | Log in to the personal account |
| | `+` | More Claude commands › (editor, draft, fast mode, redraw, `/status`, `/usage`, `/mcp`, `/effort`) |

### "Tabs and session" (`s`)

| Key | Label |
|---|---|
| `N` | Go by number… |
| `S` | Groups and tabs |
| `i` | Summary: what, where and where it left off |
| `*` | Add to favorites ★ / Remove from favorites ☆ |
| `E` | Tab label |
| `r`, `x` | Rename tab; Close tab |
| `s`, `R` | Save session now; Restore tabs from a save… (`tmux-recover`: lists the saves, the latest first) |
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
| `f` | Focus mode: 25/50/90 min, no notifications |
| `m`, `e` | Second monitor (same group, independent); Read-only mirror (screen sharing) |
| `g`, `P` | Persistent floating shell; Floating PowerShell |
| `h`, `y` | Search the history of all panes; Searchable history: turn on / turn off (off by default) |
| `r`, `V` | Record this pane / Stop recording; Open the recordings folder |

### "Usage and reports" (`r`)

| Key | Label | Command |
|---|---|---|
| `i` | Full report with Claude findings (usage, agents, MemPalace, recall) | `ws-report --ai --ai-memory --open` |
| `j` | Quick report, without Claude | `ws-report --open` |
| `a` | Learn from me: facts for MemPalace (you choose) | `ws-learn facts` |
| `k` | Create "/" commands from what you repeat | `ws-learn commands` |
| `c` | Usage dashboard (browser) | `ws-telemetry open` |
| `r` | Tools: timings, errors and cost (7 days) | `ws-telemetry traces` |
| `t` | Estimate per ticket (90 days) | `ws-telemetry estimate` |
| `s` | Report for last week | `ws-telemetry week` |
| `p` | Budgets for the month | `ws-telemetry budgets` |
| `x` | Export CSV for Excel or Power BI | `ws-telemetry export` |

### "Workstation" (`e`)

| Key | Label | Command |
|---|---|---|
| `v` | Workstation check | `ws-check`, `ws-health` |
| `b`, `B` | Back up Claude now; Test the latest backup | `ws-backup-lite`; `ws-restore-lite` |
| `P` | Your personal configuration: sync | `ws-personal sync` |
| `R` | Restart Claude in all idle tabs (picks up the new configuration) | `tmux-claude-restart --all` |
| `U` | Update the workstation from the kit | `ws-kit-update` |
| `Q` | Repo quality and security | `ws-gate repo-view` |
| `u` | Claude audit | `claude-report` |
| `z` | Switch Azure subscription | `tmux-az-sub` |
| `I` | Installed tools | `ws-tools` |
| `n` | Windows notifications: on / off | toggles `@cnotify` |
| `g`, `G` | Telegram: turn notifications on or off; Telegram: text replies on/off (PIN) | `ws-telegram toggle`; `ws-telegram text toggle` |
| `l` | Language of prompts and reports: English / Spanish (switch) | `ws-lang --toggle` |

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
| 🔒 / 🔓 | Protection level `full` / `bare` |
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
asks you to run a command, decide, confirm or provide a value. `WS_YOURTURN=0` turns it off, and those tabs then show
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
| `Alt+s` or `Ctrl+b f` | The finder on its view **all**: every open tab of every group, ordered with the waiting tabs first |
| `Ctrl+b a` | The finder on its view **active**: first what waits for you (✋ ❓ 👉 ✖), then what is working, then what finished in the last 15 minutes; it refreshes itself every 3 seconds |
| `Ctrl+b F` | The finder on its view **favorites**: favorite folders, open or not |
| `Ctrl+b j` | The finder on its view **recent**: Claude conversations of the last 7 days from all projects, open or not |
| `Ctrl+b D` | Dashboard of every tab: state with its time, what it is doing, turn duration, model, context, cost, branch, uncommitted changes, label |
| Windows notification | Sent when a tab you are not looking at needs you or finishes a turn of at least 20 seconds. A tab with an open dialog is reminded every `@cwatch_remind` minutes; a "waiting for you" tab gets a single reminder |

The finder (`tmux-find`) is one list with four views and one pane on the right. For an open tab the pane shows its
live screen; for a folder or a conversation without a tab it shows the conversation: your latest requests and Claude's
last answer, redacted. You can answer a tab from the list without going to it.

| Key in the finder | Action |
|---|---|
| `Tab` / `Shift+Tab` | Next / previous view |
| `Alt+1` … `Alt+4` | View all, active, favorites, recent |
| `Enter` | Open tab: go to it. Favorite folder without a tab: open it. Conversation without a tab: open a tab in its group and resume that conversation |
| `Ctrl+S` | Quick reply: type one line and it is sent to that tab's Claude; an empty line cancels. What was typed in Claude's input box is cleared first, unless Claude is working (then the line stays queued) |
| `Alt+Y` / `Alt+N` | Approve (option 1) / reject (Escape) the permission dialog of that tab. Only when the tab is in the "approve" state |
| `Ctrl+O` | Open here: use the tab inside the finder window, without moving your own view. `Ctrl+b d` comes back to the list |
| `Ctrl+R` | Refresh |
| `Ctrl+X` | Favorites view: remove the folder from the favorites |
| `Ctrl+Y` | Recent view: copy the command that resumes the conversation |

"Open here" shows the tab through a temporary tmux session linked to the tab's group, removed when you leave. While
it is open, the tab takes the size of the finder window.

## 9. Working with Claude in a tab

| Task | How |
|---|---|
| Give Claude the output of your tests or build | Run them in a side pane, then `Ctrl+b e` in Claude's pane. The last lines are redacted and pasted into the prompt without sending |
| Ask something without polluting the context | `Ctrl+b ?`. End the line with `+p` to include the last 60 lines of the pane. No tools, no saved session |
| Choose the model for a task | `cr "task"` classifies it, says which tier and why, and sends it after you confirm. `cr -t sonnet "task"` forces a tier; `cr --dry-run` only classifies |
| Change the tab's model | Menu → "Claude in this tab" → "Model". Only this tab changes |
| Be asked before a mismatched model is used | Automatic routing: when a rule in `~/.config/ws-routing/rules.conf` says the task belongs to another tier, a popup offers `y` switch and send, `n` send as is, `x` return the text. No answer in 30 seconds sends with the current model. Toggle it in the "Model" submenu |
| Leave Claude working alone | Menu → "Claude in this tab" → "Protection" → "Solo Claude in a new tab" or "Solo Claude in a new worktree" |
| Run several Claudes on one goal | Menu → "Claude in this tab" → "Swarm: several Claudes in parallel on one goal". Claude proposes 2–6 independent subtasks, you edit and confirm, each gets its worktree, branch and tab. `tmux-swarm integrate <id>` merges them into an integration branch; it never pushes |
| Send the same text to several tabs | Menu → "Claude in this tab" → "Same text to several Claude tabs" |
| Hand the work to another Claude | `ws-handoff` (menu key `E`): a Markdown package with a summary, branch, changes, commits, diff, task list and touched files, saved and copied to the clipboard. `--conversation` adds the transcript |
| Restart Claude so it picks up new settings | Menu → "Claude in this tab" → "Protection" → "Restart without changing the protection (resumes the conversation)", or for every tab `tmux-claude-restart --all` |
| Be told when a long command ends | `Ctrl+b N` on the pane |

The routing rules in `rules.conf` match prompts typed in English. With `ws-lang es` the Spanish expressions of
`rules.es.conf` are matched as well (see [Language](#15-language)).

Documents: when Claude reads a PDF, Office file, `.csv`, `.rtf`, `.odt` or `.epub`, a hook converts it to Markdown
first (`ws-tomd`), in a sandbox without network.

Restart all tabs:

```bash
tmux-claude-restart --all --list             # shows what it would do: restart / busy / solo
tmux-claude-restart --all                     # restarts idle tabs; each resumes its conversation
tmux-claude-restart --all --include-busy  # also interrupts tabs that are working
```

Tabs that are thinking, running a tool, compacting or showing a dialog are skipped by default. Each tab keeps its
protection level; tabs in solo mode are left as they are.

## 10. Accounts

The workstation runs two Claude accounts: `work` (in `~/.claude`) and `personal` (in `~/.claude-personal`).
Each has its own login. Settings, hooks, agents and conversations are shared, so switching a tab continues the same
conversation.

### First-time setup of the personal account

```bash
claude-account setup            # prepares ~/.claude-personal; does not touch ~/.claude
claude-account login personal   # switch claude.ai to your personal organization in the browser first
claude-account status           # default account, organization of each login, pinned projects
```

### Daily use

The menu keys are in "Claude in this tab", section "Account".

| Task | Command | Menu key |
|---|---|---|
| Switch this tab to the other account | `claude-account tab` | `a` |
| Choose the account for new tabs | `claude-account use work`, `claude-account use personal` | `n` |
| Pin a project to an account | `claude-account project personal [folder]` | `f` (pins the project to this tab's account) |
| Unpin | `claude-account project remove [folder]` | None |
| List pinned projects | `claude-account projects` | None |
| Close only the personal session | `claude-account logout personal` | None |
| Start one Claude with a given account | `claude-work`, `claude-personal` (shell aliases) | None |

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
| Full (`full`) 🔒 | `c` | Sandbox on with no way out: no unsandboxed commands and no excluded commands, so `az`, `gh`, `git push`, `kubectl` and similar run inside the sandbox, without network or credentials, and mostly fail. All kit rules stay |
| Normal (`normal`) | `n` | Your `~/.claude/settings.json` as it is: sandbox on, with the excluded commands that need network and credentials |
| Pure (`bare`) 🔓 | `p` | No sandbox and none of the kit's `allow`/`ask` rules: Claude asks as it would without the kit |
| Solo mode 🤖 | `s` | Claude in `auto` permission mode without the sandbox, to work alone. The `ask` rules still ask you. `t` starts it in a new tab and `w` in a new worktree |

In every level, including `bare` and solo mode, two things stay on: the `deny` rules (credential files, printing
secrets, bypassing the git gate) and the `guard.sh` hook (forced pushes, pushes to `main`, `--no-verify`, production
changes, secrets written to files). State, traces and notifications also keep working.

```bash
tmux-level full                # current tab
tmux-level normal %12          # a given pane
tmux-level --command bare      # prints the command Claude would be started with
tmux-solo this | normal        # this tab into / out of solo mode
tmux-solo new [folder]         # new tab in solo mode
tmux-solo worktree [folder]    # new tab in a fresh worktree <repo>.wt/solo-<date>
```

In the "Protection" submenu, "Active rules (/permissions)" and "Sandbox status (/sandbox)" show what Claude actually
loaded. After a restart of the workstation, restored tabs are started again with `claude-resume`, that is, with your
normal settings.

When Claude reports a read-only file system or a blocked command, that is the sandbox or the guard working. Run the
command yourself with `!` or in a floating shell (`Ctrl+b g`).

Telegram never offers to run commands in a `bare` or solo-mode tab.

## 12. Reports and telemetry

Everything is computed and stored locally under `~/.local/share/ws-telemetry`. Costs are API-equivalent prices; a
subscription plan is not billed per token.

### Dashboard

```bash
ws-telemetry open       # regenerates and opens the dashboard in the Windows browser
ws-telemetry summary    # today and 7 days, per project, in the terminal
```

The dashboard is regenerated about once a minute while tmux is running. It shows today, 7 and 30 days; trends over the
whole history; per project, model, session and tool; machine resources and network; the OpenTelemetry section "API,
permissions and active time" (API calls with typical duration, p95 and time to first token; errors by code; who decides
each permission; your active time and Claude's; hook time; compactions; subagents; MCP and skills); and the estimation
ratios.

### Report

```bash
ws-report                  # last 30 days, HTML and Markdown
ws-report --days 14 --open
ws-report --ai             # adds findings written by Claude from the aggregated metrics only
ws-report --ai-memory     # also reviews the memory store through its MCP server
ws-report --json           # the measured data
```

Reports are written to `~/.local/share/ws-telemetry/reports/` as `report-YYYY-MM-DD.html` and `.md`, and copied to
`%UserProfile%\ws-telemetry\`.

**Estimation ratios** ("Ratios for estimating" in the dashboard, 30 days) appear in both the dashboard and the report:
your words and Claude's per turn, tokens per word, model and tool calls per turn, output speed, cost per turn, per
thousand words, per million tokens and per active hour, and CPU, disk and RAM per token and per turn. Each states its
sample size. The report also has an **estimation baseline** per project: active hours, turns, tokens, words, lines, CPU
and cost, with cost per hour and per 100 lines.

### Per ticket, per week, budgets

```bash
ws-telemetry estimate                      # active hours, turns, cost, lines, commits per ticket (90 days)
ws-telemetry estimate --by branch|project  # grouped by branch or project
ws-telemetry estimate --csv ABC            # CSV, filtered
ws-telemetry week                          # last week against the one before, Markdown
ws-telemetry budgets                       # month to date against ~/.config/ws-telemetry/budgets.conf
ws-telemetry traces --days 7               # tools: uses, time, errors, approximate cost
ws-telemetry export                        # CSV of turns, traces and estimation
ws-telemetry sql                           # DuckDB with the views `turns` and `traces`
```

The ticket comes from the branch name (`feature/ABC-123-…`).

### OpenTelemetry collector and hook timing

```bash
ws-otel status               # running or not, port, signals stored today, folder
ws-otel summary --days 7     # counts per signal type and per event
ws-otel start | stop         # start in the background / stop
ws-hooks                     # time in hooks per event, as measured by Claude Code
ws-hooks list SessionStart   # configured hooks for an event
ws-hooks time SessionStart -n 3   # runs each hook of the event separately, three times, and times it
```

Notes:

- The watcher starts the collector whenever tmux is running; you rarely need `start`.
- A tab starts exporting when its Claude starts. After installing or changing the telemetry settings, restart the tabs
  (`tmux-claude-restart --all`).
- The collector stores prompt, response and tool text with recognizable secrets masked. To store counts, timings and
  names only, the collector process must start with `WS_OTEL_CONTENT=0`: `ws-otel stop`, then
  `WS_OTEL_CONTENT=0 ws-otel start`. The watcher restarts the collector from tmux's environment, so also set it
  there (`tmux set-environment -g WS_OTEL_CONTENT 0`) and in `~/.bashrc`.
- `ws-hooks time` really executes the hooks, with a test session id and without a tmux pane. Events that block or
  modify tools are not run.

### Other

| Command | What it shows |
|---|---|
| `claude-report [days]` | Summary of the audit log: sessions, prompts, actions per repository and tool, blocked and denied actions |
| `ws-audit` | Read-only audit of the workstation by pillar, with a report |
| `tmux-focus 25` | Focus mode for 25 minutes: minimal bar, no Windows notifications |

## 13. Notifications and Telegram

Windows notifications are on by default; clicking one brings Windows Terminal to the front on that tab. Toggle them in
Menu → "Workstation" → "Windows notifications", or `tmux set -g @cnotify off`.

Telegram is optional:

```bash
ws-telegram setup          # once: links your bot; the token goes to the Windows Credential Manager
ws-telegram status         # configuration, service and recent events
ws-telegram test           # sends a test message
ws-telegram on | off
ws-telegram text on        # free-text replies, protected by a 4–6 digit PIN (off by default)
ws-telegram forget         # deletes token, chat and state
```

| From the phone | How |
|---|---|
| Answer a permission or question dialog | Tap one of the buttons (the dialog's options, or "⎋ Cancel"). Codes are single-use and expire in 10 minutes |
| Reply with text to an open question | Reply to the message starting with your PIN, then a space and the answer. Requires `ws-telegram text on` |
| Run a command Claude proposed | Tap "▶ Run" under the command, then reply with your PIN. Dangerous commands arrive as text only, to be run at the PC |

See the [threat model](THREAT_MODEL.md#telegram-remote-control) for what this channel does and does not protect.

## 14. Appearance and screensaver

```bash
tmux-theme dark | light | auto      # auto follows Windows
tmux-saver --scene ocean            # show a scene now; any key returns
tmux-saver --pin ocean              # keep one scene; `random` picks a different one each time
tmux-saver --toggle                 # turn the screensaver on or off
tmux-scene                          # pick from a list (Menu → "Appearance and screensaver" → s)
tmux-art --list                     # scenes this machine can draw (--all: all)
```

The screensaver (`tmux-saver`) appears after 10 minutes without touching the terminal (`minutes=` in
`~/.config/tmux-claude/appearance`) and any key dismisses it; tabs keep working behind it. It does not appear while a
permission dialog is open. All scenes are drawn by `tmux-art`.

| Scenes | Names | Needs |
|---|---|---|
| ASCII art (13) | `peaks`, `aurora`, `snowfall`, `sailboat`, `fish`, `pipes`, `battle`, `campfire`, `cherry`, `rain`, `galaxy`, `nebula`, `hyperspace` | Nothing extra |
| Shading engine (12) | `ocean`, `planet`, `donut`, `lava`, `flight`, `boreal`, `clouds`, `blackhole`, `pond`, `fire`, `tunnel`, `fractal` | `python3-numpy`; without it they are left out of the random choice |
| `gallery` | Your images and animated GIFs (`png`, `jpg`, `gif`, `webp`) | `chafa`, and files in `~/.config/tmux-claude/gallery` |

```bash
ws-tools install numpy chafa
```

## 15. Language

The interface is English only. What you choose is which languages the kit **recognizes** in the prompts you type and in
Claude's answers, and the language Claude is asked to write reports and handoffs in.

| Setting | Recognized in prompts and answers | Claude writes reports and handoffs in |
|---|---|---|
| `en` (default on a new installation) | English | English |
| `es` (written by the installer when it migrates a 2.x installation) | English and Spanish | Spanish |

```bash
ws-lang            # shows the current language and what it affects
ws-lang es         # English and Spanish
ws-lang en         # English only
ws-lang --get      # prints only the code, for scripts
ws-lang --name     # prints English or Spanish
ws-lang --toggle   # switches between the two (used by the menu)
```

In the Workstation menu (`Ctrl+b m`, then `e`), the entry "Language of prompts and reports" (`l`) shows the current
language and switches it. The choice is saved in `~/.config/tmux-claude/lang`; the environment variable
`WS_LANG=en|es` overrides it. Every script reads the setting each time, so a change needs no restart. Anything other
than `es` means `en`.

What the language changes:

| Feature | Effect of `es` |
|---|---|
| Subagent hint (`intent-route.sh`) | Design, security and search requests typed in Spanish are recognized |
| Model routing (`cr` and the routing hook) | A rule matches when its English expression in `rules.conf` or its Spanish one in `rules.es.conf` matches |
| "waiting for you" (`tmux-state.sh`) and Windows notifications (`win-notify.sh`) | Requests and questions Claude writes in Spanish are recognized, including a question opened with `¿` |
| Commands proposed over Telegram (`ws-telegram`) | Spanish verbs before a command are recognized |
| Audit escape test (`ws-audit --ai`) | A refusal written in Spanish counts as a refusal |
| Recurring prompts (`ws-report`) | Spanish stop words are dropped and accented letters are kept |
| `ws-report --ai`, `ws-handoff`, `ws-learn` | Claude is asked to write in Spanish. The tab summary (`Ctrl+b i`) is not affected: it answers in the language of the conversation |
| `cr --test` | Runs the Spanish task set as well as the English one |

Yes/no confirmations accept `y`, `yes`, `s`, `si` and `sí` in both settings.

### Language packs

The words and expressions live in two files, one per language:

| File | Content |
|---|---|
| `~/.local/lib/ws-lang/en.conf` | English pack, always active |
| `~/.local/lib/ws-lang/es.conf` | Spanish pack, added to the English one with `ws-lang es` |
| `~/.config/ws-routing/rules.conf` | Routing rules, `level\|id\|expression`, English |
| `~/.config/ws-routing/rules.es.conf` | Spanish expressions for the same rule ids, `id\|expression` |

A pack has one `key=value` per line; lines that start with `#` are comments. The value is everything after the first `=`
up to the end of the line, taken as written: no quotes, no escaping, no comment after it. It is a list of alternatives
joined with `|`, or a list of words separated by spaces. The key names the one script that reads it (`intent.design`,
`state.asks`, `notify.command`, `telegram.run_verbs`, `audit.denied`, `report.stopwords`), and the comment above each
key says which kind of expression that script expects (`grep -E` or Python `re`).

To add a word:

1. Open the pack of its language and find the key of the feature that missed it. For example, to make "waiting for
   you" react to "revisa" in Spanish, edit `state.asks` in `es.conf`.
2. Append the word as one more alternative, in lowercase: `state.asks=corre|ejecuta|…|revisa`. For a word list, append
   it after a space.
3. Save. The next prompt or answer uses it.

The packs are kit files: `install.sh` replaces an edited pack with the kit's version and keeps yours next to it as
`<file>.bak.<date>`. To keep an addition, make it in the kit (`files/home/.local/lib/ws-lang/`) and send it as a pull
request, or apply it again after an update. After a change to the routing rules, run `cr --test`: with `ws-lang es` it
runs the English and the Spanish task sets, and each must stay at 90 % or more.

## 16. Backups and restore

Nothing here needs to be run by hand in normal use; these are the commands for checking and recovering.

| What | Where it goes | Command |
|---|---|---|
| tmux session (tabs, panes) | `~/.local/share/tmux/resurrect`, copied to `%UserProfile%\.tmux-resurrect-backup` | automatic; `Ctrl+b Ctrl+s` to force |
| Conversations and audit log | `%UserProfile%\.claude-wsl-backup` | automatic (`ws-backup`) |
| Light backup of Claude data, tmux saves and an inventory for reinstalling; never credentials | `%UserProfile%\WSL-Backups\lite` (14 kept) | `ws-backup-lite` |
| Encrypted copy of the light backup | OneDrive | `ws-backup-cloud setup` once, then automatic |
| Personal configuration | Your private repository | `ws-personal sync` |

```bash
ws-restore-lite                 # tests the latest backup in a temporary folder; does not touch $HOME
ws-restore-lite --restore     # restores into $HOME (asks; refuses with Claude open; keeps differing files)
ws-backup-cloud test          # decrypts the latest cloud copy into a temporary folder and checks it
ws-backup-cloud fetch         # decrypts a cloud copy to restore it with ws-restore-lite
tmux-recover                  # lists tmux saves and restores the one you choose
```

Recovering a machine: new Ubuntu → `bash install.sh` → `ws-restore-lite --restore` → `ws-personal restore` →
logins (`claude auth login`, `az login`, `gh auth login`). The step-by-step version is in the
[runbook](runbook.md#17-recovery).

## 17. Updating from the kit

```bash
ws-update            # Claude Code, tmux plugins, system packages
ws-kit-update        # the workstation itself, from the kit's repository
ws-kit-update --check   # only says whether there is a new version
```

`ws-kit-update` pulls with `--ff-only`, runs `install.sh` (every changed file is backed up as `*.bak.<date>`) and then
`ws-test`. If the tests fail it goes back to the previous commit and reinstalls. It does nothing when the kit folder
has uncommitted changes or unpushed commits.

An update from 2.x to 3.0 also renames commands, folders and settings: follow
[Upgrading from 2.x names](#18-upgrading-from-2x-names), which ends with a restart of tmux.

After any other update:

```bash
tmux source-file ~/.tmux.conf     # or Ctrl+b r
tmux-claude-restart --all       # running Claude sessions pick up new settings, hooks and telemetry
```

Restarting Claude in all tabs skips the tabs that are working or have a dialog open, keeps each tab's protection
level and leaves solo-mode tabs alone; `--list` shows what it would do and `--include-busy` includes busy tabs.

If you maintain the kit, the reverse direction is `bash export.sh` (captures what is installed into `files/`), review
the diff, `ws-verify`, commit.

## 18. Upgrading from 2.x names

Version 3.0 renamed the commands, options, environment variables, tmux options, folders and stored values that were
Spanish words in 2.x. `install.sh` migrates an existing installation before it copies the new files; nothing is deleted
and nothing of yours is overwritten. The reasons are in
[ADR 0015](adr/0015-english-names-and-language-selector.md).

### How the migration works

The installer reads `renames.tsv` and treats each old name in one of three ways:

| Kind | Applies to | What happens |
|---|---|---|
| Data moved | Your settings and data: telemetry, routing rules, accounts, favorites, appearance, templates, gallery, Telegram switches, swarm state | The file or folder is moved to its new name. If the new name already exists, neither is touched and a warning asks you to merge them by hand |
| Wrapper left | The 41 renamed commands in `~/.local/bin` and the three renamed hooks in `~/.claude/hooks` | The old file is set aside and replaced by a wrapper that prints the new name and runs it with the same arguments. Tabs opened before the update keep working |
| File set aside | Old kit files that nothing calls any more: menus, themes, agents, `estandares.md`, `cuentas.sh`, the dashboard template | The file is set aside; the new one is installed under the new name |

"Set aside" means moved to `~/.local/share/ws-kit/pre-english.<date>/` with its path under `$HOME` kept, for example
`pre-english.<date>/.local/bin/tmux-nivel`.

The installer also changes the line of `~/.bashrc` that loads `cuentas.sh` so that it loads `accounts.sh` (backup:
`~/.bashrc.bak.<date>`), sets aside the generated profiles of `~/.config/claude-niveles`, stops the Telegram service
and the OpenTelemetry collector of the old version (tmux starts the new ones within a minute), patches the Windows
notification handler registered for `ws-claude://` so that it accepts `ws-claude://focus/N` and calls `tmux-goto`
(backup: `<file>.bak.<date>`), and writes `es` to `~/.config/tmux-claude/lang` so that
prompts typed in Spanish stay recognized (see [Language](#15-language)).

### Steps

1. Preview. The section "Names from before 3.0 → English (renames.tsv)" lists every `moved`, `shim` and `dropped`
   line, including the files inside a folder that is renamed too; nothing is written:

   ```bash
   bash install.sh --dry-run
   ```

2. Save your work and install. `ws-kit-update` runs the same installer:

   ```bash
   bash install.sh
   ```

3. Restart tmux. A running tmux server keeps the old option names and values:

   ```bash
   tmux kill-server     # then open the session again with dev; the tabs come back
   ```

4. Check the install output for `changed Windows handler …`. If it warns that the handler could not be updated,
   edit the registered `.ps1` to accept `ws-claude://focus/N` and call `tmux-goto` (see `windows/ws-claude-focus.ps1`).
5. Replace the old names in your own scripts, aliases, cron entries and personal tmux configuration, using the tables
   below. A wrapper passes its arguments through unchanged, so `tmux-nivel completo` works (the level names are still
   accepted) but `ws-telemetria abrir` fails: the subcommand is now `open`.
6. When nothing calls the old names any more, delete the wrappers. Only files that carry the wrapper mark are deleted:

   ```bash
   bash install.sh --remove-shims
   ```

The wrappers and the `claude-trabajo` alias are deprecated and are removed in the next major version. To go back, see
the [runbook](runbook.md#16-upgrading).

### What is still read under its old name

These live outside what the installer can move, or are values you typed, so the code accepts both spellings:

| Item | Old | New | Behavior |
|---|---|---|---|
| Cloud backup key in the Windows Credential Manager | `age-respaldo` | `age-backup` | The old entry is read while the new one does not exist; a new setup writes the new one |
| OneDrive folder of the cloud backup | `Respaldos\estacion-wsl` | `Backups\workstation-wsl` | The old folder stays in use while it exists and the new one does not |
| Personal repository | `~/code/estacion-personal`, `incluir.txt` | `~/code/workstation-personal`, `include.txt` | The old directory and file are used when only they exist; old paths listed in the file are translated |
| Light backup archives | `inventario/` | `inventory/` | A restore reads either |
| Telemetry history (traces, routing, Telegram, OpenTelemetry rows) | Spanish field names and values | English | Old rows are translated when read; the files are never rewritten. `ws-telemetry sql` shows old days with their old column names |
| Keys in files you edit | `tema=`, `protector=`, `escena=`, `minutos=`, `grupos=`, `bajar_max_ctx=`, `destino=`, the Telegram settings keys, the template keywords `principal`, `derecha`, `abajo`, `ventana`, `acomodo` | `theme=`, `saver=`, `scene=`, `minutes=`, `groups=`, `downgrade_max_ctx=`, `dest=`, English keys, `main`, `right`, `below`, `window`, `layout` | Both are read; the English one is written |
| Typed values | `completo`, `puro`; the Spanish scene names; `ws-cache --tope`; `ws-claude://foco/N`; `WS_OTEL_CONTENIDO`, `WS_OTEL_PUERTO`, `WS_OTEL_RETENCION_DIAS` | `full`, `bare`; English scene names; `--timeout`; `ws-claude://focus/N`; `WS_OTEL_CONTENT`, `WS_OTEL_PORT`, `WS_OTEL_RETENTION_DAYS` | Both are accepted |
| Account name on disk | `trabajo` | `work` | Anything that is not `personal` is the work account |
| Swarms created before the upgrade | Session `enj-<id>`, branch `enjambre/<id>/integracion` | `swarm-<id>`, `swarm/<id>/integration` | An existing swarm keeps its names until it is integrated and cleaned |

Not compatible: the other subcommands and options, the remaining environment variables, the tmux options, and the column
names of the CSV and JSON exports (`ws-telemetry export`, `ws-telemetry estimate --csv` and `--json`, `ws-report
--json`). Update the spreadsheets and queries that read them. The Windows folder `%UserProfile%\ws-telemetria` is not
moved: new reports go to `%UserProfile%\ws-telemetry`.

### Commands

| Old | New | Old | New |
|---|---|---|---|
| `claude-cuenta` | `claude-account` | `tmux-recuperar` | `tmux-recover` |
| `tmux-activas` | `tmux-active` | `tmux-resumen` | `tmux-summary` |
| `tmux-arte` | `tmux-art` | `tmux-traer` | `tmux-bring` |
| `tmux-avisame` | `tmux-notify-me` | `ws-actualizar` | `ws-kit-update` |
| `tmux-difundir` | `tmux-broadcast` | `ws-aprender` | `ws-learn` |
| `tmux-enfoque` | `tmux-focus` | `ws-arranque` | `ws-startup` |
| `tmux-enjambre` | `tmux-swarm` | `ws-auditoria` | `ws-audit` |
| `tmux-escena` | `tmux-scene` | `ws-aviso` | `ws-notify` |
| `tmux-estado` | `tmux-status` | `ws-copiar` | `ws-copy` |
| `tmux-etiqueta` | `tmux-label` | `ws-copiloto` | `ws-copilot` |
| `tmux-extraer` | `tmux-extract` | `ws-historial` | `ws-history` |
| `tmux-favoritos` | `tmux-favorites` | `ws-informe` | `ws-report` |
| `tmux-flot-run` | `tmux-popup-run` | `ws-redactar` | `ws-redact` |
| `tmux-foco` | `tmux-goto` | `ws-respaldo-nube` | `ws-backup-cloud` |
| `tmux-fondo` | `tmux-background` | `ws-ruteo-confirmar` | `ws-routing-confirm` |
| `tmux-grabar` | `tmux-record` | `ws-telemetria` | `ws-telemetry` |
| `tmux-historial` | `tmux-history` | `ws-traspaso` | `ws-handoff` |
| `tmux-nivel` | `tmux-level` | Hook `ws-ruteo.sh` | `ws-routing.sh` |
| `tmux-paleta` | `tmux-palette` | Hook `ws-sandbox-aviso.sh` | `ws-sandbox-notice.sh` |
| `tmux-panel` | `tmux-pane` | Hook `ws-trazas.sh` | `ws-traces.sh` |
| `tmux-plantilla` | `tmux-template` | Alias `claude-trabajo` | `claude-work` |
| `tmux-pregunta` | `tmux-ask` | `windows\instalar.ps1` | `windows\install.ps1` |
| `tmux-rama` | `tmux-branch` | `windows\ws-claude-foco.ps1` | `windows\ws-claude-focus.ps1` |
| `tmux-recientes` | `tmux-recent` | Subagents `arquitecto`, `depurador`, `explorador`, `sql-rapido` | `architect`, `debugger`, `explorer`, `sql-quick` |
| `tmux-pick` | `tmux-find` | | |

Commands that are not in the table kept their name.

### Subcommands and options

| Command | Old | New |
|---|---|---|
| `claude-account` | `usar trabajo`, `pestaña`, `proyecto … quitar`, `proyectos`, `estado` | `use work`, `tab`, `project … remove`, `projects`, `status` |
| `tmux-level` | `completo`, `puro`, `--comando`, `--perfil` | `full`, `bare`, `--command`, `--profile` |
| `tmux-solo` | `esta`, `nueva` | `this`, `new` |
| `tmux-claude-restart` | `--todas`, `--lista`, `--tambien-ocupadas` | `--all`, `--list`, `--include-busy` |
| `tmux-swarm` | `nuevo`, `tablero`, `integrar`, `limpiar`, `lista` | `new`, `dashboard`, `integrate`, `clean`, `list` |
| `tmux-theme` | `oscuro`, `claro` | `dark`, `light` |
| `tmux-saver` | `--escena`, `--fijar`, `--siguiente-escena`; scenes `aleatoria`, `galeria` | `--scene`, `--pin`, `--next-scene`; `random`, `gallery` |
| `tmux-focus` | `restante`, `estado` | `remaining`, `status` |
| `tmux-label` | `quitar` | `remove` |
| `ws-telemetry` | `abrir`, `resumen`, `trazas`, `estimar`, `semana`, `presupuestos`, `exportar`, `ritmo` | `open`, `summary`, `traces`, `estimate`, `week`, `budgets`, `export`, `rate` |
| `ws-telemetry` options | `--por rama\|proyecto`, `--dias`, `--actual`, `--alertas`, `--si-toca` | `--by branch\|project`, `--days`, `--current`, `--alerts`, `--if-due` |
| `ws-report` | `--dias`, `--ia`, `--ia-memoria`, `--abrir` | `--days`, `--ai`, `--ai-memory`, `--open` |
| `ws-otel` | `servir`, `iniciar`, `detener`, `asegurar`, `estado`, `resumen` | `serve`, `start`, `stop`, `ensure`, `status`, `summary` |
| `ws-hooks` | `tiempo`, `lista` | `time`, `list` |
| `ws-telegram` | `configurar`, `estado`, `prueba`, `encender`, `apagar`, `alternar`, `texto`, `ejecutar sin-pin`, `resumen`, `alertas`, `olvidar` | `setup`, `status`, `test`, `on`, `off`, `toggle`, `text`, `run no-pin`, `summary`, `alerts`, `forget` |
| `ws-learn` | `hechos`, `comandos` | `facts`, `commands` |
| `ws-personal` | `agregar`, `restaurar`, `estado`, `--silencioso` | `add`, `restore`, `status`, `--quiet` |
| `ws-backup-cloud` | `configurar`, `probar`, `bajar`, `estado` | `setup`, `test`, `fetch`, `status` |
| `ws-backup-lite`, `ws-restore-lite` | `--ahora`; `--probar`, `--restaurar` | `--now`; `--test`, `--restore` |
| `ws-kit-update` | `--revisar`, `--aplicar` | `--check`, `--apply` |
| `cr` | `--explica`, `--probar`, `--sin-ia`, `--cambiar` | `--explain`, `--test`, `--no-ai`, `--switch` |
| `ws-menus`, `ws-verify`, `ws-handoff` | `--ver`; `--rapido`; `--conversacion` | `--show`; `--quick`; `--conversation` |
| `ws-tools install` groups | `nube`, `contenedores`, `calidad` | `cloud`, `containers`, `quality` |

The current usage of each command is in the header of its script; `ws-menus --show` collects them in the manual.

### Environment variables and tmux options

| Old | New | Old | New |
|---|---|---|---|
| `WS_TETOCA` | `WS_YOURTURN` | `WS_PREGUNTA_MODELO` | `WS_ASK_MODEL` |
| `WS_OTEL_CONTENIDO` | `WS_OTEL_CONTENT` | `WS_HISTORIAL_DIAS` | `WS_HISTORY_DAYS` |
| `WS_OTEL_PUERTO` | `WS_OTEL_PORT` | `WS_TELEMETRIA_DIR` | `WS_TELEMETRY_DIR` |
| `WS_OTEL_RETENCION_DIAS` | `WS_OTEL_RETENTION_DAYS` | `WS_RUTEO_REGLAS` | `WS_ROUTING_RULES` |
| `WS_GALERIA` | `WS_GALLERY` | `WS_NIVELES_DIR` | `WS_LEVELS_DIR` |
| `WS_GALERIA_SEG` | `WS_GALLERY_SEC` | `WS_BARRA_EXTRA` | `WS_BAR_EXTRA` |
| `WS_GALERIA_SIMBOLOS` | `WS_GALLERY_SYMBOLS` | `WS_SANDBOX_AVISO` | `WS_SANDBOX_NOTICE` |
| `WS_ARTE_COLOR` | `WS_ART_COLOR` | `PESTANA` | `WS_TAB` |
| `@cruteo` | `@croute` | `@rama_barra` | `@branch_bar` |
| `@cfase`, `@cdesde` | `@cphase`, `@csince` | `@cnivel`, `@ccuenta` | `@clevel`, `@caccount` |

The other `WS_*` variables follow the same pattern: the Spanish word became its English equivalent.

### Folders and files

| Old | New |
|---|---|
| `~/.config/ws-telemetria/` with `precios.json`, `presupuestos.conf` | `~/.config/ws-telemetry/` with `prices.json`, `budgets.conf` |
| `~/.local/share/ws-telemetria/` with `trazas/`, `ruteo/`, `informes/`, `reportes/`, `datos/`, `niveles/`, `avisos/`, `enfoque/`, `preguntas/`, `traspasos/`, `aprendizaje/` | `~/.local/share/ws-telemetry/` with `traces/`, `routing/`, `reports/`, `weekly/`, `data/`, `levels/`, `notices/`, `focus/`, `asks/`, `handoffs/`, `learning/` |
| `~/.config/ws-ruteo/` with `reglas.conf`, `ajustes.conf`, `modelos.conf` | `~/.config/ws-routing/` with `rules.conf`, `settings.conf`, `models.conf` |
| `~/.config/claude-cuentas/` with `activa`, `proyectos.conf` | `~/.config/claude-accounts/` with `active`, `projects.conf` |
| `~/.config/claude-niveles/` | `~/.config/claude-levels/` (generated again; the old folder is set aside) |
| `~/.config/anthropic-copiloto/` | `~/.config/anthropic-copilot/` |
| `~/.config/tmux-claude/` with `favoritos`, `apariencia`, `ajustes`, `galeria/`, `plantillas/`, `sin-ble` | The same folder with `favorites`, `appearance`, `settings`, `gallery/`, `templates/`, `no-ble` |
| `~/.config/ws-local/barra-extra.conf` | `~/.config/ws-local/bar-extra.conf` |
| `~/.config/ws-backup/` with `nube.conf`, `nube-recipient` | The same folder with `cloud.conf`, `cloud-recipient` |
| `~/.config/ws-informe.conf` | `~/.config/ws-report.conf` |
| `~/.config/ws-telegram/` with `apagado`, `texto`, `ejecutar-sin-pin`, `ajustes` | The same folder with `off`, `text`, `run-no-pin`, `settings` |
| `~/.local/state/ws-telegram/alertas/` | `~/.local/state/ws-telegram/alerts/` |
| `~/.local/share/tmux-enjambre/`, `~/.local/share/tmux-historial/` | `~/.local/share/tmux-swarm/`, `~/.local/share/tmux-history/` |
| Report files `informe-YYYY-MM-DD.html`, `semana-YYYY-Www.md` | `report-YYYY-MM-DD.html`, `week-YYYY-Www.md` |

## 19. Command reference

### Commands by task

| Task | Commands | Section |
|---|---|---|
| Open folders and tabs | `tw`, `two`, `twt`, `tp`, `tmux-open`, `tmux-bring`, `tmux-favorites` | [4](#4-opening-repositories) |
| Find a tab, a favorite or a conversation | `tmux-find` (views: `tmux-active`, `tmux-favorites`, `tmux-recent`), `tmux-dash` | [8](#8-finding-the-tab-that-needs-you) |
| Model per task | `cr` | [9](#9-working-with-claude-in-a-tab) |
| Restart Claude | `tmux-claude-restart` | [9](#9-working-with-claude-in-a-tab) |
| Swarm and handoff | `tmux-swarm`, `ws-handoff` | [9](#9-working-with-claude-in-a-tab) |
| Accounts | `claude-account`, `claude-work`, `claude-personal` | [10](#10-accounts) |
| Protection | `tmux-level`, `tmux-solo` | [11](#11-protection-levels) |
| Dashboard and reports | `ws-telemetry`, `ws-report`, `ws-otel`, `ws-hooks`, `claude-report`, `ws-audit` | [12](#12-reports-and-telemetry) |
| Focus mode | `tmux-focus` | [12](#12-reports-and-telemetry) |
| Telegram | `ws-telegram` | [13](#13-notifications-and-telegram) |
| Theme and screensaver | `tmux-theme`, `tmux-saver`, `tmux-scene`, `tmux-art` | [14](#14-appearance-and-screensaver) |
| Language | `ws-lang` | [15](#15-language) |
| Backups | `ws-backup-lite`, `ws-restore-lite`, `ws-backup-cloud`, `tmux-recover`, `ws-personal` | [16](#16-backups-and-restore) |
| Updates and health | `ws-update`, `ws-kit-update`, `ws-check`, `ws-health`, `ws-verify`, `ws-test`, `ws-tools` | [17](#17-updating-from-the-kit) |
| Names from before 3.0 | `install.sh --dry-run`, `install.sh --remove-shims` | [18](#18-upgrading-from-2x-names) |
| Manual and shortcuts | `ws-menus --show`, `Ctrl+b h` | [5](#5-key-bindings) |
| PowerShell | `dev`, `devo`, `devdash`, `devagents`, `devsave`, `devcheck`, `devsnapshot`, `devrestoretest` | [3](#3-first-run) |

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `WS_YOURTURN` | `1` | `0` disables the "waiting for you" state |
| `WS_LANG` | Not set | `en` or `es` overrides the language saved with `ws-lang` |
| `WS_OTEL_CONTENT` | `1` | `0` makes the collector store no text or identity |
| `WS_OTEL_PORT` | `14318` | Collector port (the endpoints in `settings.json` must match) |
| `WS_OTEL_RETENTION_DAYS` | `395` | Days the collector keeps its files |
| `WS_GALLERY` | `~/.config/tmux-claude/gallery` | Folder for the `gallery` scene |
| `WS_GALLERY_SEC` | `25` | Seconds per image |
| `WS_GALLERY_SYMBOLS` | Not set | `ascii` to use letters and signs only |
| `WS_ART_COLOR` | auto | `24` or `256` forces the color depth of the scenes |
| `WS_ASK_MODEL` | Haiku | Model for the quick question (`sonnet`, `opus`) |
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
| `@croute` | on | `off` turns automatic model routing off in all tabs |
| `@branch_bar` | on | `off` hides CI, pull request and ticket in the bar |

## 20. Troubleshooting

| Symptom | Action |
|---|---|
| Tabs are missing after a restart | Menu → "Tabs and session" → "Restore tabs from a save…" (`tmux-recover`) |
| Claude does not resume the conversation | In the tab: `claude -c` or `claude -r` |
| Something broke after `install.sh` | Restore the file's `*.bak.<date>` |
| A command prints "was renamed to …" or is not found after upgrading to 3.0 | Use the new name and the new subcommand or option: [Upgrading from 2.x names](#18-upgrading-from-2x-names) |
| Prompts typed in Spanish are no longer routed or detected | `ws-lang es` ([Language](#15-language)) |
| `export.sh` refuses because of "possible secrets" | Move the secret to a vault; a detection pattern goes in `secrets-allow.txt` after review |
| The gate blocks a commit | Fix what is marked; per repository, from your own shell: `git config ws.gate.skip …` |
| Claude reports a read-only file system | That is the sandbox; run the command yourself or add a justified exclusion |
| Open tabs do not send OpenTelemetry data | Export starts when Claude starts: restart the tab (`tmux-claude-restart --all`) |
| WSL is damaged | New Ubuntu → `install.sh` → `ws-restore-lite --restore` → logins |

The full step-by-step guide, with causes, is [runbook.md](runbook.md).

## 21. Known limitations

- Windows with WSL2 only.
- Version 3.0 renamed commands, options, variables, folders and stored values to English. The wrappers under the old
  command names pass the arguments through unchanged, so an old subcommand or option fails; they are removed in the
  next major version.
- The interface is English only. `ws-lang` chooses which languages the kit recognizes in prompts and answers (English,
  or English and Spanish), not the language of the menus and messages.
- A live tmux server keeps the old option names and values until it is restarted after the upgrade.
- Hook-based traces and OpenTelemetry data exist only from the day the workstation is installed; cost and token
  history is rebuilt from the transcripts Claude Code keeps.
- OpenTelemetry traces are a beta feature of Claude Code and may change.
- A tab that was already open when the telemetry settings changed emits nothing until its Claude is restarted.
- Changing a tab's protection level restarts Claude; anything half done in that turn is lost.
- After a restart of the workstation, restored tabs start with your normal settings, whatever level they had.
- The lock icon in the bar comes from a tmux option set when the level is applied; a Claude started by hand in a pane
  does not update it.
- Costs are API-equivalent prices, not what a subscription plan bills.
