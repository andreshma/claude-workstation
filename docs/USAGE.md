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
- [10. Accounts and profiles](#10-accounts-and-profiles)
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
| gitleaks | Required for commits: the gate blocks a commit without it (`ws-tools install base`) |
| osv-scanner, checkov | Required for a push that changes a lock file or manifest (osv-scanner), or Terraform, Bicep, a Dockerfile, a Kubernetes manifest or a CI workflow (checkov): `ws-tools install gate` installs the three scanners, pinned |
| `age` | Encrypts the light backups (`ws-backup-cloud setup` installs it) |
| `npm` | Installs the pinned MCP servers and agent tools (`ws-pinned`) |
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
5. Once, in a plain shell: `ws-backup-cloud setup` (the key that encrypts the backups), `ws-telegram text pin` if you
   use Telegram, and `claude plugin install claude-security@claude-plugins-official` (the settings enable it; the guard
   blocks installing plugins from inside Claude).

Upgrading an existing installation has steps of its own for each release: see "Upgrade notes" in
[CHANGELOG.md](../CHANGELOG.md).

`install.sh` copies every file it changes to `~/.local/share/ws-kit/backup.<date>/`, under the same path it has in
your home, before replacing it; the folder is named in the line `Files (backup: …)` and the newest 10 are kept.
Versions before 3.0 left `<file>.bak.<date>` next to each file instead: `bash install.sh --prune-backups` moves those
into `~/.local/share/ws-kit/backup.legacy/` (`--dry-run` lists them first). The installer also points git at the kit
hooks (commit gate) unless you already use another hooks path.

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
| `--mcp-opt-in NAME` | Also register an MCP server the lock marks opt-in (`chrome-devtools`); repeatable |
| `--mcp-accept NAME` | Re-pin a local MCP executable (MemPalace, recall) whose sha256 changed, after you reviewed the change |
| `--mcp-refresh` | Re-register the kit's MCP servers whose registered definition differs from `files/mcp-servers.json` (for example an old `npx` registration) |
| `--managed` | Install only the managed policy, as root (see [Managed policy](#managed-policy-optional)); combine with `--dry-run` to see the commands |

### MCP servers

`install.sh` registers the servers of `files/mcp-servers.json` only when `files/mcp-servers.lock.json` vouches for
them ([ADR 0018](adr/0018-supply-chain-pinning-and-signed-releases.md)):

| Kind | Servers | How it is pinned |
|---|---|---|
| npm | `azure`, `chrome-devtools` (opt-in) | Exact version and sha512; installed by `ws-pinned install` with `npm ci --ignore-scripts` into `~/.local/share/ws-kit/npm/<name>/`, never through `npx -y` |
| local | `mempalace`, `recall` | Built on each machine: the sha256 of the executable is pinned on first registration; a changed one is skipped until `--mcp-accept NAME` |
| remote | `microsoft-learn`, `ms-release-comms` | By URL |

A server that fails its check is skipped with a warning and the session runs without it. `ws-pinned verify` checks
the installed trees later; `ws-update` runs `ws-pinned verify --online` (registry signatures). Moving a pin is a
reviewed change to the kit: [runbook](runbook.md#pinned-npm-packages).

**Confinement** ([ADR 0024](adr/0024-mcp-server-confinement-and-allow-list.md)). Claude Code starts MCP servers
outside its sandbox, so the kit starts each local Linux server through `ws-mcp-jail` (bubblewrap):

| Server | In the jail | It sees | Network |
|---|---|---|---|
| `azure` | Yes | The system, the kit, its pinned install, its state dir `~/.local/state/ws-mcp/azure` and the tab's own `AZURE_CONFIG_DIR` | Yes (`--net`) |
| `chrome-devtools` (opt-in) | Yes | The system, the kit, its pinned install and its state dir | Yes (`--net`) |
| `mempalace`, `recall` | No: Windows executables through WSL interop, which bubblewrap cannot confine (`jailOptOut` in `files/mcp-servers.json`) | Everything you can read | Yes |

Never inside the jail: `~/.ssh` and every credential store of the guard's list, `~/.claude*`, the audit log, the
other profiles' logins, telemetry and the Windows drives; token variables are removed from its environment. Without a
working bubblewrap the server does not start (`ws-mcp-jail --probe` says why). `bash install.sh --mcp-refresh`
registers the jailed form over an older one; `ws-audit` warns about a local server that is neither jailed nor opted
out. To jail a server of your own, give it a `"jail": {"net": true}` object in `files/mcp-servers.json` (and its lock);
to leave one out, `"jail": false` with a `"jailOptOut"` reason.

### Browser tools (optional)

Two ways to let an agent drive a browser, both off until you install them:

- **agent-browser** (`ws-tools install agent-browser`): the pinned agent-browser behind the kit's wrapper
  `~/.local/bin/agent-browser`, with Chrome for Testing in its own profile (Google publishes no checksum for that
  download). The wrapper enforces a domain allow list (`~/.config/agent-browser/allowed-domains.txt`: localhost only;
  add yours in `allowed-domains.local.txt`, or `WS_AGENT_BROWSER_DOMAINS="a.com,*.b.com"` for one run), an action
  policy that denies `eval`, download and upload, and content boundaries around page output; it refuses flags that
  would attach to your real browser or replace those settings. These are defaults, not a sandbox boundary: an agent
  could call the binary directly, so Claude's sandbox and its network allow list remain the control.
- **chrome-devtools** MCP server (opt-in): `ws-tools install chrome-devtools-mcp`, then
  `bash install.sh --mcp-opt-in chrome-devtools`. It starts with `--isolated --no-usage-statistics
  --no-performance-crux --redact-network-headers` and with update checks and usage statistics off. It needs a Chrome
  reachable from WSL, in one of three ways:

  | Option | How | Notes |
  |---|---|---|
  | a. Google Chrome inside WSL (recommended) | `curl -fsSLO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo apt-get install -y ./google-chrome-stable_current_amd64.deb` | The window shows through WSLg; add `--headless` to the server's arguments if there is none |
  | b. Chrome for Testing from agent-browser | Add `--executablePath <path that agent-browser doctor prints>` to the server's arguments | Reuses the browser agent-browser downloaded |
  | c. Windows Chrome | Start it with `--remote-debugging-port=9222 --user-data-dir=%TEMP%\cdp-profile` (never your daily profile), set `networkingMode=mirrored` in `.wslconfig`, and replace `--isolated` with `--browserUrl http://127.0.0.1:9222` | While that port is open, any local process can drive that browser |

### Managed policy (optional)

`bash install.sh --managed` installs, with `sudo` and only after you answer `y`, a drop-in that neither the agent nor
your own files can change ([ADR 0019](adr/0019-strict-base-and-level-profiles.md)):

| File (root-owned) | Content |
|---|---|
| `/etc/claude-code/managed-settings.d/50-ws-kit.json` | The `deny` floor, `disableBypassPermissionsMode`, `enableAllProjectMcpServers: false` and the guard hook failing closed |
| `/etc/claude-code/hooks/guard.sh` | A copy of the guard that the managed hook runs |
| `/etc/claude-code/ws-credential-paths.txt` | The credential paths the guard also reads |
| `/etc/claude-code/managed-settings.d/55-ws-mcp-allow.json` (only with `--mcp-allowlist`) | `allowedMcpServers`: the kit's servers by exact command (the `ws-mcp-jail` form included) or URL, plus `allowManagedMcpServersOnly: true` so no user, project or local setting can add to it |

It prints every command first; `--dry-run` only prints them. An organization's own `managed-settings.json` is left
alone. Restart Claude afterwards (`/status` shows the managed source). After a kit update that changes `guard.sh`, run
it again; `install.sh` warns when the root copy is older.

`--mcp-allowlist` blocks every MCP server it does not list, and Claude Code applies it to the claude.ai connectors
and plugin servers too ([managed MCP](https://code.claude.com/docs/en/managed-mcp.md); a `serverName` entry "is not a
security control", so the kit never uses one). Before installing it, list the connectors and plugin servers you keep
in `~/.config/ws-mcp/allow-extra.json`, a JSON array such as `[{"serverUrl": "https://mcp.example.com/*"}]`; the
generated list is printed before `sudo` asks. Run it again after a kit update that changes `files/mcp-servers.json`;
`ws-audit` lists the registered servers the list would block.

## 3. First run

1. Start the session with `dev` in PowerShell, the desktop shortcut, or the Ubuntu profile of Windows Terminal.
2. The tmux plugins are installed by `install.sh` at the commits pinned in `~/.config/tmux-claude/plugins.lock`
   (`ws-plugins verify` checks them). Do not use `Ctrl+b I` or `Ctrl+b U`: TPM would install or move them to the
   branch tip, and `ws-audit` reports a plugin off its pin (`ws-plugins apply` puts it back).
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
| Bring many recent conversations that have no tab, in one go | Menu → "Tabs and session" → "Bring many conversations at once…" (`tmux-bring`) |

The picker lists the folders under the roots in `~/.config/tmux-claude/roots.txt`, one per line as
`label|depth|path`. The label is also the **group**: each group is its own tmux session, and a new tab is created in
the session of its group. `Alt+↑/↓` switches group and `Ctrl+b S` lists all groups with their tabs. To keep everything
in one session, set `groups=off` in `~/.config/tmux-claude/settings`.

`roots.txt` comes from the kit and is replaced on every install. Put your own roots in
`~/.config/ws-local/roots.txt`, in the same format; the kit never touches that file, and `ws-personal` versions it
in your private repository by default (see [Backups and restore](#16-backups-and-restore)). A folder outside every
root opens in the group `other`.

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
| Account and profile | `P` | Profile › (the tab's profiles: switch this tab, new tabs, pin the project, log in, status, new profile; see [Profiles](#profiles-several-organisations-and-tenants)) |
| | `a` | Switch this tab to the personal / work account (same conversation) |
| | `n` | New tabs use: … (default account for new tabs) |
| | `f` | Always use the account of this tab for this project (pin the project) |
| | `L` | Log in to the personal account |
| | `+` | More Claude commands › (editor, draft, fast mode, redraw, `/status`, `/usage`, `/mcp`, `/effort`) |
| Emergency | `X` | Emergency stop: block and close every Claude, Telegram off (asks first; see [Emergency stop and anomalies](#emergency-stop-and-anomalies)) |

### "Tabs and session" (`s`)

| Key | Label |
|---|---|
| `N` | Go by number… |
| `i` | Summary: what, where and where it left off |
| `*` | Add to favorites ★ / Remove from favorites ☆ |
| `E` | Tab label |
| `r`, `x` | Rename tab; Close tab |
| `s`, `R` | Save session now; Restore tabs from a save… (`tmux-recover`: lists the saves, the latest first) |
| `t` | Bring many conversations at once… |
| `G` | Save this tab as a template |

The tree of groups with their tabs is not in this menu: the finder (`Ctrl+b f`) lists every tab, and `Ctrl+b S`
opens the tree.

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
| `i` | Reports › | submenu, below |
| `a` | Learn from me: facts for MemPalace (you choose) | `ws-learn facts` |
| `k` | Create "/" commands from what you repeat | `ws-learn commands` |
| `c` | Usage dashboard (browser) | `ws-telemetry open` |
| `r` | Tools: timings, errors and cost (7 days) | `ws-telemetry traces` |
| `t` | Estimate per ticket (90 days) | `ws-telemetry estimate` |
| `p` | Budgets for the month | `ws-telemetry budgets` |
| `x` | Export CSV for Excel or Power BI | `ws-telemetry export` |

"Reports ›" (`i`) opens:

| Key | Label | Command |
|---|---|---|
| `i` | Full report with Claude findings (usage, agents, MemPalace, recall) | `ws-report --ai --ai-memory --open` |
| `j` | Quick report, without Claude | `ws-report --open` |
| `s` | Report for last week | `ws-telemetry week` |

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
| 🤖 before the name | Solo mode (🌐🤖 with the network tools, 🔓🤖 without sandbox) |
| `·P` after the name | The tab was switched to the personal account |
| `⬢acme` (colored) | The tab runs with the custom profile `acme` (its label and colour from `profile.conf`) |
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
| Leave Claude working alone | Menu → "Claude in this tab" → "Protection" → "Solo Claude in a new tab (own worktree in a repo)" or "Solo Claude in a new worktree". Solo mode runs inside the sandbox and expires after 4 hours (see [Protection levels](#11-protection-levels)) |
| Run several Claudes on one goal | Menu → "Claude in this tab" → "Swarm: several Claudes in parallel on one goal". Claude proposes 2–6 independent subtasks, you edit and confirm, each gets its worktree, branch and tab, at the `full` level with `git push` and `gh pr create`/`merge` denied. `tmux-swarm new --budget USD` stops the swarm when its branches together reach that spend (while the dashboard runs). The swarm refuses to start if your Claude has no `--setting-sources` (`WS_SWARM_LEVEL=normal` is the audited exception). `tmux-swarm integrate <id>` merges them into an integration branch; it never pushes |
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

## 10. Accounts and profiles

The workstation runs two Claude accounts: `work` (in `~/.claude`) and `personal` (in `~/.claude-personal`).
Each has its own login. Settings, hooks, agents and conversations are shared, so switching a tab continues the same
conversation. They are the two built-in profiles of `ws-profile`; for clients with their own Claude organisation or
Azure tenant, add a profile per client ([Profiles](#profiles-several-organisations-and-tenants)).

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

### Profiles (several organisations and tenants)

A profile gives a tab one client's identities end to end
([ADR 0021](adr/0021-per-tab-profiles.md)): its own Claude login and organisation (`~/.claude-profiles/NAME`), its
Azure tenant and default subscription, `gh` and `kubectl` logins (`~/.config/ws-agent/NAME/`, the agent identity of
the same name) and, by default, its own conversations and no MemPalace. The Claude in that tab, the Azure MCP server it
starts and every `az`, `gh` or `kubectl` you type in that tab use them. `work` and `personal` are built in.

Worked example, for two clients (the ids are placeholders):

```bash
# In a terminal (not from Claude): creates the profile and asks for each login (Claude, az, gh, a kubeconfig)
ws-profile new contoso --tenant 00000000-0000-0000-0000-00000000c001 --subscription 00000000-0000-0000-0000-00000000c0a1
ws-profile new fabrikam --tenant fabrikam.example.com --memory wing:fabrikam
ws-profile project contoso ~/code/contoso-app     # every new tab in that repo (and its worktrees) opens as contoso
ws-profile tab fabrikam                           # this tab, now: new conversation, fabrikam's logins
ws-profile list                                   # profiles, memory mode, conversations (own / shared), tenant
ws-profile status                                 # each profile's Claude organisation and az default subscription
```

| Task | Command | Menu |
|---|---|---|
| Create a profile and log in | `ws-profile new NAME [--tenant ID] [--subscription ID] [--share-with PROFILE] [--memory off\|on\|wing:W] [--label TEXT] [--colour C] [--claude-dir work\|personal]` | Profile › New profile… (`N`) |
| Log in again to one tool | `ws-profile login NAME [claude\|azure\|gh\|kube]` | Profile › Log in to Claude (`L`) |
| Switch this tab | `ws-profile tab NAME [PANE]` | Profile › the profile's line |
| Profile for new tabs | `ws-profile use NAME` | Profile › New tabs use (`u`) |
| Pin a project (repo and worktrees) | `ws-profile project NAME [folder]`, `ws-profile project remove [folder]` | Profile › `f`, `r` |
| See them | `ws-profile list`, `ws-profile show NAME`, `ws-profile status`, `ws-profile projects` | Profile › Status (`s`) |
| Re-link the kit setup and MCP servers | `ws-profile setup [NAME]` | None |
| Remove one | `ws-profile remove NAME` (asks; its logins and conversations are deleted only when you type its name) | None |
| One Claude with another profile, from a shell | `claude-as NAME [args]` (and `claude-work`, `claude-personal`) | None |

Rules:

- Which profile a new tab or pane gets: the project pin, else the tab's profile (a split), else `ws-profile use`, else
  `work`. A restart of a tab (level, solo, `tmux-claude-restart`) keeps the tab's profile. A tab restored by
  tmux-resurrect gets its folder's profile, so pin client repositories.
- Switching to a profile that does not share the conversation store starts a new conversation and says so; its earlier
  conversations are in `claude-resume -r` inside that profile. `--share-with PROFILE` links the conversations of two
  profiles on purpose (the same client in two Azure tenants, for example).
- `--claude-dir work|personal` reuses that account's Claude login and conversations for another Azure tenant of the
  same organisation.
- Memory: `off` (the default of a new profile) keeps MemPalace out of the tab, reads and writes, and its hooks get
  nothing; `wing:W` files the tab's sessions into wing `W` only and limits searches to it; `on` is what `work` does.
  The recall (books) server is unaffected.
- What the agent cannot do in a profile's tab: read any profile's logins (sandbox, guard and `Read` deny rules),
  read the conversations of another store (the fence `claude-resume` adds to the level settings), change
  `CLAUDE_CONFIG_DIR`, the credential variables, `WS_PROFILE` or `WS_MEMORY`, log in, or run `ws-profile` or
  `claude-account` commands that change profiles.
- `ws-audit` (section Profiles) warns when two profiles declare the same tenant and subscription, an isolated profile
  links conversations, a profile's credentials could be read by sandboxed commands, or a tab runs with a profile that
  no longer exists.
- `tmux-level … --agent NAME` is the credentials-only case: the tab keeps its Claude account and takes NAME's `az`,
  `gh` and `kubectl` logins.
- After `ws-profile new`, check that each login landed where it should: `ws-profile status` shows the Claude
  organisation and the default subscription; in the tab, `/mcp` and an Azure MCP read show the tenant.

## 11. Protection levels

Each tab has its own level. Changing it restarts Claude in that tab and resumes the conversation; anything half done
in that turn is lost.

The user settings (`~/.claude/settings.json`) are the strict base: no command leaves the sandbox. Each level is a
generated profile that adds or removes permissions on top of it
([ADR 0019](adr/0019-strict-base-and-level-profiles.md)):

| Level | Menu key | What changes |
|---|---|---|
| Full (`full`) 🔒 | `c` | Sandbox on with no way out: no unsandboxed commands and no excluded commands, so `az`, `gh`, `git push`, `kubectl` and similar run inside the sandbox, without network or credentials, and mostly fail. Sandboxed commands read only the tab's project. All kit rules stay |
| Normal (`normal`) | `n` | The strict base plus what `~/.config/claude-levels/normal-adds.json` adds: the commands excluded from the sandbox that need network and credentials (`az`, `gh`, `git push`, `terraform`, `kubectl`…). Every kit launcher, `claude-resume` and a restored tab start here |
| Pure (`bare`) 🔓 | `p` | No sandbox and none of the kit's `allow`/`ask` rules: Claude asks as it would without the kit |
| Solo mode 🤖 | `s` | Claude in `auto` permission mode **inside** the sandbox: commands run without asking one by one, but in bubblewrap and the network allow list, and no command leaves it: `az`, `gh`, `git push`, `kubectl` and the other commands normal excludes run inside the sandbox (without your credentials), and each of them asks you, so the auto-mode classifier never approves one. The other `ask` rules still ask you. It expires after 4 hours. `t` starts it in a new tab and `w` in a new worktree ([ADR 0016](adr/0016-solo-mode-inside-the-sandbox.md), [ADR 0022](adr/0022-solo-mode-without-excluded-commands.md)) |

A `claude` typed by hand in a shell starts at the strict base, without the excluded commands; start it with
`claude-resume` (or restart the tab) to get the normal level.

In every level, including `bare` and solo mode, the floor stays on: the `deny` rules (credential files, printing
secrets, bypassing the git gate, the agent's own configuration), `disableBypassPermissionsMode` and the `guard.sh`
hook, which fails closed (forced pushes, pushes to `main`, `--no-verify`, production changes, secrets written to
files, writes to settings and hooks). State, traces, notifications and the other gates below also keep working.

```bash
tmux-level full                # current tab
tmux-level normal %12          # a given pane
tmux-level normal --agent ops  # the tab acts as agent identity "ops" (below); --agent none drops it
tmux-level --command bare      # prints the command Claude would be started with
tmux-solo this [--hours N]     # this tab into solo mode (1 to 24 hours; default 4, @csolo_hours, WS_SOLO_HOURS)
tmux-solo normal               # back to normal
tmux-solo new [folder] [--here]  # new tab in solo mode; in a git repo, its own worktree unless --here
tmux-solo worktree [folder]    # new tab in a fresh worktree <repo>.wt/solo-<date> (branch solo/<date>)
tmux-solo this --unsandboxed   # the old solo mode, sandbox off: an audited exception (🔓 in the tab name)
tmux-solo this --with-network-tools [--hours N]
                               # normal's excluded commands for this solo tab, each one asking you; 1 h by default,
                               # 4 h at most (WS_SOLO_NET_HOURS), 🌐 in the tab name, audited
```

In the "Protection" submenu, "Active rules (/permissions)" and "Sandbox status (/sandbox)" show what Claude actually
loaded. After a restart of the workstation, restored tabs are started again with `claude-resume`, that is, at the
normal level.

When Claude reports a read-only file system or a blocked command, that is the sandbox or the guard working. Run the
command yourself with `!` or in a floating shell (`Ctrl+b g`).

Telegram never offers to run commands in a `bare` or solo-mode tab.

### Agent identities

`tmux-level <level> --agent NAME` starts Claude with `WS_AGENT=NAME` and the `az`, `gh` and `kubectl` credentials of
`~/.config/ws-agent/NAME/` (`AZURE_CONFIG_DIR=…/azure`, `GH_CONFIG_DIR=…/gh`, `KUBECONFIG=…/kube/config`), so cloud
and git logs show the agent, not you. Create the folder and log in there yourself with a reduced-scope identity; an
unknown name is refused. The tab remembers it (`@cagent`) for later level changes. With `WS_AGENT` set, the guard
refuses to point those variables elsewhere, `--kubeconfig`, `az login` and `gh auth login`/`switch`; Claude cannot read
`~/.config/ws-agent/` ([ADR 0020](adr/0020-agent-scoped-identities.md)). A profile `NAME` keeps its credentials in that same folder: `--agent NAME` is
the credentials-only case, and `ws-profile tab NAME` also switches the Claude account, conversations and memory
([Profiles](#profiles-several-organisations-and-tenants)).

### What the gates do in a session

| You notice | What it is | What you can do |
|---|---|---|
| "BLOCKED by policy (guard.sh)" when Claude edits `settings.json`, hooks, `~/.claude.json`, plugins, the level profiles, `~/.config/git/hooks` or the kit's lists | The agent never writes its own configuration ([ADR 0017](adr/0017-defence-in-depth-for-agent-configuration.md)); `claude mcp add`, `claude plugin install` and running `ws-learn` from Claude are blocked too | Edit it yourself in a plain shell |
| The same for `CLAUDE.md`, commands, agents, skills or the Windows-side `.claude` folder | Writable only inside a window you open | `date -d '+30 min' +%s > ~/.config/ws-guard/allow-config-writes` opens 30 minutes; each write is audited (`config-write-allowed`) |
| A production change is blocked although its name has no "prod" | It is listed in `~/.config/ws-guard/production.conf` | Lines `subscription <id or name>` and `context <kube context>`; also checked for mutating Azure MCP tools |
| "the prompt seems to contain a secret" | `prompt-screen.sh` ran the prompt through `ws-redact` | Remove the secret, or start the prompt with `#allow-secret` (audited, the prompt is never logged) |
| A note next to a web page, search, MCP result or `curl`/`gh api` output that the content is untrusted | `untrusted-content.sh` labels it and screens it for injection markers; a hit is logged as `injection-suspect` | Read what it flagged before you let Claude act on it |
| Every MemPalace write asks, also after "don't ask again" and in solo mode | `memory-gate.sh` asks, stamps the provenance and logs the hash of the input | Approve or reject; `ws-memory review --older-than 90` and `ws-memory log` in a terminal |
| Text you do not want stored | Wrap it in `<private>` … `</private>` in the prompt | Memory writes that contain it are blocked, and the lifecycle hooks hand MemPalace and recall a redacted copy. A paraphrase is not recognised; `WS_MEMORY_PRIVATE=skip` sends nothing of such a session |
| Every `.exe` command asks | Windows executables run outside the sandbox | Approve the ones you expect ([runbook](runbook.md#wsl-interop)) |
| Prompts and tools are "held" | The emergency stop is on, or a hard budget is spent | `ws-stop-all --clear`, or `ws-telemetry budgets --override <project> [hours]`, in a terminal |

### Emergency stop and anomalies

```bash
ws-stop-all                       # blocks every Claude, closes them all, turns Telegram off (asks first)
ws-stop-all --pane %12 --yes      # only one tab
ws-stop-all --session swarm-<id>  # only one tmux session, for example a swarm
ws-stop-all --status | --list     # marker state · panes that have a Claude now
ws-stop-all --clear               # lets prompts and tools run again (Telegram stays off: ws-telegram on)
ws-anomaly [--minutes 10] [--threshold 5] [--tsv|--json]   # sessions with repeated blocks, denials or sandbox hits
```

The menu entry is Menu → "Claude in this tab" → "Emergency stop: block and close every Claude, Telegram off" (`X`).
`tmux-watch` runs `ws-anomaly` once a minute: a session at the threshold shows 🚨 in the bar and raises a Windows
alert, and Telegram offers "⛔ Stop this tab". The thresholds are the tmux options `@canomaly_n` and
`@canomaly_min`. What the stop does step by step, and how to verify the audit log afterwards, is in the
[runbook](runbook.md#emergency-stop).

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
ws-telemetry budgets --override api 4      # with hard=1: lets project "api" go on over its budget for 4 h (audited)
ws-telemetry prompts [--days 7] [--json]   # approval fatigue: approvals per hour, time to answer, answers under 2 s
ws-telemetry prompts --alerts [--rate 30]  # what Telegram would alert on (high rate, rubber-stamping, broad rules)
ws-telemetry traces --days 7               # tools: uses, time, errors, approximate cost
ws-telemetry export                        # CSV of turns, traces and estimation
ws-telemetry sql                           # DuckDB with the views `turns` and `traces` (English column names)
```

The ticket comes from the branch name (`feature/ABC-123-…`).

Budgets are warnings by default. A line `hard=1` in `budgets.conf` makes them a limit: `ws-telemetry build` writes
the projects at or over 100 % to `~/.local/state/ws-budget-over`, and the `ws-runtime-gate.sh` hook holds prompts and
tools there until `ws-telemetry budgets --override <project> [hours]` (24 h by default, 1 to 744; run it in a
terminal, Claude is denied it). A flag older than 2 hours is ignored, so a stopped dashboard never blocks work. The
"Prompts" numbers also appear in the weekly report; they need the OpenTelemetry collector.

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
| `ws-audit` | Read-only audit of the workstation by pillar, with a report. Among other checks it fails on repositories where the gate does not run in full (a local `core.hooksPath` or `ws.gate.allowNoGitleaks`; `ws.gate.skip` only warns), an unencrypted last backup or Windows-side mirror, a pinned package that no longer matches its lock (`ws-pinned verify`), a tmux plugin off its pinned commit (`ws-plugins verify`), a registered MCP server that is not in `files/mcp-servers.json`, a managed policy file that is invalid, not root-owned or lost its floor (it reads `managed-settings.json` and the kit's drop-in `managed-settings.d/50-ws-kit.json`), and a broken audit chain, checks that the user settings are the strict base, and warns on a repository's `.claude/settings*.json` that widens every level |
| `ws-audit --verify-log [folder]` | Only the hash chain of the audit log and its anchors: exit 1 if a line was edited, deleted or reordered ([runbook](runbook.md#verifying-the-audit-log)) |
| `ws-audit --compliance [--json] [--kit DIR] [--catalogue FILE]` | Runs the machine-checkable `check` of every control in the kit's `docs/compliance/controls.yaml` and prints a table per framework with the coverage (see below) |
| `ws-memory review [--older-than 90] [--list\|--count]`, `ws-memory log [--days 30]` | Facts saved through `ws-learn` that are due for review (invalidate or keep), and the memory writes, redactions and private blocks in the audit log. Run them in a terminal |
| `tmux-focus 25` | Focus mode for 25 minutes: minimal bar, no Windows notifications |

`ws-audit --compliance` finds the catalogue in the kit checkout: `$WS_KIT/docs/compliance/controls.yaml`, with
`WS_KIT` defaulting to `~/code/claude-workstation` as for `ws-kit-update` (`--kit DIR` or `--catalogue FILE`
override it). It treats the YAML as untrusted input and runs only checks of an allow list of read-only forms
(`bash tests/<suite>.sh`, `test -f`, `jq`, `grep`, kit commands with read-only flags); anything else, and checks that
need something this machine lacks, are reported as `not-run`, not as failures. It changes nothing, writes the result
to `~/.local/share/ws-telemetry/compliance.json` (`--json` prints it) and exits 1 when a control marked
`implemented` fails its check. The catalogue and the assessment are in [compliance/](compliance/assessment.md).

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
ws-telegram text pin       # sets or changes the PIN (also needed to approve risky dialogs from the phone)
ws-telegram approve risky  # default: the PIN only for risky approvals · approve pin: for every approval
ws-telegram forget         # deletes token, chat and state
```

| From the phone | How |
|---|---|
| Answer a permission or question dialog | Tap one of the buttons (the dialog's options, or "⎋ Cancel"). Codes are single-use and expire in 10 minutes. Approving a risky dialog (an MCP tool, an ask rule, a command that runs outside the sandbox; marked 🔐) asks you to reply with your PIN, and the key is sent only if the same dialog is still on screen. "Don't ask again" and other persistent allows are never offered |
| Reply with text to an open question | Reply to the message starting with your PIN, then a space and the answer. Requires `ws-telegram text on` |
| Run a command Claude proposed | Tap "▶ Run" under the command, then reply with your PIN. Only read-only commands of an allow list (`git status`, `git log`, `ls`, `kubectl get`, `az account show`…, without shell syntax or `.exe`) get the button; everything else arrives as text only, to be run at the PC |
| Stop a tab that an anomaly alert names | Tap "⛔ Stop this tab" (runs `ws-stop-all --pane` for it) |

While the emergency stop is on, buttons and ▶ Run send nothing. Without a PIN set, risky approvals from the phone are
refused. Alert switches in `~/.config/ws-telegram/settings`: `anomaly`, `anomaly_n`, `anomaly_min`, `prompts`,
`prompts_rate`.

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

The packs are kit files: `install.sh` replaces an edited pack with the kit's version and keeps yours under
`~/.local/share/ws-kit/backup.<date>/`. To keep an addition, make it in the kit (`files/home/.local/lib/ws-lang/`)
and send it as a pull request, or apply it again after an update. After a change to the routing rules, run
`cr --test`: with `ws-lang es` it runs the English and the Spanish task sets, and each must stay at 90 % or more.

## 16. Backups and restore

Nothing here needs to be run by hand in normal use; these are the commands for checking and recovering.

| What | Where it goes | Command |
|---|---|---|
| tmux session (tabs, panes) | `~/.local/share/tmux/resurrect`, copied to `%UserProfile%\.tmux-resurrect-backup` (encrypted per file) | automatic; `Ctrl+b Ctrl+s` to force; recover with `ws-restore-lite --mirror` |
| Conversations and audit log | `%UserProfile%\.claude-wsl-backup` (encrypted per file with `age`) | automatic (`ws-backup`); recover with `ws-restore-lite --mirror` |
| Light backup of Claude data, tmux saves and an inventory for reinstalling; never credentials. Encrypted with `age` by default | `%UserProfile%\WSL-Backups\lite` (14 kept) | `ws-backup-lite` |
| Encrypted copy of the light backup | OneDrive | `ws-backup-cloud setup` once, then automatic |
| Personal configuration | Your private repository | `ws-personal sync` |

`ws-personal` versions the paths listed in the `include.txt` of that repository. The default list has
`~/.config/ws-local/` (status bar segments and your own folder roots, `ws-local/roots.txt`, which is also listed by
name), your budgets, the routing and Telegram settings, your templates, the kit's `roots.txt` and `~/.claude/CLAUDE.md`;
`ws-personal add <path>` adds one. `ws-personal restore` copies what it replaces to
`~/.local/share/ws-kit/backup.<date>/` first.

```bash
ws-restore-lite                 # tests the latest backup in a temporary folder; does not touch $HOME
ws-restore-lite --restore     # restores into $HOME (asks; refuses with Claude open; keeps differing files)
ws-restore-lite --identity <age file> [FILE]   # an encrypted backup with a key other than the cloud key
ws-backup-cloud test          # decrypts the latest cloud copy into a temporary folder and checks it
ws-backup-cloud fetch         # decrypts a cloud copy to restore it with ws-restore-lite
tmux-recover                  # lists tmux saves and restores the one you choose
```

The light backup is encrypted to the cloud key of `ws-backup-cloud` and to every key in
`~/.config/ws-backup/age-recipients`. With neither (run `ws-backup-cloud setup` once), it is made in clear with a loud
warning and `ws-audit` fails. After each backup, the Windows-side copies of `ws-backup` and `tmux-backup` older than
`WS_BACKUP_COPY_DAYS` (30) are pruned: conversation copies whose original is gone, and old tmux saves.
`ws-restore-lite` opens an encrypted backup with the cloud key from Credential Manager
([runbook](runbook.md#restoring-encrypted-backups)).

Recovering a machine: new Ubuntu → `bash install.sh` → `ws-restore-lite --restore` → `ws-personal restore` →
logins (`claude auth login`, `az login`, `gh auth login`). The step-by-step version is in the
[runbook](runbook.md#17-recovery).

## 17. Updating from the kit

```bash
ws-update            # Claude Code, tmux plugins, system packages
ws-kit-update        # the workstation itself, from the kit's repository
ws-kit-update --check   # only says whether there is a new version
```

`ws-kit-update` installs only signed releases: it fetches the `vX.Y.Z` tags, takes the newest one ahead of your
checkout and runs `git verify-tag` against the signers in your installed `~/.config/ws-kit/allowed_signers` (plus
`allowed_signers.local`), never the branch tip. Then `git merge --ff-only <tag>`, `install.sh` (every changed file is
copied to `~/.local/share/ws-kit/backup.<date>/` first) and `ws-test`. If the tests fail it goes back to the previous
commit and reinstalls. It does nothing when the kit folder has uncommitted changes or commits the release does not
contain. `--check` exits 10 when a signed release is waiting and 11 when a newer release fails its signature (Telegram
raises a security alert); `--allow-unsigned` accepts an unsigned tag for forks, logged in
`~/.local/state/ws-kit-update.log`. Until the kit ships a maintainer key every release is refused with 11
([runbook](runbook.md#signing-a-release)).

`ws-update` also verifies the pinned MCP servers and tools (`ws-pinned verify --online`) and the sha256 of the local
ones, and reports newer versions (`ws-pinned outdated`) without installing them.

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
`~/.local/share/ws-kit/backup.<date>/.bashrc`), sets aside the generated profiles of `~/.config/claude-niveles`,
stops the Telegram service and the OpenTelemetry collector of the old version (tmux starts the new ones within a minute), patches the Windows
notification handler registered for `ws-claude://` so that it accepts `ws-claude://focus/N` and calls `tmux-goto`
(backup: `<file>.bak.<date>` next to it, on the Windows side), and writes `es` to `~/.config/tmux-claude/lang` so that
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
| Telemetry history (traces, routing, Telegram, OpenTelemetry rows) | Spanish field names and values | English | Old rows are translated when read; the files are never rewritten. `ws-telemetry sql` folds the old column names and values into the English ones in its `traces` view |
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
| Accounts and profiles | `ws-profile`, `claude-account`, `claude-as`, `claude-work`, `claude-personal` | [10](#10-accounts-and-profiles) |
| Protection | `tmux-level` (`--agent`), `tmux-solo` (`--hours`, `--unsandboxed`, `--with-network-tools`), `ws-mcp-jail` | [11](#11-protection-levels) |
| Emergency stop and anomalies | `ws-stop-all`, `ws-anomaly` | [11](#emergency-stop-and-anomalies) |
| Memory review | `ws-memory` | [12](#other) |
| Dashboard and reports | `ws-telemetry` (`prompts`, `budgets --override`), `ws-report`, `ws-otel`, `ws-hooks`, `claude-report`, `ws-audit` (`--verify-log`, `--compliance`) | [12](#12-reports-and-telemetry) |
| MCP servers, pinned packages, browser tools | `install.sh --mcp-opt-in/--mcp-accept/--mcp-refresh`, `ws-pinned`, `agent-browser` | [2](#mcp-servers) |
| Managed policy | `install.sh --managed` | [2](#managed-policy-optional) |
| Focus mode | `tmux-focus` | [12](#12-reports-and-telemetry) |
| Telegram | `ws-telegram` | [13](#13-notifications-and-telegram) |
| Theme and screensaver | `tmux-theme`, `tmux-saver`, `tmux-scene`, `tmux-art` | [14](#14-appearance-and-screensaver) |
| Language | `ws-lang` | [15](#15-language) |
| Backups | `ws-backup-lite`, `ws-restore-lite`, `ws-backup-cloud`, `tmux-recover`, `ws-personal` | [16](#16-backups-and-restore) |
| Updates and health | `ws-update`, `ws-kit-update`, `ws-check`, `ws-health`, `ws-verify`, `ws-test`, `ws-tools`, `ws-plugins` | [17](#17-updating-from-the-kit) |
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
| `GUARD_PROD_REGEX` | `prod\|prd\|produccion` | What the guard treats as a production subscription or context, after the list in `~/.config/ws-guard/production.conf` |
| `WS_KIT` | `~/code/claude-workstation` | The kit checkout `ws-kit-update` and `ws-audit --compliance` use |
| `WS_SOLO_HOURS` | `4` | Default expiry of solo mode (1 to 24); the tmux option `@csolo_hours` also sets it |
| `WS_SOLO_NET_HOURS` | `1` | Default expiry of `tmux-solo --with-network-tools` (1 to 4) |
| `WS_GATE_TEMP_ROOTS` | `/tmp:/var/tmp` | Tests only: narrows the roots where the git gate treats a repository without remotes as a throwaway; an entry outside `/tmp` and `/var/tmp` is ignored |
| `WS_SWARM_LEVEL` | `full` | `normal` starts swarm agents at the normal level (audited exception; push still denied) |
| `WS_MEMORY_PRIVATE` | Not set | `skip` sends nothing of a session that contains a `<private>` tag to MemPalace |
| `WS_MEMORY_GATE` | Not set | `warn` keeps the private block and the audit record of memory writes but does not ask (audited on every write; never set it from Claude) |
| `WS_BACKUP_COPY_DAYS` | `30` | Age after which the Windows-side copies of `ws-backup` and `tmux-backup` are pruned |
| `WS_AGENT_BROWSER_DOMAINS` | Not set | Extra domains for one `agent-browser` run (`a.com,*.b.com`) |
| `WS_ANOMALY_MINUTES`, `WS_ANOMALY_THRESHOLD` | `10`, `5` | Defaults of `ws-anomaly` |
| `WS_PROFILE`, `WS_MEMORY` | Set by the tab's profile | The tab's profile and its MemPalace mode (`off`, `on`, `wing:W`), honoured by the memory hooks; never set them from Claude |
| `AZURE_TOKEN_CREDENTIALS` | `AzureCliCredential` in a custom profile | Makes the Azure MCP server use only the profile's `az` login |
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
| `@csolo_hours` | 4 | Default expiry of solo mode, in hours |
| `@cprofile`, `@cprofile_label`, `@cprofile_colour` | Set by `ws-profile tab` and at Claude's start | The tab's profile; the label and colour the bar shows for a custom one |
| `@canomaly_n`, `@canomaly_min` | 5, 10 | Blocked or denied actions in that many minutes that make a session anomalous (🚨 in the bar) |

## 20. Troubleshooting

| Symptom | Action |
|---|---|
| Tabs are missing after a restart | Menu → "Tabs and session" → "Restore tabs from a save…" (`tmux-recover`) |
| Claude does not resume the conversation | In the tab: `claude -c` or `claude -r` |
| Something broke after `install.sh` | Copy the file back from `~/.local/share/ws-kit/backup.<date>/` (the date is in the installer's `Files (backup: …)` line) |
| Menus or hooks say "command not found", tabs are not saved or did not come back | `ws-verify --live` checks the running tmux server and prints the fix for each failure |
| A command prints "was renamed to …" or is not found after upgrading to 3.0 | Use the new name and the new subcommand or option: [Upgrading from 2.x names](#18-upgrading-from-2x-names) |
| Prompts typed in Spanish are no longer routed or detected | `ws-lang es` ([Language](#15-language)) |
| `export.sh` refuses because of "possible secrets" | Move the secret to a vault; a detection pattern goes in `secrets-allow.txt` after review |
| The gate blocks a commit | Fix what is marked; per repository, from your own shell: `git config ws.gate.skip …` |
| Claude reports a read-only file system | That is the sandbox; run the command yourself or add a justified exclusion |
| Open tabs do not send OpenTelemetry data | Export starts when Claude starts: restart the tab (`tmux-claude-restart --all`) |
| WSL is damaged | New Ubuntu → `install.sh` → `ws-restore-lite --restore` → logins |
| `az`, `gh` or `git push` fail in a Claude started by hand | The base is strict: start it with `claude-resume` or restart the tab ([Protection levels](#11-protection-levels)) |
| A tab asks to log in to Claude, or `az` says "Please run az login", after a switch | That profile is not signed in: `ws-profile login NAME claude` (or `azure`) in a terminal |
| A shell prints "this tab runs as «NAME», which is not set up" | A project is pinned to a profile that does not exist: `ws-profile new NAME` or `ws-profile project remove` there |
| Live tabs lost `az`, `gh` or `git push` after upgrading | They started before the strict base: `tmux-claude-restart --all`, and again for the busy ones |
| "BLOCKED by policy (guard.sh)" on a settings, hooks or `CLAUDE.md` edit | Edit it yourself, or open the config-write window ([What the gates do](#what-the-gates-do-in-a-session)) |
| Every commit fails with "gitleaks is missing" | `ws-tools install base` |
| `ws-kit-update` refuses with exit 11 | The release is not signed by a key you trust ([runbook](runbook.md#signing-a-release)) |
| An MCP server is "skipped" by `install.sh` | A changed local executable: review, then `--mcp-accept NAME`; an opt-in one: `--mcp-opt-in NAME`; an old registration: `--mcp-refresh` |
| Every prompt and tool is "held" | The emergency stop is on (`ws-stop-all --status`, then `--clear`) or a hard budget is spent (`ws-telemetry budgets`) |

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
- A `claude` typed by hand runs at the strict base, without the commands the normal level excludes from the sandbox.
- The untrusted-content labels and the injection markers are heuristics: plain social-engineering text with no marker
  is labelled untrusted but not flagged.
- `<private>` redaction works on the exact text; what Claude paraphrased from it is not recognised.
- The hard spend limit is updated about once a minute and only while the dashboard is built; a swarm's `--budget` is
  enforced only while its dashboard runs.
- agent-browser's domain allow list and action policy are defaults of the wrapper, not a sandbox boundary.
