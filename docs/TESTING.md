# Testing

claude-workstation has three kinds of test entry points, a compliance layer and a set of static checks. They test
different things on purpose:

| Suite | Tests | Needs | Touches your machine |
|---|---|---|---|
| `tests/run.sh` | The **kit**: `export.sh`, `install.sh`, the payload's JSON and shell lint, and the guard | bash, jq, git; shellcheck optional | No: temporary homes only |
| `tests/guard.sh` | The PreToolUse guard (`files/home/.claude/hooks/guard.sh`) | bash, jq, git | No: a temporary home and repository |
| `tests/<area>.sh` (19 more) | One security control or area each: hooks, audit, memory, spend, solo, per-tab profiles, supply chain, Telegram, backups, gate, interop, and the compliance catalogue and AI-BOM | bash, jq, git; some need `age`, `npm`, `ssh-keygen` or Python 3 | No: temporary homes, simulated tmux, Telegram and Claude |
| `ws-test` | The **installed** workstation: the scripts in `~/.local/bin` and the installed tmux configuration | tmux, jq, git, an installed workstation | No: an isolated home, isolated tmux sockets and a simulated Claude |
| `ws-audit --compliance` | The controls of `docs/compliance/controls.yaml` whose `check` can run on this machine | Python 3, the kit checkout | No: read-only, allow-listed checks only |

## Contents

- [Commands](#commands)
- [What the suites cover](#what-the-suites-cover)
  - [`tests/run.sh`: the kit](#testsrunsh-the-kit)
  - [`tests/guard.sh`: the guard](#testsguardsh-the-guard)
  - [The security suites](#the-security-suites)
  - [Compliance and AI-BOM checks](#compliance-and-ai-bom-checks)
  - [`ws-test`: the installed workstation](#ws-test-the-installed-workstation)
- [What is not covered](#what-is-not-covered)
- [Static checks](#static-checks)
- [Continuous integration](#continuous-integration)
- [Manual checks](#manual-checks)
- [Before opening a pull request](#before-opening-a-pull-request)

## Commands

```bash
bash tests/run.sh      # exit 0 = all passed; prints "<n> ok, <m> failed"
bash tests/guard.sh    # prints "guard: <n> ok, <m> failed"
for t in tests/*.sh; do bash "$t" || echo "FAILED: $t"; done   # every suite, as the CI "suites" job runs them
bash tests/compliance.sh   # the control catalogue and the assessment's coverage tables agree
bash tests/ai-bom.sh       # docs/governance/AI-BOM.md matches the files it inventories (--write to regenerate)
ws-test                # deterministic behavior tests of what is installed
ws-test --ai           # the same plus non-deterministic checks against the real Claude (uses a little usage)
ws-test --list        # names of the tests
ws-audit --compliance  # the machine-checkable controls on this workstation (--json for the raw result)
```

Test output uses three words: `ok`, `FAIL` and `warn`. Every suite exits non-zero when one of its checks fails.

## What the suites cover

### `tests/run.sh`: the kit

The script copies `lib.sh`, `migrate.sh`, `renames.tsv`, `export.sh`, `install.sh`, `manifest.txt` and
`secrets-allow.txt` into a temporary directory, builds a small sample home, and runs the real scripts against temporary
`HOME` values. Nothing is read from or written to your home.

| Section (as printed) | What it checks |
|---|---|
| 1) export | Files and directories of the manifest are exported; execute permissions are kept; `*.bak.*` files are skipped; user MCP servers are exported; a file listed in `secrets-allow.txt` does not block the export; personal paths become `@WINHOME@` and `@HOME@`; the Windows user name does not remain in the kit |
| 2) secret blocking | An export with a storage account key fails and leaves no partial `files/`; a detection pattern in a file that is not in `secrets-allow.txt` also blocks |
| 3) install on a new machine | `--dry-run` writes nothing and lists what is new; the installed result equals the source; without a Windows user the installer refuses and names `--win-user`; scripts stay executable; the kit's lines are added to `.bashrc`; templates are rendered with the target machine's paths; `REPOS` follows the target user |
| 4) idempotency and no overwriting | A second install reports nothing new or changed; `.bashrc` has no duplicates; a modified file is reported as `changed` and copied to `~/.local/share/ws-kit/backup.<date>/` before being replaced, with nothing left next to it; the header names the backup folder once; the newest 10 backup folders are kept and `pre-english.<date>` and `backup.legacy` are never deleted; `--prune-backups` moves the `*.bak.<date>` copies of manifest paths, of `.bashrc` and of the pre-3.0 names to `backup.legacy/`, counts them, leaves other files alone and respects `--dry-run` |
| 6) real export of the repo | `files/home/.claude/settings.json` and `files/mcp-servers.json` are valid JSON; every file under `files/home` with a bash or sh shebang passes `shellcheck -S warning` (skipped when shellcheck is not installed) |
| 7) PreToolUse guard | Runs `tests/guard.sh` as one check |

Section 6 produces one check per script, so the total grows with the payload.

Section 5 tests the migration from the names used before 3.0 (`migrate.sh`, `renames.tsv`) against a sample home laid
out with the old names. The suite puts a silent `reg.exe` first in `PATH`, so the real Windows registry is never read:

| Case | What it checks |
|---|---|
| Preview | `install.sh --dry-run` lists what would be moved, wrapped and set aside, and writes nothing |
| Data | A file or folder of kind `data` ends up under its new name with its content; when the old and the new name both exist, neither is touched and a warning is printed |
| Wrappers | An old command of kind `shim` is set aside under `~/.local/share/ws-kit/pre-english.<date>/` and replaced by an executable wrapper that runs the new command with the same arguments |
| Set aside | An old kit file of kind `drop` is moved to the set-aside folder and not deleted |
| `.bashrc` | The line that loads `cuentas.sh` is rewritten once to `accounts.sh`, with a backup in `~/.local/share/ws-kit/backup.<date>/` |
| Windows handler | With a fake `reg.exe` and `wslpath`: the registered `.ps1` then accepts `focus` and `foco`, calls `tmux-goto`, keeps its CRLF line endings and has a `.bak.<date>` copy next to it (it lives on the Windows side); `--dry-run` and a second run change nothing; without `reg.exe` nothing fails |
| Language | A migrated home gets `es` in `~/.config/tmux-claude/lang`; a new home gets no file |
| Idempotency | A second install migrates nothing |
| `--remove-shims` | Deletes the wrappers and leaves a file with the same name that is not a wrapper |

### `tests/guard.sh`: the guard

The script feeds the hook the JSON that Claude Code would send for a tool call and checks the exit code (2 = blocked,
0 = allowed). It uses a temporary home with a stub `audit.sh` and a temporary git repository, first on `main` and then
on a feature branch. It ends with a timing check: a typical Bash call must take under 150 ms in the guard.

| Group | Examples |
|---|---|
| Must block (on `main`) | `git push --force origin x`, `git push -fu origin x`, a bare `git push`, `git push origin HEAD:refs/heads/main`, `git -C . push origin main`, `git commit --no-verify`, `git -c core.hooksPath=/dev/null commit`, `git config ws.gate.allowMain true`, `curl … \| sudo -E bash`, `bash <(curl …)`, `ws-secret get …`, `az vm delete … --subscription my-prod-01`, `kubectl --context aks-prod delete pod x`, `helm uninstall x --kube-context prd-1` |
| Must pass (on a feature branch) | `echo "git push --force"`, `grep -r 'git push origin main' .`, `git push --force-with-lease origin feat/x`, a commit message that mentions `--no-verify`, `kubectl --context aks-dev delete pod x`, `az vm delete … --subscription dev-01`, `ws-secret set name` |
| Must block (PowerShell and git internals) | `pwsh.exe -EncodedCommand …`, PowerShell that downloads and runs, copying a file into `.git/hooks/`, `sed -i` on `.git/config`, a `Write` to `.git/hooks/pre-push` or `.git/config` |
| Must pass (PowerShell and git internals) | `pwsh.exe -NoProfile -Command "Get-Process …"`, `cat .git/config`, `ls .git/hooks`, a `Write` to `.gitignore` |
| Persistent agent configuration | Writes to `~/.claude/settings.json` (direct, `$HOME`, `../`, a symlink), hooks, the level and solo profiles, `production.conf`, the credential list, `CLAUDE.md`, commands and agents outside the owner's window and inside it, the Windows-side `.claude`, the kit's signers, agent-browser's policy, the Telegram folder, the stop and budget markers, the audit anchors; recursive `rm`, `mv`, `rsync` over them; `claude mcp add`, `ws-learn`, `ws-memory review`; a quoted mention that must pass |
| Credential stores | `echo $(cat ~/.ssh/id_ed25519)`, `tar c ~/.ssh`, `base64` of a token cache, `gh auth token`, `kubectl config view --raw`, reads through a link or `..` |
| Production list and agent identity | A subscription or context listed in `production.conf` without "prod" in its name, also for mutating Azure MCP tools; with `WS_AGENT` set, switching `AZURE_CONFIG_DIR`, `GH_CONFIG_DIR`, `KUBECONFIG`, `az login` or `gh auth login` |
| Fail closed | Input that is not JSON must block |
| Normal write | A `Write` with ordinary content must pass |

When you change `guard.sh`, add the bypass you fixed to a "must block" group and a legitimate look-alike to a "must
pass" group.

### The security suites

Each `tests/<area>.sh` is a standalone bash script with the same `ok`/`FAIL` style: temporary folders only, no tmux
server (tmux, Telegram, Claude and MemPalace are simulated where needed), and a non-zero exit on any failure. The CI
`suites` job runs all of them.

| Suite | Controls | What it checks |
|---|---|---|
| `hooks-untrusted.sh` | WS-AI-001, WS-SEC-010 | Every web, MCP and network result is labelled untrusted; published injection samples are flagged and logged; benign controls are not; the hook never fails. Prints the detection and false-positive rates |
| `hooks-prompt-screen.sh` | WS-AI-022 | Prompts with secrets are blocked and never echoed back; `#allow-secret` passes and is logged; ordinary prompts about code and credentials pass; without `ws-redact` or `jq` the screen lets prompts through with one warning |
| `hooks-settings.sh` | WS-AI-002, WS-AI-010, WS-AI-014, WS-SEC-002 | The settings and the managed policy template are valid; the deny rules for MCP and plugin registration and for the agent's own configuration exist; the credential list equals `sandbox.filesystem.denyRead`; the hooks are registered, the guard with `onFailure: block`; the template's deny list equals the user one |
| `hooks-ws-learn.sh` | WS-AI-014, WS-AI-017 | `ws-learn commands` rejects proposals that fail the shape or safety checks, shows each full prompt, cannot be made to inject frontmatter, overwrites nothing and refuses to run inside Claude |
| `audit-chain.sh` | WS-SEC-011 | `audit.sh` chains every line and anchors the day's head; `ws-audit --verify-log` detects an edited, deleted or reordered line, a deleted day file and a truncated tail |
| `audit-anomaly.sh` | WS-AI-030, WS-AI-025 | `ws-anomaly` counts blocks, denials and sandbox hits per session in a window; `ws-stop-all` sets the marker, turns Telegram off, records the event and closes every Claude pane, naming the ones that do not close |
| `audit-prompts.sh` | WS-AI-006 | `ws-telemetry prompts` counts the prompts you answered and how fast, the permanent allow rules, and `--alerts` reports a high rate, rubber-stamping and new or broad rules |
| `spend-gate.sh` | WS-AI-019, WS-AI-025 | The over-budget flag is written only with `hard=1`; `ws-runtime-gate.sh` holds a project over budget (or every project when the total is over); an override or a stale flag lets work go on; the stop marker holds everything except `/exit` |
| `memory-gate.sh` | WS-AI-012, WS-AI-013 | Every MemPalace write asks, carries stamped provenance and never contains `<private>` text; only approved facts pass; `memory-filter.sh` strips private spans from what the lifecycle hooks hand over; `ws-memory` builds the one-tool profile, checks saves in the tool results and refuses inside Claude |
| `solo-sandbox.sh` | WS-AI-004, WS-SEC-003, WS-AI-015 | The solo profile keeps the sandbox; `tmux-solo` marks an expiry that `tmux-watch` enforces; `--unsandboxed` is audited; `new` goes to a worktree; `tmux-swarm` starts each agent at the `full` level with `git push` denied, or refuses without `--setting-sources` |
| `profiles.sh` | WS-AI-026, WS-SEC-025, WS-AI-012, WS-SEC-002 | `ws-profile`: a new profile is isolated (kit setup linked, conversations not, MCP without MemPalace), `--share-with` links them; logins run with the profile's own folders and refuse inside Claude; the environment of each profile, and back to `work` drops it; a new shell's profile (project pin > tab > default, worktrees, nested shells, no inheritance across panes); the fence of other stores' conversations and every Claude login, written by `tmux-level --fenced` and used by `claude-resume`; `memory=off` keeps the MemPalace hooks and tools out, `wing:W` rewrites the wing; switching a tab (new conversation across stores, resume within one, solo kept, refusal when not signed in); `claude-account` as a wrapper; removal with the typed name; the audit checks; the migration from `claude-accounts`. Simulated tmux, fake `claude`, `az` and `gh` |
| `supply-chain.sh` | WS-AI-009 | The lock agrees with `files/mcp-servers.json` and the committed `package-lock.json` files; nothing runs through `npx` or a moving tag; `ws-pinned` installs from the lock and notices a changed tree; local executables are pinned on first use; `install.sh` skips what the lock does not vouch for. Needs `npm` |
| `supply-kit-update.sh` | WS-SEC-015 | Against a fixture remote: `ws-kit-update` applies only a `vX.Y.Z` tag signed by an installed signer; refuses an unsigned tag, another key, a lightweight tag and a re-pointed tag; ignores the branch tip; `--allow-unsigned` is logged. Needs `ssh-keygen` |
| `telegram-approvals.sh` | WS-AI-007, WS-AI-018 | "Don't ask again" is never a button and is refused if forged; a plain approval is one tap; a risky one needs the PIN and is sent only if the dialog is still on screen; ▶ Run is offered only for the read-only allow list |
| `backup-encryption.sh` | WS-SEC-013 | With only the cloud key the backup is `.age` and opens with it; without a key it is made in clear, warned and logged `UNENCRYPTED`; `ws-restore-lite --test` opens an encrypted one; the expiry pass deletes old copies whose original is gone. Needs `age` |
| `gate-secret-scan.sh` | WS-SEC-004 | Without gitleaks a commit is blocked with the install command; `ws.gate.allowNoGitleaks` lets it through and logs it; a finding blocks; a clean scan passes; `ws-gate bypasses` lists repositories where the gate does not run in full |
| `interop-adversarial.sh` | WS-SEC-022, WS-AI-027 | Every Windows executable an agent could use to step around the sandbox (`cmd.exe`, `powershell.exe`, `curl.exe`, `certutil.exe`, `reg.exe`, `explorer.exe`, by name or by `/mnt/c` path) ends blocked or asked; credential folders are denied; a README that tells the agent to push to `main` is stopped by the guard and the gate. `--live` probes interop from inside bubblewrap (report only) |

### Compliance and AI-BOM checks

| Suite | What it checks |
|---|---|
| `tests/compliance.sh` | The catalogue `docs/compliance/controls.yaml`: required fields, valid statuses, risk and effort values, unique ids, every `maps_to` id present in `docs/compliance/frameworks.md`; every `evidence` file exists; the `check` of every `implemented` control passes (checks tagged `live`, which need a real workstation, are skipped); the coverage tables in `docs/compliance/assessment.md` equal the counts computed from the YAML, so the document cannot drift |
| `tests/ai-bom.sh` | Regenerates the inventory tables of `docs/governance/AI-BOM.md` (between its generated-section markers) with `.github/scripts/ai_bom.py` from the files the BOM names (`settings.json`, the agent files, `files/mcp-servers.json`, `files/mcp-servers.lock.json`, `files/home/.local/lib/ws-npm/*/package.json`, the hooks) and fails when the committed document differs. `bash tests/ai-bom.sh --write` updates the document; the prose outside the markers stays hand-written |

`ws-audit --compliance` is the workstation-side counterpart: it reads the same catalogue from the kit checkout
(`$WS_KIT`, default `~/code/claude-workstation`; `--kit DIR` or `--catalogue FILE` override it), treats the YAML as
untrusted input, runs only checks of an allow list of read-only forms (`bash tests/<suite>.sh`, `test -f`, `jq`,
`grep`, kit commands with read-only flags), reports the others and those that cannot run here as `not-run`, prints a
table per framework with the coverage, writes `~/.local/share/ws-telemetry/compliance.json` and exits 1 when a
control marked `implemented` fails its check. The engine is `files/home/.local/lib/ws_compliance.py`.

### `ws-test`: the installed workstation

`ws-test` is itself part of the payload (`files/home/.local/bin/ws-test`). It tests **what is installed in your home**,
not the files in the repository: to test a change, install it first (`bash install.sh`) or let `ws-kit-update` do it.

#### Isolation

| What | How |
|---|---|
| Home | A temporary `HOME` that receives a copy of `~/.local/bin`, `~/.tmux.conf`, the `tmux-claude`, `claude-solo` and `ws-telemetry` configuration folders and the kit's `claude-levels/normal-adds.json`. Your real home is only read for that copy. |
| tmux | `TMUX` and `TMUX_PANE` are unset and each test gets its own socket directory through `TMUX_TMPDIR`, so no test can talk to your real session. Cleanup kills only the servers on those sockets. |
| Claude | A fake `claude` executable, named by version like the native binary, that records how it was started, answers `--version`, `--help` (with `--setting-sources`), `auth status` and `-p`, and exits on `/exit`. The real `claude` is removed from the copied `bin`, and `CLAUDECODE` is unset. |
| API | A fake `ant` CLI that returns a canned completion; only an empty credentials file exists. |
| Telegram | The Bot API is simulated; the token and PIN come from test-only environment variables. |
| Windows side | Destinations for backups and reports are redirected to temporary folders. |

The deterministic run costs no Claude usage and exits 1 if any test fails. The summary line is
`Result: <n> ok · <n> warnings · <n> failed`.

#### Running ws-test from a private tmux server

`ws-test` does not need to run inside tmux, and it isolates every tmux server it starts. To run it against a tree you
have not installed in your own home (a branch, a release candidate), or from an agent session that must never reach
your live tmux server, install the tree into a throwaway home and run `ws-test` from a private, named server:

```bash
T="$(mktemp -d)"; mkdir -p "$T/bin" "$T/home"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/reg.exe"; chmod +x "$T/bin/reg.exe"     # silent fake: no Windows registry
HOME="$T/home" PATH="$T/bin:$PATH" bash install.sh --no-plugins --no-mcp --no-git-hooks --win-user tester
tmux -L wstest -f /dev/null new-session -d -s t \
  "env HOME=$T/home PATH=$T/home/.local/bin:$T/bin:/usr/bin:/bin TERM=xterm-256color ws-test > $T/ws-test.log 2>&1"
tail -1 "$T/ws-test.log"        # repeat until the "Result:" line appears
tmux -L wstest kill-server
```

Rules: name the private server on **every** tmux command (`tmux -L <name> …`), never the default server; one tmux
command per call when an agent runs it; kill the private server at the end. The run takes a few minutes.

#### Sections

There are 28 test functions. Each prints a section header, except the usage and telemetry test:

| Section (as printed) | Covers |
|---|---|
| tmux configuration and menus | The installed `.tmux.conf` and menus load in a real tmux server |
| Menus: what they promise exists (without opening tmux) | Every script and shell function a menu calls is installed; every `Ctrl+b X` shortcut a menu announces exists; the help does not announce retired options; each menu pauses the status refresh while open and restores it |
| Restart Claude in all tabs | `tmux-claude-restart --all`: idle tabs restart, busy ones are left alone; the restore command resumes at the normal level |
| Solo mode | `tmux-solo`: start arguments (auto mode with the generated `solo.json`), the tab flag, reopening inside the sandbox and resuming, returning to the normal level; a tab without a conversation gets a new Claude with the same flags |
| Claude accounts | `claude-account`: the personal account shares conversations and not credentials; switching a tab resumes the same conversation at the normal level, or starts a new one when the tab never had any; refusal when both accounts are in the same organization; a pinned project (and its worktrees) wins over the default account |
| Tab persistence | No save in the first minutes after start; tabs are restored only when the session came back empty |
| Interactive floating windows | Popups hosted by `tmux-popup-run`; the popup server's socket file is removed when its last window closes |
| Backup and restore | A backup is created, the restore test passes, and the backup carries no credentials |
| Screensaver | Every `tmux-art` scene draws, also on a small screen and in 256 colors; the scene menu and `tmux-art` name the same scenes; a retired saved scene falls back to random; the screensaver appears with a tab in "waiting for you" and does not with a permission dialog open; choosing a scene saves it |
| Terminal: ble.sh, completion and copilot | Shell helpers and the terminal copilot against the fake API |
| No header (`test_telemetry`) | `ws-telemetry`: turns, costs, dashboard generation |
| Export work to another Claude and learn from you | `ws-handoff`, `ws-learn` (facts are saved through `ws-memory`: only `kg_add`, checked in the tool results, logged) |
| Full report (ws-report) | Agents, recurring prompts, tokens, words, weekly trend and estimation baseline are measured; HTML and Markdown are generated without prompt text |
| Local OpenTelemetry collector (ws-otel) | Starts in the background and listens on `127.0.0.1` only; accepts logs, metrics and traces as JSON and rejects protobuf and other paths; stores with mode 0600, secrets masked; `WS_OTEL_CONTENT=0` stores no text or identity; the dashboard aggregates latency, errors by code, permissions and active time; stops |
| Protection per tab: full, normal, bare | Generated profiles: `full` drops the excluded commands and keeps rules and guard; `normal` starts through `claude-resume` with a 0600 profile that adds the sandbox exclusions; the installed user settings exclude no command (strict base); `bare` has no sandbox and no `allow`/`ask` and keeps `deny`, the bypass-mode lock and the guard; an agent identity starts Claude with its own `az`, `gh` and `kubectl` credentials and an unknown one is refused; the shipped settings have no wildcard `az` allow rules and contain the floor's `deny` rules |
| Menus and UX: active tabs, scenes, monitor, model switch | `tmux-active`, `tmux-scene`, `tmux-hud`, model switching |
| Finder: tabs, active, favorites and recent conversations in one list (tmux-find) | The four views in one row format; the preview of a tab, a conversation and a folder; quick reply (clears the input, never types into a dialog or a shell); approve and reject only in the permission phase; "open here" creates a grouped session and removes it; the old entry points open the finder |
| Detailed Claude state (phase, time, what it is doing, without getting stuck) | Phases, elapsed time, detail, "waiting for you", and self-correction so a state does not stay stuck |
| Versioned personal configuration (ws-personal) | Sync and restore of the personal repository; `ws-local/roots.txt` is versioned by default; a restore copies what it replaces to `~/.local/share/ws-kit/backup.<date>/` |
| Status bar: personal segments and ws-cache | Personal bar segments and the `ws-cache` behavior |
| tmux: CI/PR in the status bar, templates, recording, history and swarm | `tmux-branch`, `tmux-template`, `tmux-record`, `tmux-history`, `tmux-swarm` |
| tmux: pane → Claude, palette, notify me, extract, labels, focus, logs | The `Ctrl+b e`, palette, notify-when-done, extract, label, focus and log features |
| Traces, estimation, weekly report and budgets | `ws-traces.sh` output and the commands that read it; `estimate --by` with the old values; the `traces` view of `ws-telemetry sql` (simulated DuckDB) |
| Model routing (cr + hook) | Routing rules, the hook, the confirmation |
| Telegram: notifications and answering with buttons (simulated API) | Notifications with the dialog's options; buttons from another chat are ignored; one-time codes; running a proposed command and returning its output; dangerous commands arrive without a button; alerts are not repeated; a wrong PIN sends nothing and a correct one delivers the reply; with the emergency stop on, a button sends nothing |
| Tab groups and bringing conversations in | Tab groups and `tmux-bring` (the tab is left ready to resume at the normal level) |
| ws-verify --live: the running tmux server (PATH, save, tabs, scripts, sockets) | Against a throwaway server: a healthy one passes and a linked session does not count as more tabs; a server without `~/.local/bin` in `PATH`, a tab missing from the save, a leftover `find-peek-*` session, a key bound to a missing script and a dead socket each fail with their remedy; `--clean-sockets` removes only dead sockets |
| Sandbox placeholders in your repos (read-only) | Read-only check of sandbox placeholder files in your repositories |
| Language selector (ws-lang) | `ws-lang`: `en` when nothing is set, setting and reading the language, `WS_LANG` overriding the file, and the packs: with `en` a key returns the English value only, with `es` the English and the Spanish values joined |

`ws-test --ai` adds a section "With the real Claude and API (non-deterministic)": `claude -p` answers, the copilot
proposes a valid command, the API-backed inline suggestion is coherent, and auto mode runs a command and returns its
output. These retry, validate by pattern and only warn; they never fail the run.

Some fixtures are in Spanish on purpose: they test the Spanish language pack (routing rules, the "waiting for you"
detector, the Telegram command extractor, the recurring-prompt normalizer), which matches prompts and answers typed
in Spanish. Those tests run with the language set to `es`.

## What is not covered

- `ws-test` needs tmux and an installed workstation. It cannot run inside Claude Code's sandbox.
- It does not exercise the real Windows side (notifications, Credential Manager, Windows Terminal) or a real Telegram
  bot.
- The protection levels are tested at the profile-generation level; whether Claude Code honors the profile is checked
  by hand (see [Manual checks](#manual-checks)).
- Claude Code's own hook semantics are read from its documentation, not tested: the deep merge of `--settings` on top
  of every source, `updatedInput` together with `ask` (memory gate), `onFailure` and per-handler `if` at run time, and
  exit 2 on `UserPromptSubmit`. `claude doctor` validates the settings files; the rest is in
  [Manual checks](#manual-checks).
- The managed policy is not installed as root in any test (`tests/hooks-settings.sh` checks the template only).
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
| Workflow security | `zizmor --offline --min-severity low .github/workflows/` | Template injection, unpinned `uses`, excessive permissions, credential persistence |
| SBOM | `python3 .github/scripts/sbom.py -o sbom.cdx.json && python3 .github/scripts/sbom.py --check sbom.cdx.json` | CycloneDX 1.5 of what the kit installs or calls |
| Menu consistency | `ws-menus` | Repeated keys in a menu, the same action in two menus, scripts a menu calls that do not exist |

## Continuous integration

Four workflows in `.github/workflows/`, all with `contents: read` by default, `persist-credentials: false` on every
checkout and no third-party actions. GitHub's own actions are pinned by commit SHA with the version as a comment.

### `ci.yml`

Runs on pushes to `main` and on pull requests. Concurrent runs for the same ref are cancelled.

| Job | Name shown in GitHub | Steps | Blocking |
|---|---|---|---|
| `lint` | Lint (shellcheck, Python, JSON, tmux) | shellcheck on every script with a bash or sh shebang; `py_compile` on every Python script; `jq empty` on every JSON file; tmux syntax check of `.tmux.conf` and every menu in a throwaway server | Yes |
| `sast` | SAST and secrets (bandit, gitleaks) | bandit at a pinned version (medium severity and above); gitleaks at a pinned version, verified against the release checksum | Yes |
| `zizmor` | Workflow security (zizmor) | zizmor at a pinned version, verified by sha256, on every workflow | Yes |
| `sbom` | SBOM (CycloneDX) | Generates the SBOM from the lock files, the package locks, `ws-tools`, the tmux plugins, the pinned actions and the CI tool versions, and validates it | Yes |
| `test` | Kit tests | `bash tests/run.sh` (after `lint` and `sast`) | Yes |
| `suites` | Security suites (tests/*.sh) | Every `tests/*.sh` except `run.sh`, with `tmux`, `age` and `zstd` installed; all of them run and the job fails if any does. This includes `tests/compliance.sh` and `tests/ai-bom.sh` | Yes |
| `install` | Clean install (Ubuntu 24.04) | `install.sh --dry-run` and `install.sh` into an empty home on Ubuntu 24.04, then `ws-test` on the result | No (`continue-on-error`): it reports without blocking the merge |

### `codeql.yml`

CodeQL for `python` and `actions` (job `analyze`, one run per `language` of the matrix), on pushes and pull requests to
`main` and weekly.

### `release.yml`

On a `vX.Y.Z` tag: job "Signed tag" runs `git verify-tag` against `files/home/.config/ws-kit/allowed_signers` (an
unsigned tag, or no key in the file, fails and nothing is published), then builds the SBOM and attaches it to the
GitHub release. See the [runbook](runbook.md#signing-a-release).

### `compliance-monthly.yml`

Monthly on a schedule, and by hand (`workflow_dispatch`): `tests/compliance.sh`, `tests/ai-bom.sh` and the
framework-currency check `.github/scripts/framework_currency.py`, which fetches the OWASP Top 10 for LLM and agentic
applications pages and compares the edition with the one recorded in `docs/compliance/frameworks.md`; a changed
edition fails softly with a message ready to paste into an issue. Review it as part of the
[review cadence](governance/REVIEW-CADENCE.md).

A branch-protection rule that lists required checks uses the names shown in GitHub: `Lint (shellcheck, Python, JSON,
tmux)`, `SAST and secrets (bandit, gitleaks)`, `Workflow security (zizmor)`, `SBOM (CycloneDX)`, `Kit tests`,
`Security suites (tests/*.sh)`, `Clean install (Ubuntu 24.04)`, `analyze (python)` and `analyze (actions)`.

### Dependabot

Dependabot (`.github/dependabot.yml`) updates, weekly, the GitHub Actions used by the workflows (SHA and version
comment together, one grouped pull request) and the pinned npm packages under `files/home/.local/lib/ws-npm/`, with a
7-day cool-down. A bump of an npm package also needs `files/mcp-servers.lock.json` updated; `tests/supply-chain.sh`
fails until it is.

## Manual checks

| Command | Purpose |
|---|---|
| `ws-check` | Read-only status of the installed workstation: tmux, MCP servers, sandbox tools, the kit, the git gate, backups |
| `ws-health` | Resilience: disk space, distro snapshot, tmux save freshness, kit in sync |
| `ws-verify [--quick]` | Everything before pushing kit changes: scripts (`bash -n`, shellcheck), tmux (configuration, and the running server: `ws-verify --live` runs those checks alone), screensaver, Claude Code settings, the workstation, the kit, and the behavior tests. Read-only; exits 1 on any failure |
| `ws-audit [--ai]` | Read-only audit by pillar (tmux, shortcuts and menus, Claude Code, sandbox, security, resilience, performance, observability) with an HTML and Markdown report |
| `ws-audit --verify-log` | The audit log's hash chain and its anchors |
| `ws-audit --compliance` | The machine-checkable controls of the catalogue on this workstation |
| `claude doctor` | Claude Code reports settings it rejects in `settings.json` and in every generated profile |
| `cr --test` | Runs the 20 labeled tasks of each active language against the routing rules (the English set, plus the Spanish set with `ws-lang es`); exits 1 below 90 percent |

Whether Claude Code honors a protection profile is checked by hand in a real tab with `/permissions` and `/sandbox`,
and by `ws-audit --ai`, which attempts real sandbox escapes with `claude -p` in a temporary folder. Two checks are
worth doing once in a live session after installing: a MemPalace write shows a prompt with the provenance filled in,
and a blocked prompt (for example one with a fake token) shows its reason.

## Before opening a pull request

```bash
shellcheck -S warning <changed scripts>
python3 -m py_compile <changed python scripts> && bandit -q -ll <changed python scripts>
bash tests/run.sh
for t in tests/*.sh; do bash "$t" >/dev/null || echo "FAILED: $t"; done
bash install.sh && ws-test     # in a normal shell, outside Claude Code
```

New behavior comes with a test: a check in `ws-test` for an installed script, a case in `tests/guard.sh` for the
guard, a check in `tests/run.sh` for the installer, or a new `tests/<area>.sh` for a security control. A change to a
control's status, evidence or check goes into `docs/compliance/controls.yaml`, and `tests/compliance.sh` must stay
green. Test data uses generic values (`ABC-123` tickets, example users); never real project, customer or account names.
