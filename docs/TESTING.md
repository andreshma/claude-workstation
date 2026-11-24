# Testing

claude-workstation has three test entry points and a set of static checks. They test different things on purpose:

| Suite | Tests | Needs | Touches your machine |
|---|---|---|---|
| `tests/run.sh` | The **kit**: `export.sh`, `install.sh`, the payload's JSON and shell lint, and the guard | bash, jq, git; shellcheck optional | No: temporary homes only |
| `tests/guard.sh` | The PreToolUse guard (`files/home/.claude/hooks/guard.sh`) | bash, jq, git | No: a temporary home and repository |
| `ws-test` | The **installed** workstation: the scripts in `~/.local/bin` and the installed tmux configuration | tmux, jq, git, an installed workstation | No: an isolated home, isolated tmux sockets and a simulated Claude |

## Contents

- [Commands](#commands)
- [What the suites cover](#what-the-suites-cover)
- [What is not covered](#what-is-not-covered)
- [Static checks](#static-checks)
- [Continuous integration](#continuous-integration)
- [Manual checks](#manual-checks)
- [Before opening a pull request](#before-opening-a-pull-request)

## Commands

```bash
bash tests/run.sh      # exit 0 = all passed; prints "<n> ok, <m> failed"
bash tests/guard.sh    # prints "guard: <n> ok, <m> failed"
ws-test                # deterministic behavior tests of what is installed
ws-test --ia           # the same plus non-deterministic checks against the real Claude (uses a little usage)
ws-test --lista        # names of the tests
```

Test output uses three words: `ok`, `FAIL` and `warn`.

## What the suites cover

### `tests/run.sh`: the kit

The script copies `lib.sh`, `export.sh`, `install.sh`, `manifest.txt` and `secrets-allow.txt` into a temporary
directory, builds a small sample home, and runs the real scripts against temporary `HOME` values. Nothing is read from
or written to your home.

| Section (as printed) | What it checks |
|---|---|
| 1) export | Files and directories of the manifest are exported; execute permissions are kept; `*.bak.*` files are skipped; user MCP servers are exported; a file listed in `secrets-allow.txt` does not block the export; personal paths become `@WINHOME@` and `@HOME@`; the Windows user name does not remain in the kit |
| 2) secret blocking | An export with a storage account key fails and leaves no partial `files/`; a detection pattern in a file that is not in `secrets-allow.txt` also blocks |
| 3) install on a new machine | `--dry-run` writes nothing and lists what is new; the installed result equals the source; without a Windows user the installer refuses and names `--win-user`; scripts stay executable; the kit's lines are added to `.bashrc`; templates are rendered with the target machine's paths; `REPOS` follows the target user |
| 4) idempotency and no overwriting | A second install reports nothing new or changed; `.bashrc` has no duplicates; a modified file is reported as `changed` and backed up before being replaced |
| 5) real export of the repo | `files/home/.claude/settings.json` and `files/mcp-servers.json` are valid JSON; every file under `files/home` with a bash or sh shebang passes `shellcheck -S warning` (skipped when shellcheck is not installed) |
| 6) PreToolUse guard | Runs `tests/guard.sh` as one check |

Section 5 produces one check per script, so the total grows with the payload.

### `tests/guard.sh`: the guard

The script feeds the hook the JSON that Claude Code would send for a tool call and checks the exit code (2 = blocked,
0 = allowed). It uses a temporary home with a stub `audit.sh` and a temporary git repository, first on `main` and then
on a feature branch.

| Group | Cases | Examples |
|---|---|---|
| Must block (on `main`) | 25 | `git push origin +rama`, `git push -fu origin x`, a bare `git push`, `git push origin HEAD:refs/heads/main`, `git -C . push origin main`, `git commit --no-verify`, `git -c core.hooksPath=/dev/null commit`, `git config ws.gate.allowMain true`, `curl … \| sudo -E bash`, `bash <(curl …)`, `ws-secret get …`, `az vm delete … --subscription mi-prod-01`, `kubectl --context aks-prod delete pod x`, `helm uninstall x --kube-context prd-1` |
| Must pass (on a feature branch) | 17 | `echo "git push --force"`, `grep -r 'git push origin main' .`, `git push --force-with-lease origin feat/x`, a commit message that mentions `--no-verify`, `kubectl --context aks-dev delete pod x`, `az vm delete … --subscription dev-01`, `ws-secret set nombre` |
| Fail closed | 1 | Input that is not JSON must block |
| Normal write | 1 | A `Write` with ordinary content must pass |

When you change `guard.sh`, add the bypass you fixed to the first list and a legitimate look-alike to the second.

### `ws-test`: the installed workstation

`ws-test` is itself part of the payload (`files/home/.local/bin/ws-test`). It tests **what is installed in your home**,
not the files in the repository: to test a change, install it first (`bash install.sh`) or let `ws-actualizar` do it.

#### Isolation

| What | How |
|---|---|
| Home | A temporary `HOME` that receives a copy of `~/.local/bin`, `~/.tmux.conf` and the `tmux-claude`, `claude-solo` and `ws-telemetria` configuration folders. Your real home is only read for that copy. |
| tmux | `TMUX` and `TMUX_PANE` are unset and each test gets its own socket directory through `TMUX_TMPDIR`, so no test can talk to your real session. Cleanup kills only the servers on those sockets. |
| Claude | A fake `claude` executable, named by version like the native binary, that records how it was started, answers `--version`, `auth status` and `-p`, and exits on `/exit`. The real `claude` is removed from the copied `bin`. |
| API | A fake `ant` CLI that returns a canned completion; only an empty credentials file exists. |
| Telegram | The Bot API is simulated; the token and PIN come from test-only environment variables. |
| Windows side | Destinations for backups and reports are redirected to temporary folders. |

The deterministic run costs no Claude usage and exits 1 if any test fails. The summary line is
`Result: <n> ok · <n> warnings · <n> failed`.

#### Sections

There are 26 test functions. Each prints a section header, except the usage and telemetry test:

| Section (as printed) | Covers |
|---|---|
| tmux configuration and menus | The installed `.tmux.conf` and menus load in a real tmux server |
| Menus: what they promise exists (without opening tmux) | Every script and shell function a menu calls is installed; every `Ctrl+b X` shortcut a menu announces exists; the help does not announce retired options; each menu pauses the status refresh while open and restores it |
| Restart Claude in all tabs | `tmux-claude-restart --todas`: idle tabs restart, busy ones are left alone |
| Solo mode | `tmux-solo`: start arguments, the tab flag, returning to normal |
| Claude accounts | `claude-cuenta`: the personal account shares conversations and not credentials; switching a tab resumes the same conversation; refusal when both accounts are in the same organization; a pinned project (and its worktrees) wins over the default account |
| Tab persistence | No save in the first minutes after start; tabs are restored only when the session came back empty |
| Interactive floating windows | Popups hosted by `tmux-flot-run` |
| Backup and restore | A backup is created, the restore test passes, and the backup carries no credentials |
| Screensaver | Every `tmux-arte` scene draws, also on a small screen and in 256 colors; the scene menu and `tmux-arte` name the same scenes; a retired saved scene falls back to random; the screensaver appears with a tab in "waiting for you" and does not with a permission dialog open; choosing a scene saves it |
| Terminal: ble.sh, completion and copilot | Shell helpers and the terminal copilot against the fake API |
| No header (`prueba_telemetria`) | `ws-telemetria`: turns, costs, dashboard generation |
| Export work to another Claude and learn from you | `ws-traspaso`, `ws-aprender` |
| Full report (ws-informe) | Agents, recurring prompts, tokens, words, weekly trend and estimation baseline are measured; HTML and Markdown are generated without prompt text |
| Local OpenTelemetry collector (ws-otel) | Starts in the background and listens on `127.0.0.1` only; accepts logs, metrics and traces as JSON and rejects protobuf and other paths; stores with mode 0600, secrets masked; `WS_OTEL_CONTENIDO=0` stores no text or identity; the dashboard aggregates latency, errors by code, permissions and active time; stops |
| Protection per tab: completo, normal, puro | Generated profiles: `completo` drops the excluded commands and keeps rules and guard; `puro` has no sandbox and no `allow`/`ask` and keeps `deny` and the guard; the shipped settings have no wildcard `az` allow rules and contain the floor's `deny` rules |
| Menus and UX: active tabs, scenes, monitor, model switch | `tmux-activas`, `tmux-escena`, `tmux-hud`, model switching |
| Detailed Claude state (phase, time, what it is doing, without getting stuck) | Phases, elapsed time, detail, "waiting for you", and self-correction so a state does not stay stuck |
| Versioned personal configuration (ws-personal) | Sync and restore of the personal repository |
| Status bar: personal segments and ws-cache | Personal bar segments and the `ws-cache` behavior |
| tmux: CI/PR in the status bar, templates, recording, history and swarm | `tmux-rama`, `tmux-plantilla`, `tmux-grabar`, `tmux-historial`, `tmux-enjambre` |
| tmux: pane → Claude, palette, notify me, extract, labels, focus, logs | The `Ctrl+b e`, palette, notify-when-done, extract, label, focus and log features |
| Traces, estimation, weekly report and budgets | `ws-trazas.sh` output and the commands that read it |
| Model routing (cr + hook) | Routing rules, the hook, the confirmation |
| Telegram: notifications and answering with buttons (simulated API) | Notifications with the dialog's options; buttons from another chat are ignored; one-time codes; running a proposed command and returning its output; dangerous commands arrive without a button; alerts are not repeated; a wrong PIN sends nothing and a correct one delivers the reply |
| Tab groups and bringing conversations in | Tab groups and `tmux-traer` |
| Sandbox placeholders in your repos (read-only) | Read-only check of sandbox placeholder files in your repositories |

`ws-test --ia` adds a section "With the real Claude and API (non-deterministic)": `claude -p` answers, the copilot
proposes a valid command, the API-backed inline suggestion is coherent, and auto mode runs a command and returns its
output. These retry, validate by pattern and only warn; they never fail the run.

Some fixtures are in Spanish on purpose: the routing rules and the "waiting for you" detector match prompts and
answers typed in Spanish.

## What is not covered

- `ws-test` needs tmux and an installed workstation. It cannot run inside Claude Code's sandbox.
- It does not exercise the real Windows side (notifications, Credential Manager, Windows Terminal) or a real Telegram
  bot.
- The protection levels are tested at the profile-generation level; whether Claude Code honors the profile is checked
  by hand (see [Manual checks](#manual-checks)).
- Build, DAST and deploy stages do not apply: the kit is scripts and configuration copied into a home directory.

## Static checks

| Check | Command | Scope |
|---|---|---|
| Shell lint | `shellcheck -S warning -x <script>` | Every tracked file with a bash or sh shebang |
| Python compile | `python3 -m py_compile <script>` | Every tracked file with a Python shebang |
| Python SAST | `bandit -ll <script>` | The same files, medium severity and above |
| JSON | `jq empty <file>` | Every tracked `*.json` |
| tmux syntax | `tmux source-file -n <file>` | `.tmux.conf` (without its `run-shell` lines) and every `menu*.tmux` |
| Secrets | `gitleaks dir --config .gitleaks.toml --redact .` | The whole repository |
| Menu consistency | `ws-menus` | Repeated keys in a menu, the same action in two menus, scripts a menu calls that do not exist |

## Continuous integration

Two workflows in `.github/workflows/`, both with `contents: read` and no third-party actions.

### `ci.yml`

Runs on pushes to `main` and on pull requests. Concurrent runs for the same ref are cancelled.

| Job | Steps | Blocking |
|---|---|---|
| `lint` | shellcheck on every script with a bash or sh shebang; `py_compile` on every Python script; `jq empty` on every JSON file; tmux syntax check of `.tmux.conf` and every menu in a throwaway server | Yes |
| `sast` | bandit at a pinned version (medium severity and above); gitleaks at a pinned version, verified against the release checksum | Yes |
| `test` | `bash tests/run.sh` (after `lint` and `sast`) | Yes |
| `instalacion` | `install.sh --dry-run` and `install.sh` into an empty home on Ubuntu 24.04, then `ws-test` on the result | No (`continue-on-error`): it reports without blocking the merge |

### `codeql.yml`

CodeQL for `python` and `actions`, on pushes and pull requests to `main` and weekly.

### Dependabot

Dependabot (`.github/dependabot.yml`) updates the GitHub Actions used by the workflows weekly.

## Manual checks

| Command | Purpose |
|---|---|
| `ws-check` | Read-only status of the installed workstation: tmux, MCP servers, sandbox tools, the kit, the git gate, backups |
| `ws-health` | Resilience: disk space, distro snapshot, tmux save freshness, kit in sync |
| `ws-verify [--rapido]` | Everything before pushing kit changes: scripts (`bash -n`, shellcheck), tmux, screensaver, Claude Code settings, the workstation, the kit, and the behavior tests. Read-only; exits 1 on any failure |
| `ws-auditoria [--ia]` | Read-only audit by pillar (tmux, shortcuts and menus, Claude Code, sandbox, security, resilience, performance, observability) with an HTML and Markdown report |
| `cr --probar` | Runs 20 labeled tasks against the routing rules; exits 1 below 90 percent |

Whether Claude Code honors a protection profile is checked by hand in a real tab with `/permissions` and `/sandbox`,
and by `ws-auditoria --ia`, which attempts real sandbox escapes with `claude -p` in a temporary folder.

## Before opening a pull request

```bash
shellcheck -S warning <changed scripts>
python3 -m py_compile <changed python scripts> && bandit -q -ll <changed python scripts>
bash tests/run.sh
bash install.sh && ws-test     # in a normal shell, outside Claude Code
```

New behavior comes with a test: a check in `ws-test` for an installed script, a case in `tests/guard.sh` for the
guard, a check in `tests/run.sh` for the installer. Test data uses generic values (`ABC-123` tickets, example users);
never real project, customer or account names.
