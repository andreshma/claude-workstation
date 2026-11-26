# Runbook

Operation, troubleshooting and recovery steps tested on this workstation (WSL2 + tmux + Claude Code). Each case is
written as symptom, cause and steps.

General rule: run commands that change your home (patches, `install.sh`, `jq` on settings) in a **normal shell**,
never inside Claude, because the sandbox prevents it on purpose. `Ctrl+b g` opens a floating shell.

Menu labels, statuses and messages are quoted exactly as the screen shows them. Command names, flags and stored values
are written as you type them. The names used before 3.0 are listed in
[USAGE.md](USAGE.md#18-upgrading-from-2x-names).

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
- [18. Security operations](#18-security-operations)

## 1. Where things are

| What | Where |
|---|---|
| The kit (this repository) | Where you cloned it, for example `~/code/claude-workstation`; remote `andreshma/claude-workstation` |
| Installed scripts | `~/.local/bin/tmux-*`, `~/.local/bin/ws-*`, `~/.local/bin/claude-account` |
| tmux configuration and menus | `~/.tmux.conf`, `~/.config/tmux-claude/` |
| Claude Code settings and hooks | `~/.claude/settings.json`, `~/.claude/hooks/` |
| Conversations | `~/.claude/projects/<folder>/<session>.jsonl` |
| Audit log | `~/.claude/audit/` |
| tmux saves | `~/.local/share/tmux/resurrect` (30 days) |
| Telemetry, dashboard and reports | `~/.local/share/ws-telemetry/`; copies in `%UserProfile%\ws-telemetry\` |
| Routing rules and settings | `~/.config/ws-routing/rules.conf`, `~/.config/ws-routing/settings.conf` |
| Telegram settings | `~/.config/ws-telegram/settings` |
| Language | `~/.config/tmux-claude/lang` (`ws-lang`); packs in `~/.local/lib/ws-lang/` |
| Files set aside by the migration to English names | `~/.local/share/ws-kit/pre-english.<date>/` |
| Budgets and prices | `~/.config/ws-telemetry/budgets.conf`, `~/.config/ws-telemetry/prices.json` |
| Backups on the Windows side | `%UserProfile%\.tmux-resurrect-backup`, `%UserProfile%\.claude-wsl-backup`, `%UserProfile%\WSL-Backups\lite`, `%UserProfile%\WSL-Backups` |
| Secrets | Windows Credential Manager, entries named `ws/<name>` (`ws-secret`) |
| Audit log anchors (outside the agent's sandbox) | `%UserProfile%\ws-telemetry\audit-anchors.txt` |
| Guard lists you edit | `~/.config/ws-guard/production.conf` (production subscriptions and contexts), `~/.config/ws-guard/allow-config-writes` (the config-write window) |
| What the normal level adds | `~/.config/claude-levels/normal-adds.json` (kit file); generated profiles `normal.json`, `solo.json`, `full*.json`, `bare.json` next to it |
| Agent identities | `~/.config/ws-agent/<name>/{azure,gh,kube/config}` (`tmux-level … --agent <name>`) |
| Emergency stop and spend markers | `~/.local/state/ws-stop-all`, `~/.local/state/ws-budget-over`, `~/.local/state/ws-budget-override` |
| Pinned npm packages | Locks in `~/.local/lib/ws-npm/<name>/`; installed trees in `~/.local/share/ws-kit/npm/<name>/`; local MCP executables pinned in `~/.local/share/ws-kit/mcp-trust.tsv` |
| Release signing keys the kit trusts | `~/.config/ws-kit/allowed_signers` (kit) and `allowed_signers.local` (yours); update log `~/.local/state/ws-kit-update.log` |
| Gate opt-outs | `~/.local/state/ws-gate/opt-outs.log` |
| Managed policy (optional, root) | `/etc/claude-code/managed-settings.d/50-ws-kit.json`, `/etc/claude-code/hooks/guard.sh`, `/etc/claude-code/ws-credential-paths.txt` |
| Compliance report (`ws-audit --compliance`) | `~/.local/share/ws-telemetry/compliance.json` |
| Backups of files changed by `install.sh` | `~/.local/share/ws-kit/backup.<date>/<path under $HOME>` (newest 10 kept); copies left next to the files by versions before 3.0: `~/.local/share/ws-kit/backup.legacy/` after `bash install.sh --prune-backups` |

## 2. Is it healthy?

```bash
ws-check && ws-health        # workstation and resilience status
ws-verify                    # read-only verification before pushing kit changes
ws-test                      # isolated behavior tests of what is installed
ws-otel status               # local OpenTelemetry collector
ws-telegram status           # Telegram configuration, service and recent events
ws-lang                      # language in use and what it affects
ws-audit                     # read-only audit by pillar; also: --verify-log, --compliance
```

| Check | Healthy when |
|---|---|
| `ws-check` | No line ends in `MISSING` |
| `ws-health` | 15 % free on `/` and 50 GB free on `C:`; a recent tmux save and backup; the kit in sync |
| `ws-verify` | No `FAIL` line; warnings are to be reviewed |
| `ws-test` | The summary line reports no failed tests |
| `ws-audit --verify-log` | Exit 0: no audit line was edited, deleted or reordered |
| `ws-audit --compliance` | Exit 0: no control marked `implemented` fails its check |

### Is the copy to Windows up to date?

```bash
B=/mnt/c/Users/<user>/.claude-wsl-backup
stat -c 'last copy: %y' "$B/.last"                     # less than 15 min ago
tail -2 ~/.local/state/ws-backup-mirror.state            # "encrypted" for both mirrors (UNENCRYPTED: no key yet)
find "$B/projects" -type f ! -name '*.age' | head        # nothing: every copy is <name>.age
```

The mirrors are encrypted per file with `age` to the light backup's keys (WS-SEC-013): `ws-backup` for the
conversations and the audit log, `tmux-backup` for the tmux saves. Without a key (before `ws-backup-cloud setup`) they
stay in clear and `ws-audit` fails; the first run with a key seals the clear copies in place.

## 3. Tabs and tmux

### The tabs did not come back after a restart

- **Typical cause:** at startup, something saved the empty session as the "last save" before tmux restored (fixed in
  v1.6.0: `tmux-save-now` waits 3 min and `.tmux.conf` restores only if the session ends up empty). Earlier saves are
  **not deleted** (they are kept for 30 days).
- **Steps (quick):** Menu → "Tabs and session" → "Restore tabs from a save…" (`tmux-recover`). Pick the most
  recent one that has your tabs from **before** the problem (the one marked `← at startup` is usually the right one).
- **Steps (manual):**

  ```bash
  cd ~/.local/share/tmux/resurrect
  for f in $(ls -t tmux_resurrect_*.txt | head -15); do printf '%s  %s tabs\n' "$f" "$(grep -c '^window' "$f")"; done
  ln -sf ~/.local/share/tmux/resurrect/<good-file>.txt last && tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh
  ```

  Use the real file name (not the example one). Do it on a single line: continuum saves again every minute.
- **If there is no good save:** recover the copy in `%UserProfile%\.tmux-resurrect-backup`
  (`ws-restore-lite --mirror /mnt/c/Users/<user>/.tmux-resurrect-backup`, then copy the save you want into
  `~/.local/share/tmux/resurrect/`) or use the daily backup (`ws-restore-lite`, [section 17](#17-recovery)).
- Close the leftover empty tab with `Ctrl+b &`.

### Restarting the workstation cleanly

- **Keeping tabs and conversations (recommended):**

  ```bash
  ws-backup-lite --now      # optional: an extra backup
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
- Check the syntax without touching your session: `ws-verify --quick` (tmux section).

## 4. Claude and conversations

### A tab opened without Claude or did not resume the conversation

- In the tab: `claude -c` (the most recent one for that folder) or `claude -r` (pick from the list).
- Menu → "Claude in this tab" → "Protection" → "Restart without changing the protection (resumes the conversation)":
  it closes Claude and resumes.

### A conversation was lost

- Conversations are in `~/.claude/projects/<folder>/<session>.jsonl` and are copied to Windows every 15 min
  (`%UserProfile%\.claude-wsl-backup\projects`, encrypted). Recover the project folder with
  `ws-restore-lite --mirror /mnt/c/Users/<user>/.claude-wsl-backup/projects/<folder>` (it decrypts `.age` copies and
  copies the clear ones of older mirrors into `~/.local/state/ws-restore/mirror-<date>/`), copy it back to
  `~/.claude/projects/` with `cp -rn`, and run `claude -r` in the tab.
- From the daily backup: `ws-restore-lite` (test) and then `ws-restore-lite --restore`
  ([section 17](#17-recovery)).
- Whatever an agent was executing at the instant of an outage is not recovered; the conversation is, up to the last
  message: ask it to continue.

## 5. Claude accounts (work and personal)

- The work account (`work`) uses `~/.claude`; the personal account uses `~/.claude-personal`. They share
  conversations and setup; login and policies are separate.
- **Switch the tab's account (same conversation):** Menu → "Claude in this tab" → "Switch this tab to the … account
  (same conversation)". Verify with `/status` inside Claude.
- **See which organization each one has:**

  ```bash
  timeout 15 claude auth status --text | grep -iE 'org|email'
  timeout 15 env CLAUDE_CONFIG_DIR=~/.claude-personal claude auth status --text | grep -iE 'org|email'
  ```

- **The personal account ended up with the work organization:** log out of the personal one **only**
  (`claude-account logout personal`), switch claude.ai to the personal organization in the browser and log in again
  (`claude-account login personal`). **Never** use `/logout` or `claude auth logout` without `CLAUDE_CONFIG_DIR`: they
  would log out the work account.
- **Both accounts show the same organization** (it happened when switching organization in the browser during the
  personal login): log in again on the one that is wrong, with the browser on the correct organization. Work:
  `env -u CLAUDE_CONFIG_DIR claude auth login`; personal: `claude-account login personal`. Switching account per tab is
  refused while both are on the same organization. Always check with `claude-account status`.
- **The login screen does not let you copy the URL:** do not do it in a floating window. In a normal tab:
  `BROWSER=wslview claude-account login personal`. If the browser does not open: the `c` key copies the URL, or
  Shift + drag to select and `Ctrl+Shift+C`. If the browser shows a code, paste it with `Ctrl+Shift+V`.
- Before continuing company work on the personal account, remember that the code and the conversation go to that
  organization (without the terms of the Team plan).

## 6. Terminal: completion, ble.sh and copilot

- **The copilot (`Alt+a`, `Alt+e`, `Alt+x`) does not respond:** `timeout 15 claude auth status --text`; if there is no
  session, log in. Model: `export AI_SHELL_MODEL=haiku` (the default).
- **ble.sh gets in the way or looks odd:** in the session, `ble-detach`; permanently,
  `touch ~/.config/tmux-claude/no-ble` and open a new tab. The rest (Tab, fzf, copilot) keeps working.
- **Completion is missing for a newly installed tool:** `ws-completions`.

## 7. Sandbox, solo mode and patches

- **"Read-only file system" or an operation blocked inside Claude:** that is the sandbox. Run it yourself with
  `!command` or in a floating shell (`Ctrl+b g`). Solo mode no longer helps here: it runs inside the sandbox too
  ([ADR 0016](adr/0016-solo-mode-inside-the-sandbox.md)). For work the sandbox cannot do, `tmux-solo this
  --unsandboxed` is the audited exception (🔓 in the tab name, a `solo-unsandboxed` audit event); prefer the normal
  level.
- **`az`, `gh`, `git push` or `kubectl` fail or ask in a solo tab:** on purpose ([ADR 0022](adr/0022-solo-mode-without-excluded-commands.md)):
  solo excludes no command from the sandbox, so those tools run without your credentials and outside the allow list
  they have no network, and each of them is an `ask` rule the auto-mode classifier cannot approve. For a solo task
  that needs them: `tmux-solo this --with-network-tools` (they leave the sandbox again, each one asking you; 1 hour
  by default, `--hours` up to 4; 🌐 in the tab name and `solo-network-tools` in the audit log), or the normal level.
- **`ws-audit` fails on "solo profiles: no command leaves the sandbox without asking":** a generated profile in
  `~/.config/claude-levels/` was edited or is from an older kit: `tmux-level --settings-file solo` (and `solo-net`)
  writes it again.
- **An MCP server (azure, chrome-devtools) does not start after the update:** it runs in `ws-mcp-jail`
  ([ADR 0024](adr/0024-mcp-server-confinement-and-allow-list.md)). `ws-mcp-jail --probe` exits 0 when bubblewrap can
  create its namespaces; if not: `sudo apt-get install bubblewrap` and, on Ubuntu 24.04, check that the AppArmor
  restriction on unprivileged user namespaces allows `bwrap`. To see the view a server gets:
  `ws-mcp-jail --print --name azure --net --azure-config -- <command>`. Its state is in `~/.local/state/ws-mcp/<name>`
  and each start is logged in `~/.local/state/ws-mcp/jail.log`. A server that needs a path the jail does not show gets
  it through `"jail": {"ro": […]}` in `files/mcp-servers.json` and `bash install.sh --mcp-refresh`; credential stores,
  `~/.claude*`, the audit log and Windows drives are refused even then.
- **An MCP server is "blocked by policy" in `/mcp` after `install.sh --managed --mcp-allowlist`:** it is not in the
  managed allow list. A claude.ai connector or plugin server you keep goes into `~/.config/ws-mcp/allow-extra.json`
  (`[{"serverUrl": "https://…/*"}]`), then run the command again; a kit server whose definition changed needs the same
  after `bash install.sh --mcp-refresh`. `ws-audit` lists what the list would block.
- **Solo mode ended by itself:** it expires after 4 hours (`@csolo_hours`, `WS_SOLO_HOURS`, `--hours N`, 1 to 24) and
  `tmux-watch` returns the tab to normal. Start it again with Menu → "Claude in this tab" → "Protection" → "Solo mode:
  auto inside the sandbox for 4 h (asks you for critical actions)".
- **`az`, `gh` or `git push` fail in a Claude you started by hand:** the user settings are strict and exclude no
  command from the sandbox; the kit's launchers start the normal level, which adds the exclusions from
  `~/.config/claude-levels/normal-adds.json` ([ADR 0019](adr/0019-strict-base-and-level-profiles.md)). Start it with
  `claude-resume`, or restart the tab (`tmux-claude-restart`). After installing this version, restart every Claude:
  tabs started before it lose `az`, `gh` and `git push` until they restart.
- **"BLOCKED by policy (guard.sh)" when Claude edits settings, hooks or the kit's lists:** the agent never writes its
  own configuration ([ADR 0017](adr/0017-defence-in-depth-for-agent-configuration.md)). Edit it yourself in a plain
  shell. For `CLAUDE.md`, commands, agents and skills you can open a 30-minute window in which Claude may write them,
  each write audited as `config-write-allowed`:

  ```bash
  date -d '+30 min' +%s > ~/.config/ws-guard/allow-config-writes
  rm ~/.config/ws-guard/allow-config-writes     # close it early
  ```

- **A production subscription or context has no "prod" in its name:** list it in
  `~/.config/ws-guard/production.conf`, one per line (`subscription <id or name>`, `context <kube context>`; names may
  contain spaces). The guard then blocks mutating `az`, `kubectl`, `helm` and Azure MCP tools against it.
- **A tab should act as an agent identity, not as you:** create `~/.config/ws-agent/<name>/`, log in there with a
  reduced-scope identity (`AZURE_CONFIG_DIR=~/.config/ws-agent/<name>/azure az login`, the same with `GH_CONFIG_DIR` for
  `gh auth login` and `KUBECONFIG` for the kube config), then `tmux-level normal --agent <name>`. The tab remembers it
  (`@cagent`); `--agent none` drops it. The guard refuses to switch those credentials from inside Claude
  ([ADR 0020](adr/0020-agent-scoped-identities.md)).
- **A prompt was refused as "seems to contain a secret":** remove the secret. To send it anyway, start the prompt with
  `#allow-secret`; the audit log records that you did, never the prompt.
- **Memory writes ask every time:** `memory-gate.sh` asks for every MemPalace write, also after "don't ask again" and
  in solo mode, and blocks text between `<private>` and `</private>`. Review what memory holds with
  `ws-memory review --older-than 90` and `ws-memory log`, in a terminal (both refuse to write inside Claude).
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
- **"throwaway repository (under the temp dir, no remote)":** a test or scratch repository under `/tmp` or `/var/tmp`
  with no remote skips Conventional Commits and lint at commit time; secrets, forbidden files, size and
  `Co-authored-by` still apply, and a push from it re-checks every message
  ([ADR 0023](adr/0023-git-gate-agent-trailer-and-throwaway-repositories.md)). A repository with a remote, or anywhere
  else, is never a throwaway.
- **Commits made by Claude carry `Agent-Session:` (and `Agent:`) lines:** the gate adds them to every commit made from
  a Claude Code session, so `git log` tells agent commits from yours; your own commits from a plain shell carry
  nothing. To leave them out in one repository: `git config ws.gate.agentTrailer false` (in a plain shell; logged).
  Find an agent's commits with `git log --grep '^Agent-Session: '`.
- **"gitleaks is missing, so secrets cannot be checked" blocks every commit:** the secret scan is mandatory.
  Install it with `ws-tools install base`. For a repository that must commit on a machine without it:
  `git config ws.gate.allowNoGitleaks true` (each such commit is logged in `~/.local/state/ws-gate/opt-outs.log`).
- **A push fails with "osv-scanner is missing" or "checkov is missing":** the push changes a lock file or manifest
  (osv-scanner) or Terraform, Bicep, a Dockerfile, a Kubernetes manifest or a CI workflow (checkov), and the scanner
  is not installed: `ws-tools install gate` (gitleaks, osv-scanner and checkov, pinned). Only if you must push without
  it: `git config ws.gate.allowNoOsv true` or `ws.gate.allowNoCheckov true` in that repository, logged the same way
  and reported by `ws-audit`.
  `ws-gate bypasses` lists the repositories where the gate does not run in full; `ws-audit` fails on a local
  `core.hooksPath` or `ws.gate.allowNoGitleaks` and warns on `ws.gate.skip`.
- **`export.sh` refuses because of possible secrets:** move the secret to Key Vault; if it is a detection pattern, add
  it to `secrets-allow.txt` with review.
- **The tag ended up on an earlier commit:** if it is not on GitHub yet, `git tag -f -a vX.Y.Z -m "…"`; if it was
  already pushed, leave it and the fix goes into the next version.
- **Something stopped working after `install.sh`:** every file it replaced is in
  `~/.local/share/ws-kit/backup.<date>/`, under the same path; copy it back.
- **The running tmux behaves differently from the tests** (a menu says "command not found", tabs are not saved or did
  not come back): `ws-verify --live` checks the real server (its `PATH`, the save, the tabs in it, leftover finder
  sessions, scripts the bar, keys and hooks call, stale sockets) and prints the fix under each failure.
- **Dead sockets pile up in `/tmp/tmux-<uid>/`:** `ws-verify --clean-sockets` deletes the ones no server answers on.
- **The compliance check fails:** `ws-audit --compliance` reads `docs/compliance/controls.yaml` from the kit checkout
  (`$WS_KIT`, default `~/code/claude-workstation`, or `--kit DIR` / `--catalogue FILE`) and runs only allow-listed
  read-only checks; checks it cannot run on this machine are `not-run`, not failures. Exit 1 means a control marked
  `implemented` failed its check: fix the regression, or change the control's status in a reviewed pull request.
  `--json` prints the result; the last run is in `~/.local/share/ws-telemetry/compliance.json`.

### Signing a release

`ws-kit-update` installs only a `vX.Y.Z` tag signed by a key in the **installed** `~/.config/ws-kit/allowed_signers`
(plus `allowed_signers.local`), never the branch tip ([ADR 0018](adr/0018-supply-chain-pinning-and-signed-releases.md)).
Until the kit ships a maintainer key, it refuses every release with exit 11.

1. Create the signing key once, on the maintainer's machine (keep the private key out of the kit and of any backup
   the agent can read):

   ```bash
   ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/kit_signing
   git -C ~/code/claude-workstation config gpg.format ssh
   git -C ~/code/claude-workstation config user.signingkey ~/.ssh/kit_signing.pub
   ```

2. Add one line to `files/home/.config/ws-kit/allowed_signers`, `<email> namespaces="git" <contents of
   kit_signing.pub>`, and commit it through a reviewed pull request.
3. Release from `main`: `git tag -s vX.Y.Z -m vX.Y.Z`, then `git push origin vX.Y.Z`. The `release` workflow
   (`.github/workflows/release.yml`, job "Signed tag") runs `git verify-tag` against the committed `allowed_signers`
   and attaches the CycloneDX SBOM; an unsigned tag fails there and no release is published.
4. Check locally: `git -c gpg.ssh.allowedSignersFile=files/home/.config/ws-kit/allowed_signers verify-tag vX.Y.Z`.

| Situation | Steps |
|---|---|
| A fork without the maintainer's key | Put the fork's own keys in `~/.config/ws-kit/allowed_signers.local`, or run `ws-kit-update --allow-unsigned` (logged in `~/.local/state/ws-kit-update.log` and sent to Telegram) |
| `ws-kit-update --check` exits 11 | A newer release exists whose signature fails: do not apply it. Check the tag on GitHub and who pushed it; treat an unexpected one as a compromised update ([incident response](governance/AI-INCIDENT-RESPONSE.md)) |
| The signing key is lost or exposed | See [Rotating secrets](#rotating-secrets) |

### Pinned npm packages

The npm MCP servers and agent tools (`azure-mcp`, `chrome-devtools-mcp`, `agent-browser`) are pinned by exact version
and sha512: a committed `package.json` and `package-lock.json` in `files/home/.local/lib/ws-npm/<name>/`, and the
version and integrity in `files/mcp-servers.lock.json`. `ws-pinned install <name>` runs `npm ci --ignore-scripts` into
`~/.local/share/ws-kit/npm/<name>/`; nothing runs through `npx -y`.

To move a pin (a reviewed change to the kit; Dependabot opens these weekly, after a 7-day cool-down), one
command updates every file that must agree: `package.json` and `package-lock.json`, `version`, `integrity` and the
prerelease flag in `files/mcp-servers.lock.json`, and the generated tables of `docs/governance/AI-BOM.md`; then it runs
`tests/supply-chain.sh`, `tests/ai-bom.sh` and `tests/compliance.sh`.

```bash
bash .github/scripts/bump-pinned.sh --list                      # pinned packages and versions
bash .github/scripts/bump-pinned.sh azure-mcp 4.0.0-beta.9      # move a pin yourself
```

A Dependabot pull request changes only `package.json` and `package-lock.json`, so its CI fails (supply chain, AI-BOM,
compliance) until the rest follows. To finish it:

1. `git fetch origin && git switch <dependabot branch>`.
2. `bash .github/scripts/bump-pinned.sh <name>` (no version: it takes the package files as Dependabot left them).
3. A prerelease needs its reason: review `prereleaseReason` in `files/mcp-servers.lock.json` (the script refuses a
   prerelease without one), and read the release notes.
4. Add a `CHANGELOG.md` line under Unreleased, commit (`build(deps): bump <package> to <version>`) and push.
5. After merging and installing: `ws-pinned install <name>`, then `ws-pinned verify --online` (also runs
   `npm audit signatures`).

| Command | Use |
|---|---|
| `ws-pinned list` | Pinned packages and versions |
| `ws-pinned verify [--online] [name…]` | The installed tree still matches its lock and its recorded hash; `ws-audit` fails on a mismatch |
| `ws-pinned outdated` | Newest stable and newest release next to each pin |
| `ws-pinned local-check <name> <path>` | A local MCP executable (MemPalace, recall) still has the sha256 pinned on first use |

A local MCP executable whose sha256 changed is skipped by `install.sh` with a warning. Review the change, then
`bash install.sh --mcp-accept <name>` re-pins it.

### Pinned tools and tmux plugins

The GitHub binaries `ws-tools` installs (osv-scanner, tflint, k9s, hadolint, starship, agg, cosign) are pinned by
version and sha256 in `files/home/.local/lib/ws-tools.lock`, and checkov by version. A download that differs from its
pin is refused; tflint's release is also checked with cosign (keyless, a GitHub Actions workflow of its own
repository), and the pinned cosign is installed first when missing. TPM and the tmux plugins are pinned by commit in
`files/home/.config/tmux-claude/plugins.lock` and installed with `ws-plugins apply` (by `install.sh` and `ws-update`).

| Command | Use |
|---|---|
| `ws-tools pins` | The pinned tools and how each is verified |
| `ws-plugins verify` | Every plugin at its pinned commit with no changed file, and every `@plugin` of `~/.tmux.conf` in the lock; `ws-audit` fails otherwise |
| `ws-plugins apply` | Puts each plugin back at its commit; a plugin with an added script or whose commit upstream no longer has is moved to `~/.local/share/ws-kit/plugins-quarantine/` |

To move a pin, change the version and sha256 (or the commit) in the lock after reading the release notes or the
upstream diff, and run `bash tests/supply-tools.sh`. Only when you must install something that fails its check:
`WS_TOOLS_ALLOW_UNVERIFIED=1 ws-tools install <tool>` or `WS_PLUGINS_ALLOW_UNPINNED=1 ws-plugins apply`; each use is
logged under `~/.local/state/ws-tools/` or `ws-plugins/` and recorded in the audit log.

## 9. WSL and Windows

- **WSL does not start:** `wsl --shutdown` and retry. If it still fails, see [section 17](#17-recovery) (snapshot, or
  reinstall + backup).
- **No internet in WSL after changing networks:** remove `networkingMode=mirrored` from `%UserProfile%\.wslconfig` and
  run `wsl --shutdown` (on this corporate network NAT is used).
- **fnm error when opening the terminal:** the `.bashrc` block uses `/tmp/fnm-$UID` if `/run/user/$UID` does not
  exist; open a new tab. If it persists, check that the block is complete.
- **Low disk space:** `ws-health` requires 15 % free on `/` and 50 GB on `C:`. Clean caches
  (`npm cache clean --force`, old `node_modules`) before backups.

### WSL interop

Windows executables run outside the Linux sandbox, so every `.exe` an agent names asks you first (`Bash(*.exe*)` in
`permissions.ask`; `pwsh.exe`, `powershell.exe`, `cmd.exe` and `wsl.exe` are listed by name too) and the guard blocks
PowerShell that downloads and runs code or uses `-EncodedCommand`. The kit's own hooks run Windows executables
(`pwsh.exe`, `mempalace.exe`, recall's `python.exe`) outside Claude's permission system, so they are not affected.
`bash tests/interop-adversarial.sh` checks the cases; `--live` also probes interop from inside bubblewrap (report
only).

Optional, stronger: take the Windows folders off Linux's `PATH` so a bare `explorer.exe` or `clip.exe` is not found.

```ini
# /etc/wsl.conf (edit with sudo), then in PowerShell: wsl --shutdown
[interop]
appendWindowsPath=false
```

The cost: `code`, `explorer.exe`, `clip.exe`, `pwsh.exe` and every other Windows tool must then be called by full path
(`/mnt/c/...`) or from your own `PATH` additions; the kit's hooks already use full paths. Interop itself stays on.

## 10. Floating windows, AI in the terminal and tests

- **Using a floating window like a normal tab:** wheel = scroll; drag = select and copy to the Windows clipboard;
  `Ctrl+b /` = search; `q` leaves scroll; Shift+click opens a URL; `Ctrl+b d` closes.
- **A floating window hung:** `tmux -L popup kill-server` (closes all floating windows; your tabs are untouched).
- **Turn on the grey AI suggestions:** `ws-secret set anthropic-api-key` (a Claude Console key; it is stored encrypted
  in Windows Credential Manager) and open a new tab. Check: `ws-secret has anthropic-api-key`.
- **No suggestions appear:** check the key (above), that ble.sh is active, and the circuit breaker:
  `cat ~/.cache/ai-shell/circuit` (`0 <date>` = paused for 5 min after 3 failures; `rm ~/.cache/ai-shell/circuit`
  resets it). Turn them off for one session: `export AI_SHELL_GHOST=0`. Change the model:
  `export AI_SHELL_API_MODEL=…`.
- **Cost:** suggestions use the API (Console billing, separate from the Team plan), with Haiku and short responses;
  one request in flight and at least 0.8 s between requests. Check spending at platform.claude.com.
- **Rotate or remove the key:** `ws-secret set anthropic-api-key` (replaces) or
  `ws-secret delete anthropic-api-key`.
- **Test everything:** `ws-test` (isolated: does not touch your session or your accounts and spends no usage) and
  `ws-test --ai` (real Claude and API).
- **Sandbox mask files (`Sandbox mask files left behind`):** close Claude in that repository and delete only the empty
  entries that git does not know about:

  ```bash
  find . -maxdepth 3 -empty \( -path './.claude*' -o -name .mcp.json -o -name .vscode -o -name .gitmodules \) -not -path './.git/*' \
    | while read -r p; do git ls-files --error-unmatch "$p" >/dev/null 2>&1 || echo "$p"; done | tee /tmp/masks.txt
  xargs -a /tmp/masks.txt -d '\n' rm -df
  ```

## 11. Usage and telemetry

- **Open the dashboard:** Menu → "Usage and reports" → "Usage dashboard (browser)", or `ws-telemetry open`. File:
  `%UserProfile%\ws-telemetry\dashboard.html` (regenerated every minute; the page reloads by itself).
- **The dashboard does not update:** run `ws-telemetry build` by hand and check that tmux is running (the
  every-minute save triggers it). If the "Updated" time does not change, check `~/.local/bin/tmux-backup`.
- **Costs:** they are the equivalent at API prices, not what you pay on the Team plan. Prices are in `ws-telemetry`
  (the `PRICES` table); to adjust one: `~/.config/ws-telemetry/prices.json` with
  `{"claude-opus-5-5": [input, output, cache_5m, cache_1h, cache_read]}` (input, output, 5 min cache write, 1 h cache
  write, cache read) in USD per million tokens.
- **Your own queries:** `ws-telemetry sql` (requires DuckDB) or read `~/.local/share/ws-telemetry/turns.jsonl`.
- **Privacy:** transcript-derived data and hook traces store no conversation text; only tokens, lengths, tool names,
  project and branch. Retention: 13 months. Delete everything:
  `rm -rf ~/.local/share/ws-telemetry "%UserProfile%/ws-telemetry"`.
- **Open tabs do not send OpenTelemetry data:** export starts when Claude starts; restart the tabs
  (`tmux-claude-restart --all`).

### Traces, estimation and budgets

| Task | Command |
|---|---|
| See which tools are slow or fail | `ws-telemetry traces --days 7` |
| Hours and cost of a ticket (branch `ABC-123-…`) | `ws-telemetry estimate ABC-123`; also `--by project` and `--csv` |
| Last week's report | `ws-telemetry week` (saved to `%UserProfile%\ws-telemetry\week-YYYY-Www.md`) |
| Monthly budget per project | `~/.config/ws-telemetry/budgets.conf` with `project=usd` lines (`*=usd` for the total), then `ws-telemetry budgets` |
| Hold work once a budget is spent | Add the line `hard=1` to `budgets.conf`: `ws-runtime-gate.sh` then holds prompts and tools in a project at 100 % (every project when the total is over) |
| Let one project go on over a hard budget | `ws-telemetry budgets --override <project> [hours]` in a terminal (24 h by default; audited; denied to Claude) |
| Approval fatigue | `ws-telemetry prompts [--days 7]`: approvals per hour, time to answer, answers under 2 s and permanent allow rules; `--alerts` for what Telegram would send |
| Excel or Power BI | `ws-telemetry export` writes `%UserProfile%\ws-telemetry\data\*.csv` |
| Free-form SQL | `ws-telemetry sql`, for example `SELECT tool, count(*) FROM traces GROUP BY 1` |

- Work is "held" over a hard budget: the flag `~/.local/state/ws-budget-over` is rewritten by `ws-telemetry build`
  about once a minute. If the dashboard stops updating, a flag older than 2 hours is ignored and work continues (the
  gate fails open because it cannot know the spend). A turn already running is held at its next tool call.
- No new traces: `jq '.hooks.PostToolUse' ~/.claude/settings.json | grep ws-traces` and check that
  `~/.claude/hooks/ws-traces.sh` is executable.
- Turn off: remove the `ws-traces.sh` entries from `settings.json` (a copy from before patch 51 is among the
  `*.bak.*` files, or in `~/.local/share/ws-kit/backup.legacy/` after `install.sh --prune-backups`).
- Telegram: `weekly_day`, `weekly_hour`, `budgets=on|off` in `~/.config/ws-telegram/settings`.

## 12. Model routing

- **How it works:** when you send a text to Claude, if a rule in `~/.config/ws-routing/rules.conf` says it belongs to a
  different tier than the tab's model, a window appears: `y` switches and sends (`s` also works), `n` sends with the
  current one (it does not suggest that tier again for 30 min), `x` returns the text so you can edit it. With no
  answer in 30 s it sends with the current one.
- **Moving down a model:** it only asks when context is below `downgrade_max_ctx` (30 % by default, in
  `~/.config/ws-routing/settings.conf`). Above that, routing suggests the cheap subagent to Claude and does not change
  the model.
- **Turn it off:** Menu → "Claude in this tab" → "Model" → "Turn off automatic routing in ALL tabs (asks before
  switching)", or `tmux set -g @croute off`.
- **Change the model by hand:** the same menu, or `cr -t sonnet "task"`. Your default model does not change: it is
  restored in `settings.json` after `/model`.
- **A rule classifies wrongly:** `cr --explain "the task"` says which rule won. Edit `rules.conf` (the first match wins)
  and run `cr --test` (it must stay at 90 % or more; with `ws-lang es` it runs the English and the Spanish task sets).
- **The text got "stuck":** if the window did not appear (no terminal attached), it is sent by itself with the current
  model in about 1 s. Pending texts live in `$XDG_RUNTIME_DIR/ws-routing/` (0600) and are deleted when used.
- **Uninstall the hook:** remove the `ws-routing.sh` entry from `hooks.UserPromptSubmit` in `~/.claude/settings.json`.

## 13. Telegram

- **Set up (once):** `ws-telegram setup`. Create the bot in @BotFather, paste the token (it is stored in Windows
  Credential Manager as `ws/telegram-bot-token`) and send `/start` to your bot.
- **Notifications do not arrive:** `ws-telegram status` (configured, turned on, service running) and
  `ws-telegram test`. tmux starts the service every minute; by hand: `ws-telegram ensure`. If the company network
  blocks `api.telegram.org`, the status shows `error_api`.
- **A button says "The screen changed; I sent nothing":** the dialog is no longer the same (you answered on the PC or
  Claude moved on); nothing was sent. Buttons expire after 10 min.
- **`!` commands from Telegram:** each command arrives in a code message (tap it to copy it). "▶ Run" is offered only
  for read-only commands on the allow list in `ws-telegram` (`git status`, `git log`, `ls`, `kubectl get`, `az account
  show`…; no shell syntax, no `.exe`, no `--output`) that also pass the block lists; it asks for your PIN and runs the
  command in that tab as `!`, replying with the redacted output. Anything else arrives without a button: run it on
  the PC. Nothing is offered in `bare` or solo-mode tabs. Forwarding or typing text to the bot executes nothing.
- **Approving from the phone asks for the PIN:** approving a risky dialog (an MCP tool, an ask rule, a command that
  runs outside the sandbox, or one the block lists match; marked 🔐) needs your PIN; a plain approval is one tap.
  `ws-telegram approve pin` asks for it on every approval, `ws-telegram approve risky` goes back to the default.
  "Don't ask again" and other persistent allows are never offered as buttons. Without a PIN set
  (`ws-telegram text pin`), risky approvals from the phone are refused.
- **Alerts with "⛔ Stop this tab":** an anomaly alert (repeated guard blocks, denials or sandbox hits in one session,
  5 in 10 minutes by default: `anomaly_n`, `anomaly_min`, `anomaly=off` in the settings) offers a button that runs
  `ws-stop-all --pane` for that tab. While the emergency stop is on, buttons and ▶ Run send nothing.
- **Replying with text:** `ws-telegram text on` (asks for the PIN the first time). In Telegram, use Reply on Claude's
  question (the ones that show ↩), starting with the PIN: `4821 use an opaque cursor`. Change the PIN:
  `ws-telegram text pin`. If it was turned off because of wrong PINs: `ws-telegram text on` on the PC.
- **Alerts and daily summary:** adjusted in `~/.config/ws-telegram/settings` (`summary_hour`, `usage_usd_h`,
  `context_pct`, `stalled_min`, `alerts=on|off`). Test the summary: `ws-telegram summary`. Every alert is rate
  limited (30 min per tab; reminders every 3 min). Buttons: `/compact` and switch account.
- **Turn off:** Menu → "Workstation" → "Telegram: turn notifications on or off", or `ws-telegram off`.
- **Lost phone or compromised Telegram account:** `ws-telegram forget` and, in @BotFather, `/revoke` the bot. Without
  the token, nobody can send keys to your tabs.

## 14. Kit CI

- **What runs:** on every push to `main` and on every pull request: lint (shellcheck, Python, JSON, tmux), SAST and
  secrets (bandit, gitleaks), workflow security (zizmor), the SBOM, `tests/run.sh`, every other `tests/*.sh` suite
  (job "Security suites") and a clean install. A signed `vX.Y.Z` tag runs `release.yml`; once a month
  `compliance-monthly.yml` re-runs the compliance and AI-BOM checks and the framework-currency check. Details in
  [TESTING.md](TESTING.md#continuous-integration); see the runs in GitHub → Actions.
- **zizmor fails:** every action must be pinned by commit SHA with its version as a comment, jobs need
  `persist-credentials: false` and the least `permissions`; fix the finding rather than silencing it.
- **`tests/compliance.sh` fails:** the catalogue (`docs/compliance/controls.yaml`) and the coverage tables of
  `docs/compliance/assessment.md` disagree, an `evidence` file is missing, or an `implemented` control's check fails.
  Fix the cause in the same pull request.
- **`tests/ai-bom.sh` fails:** a model, agent, MCP server or hook changed and `docs/governance/AI-BOM.md` was not
  regenerated: `bash tests/ai-bom.sh --write`, review the diff, commit.
- **gitleaks fails on a test pattern:** if the file contains only detection patterns or fake data, add it to
  `.gitleaks.toml` (`[allowlist] paths`) with a comment; if it is a real secret, rotate it and remove it.
- **bandit fails:** fix the finding; if it is a false positive, `# nosec <rule>` on that line and the reason in a
  comment above it.
- **Locally before pushing:** `ws-verify` covers the same; CI is the source of truth for anyone using the kit.

## 15. tmux shortcuts, views and swarm

### Shortcuts added by patch 52

| Something fails | Check |
|---|---|
| `Ctrl+b e` pastes nothing | Check whether the tab has another pane; if not, the picker opens. `tmux-pane --text %N` shows the block |
| The "Notify me when it finishes" notification does not arrive | `ws-notify --force test text`; Telegram: `ws-telegram status`. The notification goes out when the pane returns to bash |
| The palette runs in another tab | Open it from the target tab; the `#{formats}` are expanded against it |
| The label is not visible in the status bar | `tmux-label --bar` (a theme change rewrites the formats) |
| Focus mode got stuck on | `tmux-focus off` |
| Second monitor: leftover `-m2` sessions | They are deleted when their window closes; if not: `tmux kill-session -t <group>-m2` |

### Patch 53: branch bar, templates, recording, history and swarm

| Something fails | Check |
|---|---|
| CI/PR does not show in the status bar | `tmux-branch .` in the folder; `gh auth status` or `az account show`; `tmux set -g @branch_bar on` |
| The status bar is slow | `tmux set -g @branch_bar off` (everything network-related runs in the background with a 3 min cache) |
| Recording with no events | The pane had another capture (`Ctrl+b H` or history): turn it off and record again |
| History takes a lot of space | `tmux-history --status`; `WS_HISTORY_DAYS=7`; `tmux-history off` |
| Swarm with a conflict | Resolve in the main repository (branch `swarm/<id>/integration`), commit and `tmux-swarm integrate <id>` |
| Removing a swarm | `tmux-swarm clean <id>` (keeps unintegrated branches and worktrees with changes) |

## 16. Upgrading

```bash
ws-update                    # Claude Code, plugins, packages
ws-kit-update                # update the workstation from the kit; rolls back if ws-test fails
tmux-claude-restart --all  # make every idle tab pick up the new configuration
bash export.sh               # capture what is installed back into the kit
ws-verify                    # verify before pushing
```

An upgrade from 2.x to 3.0 has extra steps: see [Upgrading from 2.x to 3.0](#upgrading-from-2x-to-30-english-names).

1. Run `ws-update` for Claude Code, the tmux plugins and the system packages.
2. Run `ws-kit-update` for the workstation itself. It fetches the release tags, takes the newest `vX.Y.Z` ahead of
   your checkout, refuses it unless `git verify-tag` passes against your installed `allowed_signers`
   ([Signing a release](#signing-a-release)), moves to it with `git merge --ff-only`, runs `install.sh` (every changed
   file is copied to `~/.local/share/ws-kit/backup.<date>/` first) and then `ws-test`. If the tests fail it goes back
   to the previous commit and reinstalls. It does nothing when the kit folder has uncommitted changes or commits the
   release does not contain.
3. Reload tmux (`Ctrl+b r`) and restart Claude in the idle tabs (`tmux-claude-restart --all`) so they pick up the new
   settings, hooks and telemetry. Repeat for the tabs it reports as busy, or use `--include-busy`.
4. If the release changed `guard.sh` and you installed the managed policy, run `bash install.sh --managed` again
   (`install.sh` warns when the root copy is older).
5. If you maintain the kit: `bash export.sh`, review the diff, `ws-verify`, commit.

The steps to take once after installing a release are listed under "Upgrade notes" in [CHANGELOG.md](../CHANGELOG.md).

If something stopped working after the update, every file the installer replaced is in
`~/.local/share/ws-kit/backup.<date>/` under its path in your home (the installer prints the folder). The rollback of
`ws-kit-update` itself does not use these copies: it goes back in the kit's git history and reinstalls.

### Upgrading from 2.x to 3.0 (English names)

Version 3.0 renames commands, options, variables, folders and stored values. `install.sh` (and `ws-kit-update`, which
runs it) migrates the installation before copying the new files. The tables of old and new names are in
[USAGE.md](USAGE.md#18-upgrading-from-2x-names).

1. Save your work and take an extra backup: `Ctrl+b Ctrl+s`, then `ws-backup-lite --now` (in 2.x:
   `ws-backup-lite --ahora`).
2. Preview: `bash install.sh --dry-run`. Under "Names from before 3.0 → English (renames.tsv)" each line says
   `moved` (your data, moved to the new name), `shim` (an old command or hook set aside and replaced by a wrapper) or
   `dropped` (an old kit file set aside). A warning `both ~/<old> and ~/<new> exist` means neither was touched: merge
   them by hand and run the preview again.
3. Install: `bash install.sh`. Note the folder in the line `Files (backup: ~/.local/share/ws-kit/backup.<date>)`;
   the files set aside go to `~/.local/share/ws-kit/pre-english.<date>/`.
4. Restart tmux: `tmux kill-server`, then `dev`. The tabs come back. A server that keeps running holds the old option
   names and values, and the state labels, protection icons and menus do not match the new scripts.
5. Look for `changed Windows handler …` in the output: the migration patches the registered `ws-claude://` handler
   in place (backup `<file>.bak.<date>` next to it, on the Windows side) so that it accepts `ws-claude://focus/N`
   and calls `tmux-goto`. If the installer warns that it could not update it, make those two changes by hand,
   following `windows/ws-claude-focus.ps1`.
6. Check: `ws-check && ws-health`, `ws-verify --live`, `ws-test`, `ws-lang` (an installation that came from 2.x is
   set to `es`), `ws-telegram status` (the old service was stopped and tmux starts the new one within a minute) and
   `ws-telemetry summary` (the history from before the upgrade must still be there).
7. Replace the old names in your own scripts and configuration. When nothing calls them:
   `bash install.sh --remove-shims`.

| Symptom after the upgrade | Cause and steps |
|---|---|
| `<old> was renamed to <new>; its options were renamed too` on stderr | Something still calls a wrapper. Find the caller (`grep -rn '<old>' ~/.bashrc ~/.config ~/.tmux.conf ~/.claude/settings.json`) and use the new name |
| A wrapper fails with a usage error | Wrappers pass the arguments unchanged and the subcommand or option was renamed: use the new one from the tables |
| `both ~/<old> and ~/<new> exist` | A 3.0 command ran before the migration and created the new folder. Move the content of the old one into the new one by hand, delete the old one and rerun `install.sh` |
| The status labels or the menus look wrong | tmux was not restarted: `tmux kill-server` and open the session again |
| A Windows notification click does nothing | The registered `ws-claude://` handler still expects `ws-claude://foco/N`. The install output shows `changed Windows handler …` when it was patched; otherwise edit that `.ps1` to accept `focus` and call `tmux-goto` (see `windows/ws-claude-focus.ps1`) |
| The dashboard misses the days before the upgrade | Check that `~/.local/share/ws-telemetry/traces/` holds the old files (moved from `ws-telemetria/trazas/`), then `ws-telemetry build` |
| Prompts typed in Spanish are no longer routed or detected | `ws-lang` shows `en`: run `ws-lang es` |

### Rolling back the rename

The migration deletes nothing, so it can be undone by hand. Run this in a normal shell, with tmux stopped
(`tmux kill-server`).

1. From the 3.0 kit, remove the wrappers so the old commands can be put back: `bash install.sh --remove-shims`.
2. Go back to the 2.x kit, for example `git -C ~/code/claude-workstation checkout v2.7.0`.
3. Put back the files that were set aside. They keep their path under `$HOME`:

   ```bash
   cp -a ~/.local/share/ws-kit/pre-english.<date>/. ~/
   ```

4. Move your data back to the old names. The pairs are the `data` lines of `renames.tsv` in the 3.0 kit (old path,
   new path); move each new path back to its old one, the files inside a folder first, then the folder. For example:

   ```bash
   mv ~/.local/share/ws-telemetry/traces ~/.local/share/ws-telemetry/trazas
   mv ~/.local/share/ws-telemetry ~/.local/share/ws-telemetria
   ```

5. Restore the files the installer replaced, from the backup folder with the date of the upgrade (they keep their
   path under `$HOME`):

   ```bash
   (cd ~/.local/share/ws-kit/backup.<date> && find . -type f)     # lists them
   cp -a ~/.local/share/ws-kit/backup.<date>/. ~/
   ```

   The Windows notification handler is the exception: its copy is next to it, as `<file>.bak.<date>`.

6. Run `bash install.sh` from the 2.x kit, start tmux and run `ws-test`.

Records written by 3.0 between the upgrade and the rollback carry English field names, which 2.x does not read: those
days show incomplete numbers in the 2.x dashboard. The files of 3.0 that have no 2.x name (`ws-lang`, the language
packs, `~/.config/tmux-claude/lang`) stay in place and are harmless.

## 17. Recovery

### Backup layers

| Layer | What it stores | Frequency | Where | Recover with |
|---|---|---|---|---|
| tmux (continuum + resurrect) | Tabs, panes, folders | Every minute and when tabs change | `~/.local/share/tmux/resurrect` (30 days) | `tmux-recover` |
| `ws-backup` | Conversations and audit log | Every 15 min, incremental, encrypted per file with `age`; copies whose original is gone expire after 30 days (`WS_BACKUP_COPY_DAYS`, pruned by `ws-backup-lite`) | `%UserProfile%\.claude-wsl-backup` | `ws-restore-lite --mirror` |
| `ws-backup-lite` | All of Claude (conversations, subagents, todos, plans, `/rewind`, history, memory, audit log and a copy of its anchors), tmux and inventory | Daily, automatic (14 copies); encrypted with `age` to the cloud key and any `age-recipients` | `%UserProfile%\WSL-Backups\lite` | `ws-restore-lite --restore` |
| Kit (GitHub) | All the configuration | On push | `andreshma/claude-workstation` | `install.sh` |
| `devsnapshot` (optional) | The whole distro | By hand | `%UserProfile%\WSL-Backups` | `wsl --import` |

### Recovery objectives

The targets the backup layers are built for (WS-GOV-013; Well-Architected RE:04 and RE:09). The recovery point
(RPO) follows from each layer's frequency; the recovery times (RTO) are targets for one owner with the runbook open,
not measurements: time the next drill (`ws-restore-lite --restore` into a throwaway distro) and write the result here.

| What is lost | RPO (data you can lose) | RTO target | Restored from |
|---|---|---|---|
| A tab layout after a crash or restart | 1 minute | 2 minutes | tmux continuum and resurrect (`tmux-recover`) |
| Conversations and the audit log (disk lost, distro intact on Windows) | 15 minutes | 30 minutes | `ws-backup` mirror (`ws-restore-lite --mirror`) |
| Everything of Claude (memory, plans, history, anchors) | 24 hours | 1 hour | `ws-backup-lite` (`ws-restore-lite --restore`) |
| The workstation configuration | The last pushed commit of the kit | 1 hour on a new distro | `install.sh` from a verified tag |
| The whole distro | The last `devsnapshot` | 30 minutes | `wsl --import` |
| Cloud copy (Windows profile lost) | The last `ws-backup-cloud` run | Half a day (new laptop) | [Restoring encrypted backups](#restoring-encrypted-backups) |

Out of scope: availability of the remote services (Claude, GitHub, Azure, Telegram) and of Windows itself; an
outage of one of them is waited out, not recovered from (docs/compliance/assessment.md, scope).

### Test, back up and restore

- **Test that the backup works:** Menu → "Workstation" → "Test the latest backup" (`ws-restore-lite`): it extracts
  into a temporary folder and verifies SHA-256, readable conversations, tmux, inventory and that it carries no
  credentials.
- **Back up now:** Menu → "Workstation" → "Back up Claude now" (`ws-backup-lite --now`).
- **Restore on this machine:** close Claude in every tab and run `ws-restore-lite --restore`. Anything that already
  exists and differs is kept as `<file>.~N~` (nothing is overwritten).

### New laptop or lost distro, without a snapshot

1. Install a clean Ubuntu 24.04.
2. Clone the kit and run `bash install.sh`.
3. Copy the latest `claude-lite-*.tar.zst.age` (or `.tar.zst` for an old, unencrypted one) and its `.sha256` to
   `%UserProfile%\WSL-Backups\lite`.
4. Run `ws-restore-lite` (test) and then `ws-restore-lite --restore`. An encrypted backup needs its key first: see
   [Restoring encrypted backups](#restoring-encrypted-backups).
5. Install packages and tools with the commands it prints.
6. Log in (Claude, az, gh, aws).
7. Run `dev` and press `Ctrl+b Ctrl+r`.

Time: 30–60 min.

### With a snapshot

Run `wsl --unregister Ubuntu` **only** once the snapshot is verified, and then
`wsl --import Ubuntu %LOCALAPPDATA%\wsl\Ubuntu <snapshot>.vhdx --vhd`.

### Encrypted cloud backup

- **Set up (once):** `ws-backup-cloud setup`. Save the private key it shows in your password manager: without
  it, the cloud backups cannot be opened if you lose the laptop.
- **Every day** `ws-telegram` copies the latest lite backup, encrypted, to `OneDrive…\Backups\workstation-wsl` (keeps
  7). An installation that already copied to `OneDrive…\Respaldos\estacion-wsl` keeps using that folder while it
  exists and the new one does not.
- **Every month** the recovery test (local and cloud) arrives through Telegram. By hand: `ws-backup-cloud test`.
- **Restore on a new laptop:** `ws-secret set age-backup` (paste the key from your password manager),
  `ws-backup-cloud fetch`, then `ws-restore-lite` (test) and `ws-restore-lite --restore`.

### Restoring encrypted backups

Light backups are encrypted with `age` by default (`claude-lite-<date>.tar.zst.age`): to the cloud key of
`ws-backup-cloud` (`~/.config/ws-backup/cloud-recipient`) and to every key in `~/.config/ws-backup/age-recipients`.
With neither key, or without `age`, the backup is made in clear with a warning, logged as `UNENCRYPTED` in
`~/.local/state/ws-backup-lite.log`, and `ws-audit` fails until you run `ws-backup-cloud setup`.

| Situation | Steps |
|---|---|
| Same machine, key still in Credential Manager | `ws-restore-lite` (test), then `ws-restore-lite --restore`: without `--identity` it reads the cloud key from Credential Manager (`ws/age-backup`) into a 0600 temporary file deleted on exit |
| New machine | `bash install.sh`, then `ws-secret set age-backup` and paste the private key from your password manager; then `ws-restore-lite` and `ws-restore-lite --restore` |
| A backup encrypted to one of your own `age-recipients` | `ws-restore-lite --identity <your age identity file> [FILE]` |
| A backup made with a key you have since rotated | Put the old private key in a 0600 file and pass it with `--identity` ([Rotating secrets](#rotating-secrets)) |
| A copy from OneDrive | `ws-backup-cloud fetch [file] [destination]` decrypts it; then `ws-restore-lite [FILE]` |

`ws-restore-lite --test` refuses a backup that carries credentials, and `--restore` keeps every existing file that
differs as `<file>.~N~`.

## 18. Security operations

What to do when an agent misbehaves, when the audit log must be trusted, and when a secret is rotated or the
workstation is handed back. The playbooks per incident are in
[docs/governance/AI-INCIDENT-RESPONSE.md](governance/AI-INCIDENT-RESPONSE.md); the review calendar is in
[docs/governance/REVIEW-CADENCE.md](governance/REVIEW-CADENCE.md).

### Emergency stop

`ws-stop-all` stops every agent at once, in this order, so containment does not wait for the panes:

1. writes the marker `~/.local/state/ws-stop-all`: from then on the `ws-runtime-gate.sh` hook blocks every prompt and
   every tool call in every Claude (also a tab that does not close, a headless `claude -p` or a swarm agent), and
   `ws-telegram` refuses remote runs and button answers;
2. turns Telegram off (`ws-telegram off`);
3. records an audit event (`stop-all`);
4. sends Escape and `/exit` to the Claude in every tmux pane, then `Ctrl+C` twice after 10 seconds; panes still running
   after 20 seconds are listed by name, and so are headless Claude processes outside tmux.

```bash
ws-stop-all                      # everything; asks first in a terminal (Menu → Claude → Emergency stop, key X)
ws-stop-all --yes --kill         # without asking, and also ends headless Claude processes outside tmux
ws-stop-all --pane %12 --yes     # only the Claude of one pane (no marker; Telegram stays on)
ws-stop-all --session swarm-<id> # only the Claudes of one tmux session, for example a swarm
ws-stop-all --status             # is the marker on? · --list: panes that have a Claude now
```

From the phone, an anomaly alert offers "⛔ Stop this tab", which runs `ws-stop-all --pane` for that tab.

Nothing resumes on its own. Once you know what happened (keep the evidence first: next section):

```bash
ws-stop-all --clear     # removes the marker: prompts and tools run again (denied to Claude; run it in a terminal)
ws-telegram on          # Telegram stays off until you turn it on
tmux-claude-restart --all
```

### Verifying the audit log

`audit.sh` chains every line of `~/.claude/audit/YYYY-MM-DD.jsonl` to the previous one with sha256 (the first line
of a day points to the last line of the day before), and on every session end appends the day's head hash to
`%UserProfile%\ws-telemetry\audit-anchors.txt`, outside the agent's sandbox, so rewriting a whole chain shows too. The
log keeps 395 days.

```bash
ws-audit --verify-log              # checks ~/.claude/audit against the anchors; exit 1 on any break
ws-audit --verify-log <folder>     # checks a copy (for example one taken during an incident)
```

- **Exit 0:** no line was edited, deleted or reordered. Lines written before the chain started (an installation
  older than this version) are accepted only before the first chained line. Run it once after upgrading: the anchors
  file appears after the first session end.
- **Exit 1:** the output names each break (file and line). It reports and never repairs. Copy `~/.claude/audit/` and
  the anchors file to a 0700 folder outside the kit before anything else, then follow the incident playbooks.
- `ws-audit` itself fails its Security pillar when the chain is broken.
- Limits: the Telegram event logs are not chained, and an agent running without the sandbox (`bare`,
  `--unsandboxed` solo) could still reach the anchors file; the guard and the `Edit` deny rules block the direct
  writes.

### Rotating secrets

Secrets live in the Windows Credential Manager as `ws/<name>` (`ws-secret`). The rotation periods below come from
[REVIEW-CADENCE.md](governance/REVIEW-CADENCE.md#yearly) and were confirmed by the owner on 2026-11-25. Rotate at once,
whatever the period, when a device or the phone is lost, or a secret may have reached a model, memory, a log or a
backup.

| Secret | Period | Rotate or revoke |
|---|---|---|
| Telegram bot token | Yearly | In @BotFather, `/revoke` the bot's token and copy the new one; then `ws-telegram setup` (stores it with `ws-secret set telegram-bot-token`) and `ws-telegram test` |
| Telegram PIN | Yearly | `ws-telegram text pin` |
| Cloud backup key (`age-backup`) | Only on suspicion | Keep the old key: `ws-secret get age-backup` into your password manager, labelled with the date (backups encrypted to it stay readable only with it); then `mv ~/.config/ws-backup/cloud-recipient ~/.config/ws-backup/cloud-recipient.old-<date>` and `ws-backup-cloud setup` (new key pair, shown once). Delete the old key only after every backup encrypted with it has expired |
| Your own `age-recipients` keys | Only on suspicion | Replace the line in `~/.config/ws-backup/age-recipients`; keep the old identity file until its backups expire |
| Claude logins (work and personal) | On suspicion, offboarding | Work: `env -u CLAUDE_CONFIG_DIR claude auth logout`, then `claude auth login`. Personal: `claude-account logout personal`, then `claude-account login personal`. Revoke sessions in the claude.ai account settings if a device was lost |
| Terminal copilot API key (`anthropic-api-key`) | On suspicion | Create a new key in the Claude Console, `ws-secret set anthropic-api-key` (replaces), then delete the old key in the Console. `ws-secret delete anthropic-api-key` turns the suggestions off |
| MCP credentials | With the identity they use | The Azure MCP server uses your `az` login: `az logout`, `az login` (or the agent identity's `AZURE_CONFIG_DIR`). Remote servers (Microsoft Learn, release communications) hold no credential. Remove a server you no longer trust: `claude mcp remove <name>` in a plain shell |
| Agent identities (`~/.config/ws-agent/<name>`) | With the service principal or token behind them | Log out inside that folder (`AZURE_CONFIG_DIR=… az logout`, `GH_CONFIG_DIR=… gh auth logout`), rotate the identity's secret where it was issued, log in again |
| Release signing key | On suspicion, or when the maintainer changes | `ssh-keygen -t ed25519 -f ~/.ssh/kit_signing` (new key), replace the line in `files/home/.config/ws-kit/allowed_signers` through a reviewed pull request, sign the next tag with the new key. Workstations trust the new key only after installing that release, so it must still be signed with a key they already trust; a key that leaked instead calls for the compromised-update playbook |

After a rotation, note the date in the review log of [REVIEW-CADENCE.md](governance/REVIEW-CADENCE.md#review-log).
`ws-audit` does not yet warn about old secrets (WS-GOV-010).

**Offboarding: handing back the workstation or removing the kit.** In a plain shell, not inside Claude:

1. Stop everything: `ws-stop-all --yes --kill`, then `tmux kill-server`.
2. Telegram: `ws-telegram forget` (deletes token, chat and state), then in @BotFather `/deletebot` for that bot.
3. MCP servers: `claude mcp list`, then `claude mcp remove <name>` for each server of `files/mcp-servers.json`
   (`mempalace`, `recall`, `microsoft-learn`, `azure`, `ms-release-comms`, and `chrome-devtools` if you opted in).
4. Logins: the Claude logins above; `az logout`; `gh auth logout`; `kubectl config delete-context <ctx>` for each
   context; the agent identities under `~/.config/ws-agent/`.
5. Secrets in Credential Manager: `ws-secret delete telegram-bot-token`, `ws-secret delete telegram-pin`,
   `ws-secret delete anthropic-api-key`, and `ws-secret delete age-backup` once no backup you keep needs it.
6. Managed policy, if installed: `sudo rm /etc/claude-code/managed-settings.d/50-ws-kit.json
   /etc/claude-code/hooks/guard.sh /etc/claude-code/ws-credential-paths.txt`.
7. Git: `git config --global --unset core.hooksPath` (if it points at `~/.config/git/hooks`).
8. Local data: `~/.claude/audit/`, `~/.claude/projects/` (conversations), `~/.local/share/ws-telemetry/`,
   `~/.local/share/ws-kit/`, `~/.local/state/ws-*`, `~/.cache/ws-memory/`, and what MemPalace holds (its own tools).
9. Windows side and backups: `%UserProfile%\ws-telemetry\`, `%UserProfile%\.claude-wsl-backup`,
   `%UserProfile%\.tmux-resurrect-backup`, `%UserProfile%\WSL-Backups\`, and the OneDrive folder
   `Backups\workstation-wsl`.
10. The installed files: every path in `manifest.txt` under `$HOME`, and the kit's lines in `~/.bashrc`.
