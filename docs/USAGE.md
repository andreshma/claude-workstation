# claude-workstation — User Guide

Day-to-day use of the workstation once it is installed. For installation see the
[README](../README.md#quickstart); for how the pieces fit see [architecture.md](architecture.md); for what goes wrong
and how to recover see [runbook.md](runbook.md).

The interface is in Spanish. Menu labels, status labels and command names are quoted exactly as the screen shows them,
with an English gloss where it helps. `Ctrl+b` is the tmux prefix: press it, release, then press the key.

On the station itself, two commands are always up to date because they read what is installed:

```bash
Ctrl+b h          # cheat sheet of daily shortcuts
ws-menus --ver    # full manual generated from the installed menus, key bindings and commands
```

## Contents

1. [Entering and leaving](#1-entering-and-leaving)
2. [Opening repositories](#2-opening-repositories)
3. [Key bindings](#3-key-bindings)
4. [The menu](#4-the-menu)
5. [Status bar legend](#5-status-bar-legend)
6. [Finding the tab that needs you](#6-finding-the-tab-that-needs-you)
7. [Working with Claude in a tab](#7-working-with-claude-in-a-tab)
8. [Accounts](#8-accounts)
9. [Protection levels](#9-protection-levels)
10. [Reports and telemetry](#10-reports-and-telemetry)
11. [Notifications and Telegram](#11-notifications-and-telegram)
12. [Appearance and screensaver](#12-appearance-and-screensaver)
13. [Backups and restore](#13-backups-and-restore)
14. [Updating from the kit](#14-updating-from-the-kit)
15. [Environment variables](#15-environment-variables)

---

## 1. Entering and leaving

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
| `devdash` · `devagents` | Tab dashboard · live subagents |
| `devsave` | Saves the tmux session now |
| `devcheck` | Runs `ws-check` and `ws-health` |
| `devsnapshot` · `devrestoretest` | Full export of the Ubuntu distro as `.vhdx` (stops WSL for a few minutes) · imports the latest snapshot as a throwaway distro, checks it and deletes it |

Sessions survive closing the terminal and restarting WSL: tmux-continuum saves every minute, `tmux-save-now` saves
when a tab or pane is created, closed or renamed, and each restored tab resumes its Claude conversation.

## 2. Opening repositories

| Action | How |
|---|---|
| Pick a folder and open it with Claude | `Ctrl+b o`. Enter opens; `→` enters the subfolders of the highlighted entry; `←` goes up. If a tab for that folder already exists, it jumps there |
| Open from the shell | `tw <folder> [name]` |
| Open with Opus | `two <folder>` · Menu → «Abrir carpeta con Opus» |
| Open a worktree | `twt <repo> <branch>` · Menu → «Nuevo worktree de este repo» |
| Add a folder as a pane of the current tab | `tp <folder>` |
| Open with a pane layout (Claude + tests + git) | Menu → «Abrir carpeta con plantilla». Templates: `node-api`, `dotnet`, `python`, `terraform`, `qa` |
| Bring recent conversations that have no tab | Menu → «Pestañas y sesión» → «Traer conversaciones recientes a tmux» (`tmux-traer`) |

The picker lists the folders under the roots in `~/.config/tmux-claude/roots.txt`, one per line as
`label|depth|path`. The label is also the **group**: each group is its own tmux session, and a new tab is created in
the session of its group. `Alt+↑/↓` switches group and `Ctrl+b S` lists all groups with their tabs. To keep everything
in one session, set `grupos=off` in `~/.config/tmux-claude/ajustes`.

A tab opens Claude with `claude --continue` when the folder already has conversations, and plain `claude` otherwise.

## 3. Key bindings

### Without prefix

| Keys | Action |
|---|---|
| `Alt+1` … `Alt+9` | Go to tab 1–9 |
| `Alt+←` / `Alt+→` | Previous / next tab |
| `Alt+0` | Last used tab |
| `Alt+s` | Search tabs by name |
| `Alt+Shift+←` / `Alt+Shift+→` | Move the tab left / right |
| `Alt+↑` / `Alt+↓` | Previous / next group |
| Click on `≡ menú` in the bar | Open the menu |
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
| `a` | «Activas ahora»: tabs that are active now, across groups |
| `D` | Tab dashboard |
| `A` | Live subagents (`v` shows a subagent's transcript) |
| `i` | Summary of the tab: where it is, what it is doing, where it stopped |
| `S` | All groups with their tabs |
| `e` | Paste the output of the side pane into Claude's prompt (redacted, without Enter) |
| `?` | Quick question to Claude in a pop-up, outside the tab's context |
| `N` | Notify me when the command in this pane finishes (again: cancel) |
| `u` | Extract URLs, paths, hashes, IDs and tickets from the screen |
| `E` | Label for the tab (blocked, in review, done…) |
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
| `Esc` · `Esc Esc` | Interrupt · go back to an earlier point |
| `Shift+Tab` | Permission modes (plan, auto) |
| `Alt+P` | Model picker |
| `Ctrl+O` | Transcript with reasoning |
| `Ctrl+T` · `Ctrl+R` · `Ctrl+G` | Task list · history · edit the prompt in the editor |
| `Shift+Enter` | New line |
| `!` | Run a command yourself (outside the sandbox) |
| `claude -c` · `claude -r` | Resume the last conversation · choose one |

### In the shell

The interactive shell loads tab completion, fzf (`Ctrl+R` history, `Ctrl+T` file, `Alt+C` folder), grey suggestions
(ble.sh, `→` accepts) and an optional terminal copilot that never executes anything: `Alt+a` turns a request written in
natural language into a command, `Alt+e` explains the command on the line, `Alt+x` proposes a fix for the last failed
command. `AI_SHELL_GHOST=0` turns the grey AI suggestion off.

## 4. The menu

`Ctrl+b m` opens the main menu; each `›` opens a submenu and `Backspace` goes back. The key after each label selects
it. The title shows the group, the tab, Claude's state and the context percentage.

### Main menu

| Section | Key | Label | Action |
|---|---|---|---|
| Ir a (go to) | `a` | Activas ahora, de todos los grupos | Active tabs across groups |
| | `g` | Ir a la siguiente que te espera o lleva rato sin avance | Jump to the next tab that waits for you or is stalled |
| | `f` | Buscar pestaña por nombre | Search tabs |
| | `D` | Tablero de pestañas | Dashboard |
| | `o` · `O` | Abrir carpeta o repo · Abrir carpeta con Opus | Open a folder |
| | `T` | Abrir carpeta con plantilla | Open with a pane template |
| | `w` | Nuevo worktree de este repo | New worktree (asks for the branch) |
| Esta pestaña (this tab) | `c` | Claude en esta pestaña › | Submenu, enabled when the tab has Claude |
| | `s` | Pestañas y sesión › | Tabs and session |
| | `l` | Paneles, copiar y avisos › | Panes, copy and notifications |
| Herramientas (tools) | `p` | Paleta de comandos | Command palette |
| | `?` | Pregunta rápida a Claude | Quick question |
| | `x` | Vistas: monitor, enfoque, flotantes, historial › | Views |
| | `r` | Consumo e informes › | Usage and reports |
| | `e` | Estación: salud, respaldos, avisos › | Station: health, backups, notifications |
| | `v` | Apariencia y protector de pantalla › | Appearance and screensaver |
| Ayuda (help) | `m` | Manual completo | Full generated manual |
| | `h` | Atajos de teclado | Shortcuts |

### «Claude en esta pestaña» (`c`)

| Section | Key | Label |
|---|---|---|
| Conversación | `c` `k` `b` `t` `T` `e` `B` | Ver contexto · Compactar conversación · Volver a un punto anterior · Transcripción y razonamiento · Tareas y subagentes · Interrumpir · Mandar a segundo plano |
| Modelo y modo | `9` | Modelo › — Fable, Opus, Sonnet, Haiku, Claude's own picker, and the automatic-routing switch |
| | `p` | Modo de permisos / plan |
| | `S` | Protección › — see [Protection levels](#9-protection-levels) |
| Con otras pestañas | `x` | Mandar el panel de al lado a Claude |
| | `D` | Mismo texto a varias pestañas con Claude (broadcast the same text to several tabs) |
| | `Z` | Enjambre: varias Claude en paralelo sobre una meta (swarm: one worktree and branch per subtask) |
| | `E` | Exportar mi trabajo para otro Claude (handoff package, `ws-traspaso`) |
| | `s` · `w` | Claude solo en pestaña nueva · en worktree nuevo |
| Cuenta | `a` | Cambiar esta pestaña a cuenta personal / trabajo (misma conversación) |
| | `n` | Pestañas nuevas con: … (default account for new tabs) |
| | `f` | Este proyecto siempre con la cuenta de esta pestaña (pin the project) |
| | `L` | Iniciar sesión en cuenta personal |
| | `+` | Más comandos de Claude › — `/status`, `/usage`, `/mcp`, `/effort`, task list, editor, draft |

### «Pestañas y sesión» (`s`)

| Key | Label |
|---|---|
| `N` | Ir por número… |
| `S` | Grupos y pestañas |
| `i` | Resumen: qué, dónde y en qué se quedó |
| `E` | Etiqueta de la pestaña |
| `r` · `x` | Renombrar pestaña · Cerrar pestaña |
| `s` · `R` | Guardar sesión ahora · Restaurar sesión guardada |
| `u` | Recuperar pestañas de un guardado anterior (`tmux-recuperar`) |
| `t` | Traer conversaciones recientes a tmux |
| `G` | Guardar esta pestaña como plantilla |

### «Paneles, copiar y avisos» (`l`)

| Key | Label |
|---|---|
| `v` · `h` | Dividir lado a lado · Dividir arriba y abajo |
| `z` | Zoom del panel |
| `M` · `T` | Layout principal 65 % · Mosaico |
| `!` · `x` | Sacar el panel a su pestaña · Cerrar este panel |
| `c` · `Y` | Scroll y copiar · Copiar las últimas 200 líneas |
| `u` | Extraer URLs, rutas, IDs… |
| `N` | Avísame cuando termine |
| `L` | Logs en vivo con alarma (Kubernetes, App Service, Docker, a file, your own command) |

### «Vistas» (`x`)

| Key | Label |
|---|---|
| `v` | Mostrar / Ocultar monitor de cómputo |
| `A` | Subagentes en vivo |
| `f` | Modo enfoque: 25/50/90 min sin avisos (focus mode) |
| `m` · `e` | Segundo monitor · Espejo de solo lectura (read-only mirror for screen sharing) |
| `g` · `P` | Shell flotante persistente · PowerShell flotante |
| `h` · `y` | Buscar en el historial de todos los paneles · Historial buscable: encender/apagar (off by default) |
| `r` · `V` | Grabar este panel / Detener grabación · Abrir carpeta de grabaciones |

### «Consumo e informes» (`r`)

| Key | Label | Command |
|---|---|---|
| `i` | Informe completo con hallazgos de Claude | `ws-informe --ia --ia-memoria --abrir` |
| `j` | Informe rápido, sin Claude | `ws-informe --abrir` |
| `a` | Aprender de mí: hechos para MemPalace (tú eliges) | `ws-aprender hechos` |
| `k` | Crear comandos «/» de lo que repites | `ws-aprender comandos` |
| `c` | Tablero de consumo (navegador) | `ws-telemetria abrir` |
| `r` | Herramientas: tiempos, errores y costo (7 días) | `ws-telemetria trazas` |
| `t` | Estimación por ticket (90 días) | `ws-telemetria estimar` |
| `s` | Reporte de la semana pasada | `ws-telemetria semana` |
| `p` | Presupuestos del mes | `ws-telemetria presupuestos` |
| `x` | Exportar CSV para Excel o Power BI | `ws-telemetria exportar` |

### «Estación» (`e`)

| Key | Label | Command |
|---|---|---|
| `v` | Revisión de la estación | `ws-check`, `ws-health` |
| `b` · `B` | Respaldar Claude ahora · Probar el último respaldo | `ws-backup-lite` · `ws-restore-lite` |
| `P` | Tu configuración personal: sincronizar | `ws-personal sync` |
| `R` | Reiniciar Claude en todas las pestañas libres (toma la configuración nueva) | `tmux-claude-restart --todas` |
| `U` | Actualizar la estación desde el kit | `ws-actualizar` |
| `Q` | Calidad y seguridad del repo | `ws-gate repo-view` |
| `u` | Auditoría de Claude | `claude-report` |
| `z` | Cambiar suscripción de Azure | `tmux-az-sub` |
| `I` | Herramientas instaladas | `ws-tools` |
| `n` | Avisos de Windows: encendidos / apagados | toggles `@cnotify` |
| `g` · `G` | Telegram: encender o apagar avisos · respuestas de texto sí/no (PIN) | `ws-telegram alternar` · `ws-telegram texto alternar` |

### «Apariencia y protector de pantalla» (`v`)

| Key | Label |
|---|---|
| `o` · `c` · `a` | Tema oscuro · Tema claro · Automático: sigue a Windows |
| `t` | Tema de Claude en esta pestaña (`/theme`) |
| `s` | Elegir escena de una lista |
| `p` · `n` | Ponerlo ahora · Siguiente escena |
| `e` | Protector: encendido / apagado |

## 5. Status bar legend

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
| ✔ ✖ ● · `#12` ✓ ✎ 📝 · `ABC-123` | CI passed / failed / running · pull request number, approved / changes requested / draft · ticket taken from the branch name |
| A label word | The tab's label (`Ctrl+b E`) |
| ★ | The tab's folder is a favorite (`Ctrl+b *` toggles it, `Ctrl+b F` lists them) |

### State labels

| Label | Meaning |
|---|---|
| 🧠 pensando 42s | Thinking |
| 🔧 Bash 2m | Running a tool, with its name |
| ✋ aprobar Bash 5m | A permission dialog is open: Claude waits for your approval |
| ❓ te pregunta 1m | Claude opened a question dialog |
| 👉 te toca 3m | The turn ended and Claude's last message asks you something or asks you to do something |
| 📦 compactando | Compacting the conversation |
| 🐝 3 agentes 4m | Subagents working |
| ✔ listo hace 12m | Finished, nothing pending |
| ⏳ sin avance 11m | Thinking or running a tool with no events for 10 minutes |
| ⛔ interrumpido | You pressed `Esc` |
| ✖ error API | The turn ended with an API error |

«te toca» is decided from the text of Claude's last message when the turn ends: it ends in a question, or it asks you
to run a command, decide, confirm or provide a value. `WS_TETOCA=0` turns it off, and those tabs then show «listo».

### Right side

| Segment | Meaning |
|---|---|
| `≡ menú` | Click to open the menu |
| `⚠ 2,5` | Tabs 2 and 5 wait for you: a permission or question dialog, «te toca», or an API error |
| `⏳ 3(12m)` | Tab 3 has had no activity for 12 minutes |
| `◉ $4.1/h` | Estimated spend of all sessions over the last 10 minutes, at API-equivalent prices. Green, yellow from 5 USD/h, red from 15 |
| `5h 82%` | Usage limit, when the plan exposes it |
| Subscription, branch, time | Active Azure subscription, branch of the tab's folder, clock |

Thresholds are tmux options: `@cwatch_remind` (3 min), `@cwatch_stall` (10 min), `@cburn_warn` (5), `@cburn_crit`
(15). Example: `tmux set -g @cwatch_stall 20`.

`Ctrl+b v` adds a second line with CPU, RAM and network sparklines, free space on `C:`, spend per hour and the count of
working, waiting and finished Claude sessions.

## 6. Finding the tab that needs you

| Tool | Shows |
|---|---|
| `⚠` in the bar | The tab numbers that wait for you |
| `Ctrl+b m`, `g` | Jumps to the **next** tab that waits or is stalled, changing group if needed. Repeating it cycles through them |
| `Ctrl+b a` | «Activas ahora»: first what waits for you (✋ ❓ 👉 ✖), then what is working, then what finished in the last 15 minutes; all groups. Enter goes to the tab |
| `Alt+s` or `Ctrl+b f` | Tab search, ordered with the waiting tabs first |
| `Ctrl+b D` | Dashboard of every tab: state with its time, what it is doing, turn duration, model, context, cost, branch, uncommitted changes, label |
| Windows notification | Sent when a tab you are not looking at needs you or finishes a turn of at least 20 seconds. A tab with an open dialog is reminded every `@cwatch_remind` minutes; a «te toca» tab gets a single reminder |

## 7. Working with Claude in a tab

| I want to | How |
|---|---|
| Give Claude the output of my tests or build | Run them in a side pane, then `Ctrl+b e` in Claude's pane. The last lines are redacted and pasted into the prompt without sending |
| Ask something without polluting the context | `Ctrl+b ?`. End the line with `+p` to include the last 60 lines of the pane. No tools, no saved session |
| Choose the model for a task | `cr "task"` classifies it, says which tier and why, and sends it after you confirm. `cr -t sonnet "task"` forces a tier; `cr --dry-run` only classifies |
| Change the tab's model | Menu → «Claude en esta pestaña» → «Modelo». Only this tab changes |
| Be asked before a mismatched model is used | Automatic routing: when a rule in `~/.config/ws-ruteo/reglas.conf` says the task belongs to another tier, a pop-up offers `s` switch and send, `n` send as is, `x` return the text. No answer in 30 seconds sends with the current model. Toggle it in the «Modelo» submenu |
| Leave Claude working alone | Menu → «Claude en esta pestaña» → «Claude solo en pestaña nueva» or «en worktree nuevo» |
| Run several Claudes on one goal | Menu → «Enjambre». Claude proposes 2–6 independent subtasks, you edit and confirm, each gets its worktree, branch and tab. `tmux-enjambre integrar <id>` merges them into an integration branch; it never pushes |
| Send the same text to several tabs | Menu → «Mismo texto a varias pestañas con Claude» |
| Hand the work to another Claude | `ws-traspaso` (menu key `E`): a Markdown package with a summary, branch, changes, commits, diff, task list and touched files, saved and copied to the clipboard. `--conversacion` adds the transcript |
| Restart Claude so it picks up new settings | Menu → «Protección» → «Reiniciar sin cambiar la protección», or for every tab `tmux-claude-restart --todas` |
| Be told when a long command ends | `Ctrl+b N` on the pane |

Documents: when Claude reads a PDF, Office file, `.csv`, `.rtf`, `.odt` or `.epub`, a hook converts it to Markdown
first (`ws-tomd`), in a sandbox without network.

Restart all tabs:

```bash
tmux-claude-restart --todas --lista             # shows what it would do: reinicia / ocupada / solo
tmux-claude-restart --todas                     # restarts free tabs; each resumes its conversation
tmux-claude-restart --todas --tambien-ocupadas  # also interrupts tabs that are working
```

Tabs that are thinking, running a tool, compacting or showing a dialog are skipped by default. Each tab keeps its
protection level; tabs in solo mode are left as they are.

## 8. Accounts

The station runs two Claude accounts: `trabajo` (work, in `~/.claude`) and `personal` (in `~/.claude-personal`). Each
has its own login. Settings, hooks, agents and conversations are shared, so switching a tab continues the same
conversation.

### First-time setup of the personal account

```bash
claude-cuenta setup            # prepares ~/.claude-personal; does not touch ~/.claude
claude-cuenta login personal   # switch claude.ai to your personal organization in the browser first
claude-cuenta estado           # default account, organization of each login, pinned projects
```

### Daily use

| I want to | Command | Menu («Claude en esta pestaña» → Cuenta) |
|---|---|---|
| Switch this tab to the other account | `claude-cuenta pestaña` | `a` |
| Choose the account for new tabs | `claude-cuenta usar trabajo` · `claude-cuenta usar personal` | `n` |
| Pin a project to an account | `claude-cuenta proyecto personal [folder]` | `f` (pins the project to this tab's account) |
| Unpin | `claude-cuenta proyecto quitar [folder]` | — |
| List pinned projects | `claude-cuenta proyectos` | — |
| Close only the personal session | `claude-cuenta logout personal` | — |
| Start one Claude with a given account | `claude-trabajo` · `claude-personal` (shell aliases) | — |

Rules:

- A pinned project covers its repository root, every subfolder and its `<repo>.wt/…` worktrees. Every new tab opened
  there uses the pinned account, whatever the default is.
- Without a pin, new tabs use the default account.
- A tab that was switched by hand keeps its account in that pane's shell; it shows `·P` after its name when it is on
  the personal account.
- The switch is refused when both logins belong to the same organization, because the usage would be charged to the
  wrong one.
- A tab in solo mode stays in solo mode after switching.

## 9. Protection levels

Each tab has its own level. Changing it restarts Claude in that tab and resumes the conversation; anything half done
in that turn is lost.

| Level | Menu key | What changes |
|---|---|---|
| `completo` 🔒 | `c` | Sandbox on with no way out: no unsandboxed commands and no excluded commands, so `az`, `gh`, `git push`, `kubectl` and similar run inside the sandbox, without network or credentials, and mostly fail. All kit rules stay |
| `normal` | `n` | Your `~/.claude/settings.json` as it is: sandbox on, with the excluded commands that need network and credentials |
| `puro` 🔓 | `p` | No sandbox and none of the kit's `allow`/`ask` rules: Claude asks as it would without the kit |
| Modo solo 🤖 | `s` | Claude in `auto` permission mode without the sandbox, to work alone. The `ask` rules still ask you |

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

In the «Protección» submenu, «Reglas activas (/permissions)» and «Estado del sandbox (/sandbox)» show what Claude
actually loaded. After a restart of the station, restored tabs are started again with `claude-resume`, that is, with
your normal settings.

When Claude reports a read-only file system or a blocked command, that is the sandbox or the guard working. Run the
command yourself with `!` or in a floating shell (`Ctrl+b g`).

Telegram never offers to run commands in a `puro` or solo-mode tab.

## 10. Reports and telemetry

Everything is computed and stored locally under `~/.local/share/ws-telemetria`. Costs are API-equivalent prices; a
subscription plan is not billed per token.

### Dashboard

```bash
ws-telemetria abrir      # regenerates and opens the dashboard in the Windows browser
ws-telemetria resumen    # today and 7 days, per project, in the terminal
```

The dashboard is regenerated about once a minute while tmux is running. It shows today, 7 and 30 days; trends over the
whole history; per project, model, session and tool; machine resources and network; the OpenTelemetry section «API,
permisos y tiempo activo» (API calls with typical duration, p95 and time to first token; errors by code; who decides
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

**Estimation ratios** («razones para estimar», 30 days) appear in both the dashboard and the report: your words and
Claude's per turn, tokens per word, model and tool calls per turn, output speed, cost per turn, per thousand words, per
million tokens and per active hour, and CPU, disk and RAM per token and per turn. Each states its sample size. The
report also has an **estimation baseline** per project: active hours, turns, tokens, words, lines, CPU and cost, with
cost per hour and per 100 lines.

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
| `ws-auditoria` | Read-only audit of the station by pillar, with a report |
| `tmux-enfoque 25` | Focus mode for 25 minutes: minimal bar, no Windows notifications |

## 11. Notifications and Telegram

Windows notifications are on by default; clicking one brings Windows Terminal to the front on that tab. Toggle them in
Menu → «Estación» → «Avisos de Windows», or `tmux set -g @cnotify off`.

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
| Answer a permission or question dialog | Tap one of the buttons (the dialog's options, or cancel). Codes are single-use and expire in 10 minutes |
| Reply with text to an open question | Reply to the message starting with your PIN, then a space and the answer. Requires `ws-telegram texto on` |
| Run a command Claude proposed | Tap «▶ Ejecutar» under the command. Dangerous commands arrive as text only, to be run at the PC |

See the [threat model](THREAT_MODEL.md#telegram-remote-control) for what this channel does and does not protect.

## 12. Appearance and screensaver

```bash
tmux-theme oscuro | claro | auto    # auto follows Windows
tmux-saver --escena oceano          # show a scene now; any key returns
tmux-saver --fijar oceano           # keep one scene; `aleatoria` picks a different one each time
tmux-saver --toggle                 # turn the screensaver on or off
tmux-escena                         # pick from a list (Menu → Apariencia → s)
tmux-arte --lista                   # scenes this machine can draw (--todas: all)
```

The screensaver appears after 10 minutes without touching the terminal (`minutos=` in
`~/.config/tmux-claude/apariencia`) and any key dismisses it; tabs keep working behind it. It does not appear while a
permission dialog is open.

| Scenes | Names | Needs |
|---|---|---|
| ASCII art (13) | `cumbres`, `aurora`, `nevada`, `velero`, `peces`, `tuberias`, `batalla`, `fogata`, `cerezo`, `lluvia`, `galaxia`, `nebulosa`, `hiperespacio` | Nothing extra |
| Shading engine (12) | `oceano`, `planeta`, `dona`, `lava`, `vuelo`, `boreal`, `nubes`, `agujero`, `estanque`, `fuego`, `tunel`, `fractal` | `python3-numpy`; without it they are left out of the random choice |
| `galeria` | Your images and animated GIFs (`png`, `jpg`, `gif`, `webp`) | `chafa`, and files in `~/.config/tmux-claude/galeria` |

```bash
ws-tools install numpy chafa
```

## 13. Backups and restore

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
[runbook](runbook.md).

## 14. Updating from the kit

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

If you maintain the kit, the reverse direction is `bash export.sh` (captures what is installed into `files/`), review
the diff, `ws-verify`, commit.

## 15. Environment variables

| Variable | Default | Effect |
|---|---|---|
| `WS_TETOCA` | `1` | `0` disables the «te toca» state |
| `WS_OTEL_CONTENIDO` | `1` | `0` makes the collector store no text or identity |
| `WS_OTEL_PUERTO` | `14318` | Collector port (the endpoints in `settings.json` must match) |
| `WS_OTEL_RETENCION_DIAS` | `395` | Days the collector keeps its files |
| `WS_GALERIA` | `~/.config/tmux-claude/galeria` | Folder for the `galeria` scene |
| `WS_GALERIA_SEG` | `25` | Seconds per image |
| `WS_GALERIA_SIMBOLOS` | — | `ascii` to use letters and signs only |
| `WS_ARTE_COLOR` | auto | `24` or `256` forces the color depth of the scenes |
| `WS_PREGUNTA_MODELO` | Haiku | Model for the quick question (`sonnet`, `opus`) |
| `GUARD_PROD_REGEX` | `prod\|prd\|produccion` | What the guard treats as a production subscription or context |
| `CLAUDE_NOTIFY_MIN_SECS` | `20` | Minimum turn length for a "finished" notification |
| `AI_SHELL_GHOST` | `1` | `0` turns off the grey AI suggestion in the shell |
