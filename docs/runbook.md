# Runbook

Operation, troubleshooting and recovery steps tested on this workstation (WSL2 + tmux + Claude Code). Each case is
written as symptom, cause and steps.

General rule: run commands that change your home (patches, `install.sh`, `jq` on settings) in a **normal shell**,
never inside Claude, because the sandbox prevents it on purpose. `Ctrl+b g` opens a floating shell.

Menu labels, statuses and messages are quoted exactly as the screen shows them. Command names, flags and stored values
are written as you type them; many are still Spanish words.

## Contents

- [1. Where things are](#1-where-things-are)
- [2. Is it healthy?](#2-is-it-healthy)
- [3. Tabs and tmux](#3-tabs-and-tmux)
- [4. Claude and conversations](#4-claude-and-conversations)
- [5. Claude accounts (work and personal)](#5-claude-accounts-work-and-personal)
- [6. Terminal: completion, ble.sh and copilot](#6-terminal-completion-blesh-and-copilot)
- [7. Sandbox, solo mode and patches](#7-sandbox-solo-mode-and-patches)
- [8. Kit, gate and verification](#8-kit-gate-and-verification)
- [9. WSL and Windows](#9-wsl-and-windows)
- [10. Floating windows, AI in the terminal and tests](#10-floating-windows-ai-in-the-terminal-and-tests)
- [11. Usage and telemetry](#11-usage-and-telemetry)
- [12. Model routing](#12-model-routing)
- [13. Telegram](#13-telegram)
- [14. Kit CI](#14-kit-ci)
- [15. tmux shortcuts, views and swarm](#15-tmux-shortcuts-views-and-swarm)
- [16. Upgrading](#16-upgrading)
- [17. Recovery](#17-recovery)

## 1. Where things are

| What | Where |
|---|---|
| The kit (this repository) | Where you cloned it, for example `~/code/claude-workstation`; remote `andreshma/claude-workstation` |
| Installed scripts | `~/.local/bin/tmux-*`, `~/.local/bin/ws-*`, `~/.local/bin/claude-cuenta` |
| tmux configuration and menus | `~/.tmux.conf`, `~/.config/tmux-claude/` |
| Claude Code settings and hooks | `~/.claude/settings.json`, `~/.claude/hooks/` |
| Conversations | `~/.claude/projects/<folder>/<session>.jsonl` |
| Audit log | `~/.claude/audit/` |
| tmux saves | `~/.local/share/tmux/resurrect` (30 days) |
| Telemetry, dashboard and reports | `~/.local/share/ws-telemetria/`; copies in `%UserProfile%\ws-telemetria\` |
| Routing rules and settings | `~/.config/ws-ruteo/reglas.conf`, `~/.config/ws-ruteo/ajustes.conf` |
| Telegram settings | `~/.config/ws-telegram/ajustes` |
| Budgets and prices | `~/.config/ws-telemetria/presupuestos.conf`, `~/.config/ws-telemetria/precios.json` |
| Backups on the Windows side | `%UserProfile%\.tmux-resurrect-backup`, `%UserProfile%\.claude-wsl-backup`, `%UserProfile%\WSL-Backups\lite`, `%UserProfile%\WSL-Backups` |
| Secrets | Windows Credential Manager, entries named `ws/<name>` (`ws-secret`) |
| Backups of files changed by `install.sh` | Next to each file, as `*.bak.<date>` |

## 2. Is it healthy?

```bash
ws-check && ws-health        # workstation and resilience status
ws-verify                    # read-only verification before pushing kit changes
ws-test                      # isolated behavior tests of what is installed
ws-otel estado               # local OpenTelemetry collector
ws-telegram estado           # Telegram configuration, service and recent events
```

| Check | Healthy when |
|---|---|
| `ws-check` | No line ends in `MISSING` |
| `ws-health` | 15 % free on `/` and 50 GB free on `C:`; a recent tmux save and backup; the kit in sync |
| `ws-verify` | No `FAIL` line; warnings are to be reviewed |
| `ws-test` | The summary line reports no failed tests |

### Is the copy to Windows up to date?

```bash
B=/mnt/c/Users/<user>/.claude-wsl-backup
stat -c 'last copy: %y' "$B/.last"                                          # less than 15 min ago
rsync -anc --out-format='%n' ~/.claude/projects/ "$B/projects/" | grep -c 'jsonl$'   # 0, or only the active ones
```

## 3. Tabs and tmux

### The tabs did not come back after a restart

- **Typical cause:** at startup, something saved the empty session as the "last save" before tmux restored (fixed in
  v1.6.0: `tmux-save-now` waits 3 min and `.tmux.conf` restores only if the session ends up empty). Earlier saves are
  **not deleted** (they are kept for 30 days).
- **Steps (quick):** Menu → "Tabs and session" → "Recover tabs from an earlier save" (`tmux-recuperar`). Pick the most
  recent one that has your tabs from **before** the problem (the one marked `← at startup` is usually the right one).
- **Steps (manual):**

  ```bash
  cd ~/.local/share/tmux/resurrect
  for f in $(ls -t tmux_resurrect_*.txt | head -15); do printf '%s  %s tabs\n' "$f" "$(grep -c '^window' "$f")"; done
  ln -sf ~/.local/share/tmux/resurrect/<good-file>.txt last && tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh
  ```

  Use the real file name (not the example one). Do it on a single line: continuum saves again every minute.
- **If there is no good save:** use the copy in `%UserProfile%\.tmux-resurrect-backup` or the daily backup
  (`ws-restore-lite`, [section 17](#17-recovery)).
- Close the leftover empty tab with `Ctrl+b &`.

### Restarting the workstation cleanly

- **Keeping tabs and conversations (recommended):**

  ```bash
  ws-backup-lite --ahora      # optional: an extra backup
  tmux kill-server            # first: Ctrl+b Ctrl+s
  ```

  In PowerShell: `wsl --shutdown`, wait 10 s and run `dev`.
- **From scratch (without restoring tabs):** `touch ~/tmux_no_auto_restore` before `tmux kill-server`. To restore
  again afterwards: `rm ~/tmux_no_auto_restore` and `Ctrl+b Ctrl+r`.
- Neither of the two deletes conversations.

### A process got stuck in a tab

1. Press `Ctrl+C` (twice if needed).
2. From another tab: `pkill -f '<part of the command>'` (for example `pkill -f 'claude auth status'`).
3. Last resort: `Ctrl+b :` and then `respawn-pane -k` (a clean shell in the same folder, without closing the tab).

### The menu or the shortcuts do not respond

- Reload the configuration: `tmux source-file ~/.tmux.conf`.
- Check the syntax without touching your session: `ws-verify --rapido` (tmux section).

## 4. Claude and conversations

### A tab opened without Claude or did not resume the conversation

- In the tab: `claude -c` (the most recent one for that folder) or `claude -r` (pick from the list).
- Menu → "Claude in this tab" → "Protection" → "Restart without changing the protection (resumes the conversation)":
  it closes Claude and resumes.

### A conversation was lost

- Conversations are in `~/.claude/projects/<folder>/<session>.jsonl` and are copied to Windows every 15 min
  (`%UserProfile%\.claude-wsl-backup\projects`). Copy the project folder back to `~/.claude/projects/` and run
  `claude -r` in the tab.
- From the daily backup: `ws-restore-lite` (test) and then `ws-restore-lite --restaurar`
  ([section 17](#17-recovery)).
- Whatever an agent was executing at the instant of an outage is not recovered; the conversation is, up to the last
  message: ask it to continue.

## 5. Claude accounts (work and personal)

- The work account (`trabajo`) uses `~/.claude`; the personal account uses `~/.claude-personal`. They share
  conversations and setup; login and policies are separate.
- **Switch the tab's account (same conversation):** Menu → "Claude in this tab" → "Switch this tab to the … account
  (same conversation)". Verify with `/status` inside Claude.
- **See which organization each one has:**

  ```bash
  timeout 15 claude auth status --text | grep -iE 'org|email'
  timeout 15 env CLAUDE_CONFIG_DIR=~/.claude-personal claude auth status --text | grep -iE 'org|email'
  ```

- **The personal account ended up with the work organization:** log out of the personal one **only**
  (`claude-cuenta logout personal`), switch claude.ai to the personal organization in the browser and log in again
  (`claude-cuenta login personal`). **Never** use `/logout` or `claude auth logout` without `CLAUDE_CONFIG_DIR`: they
  would log out the work account.
- **Both accounts show the same organization** (it happened when switching organization in the browser during the
  personal login): log in again on the one that is wrong, with the browser on the correct organization. Work:
  `env -u CLAUDE_CONFIG_DIR claude auth login`; personal: `claude-cuenta login personal`. Switching account per tab is
  refused while both are on the same organization. Always check with `claude-cuenta estado`.
- **The login screen does not let you copy the URL:** do not do it in a floating window. In a normal tab:
  `BROWSER=wslview claude-cuenta login personal`. If the browser does not open: the `c` key copies the URL, or
  Shift + drag to select and `Ctrl+Shift+C`. If the browser shows a code, paste it with `Ctrl+Shift+V`.
- Before continuing company work on the personal account, remember that the code and the conversation go to that
  organization (without the terms of the Team plan).

## 6. Terminal: completion, ble.sh and copilot

- **The copilot (`Alt+a`, `Alt+e`, `Alt+x`) does not respond:** `timeout 15 claude auth status --text`; if there is no
  session, log in. Model: `export AI_SHELL_MODEL=haiku` (the default).
- **ble.sh gets in the way or looks odd:** in the session, `ble-detach`; permanently,
  `touch ~/.config/tmux-claude/sin-ble` and open a new tab. The rest (Tab, fzf, copilot) keeps working.
- **Completion is missing for a newly installed tool:** `ws-completions`.

## 7. Sandbox, solo mode and patches

- **"Read-only file system" or an operation blocked inside Claude:** that is the sandbox. Run it yourself with
  `!command`, or put the tab in **solo mode** (Menu → "Claude in this tab" → "Protection" → "Solo mode: auto without
  sandbox (asks you for critical actions)") and return it to normal when you finish.
- **A patch stopped while backing up or writing to your home:** it was run inside Claude. Run it in a normal shell;
  patches are idempotent (what is already applied shows as `same`).
- **A patch was cut off with no message:** run it again; if it happens again, paste the full output.

## 8. Kit, gate and verification

- **Before every push to the kit:** `ws-verify` (read-only). Do not push if it reports `FAIL`; warnings are to be
  reviewed.
- **`ws-verify` reports `FAIL` on `ws-check` with no detail:** run `ws-check </dev/null` and look at the `MISSING`
  lines.
- **The gate blocks a commit:** fix what is marked with ✖; justified per-repository exception:
  `git config ws.gate.skip <rule>`.
- **`export.sh` refuses because of possible secrets:** move the secret to Key Vault; if it is a detection pattern, add
  it to `secrets-allow.txt` with review.
- **The tag ended up on an earlier commit:** if it is not on GitHub yet, `git tag -f -a vX.Y.Z -m "…"`; if it was
  already pushed, leave it and the fix goes into the next version.
- **Something stopped working after a patch or `install.sh`:** every changed file has its `*.bak.<date>`.

## 9. WSL and Windows

- **WSL does not start:** `wsl --shutdown` and retry. If it still fails, see [section 17](#17-recovery) (snapshot, or
  reinstall + backup).
- **No internet in WSL after changing networks:** remove `networkingMode=mirrored` from `%UserProfile%\.wslconfig` and
  run `wsl --shutdown` (on this corporate network NAT is used).
- **fnm error when opening the terminal:** the `.bashrc` block uses `/tmp/fnm-$UID` if `/run/user/$UID` does not
  exist; open a new tab. If it persists, check that the block is complete.
- **Low disk space:** `ws-health` requires 15 % free on `/` and 50 GB on `C:`. Clean caches
  (`npm cache clean --force`, old `node_modules`) before backups.

## 10. Floating windows, AI in the terminal and tests

- **Using a floating window like a normal tab:** wheel = scroll; drag = select and copy to the Windows clipboard;
  `Ctrl+b /` = search; `q` leaves scroll; Shift+click opens a URL; `Ctrl+b d` closes.
- **A floating window hung:** `tmux -L flot kill-server` (closes all floating windows; your tabs are untouched).
- **Turn on the grey AI suggestions:** `ws-secret set anthropic-api-key` (a Claude Console key; it is stored encrypted
  in Windows Credential Manager) and open a new tab. Check: `ws-secret has anthropic-api-key`.
- **No suggestions appear:** check the key (above), that ble.sh is active, and the circuit breaker:
  `cat ~/.cache/ai-shell/circuito` (`0 <date>` = paused for 5 min after 3 failures; `rm ~/.cache/ai-shell/circuito`
  resets it). Turn them off for one session: `export AI_SHELL_GHOST=0`. Change the model:
  `export AI_SHELL_API_MODEL=…`.
- **Cost:** suggestions use the API (Console billing, separate from the Team plan), with Haiku and short responses;
  one request in flight and at least 0.8 s between requests. Check spending at platform.claude.com.
- **Rotate or remove the key:** `ws-secret set anthropic-api-key` (replaces) or
  `ws-secret delete anthropic-api-key`.
- **Test everything:** `ws-test` (isolated: does not touch your session or your accounts and spends no usage) and
  `ws-test --ia` (real Claude and API).
- **Sandbox mask files (`Sandbox mask files left behind`):** close Claude in that repository and delete only the empty
  entries that git does not know about:

  ```bash
  find . -maxdepth 3 -empty \( -path './.claude*' -o -name .mcp.json -o -name .vscode -o -name .gitmodules \) -not -path './.git/*' \
    | while read -r p; do git ls-files --error-unmatch "$p" >/dev/null 2>&1 || echo "$p"; done | tee /tmp/masks.txt
  xargs -a /tmp/masks.txt -d '\n' rm -df
  ```

## 11. Usage and telemetry

- **Open the dashboard:** Menu → "Usage and reports" → "Usage dashboard (browser)", or `ws-telemetria abrir`. File:
  `%UserProfile%\ws-telemetria\tablero.html` (regenerated every minute; the page reloads by itself).
- **The dashboard does not update:** run `ws-telemetria build` by hand and check that tmux is running (the
  every-minute save triggers it). If the "Updated" time does not change, check `~/.local/bin/tmux-backup`.
- **Costs:** they are the equivalent at API prices, not what you pay on the Team plan. Prices are in `ws-telemetria`
  (the `PRECIOS` table); to adjust one: `~/.config/ws-telemetria/precios.json` with
  `{"claude-opus-5-5": [input, output, cache_5m, cache_1h, cache_read]}` (input, output, 5 min cache write, 1 h cache
  write, cache read) in USD per million tokens.
- **Your own queries:** `ws-telemetria sql` (requires DuckDB) or read `~/.local/share/ws-telemetria/turnos.jsonl`.
- **Privacy:** transcript-derived data and hook traces store no conversation text; only tokens, lengths, tool names,
  project and branch. Retention: 13 months. Delete everything:
  `rm -rf ~/.local/share/ws-telemetria "%UserProfile%/ws-telemetria"`.
- **Open tabs do not send OpenTelemetry data:** export starts when Claude starts; restart the tabs
  (`tmux-claude-restart --todas`).

### Traces, estimation and budgets

| Task | Command |
|---|---|
| See which tools are slow or fail | `ws-telemetria trazas --dias 7` |
| Hours and cost of a ticket (branch `ABC-123-…`) | `ws-telemetria estimar ABC-123`; also `--por proyecto` and `--csv` |
| Last week's report | `ws-telemetria semana` (saved to `%UserProfile%\ws-telemetria\semana-YYYY-Www.md`) |
| Monthly budget per project | `~/.config/ws-telemetria/presupuestos.conf` with `project=usd` lines (`*=usd` for the total), then `ws-telemetria presupuestos` |
| Excel or Power BI | `ws-telemetria exportar` writes `%UserProfile%\ws-telemetria\datos\*.csv` |
| Free-form SQL | `ws-telemetria sql`, for example `SELECT herramienta, count(*) FROM trazas GROUP BY 1` |

- No new traces: `jq '.hooks.PostToolUse' ~/.claude/settings.json | grep ws-trazas` and check that
  `~/.claude/hooks/ws-trazas.sh` is executable.
- Turn off: remove the `ws-trazas.sh` entries from `settings.json` (`.bak.*` backup from patch 51).
- Telegram: `semanal_dia`, `semanal_hora`, `presupuestos=on|off` in `~/.config/ws-telegram/ajustes`.

## 12. Model routing

- **How it works:** when you send a text to Claude, if a rule in `~/.config/ws-ruteo/reglas.conf` says it belongs to a
  different tier than the tab's model, a window appears: `y` switches and sends (`s` also works), `n` sends with the
  current one (it does not suggest that tier again for 30 min), `x` returns the text so you can edit it. With no
  answer in 30 s it sends with the current one.
- **Moving down a model:** it only asks when context is below `bajar_max_ctx` (30 % by default, in
  `~/.config/ws-ruteo/ajustes.conf`). Above that, routing suggests the cheap subagent to Claude and does not change
  the model.
- **Turn it off:** Menu → "Claude in this tab" → "Model" → "Turn off automatic routing in ALL tabs (asks before
  switching)", or `tmux set -g @cruteo off`.
- **Change the model by hand:** the same menu, or `cr -t sonnet "task"`. Your default model does not change: it is
  restored in `settings.json` after `/model`.
- **A rule classifies wrongly:** `cr --explica "the task"` says which rule won. Edit `reglas.conf` (the first match
  wins) and run `cr --probar` (it must stay at 90 % or more).
- **The text got "stuck":** if the window did not appear (no terminal attached), it is sent by itself with the current
  model in about 1 s. Pending texts live in `$XDG_RUNTIME_DIR/ws-ruteo/` (0600) and are deleted when used.
- **Uninstall the hook:** remove the `ws-ruteo.sh` entry from `hooks.UserPromptSubmit` in `~/.claude/settings.json`.

## 13. Telegram

- **Set up (once):** `ws-telegram configurar`. Create the bot in @BotFather, paste the token (it is stored in Windows
  Credential Manager as `ws/telegram-bot-token`) and send `/start` to your bot.
- **Notifications do not arrive:** `ws-telegram estado` (configured, turned on, service running) and
  `ws-telegram prueba`. tmux starts the service every minute; by hand: `ws-telegram asegurar`. If the company network
  blocks `api.telegram.org`, the status shows `error_api`.
- **A button says "The screen changed; I sent nothing":** the dialog is no longer the same (you answered on the PC or
  Claude moved on); nothing was sent. Buttons expire after 10 min.
- **`!` commands from Telegram:** each command arrives in a code message (tap it to copy it). "▶ Run" runs it in that
  tab as `!` and replies with the redacted output. Dangerous ones arrive without a button: run them on the PC.
  Forwarding or typing text to the bot executes nothing.
- **Replying with text:** `ws-telegram texto on` (asks for the PIN the first time). In Telegram, use Reply on Claude's
  question (the ones that show ↩), starting with the PIN: `4821 use an opaque cursor`. Change the PIN:
  `ws-telegram texto pin`. If it was turned off because of wrong PINs: `ws-telegram texto on` on the PC.
- **Alerts and daily summary:** adjusted in `~/.config/ws-telegram/ajustes` (`resumen_hora`, `consumo_usd_h`,
  `contexto_pct`, `atorada_min`, `alertas=on|off`). Test the summary: `ws-telegram resumen`. Every alert is rate
  limited (30 min per tab; reminders every 3 min). Buttons: `/compact` and switch account.
- **Turn off:** Menu → "Workstation" → "Telegram: turn notifications on or off", or `ws-telegram apagar`.
- **Lost phone or compromised Telegram account:** `ws-telegram olvidar` and, in @BotFather, `/revoke` the bot. Without
  the token, nobody can send keys to your tabs.

## 14. Kit CI

- **What runs:** on every push to `main` and on every pull request: lint (shellcheck, Python, JSON, tmux), then SAST
  and secrets (bandit, gitleaks), then `tests/run.sh`. See it in GitHub → Actions.
- **gitleaks fails on a test pattern:** if the file contains only detection patterns or fake data, add it to
  `.gitleaks.toml` (`[allowlist] paths`) with a comment; if it is a real secret, rotate it and remove it.
- **bandit fails:** fix the finding; if it is a false positive, `# nosec <rule>` on that line and the reason in a
  comment above it.
- **Locally before pushing:** `ws-verify` covers the same; CI is the source of truth for anyone using the kit.

## 15. tmux shortcuts, views and swarm

### Shortcuts added by patch 52

| Something fails | Check |
|---|---|
| `Ctrl+b e` pastes nothing | Check whether the tab has another pane; if not, the picker opens. `tmux-panel --texto %N` shows the block |
| The "Notify me when it finishes" notification does not arrive | `ws-aviso --forzar prueba texto`; Telegram: `ws-telegram estado`. The notification goes out when the pane returns to bash |
| The palette runs in another tab | Open it from the target tab; the `#{formats}` are expanded against it |
| The label is not visible in the status bar | `tmux-etiqueta --barra` (a theme change rewrites the formats) |
| Focus mode got stuck on | `tmux-enfoque off` |
| Second monitor: leftover `-m2` sessions | They are deleted when their window closes; if not: `tmux kill-session -t <group>-m2` |

### Patch 53: branch bar, templates, recording, history and swarm

| Something fails | Check |
|---|---|
| CI/PR does not show in the status bar | `tmux-rama .` in the folder; `gh auth status` or `az account show`; `tmux set -g @rama_barra on` |
| The status bar is slow | `tmux set -g @rama_barra off` (everything network-related runs in the background with a 3 min cache) |
| Recording with no events | The pane had another capture (`Ctrl+b H` or history): turn it off and record again |
| History takes a lot of space | `tmux-historial --estado`; `WS_HISTORIAL_DIAS=7`; `tmux-historial off` |
| Swarm with a conflict | Resolve in the main repository (branch `enjambre/<id>/integracion`), commit and `tmux-enjambre integrar <id>` |
| Removing a swarm | `tmux-enjambre limpiar <id>` (keeps unintegrated branches and worktrees with changes) |

## 16. Upgrading

```bash
ws-update                    # Claude Code, plugins, packages
ws-actualizar                # update the workstation from the kit; rolls back if ws-test fails
tmux-claude-restart --todas  # make every idle tab pick up the new configuration
bash export.sh               # capture what is installed back into the kit
ws-verify                    # verify before pushing
```

1. Run `ws-update` for Claude Code, the tmux plugins and the system packages.
2. Run `ws-actualizar` for the workstation itself. It pulls with `--ff-only`, runs `install.sh` (every changed file is
   backed up as `*.bak.<date>`) and then `ws-test`. If the tests fail it goes back to the previous commit and
   reinstalls. It does nothing when the kit folder has uncommitted changes or unpushed commits.
3. Reload tmux (`Ctrl+b r`) and restart Claude in the idle tabs (`tmux-claude-restart --todas`) so they pick up the new
   settings, hooks and telemetry.
4. If you maintain the kit: `bash export.sh`, review the diff, `ws-verify`, commit.

If something stopped working after the update, every changed file has its `*.bak.<date>` next to it.

## 17. Recovery

### Backup layers

| Layer | What it stores | Frequency | Where | Recover with |
|---|---|---|---|---|
| tmux (continuum + resurrect) | Tabs, panes, folders | Every minute and when tabs change | `~/.local/share/tmux/resurrect` (30 days) | `tmux-recuperar` |
| `ws-backup` | Conversations and audit log | Every 15 min, incremental, never deletes | `%UserProfile%\.claude-wsl-backup` | Copy back |
| `ws-backup-lite` | All of Claude (conversations, subagents, todos, plans, `/rewind`, history, memory), tmux and inventory | Daily, automatic (14 copies) | `%UserProfile%\WSL-Backups\lite` | `ws-restore-lite --restaurar` |
| Kit (GitHub) | All the configuration | On push | `andreshma/claude-workstation` | `install.sh` |
| `devsnapshot` (optional) | The whole distro | By hand | `%UserProfile%\WSL-Backups` | `wsl --import` |

### Test, back up and restore

- **Test that the backup works:** Menu → "Workstation" → "Test the latest backup" (`ws-restore-lite`): it extracts
  into a temporary folder and verifies SHA-256, readable conversations, tmux, inventory and that it carries no
  credentials.
- **Back up now:** Menu → "Workstation" → "Back up Claude now" (`ws-backup-lite --ahora`).
- **Restore on this machine:** close Claude in every tab and run `ws-restore-lite --restaurar`. Anything that already
  exists and differs is kept as `<file>.~N~` (nothing is overwritten).

### New laptop or lost distro, without a snapshot

1. Install a clean Ubuntu 24.04.
2. Clone the kit and run `bash install.sh`.
3. Copy the latest `claude-lite-*.tar.zst` (and its `.sha256`) to `%UserProfile%\WSL-Backups\lite`.
4. Run `ws-restore-lite` (test) and then `ws-restore-lite --restaurar`.
5. Install packages and tools with the commands it prints.
6. Log in (Claude, az, gh, aws).
7. Run `dev` and press `Ctrl+b Ctrl+r`.

Time: 30–60 min.

### With a snapshot

Run `wsl --unregister Ubuntu` **only** once the snapshot is verified, and then
`wsl --import Ubuntu %LOCALAPPDATA%\wsl\Ubuntu <snapshot>.vhdx --vhd`.

### Encrypted cloud backup

- **Set up (once):** `ws-respaldo-nube configurar`. Save the private key it shows in your password manager: without
  it, the cloud backups cannot be opened if you lose the laptop.
- **Every day** `ws-telegram` copies the latest lite backup, encrypted, to `OneDrive…\Respaldos\estacion-wsl` (keeps
  7).
- **Every month** the recovery test (local and cloud) arrives through Telegram. By hand: `ws-respaldo-nube probar`.
- **Restore on a new laptop:** `ws-secret set age-respaldo` (paste the key from your password manager),
  `ws-respaldo-nube bajar`, then `ws-restore-lite` (test) and `ws-restore-lite --restaurar`.
