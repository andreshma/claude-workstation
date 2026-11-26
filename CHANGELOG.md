# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

This release hardens the agent against the gaps of the AI and security assessment in `docs/compliance/`. Several
changes are **breaking** for daily use; read the upgrade notes first.

### Upgrade notes

After installing, in this order:

1. Reinstall: `bash install.sh --mcp-refresh` (re-registers the Azure MCP server from its pinned install instead of
   `npx`; the first run also pins the sha256 of the local MemPalace and recall executables).
2. Restart every Claude through the kit: `tmux-claude-restart --all`, then repeat it once the tabs it left alone
   because they were busy are idle (or use `--include-busy`); solo tabs are skipped, switch them with `tmux-solo`.
   A tab that has not restarted keeps the old settings in memory; once it reloads them it loses `az`, `gh` and
   `git push` until it is restarted through the kit, because the excluded commands now come only from the normal
   profile that the kit's launchers pass.
3. In a plain shell (the guard blocks this from Claude):
   `claude plugin install claude-security@claude-plugins-official`.
4. Generate the SSH release-signing key and add its public key to `files/home/.config/ws-kit/allowed_signers`
   ([Signing a release](docs/runbook.md#signing-a-release)); until then `ws-kit-update` refuses every release and
   exits 11 (forks: `allowed_signers.local` or `--allow-unsigned`, which is logged).
5. Install gitleaks on every machine (`ws-tools install base`): commits fail without it.
6. `ws-backup-cloud setup`, if it was never run, so the light backups are encrypted.
7. Set a Telegram PIN if there is none (`ws-telegram text pin`): risky approvals from the phone are refused without it.
8. Run `ws-audit --verify-log` once; the anchor file appears after the first session ends.
9. Two live checks that could not be made in tests: a MemPalace write from Claude shows a prompt with the provenance
   filled in, and a prompt blocked by `prompt-screen.sh` shows its reason. Run `claude doctor` as well.
10. Profiles: `install.sh` copies `~/.config/claude-accounts/{active,projects.conf}` into `~/.config/ws-profiles/`
    once; `claude-account` keeps working. For each client: `ws-profile new NAME --tenant … --subscription …` in a
    terminal (it guides the Claude, az, gh and kubeconfig logins), then `ws-profile project NAME <repo>`, and check
    with `ws-profile status` and, in that tab, an Azure MCP read that the tenant is the client's.
11. Optional: `~/.config/ws-guard/production.conf` (production subscriptions and kube contexts), `hard=1` in
    `~/.config/ws-telemetry/budgets.conf`, `bash install.sh --managed`, agent identities (`tmux-level … --agent NAME`
    after logging in under `~/.config/ws-agent/NAME`), `ws-telegram approve pin`, `ws-tools install agent-browser`,
    the Chrome DevTools MCP server (`ws-tools install chrome-devtools-mcp`, then
    `bash install.sh --mcp-opt-in chrome-devtools`), and `[interop] appendWindowsPath=false` in `/etc/wsl.conf`.

11. Hardening follow-ups: run `ws-backup --now` once a key exists (`ws-backup-cloud setup`) so the Windows-side
    mirrors are sealed; `ws-tools install gate` on every machine that pushes lock files or IaC (a push that needs
    osv-scanner or checkov is blocked without them; `ws.gate.allowNoOsv` and `ws.gate.allowNoCheckov` opt out,
    logged); `bash install.sh` puts the tmux plugins at their pinned commits (`ws-plugins verify`); add the CI job
    "Clean install (Ubuntu 24.04)" to the required checks of `main`.

12. Round 3: `bash install.sh --mcp-refresh` (registers azure and chrome-devtools through `ws-mcp-jail`; needs
    bubblewrap, `ws-mcp-jail --probe` must exit 0); then, after listing the claude.ai connectors you use in
    `~/.config/ws-mcp/allow-extra.json` (for example `[{"serverUrl": "https://…/*"}]`),
    `bash install.sh --managed --mcp-allowlist` and check `/mcp`; restart solo tabs (`tmux-solo normal`, then
    `tmux-solo this`); run `ws-audit --ai` once and `ws-audit` for the new host checks (unattended-upgrades, umask,
    listeners, clock).

13. MCP keepalive: `bash install.sh` (no flag needed: it re-registers every local MCP server through
    `ws-mcp-keepalive` by itself, the server inside unchanged), then restart Claude in every tab
    (`tmux-claude-restart --all`); with the managed allow list, `sudo bash install.sh --managed --mcp-allowlist` too,
    or the new form is "blocked by policy". Check with `/mcp` and `ws-audit` ("restarted when they exit"). Once, on
    the owner's machine: end `mempalace-mcp.exe` in Task Manager during a session and see it come back in `/mcp` and
    in `~/.local/state/ws-mcp/mempalace.log`.

Breaking behaviour changes, each described below:

- Solo mode no longer lets `az`, `gh`, `git push`, `kubectl` and the other excluded commands out of the sandbox, and
  they ask in every solo variant; `tmux-solo this --with-network-tools` brings them back (asking) for at most 4 h.
- The Azure MCP server (and chrome-devtools when opted in) runs inside `ws-mcp-jail`: it sees only its own Azure
  config, not the rest of the home; without a working bubblewrap it does not start.

- Solo mode runs inside the sandbox; the old mode is `tmux-solo this --unsandboxed` (audited).
- More permission prompts: every MemPalace write asks, also after "don't ask again" and in solo mode, and every
  command that names a `.exe` asks.
- A `claude` typed by hand starts strict: no command leaves the sandbox.
- Commits fail when gitleaks is not installed (the repository setting `ws.gate.allowNoGitleaks` opts out, logged).
- `ws-kit-update` refuses releases whose tag is not signed by a key in `allowed_signers`.

### Added

- `ws-mcp-keepalive` (ADR 0025, WS-GOV-015): every local stdio MCP server runs behind a transparent stdio proxy that
  starts it again when it exits mid-session, which Claude Code does not do for stdio servers in an interactive
  session. The request in flight gets a JSON-RPC error, the recorded `initialize` and `notifications/initialized` are
  replayed to the new process (the answer swallowed), `notifications/tools/list_changed` (and prompts/resources when
  offered) tells Claude to refresh, and what was sent meanwhile is delivered then. Exponential backoff 1 s to 30 s;
  more than 5 restarts in 300 s gives up with exit 1, errors for what waits and a `ws-notify`. A changed executable
  is restarted only when `ws-pinned local-check` vouches for it. The server's stderr goes, redacted and capped, to
  `~/.local/state/ws-mcp/<name>.log`; restarts and give-ups are `mcp_restart` and `mcp_giveup` audit events. On stdin
  EOF or a signal it ends the server's whole tree (process group and descendants; it is a child subreaper).
  Composition: keepalive outside, `ws-mcp-jail` inside; a `"keepalive"` key per stdio server in
  `files/mcp-servers.json` (true by default, `false` opts out). Tests: `tests/mcp-keepalive.sh`.
- `ws-audit` warns about a stdio MCP server registered without the keepalive and reports the restarts and give-ups
  of the last 24 h; `ws-health` fails on both; the AI-BOM has a "Restart after an exit" column.
- `ws-mcp-jail` (ADR 0024, WS-AI-011): local stdio MCP servers run in bubblewrap with a view built from nothing
  (read-only system and kit, writable only `~/.local/state/ws-mcp/<name>`, an empty HOME, no credential store, no
  `~/.claude*`, audit log, other profiles or Windows drives, tokens removed, network only with `--net`; the tab's own
  `AZURE_CONFIG_DIR` with `--azure-config`). It refuses a Windows executable (exit 126: bubblewrap cannot confine it)
  and fails closed without bubblewrap (exit 125). `files/mcp-servers.json` carries a `jail` object per server, or
  `"jail": false` with a `jailOptOut` reason (mempalace, recall); `install.sh` registers the wrapped form,
  `export.sh` unwraps it, `ws-audit` reports unjailed servers and probes bubblewrap.
- `install.sh --managed --mcp-allowlist`: a managed drop-in `55-ws-mcp-allow.json` with `allowedMcpServers`
  generated from `mcp-servers.json` (exact `serverCommand` or `serverUrl`, never `serverName`) and
  `allowManagedMcpServersOnly`; extra entries from `~/.config/ws-mcp/allow-extra.json`; `ws-audit` reports a missing
  or widenable list and registered servers it would block (WS-AI-010).
- `tmux-solo … --with-network-tools` (ADR 0022): the normal level's excluded commands for this solo tab, each one
  asking; 1 h by default, 4 h at most (`WS_SOLO_NET_HOURS`), marked 🌐 and `@csolo_net`, audited as
  `solo-network-tools`.
- Agent commit trailer (ADR 0023, WS-AI-026): a commit made from a Claude Code session carries
  `Agent-Session: <profile>/<session id>` and, under an agent identity, `Agent: <WS_AGENT>`; a forged one is
  replaced; never `Co-authored-by`; `ws.gate.agentTrailer=false` opts a repository out (logged).
- `ws-audit` host checks: updates from the security pocket and unattended-upgrades (WS-SEC-019), the home, umask and
  data folder modes (WS-SEC-020), listeners beyond loopback, sshd and the WSL networking mode (WS-SEC-021), clock
  skew against Windows (new WS-SEC-029), journald persistence and auditd (WS-SEC-023).
- `ws-audit --ai` cases from the OWASP GenAI Red Teaming Manual: grant modification of its own settings, a write to
  the MCP registrations, the unsandboxed retry and an instruction planted in a README (WS-AI-027).
- `framework_currency.py` watches the Microsoft cloud security benchmark: the end of the v2 preview or a v3 turns the
  monthly run red.
- Compliance: the Microsoft cloud security benchmark v2 (preview), OWASP Agentic AI Threats and Mitigations 1.1,
  OWASP MCP Top 10 (beta), the GenAI Red Teaming Manual 1.0, Securing Agentic Applications V2, the Well-Architected
  Reliability, Cost, Operational Excellence and Performance checklists and ISO/IEC 25010:2023 in `frameworks.md` and
  the catalogue; every edition re-checked on 2026-11-25; four new controls (WS-AI-031 MCP tool definition integrity,
  WS-SEC-029 clock synchronisation, WS-GOV-013 recovery objectives, WS-GOV-014 performance budgets); a confinement
  column in the AI-BOM's MCP table; recovery objectives per backup layer in the runbook.
- Suites `tests/gate-commit-msg.sh`, `tests/mcp-jail.sh`, `tests/audit-host.sh` and `tests/otel-collector.sh`.
- `ws-restore-lite --mirror PATH [--to DIR]` recovers a file or folder of the Windows-side mirrors: encrypted `.age`
  copies are decrypted (cloud key from Credential Manager or `--identity`), clear copies of older mirrors are copied;
  nothing in `~/.claude` is overwritten.
- `ws-plugins apply|verify|list`: TPM and every tmux plugin pinned by commit in
  `~/.config/tmux-claude/plugins.lock`; `install.sh` and `ws-update` use it instead of TPM's `install_plugins` and
  `update_plugins`; `ws-audit` fails when a plugin is off its pin or not in the lock.
- `~/.local/lib/ws-tools.lock` pins the GitHub binaries ws-tools installs (osv-scanner, tflint, k9s, hadolint,
  starship, agg, cosign) by version and sha256, and checkov by version; `ws-tools pins` lists them;
  `ws-tools install gate` installs the git gate's scanners (gitleaks, osv-scanner, checkov).
- `.github/scripts/bump-pinned.sh <name> [version]`: one command to move a pinned npm package or to finish a
  Dependabot bump (package-lock, `files/mcp-servers.lock.json`, integrity, AI-BOM, then the three checks).
- Suites `tests/gate-scanners.sh`, `tests/supply-tools.sh`, `tests/telegram-audit.sh` and `tests/audit-mcp.sh`.

- Governance documents in `docs/governance/`: the AI use policy, the AI bill of materials (models, subagents, MCP
  servers, hooks, external services), the AI incident response playbooks and the review cadence.
- Security and AI governance assessment in `docs/compliance/`: the frameworks the kit is measured against, with
  their current editions (`frameworks.md`), a catalogue of 70 controls mapped to them with file and line evidence
  (`controls.yaml`), and the coverage and gap analysis with the hardening plan (`assessment.md`).
- Continuous compliance evidence: `ws-audit --compliance [--json] [--kit DIR] [--catalogue FILE]` reads
  `docs/compliance/controls.yaml` from the kit checkout (`$WS_KIT`, by default `~/code/claude-workstation`), runs only
  allow-listed read-only checks, reports `not-run` for those it cannot run on this machine, prints the coverage per
  framework and exits 1 when an `implemented` control fails; `tests/compliance.sh` checks the catalogue in CI
  (schema, traceability to `frameworks.md`, evidence files, implemented checks, coverage tables of `assessment.md`);
  `tests/ai-bom.sh` regenerates the generated tables of `docs/governance/AI-BOM.md` and fails on drift; a monthly
  workflow (`compliance-monthly.yml`) also checks that the framework editions recorded in `frameworks.md` are current.
- Hooks: `untrusted-content.sh` labels web, MCP and network-command output as untrusted data and flags injection
  markers; `prompt-screen.sh` blocks a prompt that carries a secret (`#allow-secret` sends it anyway, audited);
  `config-change.sh` logs every configuration change during a session; `memory-gate.sh` asks on every MemPalace write,
  stamps its provenance and blocks `<private>` text; `memory-filter.sh` strips `<private>…</private>` from what the
  MemPalace and recall hooks receive; `ws-runtime-gate.sh` holds prompts and tools during an emergency stop or a
  hard spend limit ([ADR 0017](docs/adr/0017-defence-in-depth-for-agent-configuration.md)).
- `ws-stop-all`: emergency stop (marker, Telegram off, audit event, closes every Claude; `--pane`, `--session`,
  `--clear`, `--status`); Menu → Claude → Emergency stop.
- `ws-anomaly`: sessions with repeated guard blocks, denials and sandbox hits; shown in the status bar with a Windows
  alert, and sent to Telegram with a "Stop this tab" button.
- `ws-memory`: approved memory saves (`save-facts`, used by `ws-learn`), `review --older-than 90` and `log`.
- `ws-telemetry prompts [--alerts]`: approval fatigue (approvals per hour, time to answer, answers under 2 s,
  persistent and broad allow rules); Telegram alerts above a rate.
- Hard spend limit: `hard=1` in `budgets.conf` holds work in a project at 100 % of its budget until
  `ws-telemetry budgets --override <project> [hours]` (audited).
- `ws-audit --verify-log` checks the audit log's hash chain and its anchors.
- `ws-pinned`: installs and verifies the pinned npm packages (`list`, `install`, `verify [--online]`, `outdated`,
  `local-check`, `local-pin`); `files/mcp-servers.lock.json` records every MCP server's pin
  ([ADR 0018](docs/adr/0018-supply-chain-pinning-and-signed-releases.md)).
- `install.sh --mcp-opt-in NAME`, `--mcp-accept NAME` and `--mcp-refresh`.
- `install.sh --managed [--dry-run]` installs the managed policy drop-in
  `/etc/claude-code/managed-settings.d/50-ws-kit.json`, a root-owned `guard.sh` and the credential list, after
  showing the `sudo` commands and asking ([ADR 0019](docs/adr/0019-strict-base-and-level-profiles.md)).
- `tmux-level … --agent NAME`: a tab runs with the az, gh and kubectl logins under `~/.config/ws-agent/NAME`
  (`WS_AGENT`, tab option `@cagent`), and the guard refuses to switch them
  ([ADR 0020](docs/adr/0020-agent-scoped-identities.md)).
- `agent-browser` (`ws-tools install agent-browser`), pinned, behind a wrapper with a localhost-only domain allow
  list, an action policy (no eval, download or upload) and content boundaries; the `chrome-devtools` MCP server,
  pinned and opt-in.
- `~/.config/ws-guard/production.conf`: production subscriptions (ID or name) and kube contexts by list, also checked
  for mutating Azure MCP tools.
- The official `claude-security` plugin is enabled in `settings.json` (it still has to be installed by hand).
- `ws-gate bypasses` lists repositories whose local git configuration replaces the hook chain, skips gate checks or
  allows commits without gitleaks.
- `tmux-swarm new --budget USD` stops a swarm whose branches together reach the budget.
- CI: a `suites` job runs every `tests/*.sh` suite; a zizmor job checks the workflows; an SBOM job builds a CycloneDX
  SBOM; `release.yml` refuses an unsigned tag and attaches the SBOM to the release. New suites cover the hooks,
  the audit chain, anomalies, approval fatigue, the spend gate, the memory gate, solo mode, the supply chain, kit
  updates, Telegram approvals, backup encryption, the gate's secret scan and Windows interop.
- ADRs [0016](docs/adr/0016-solo-mode-inside-the-sandbox.md) to [0021](docs/adr/0021-per-tab-profiles.md).
- Per-tab profiles (`ws-profile`, [ADR 0021](docs/adr/0021-per-tab-profiles.md)): each tab can run with its own Claude
  organisation (`~/.claude-profiles/NAME`), Azure tenant and default subscription, gh and kubectl logins
  (`~/.config/ws-agent/NAME`, the agent identity of the same name) and, by default, its own conversations and no
  MemPalace. `ws-profile new NAME [--tenant] [--subscription] [--share-with] [--memory off|on|wing:W]` guides each
  login in a terminal and refuses to run inside Claude; `ws-profile tab NAME` restarts the tab with the profile and
  starts a new conversation when the conversation store differs; `use`, `project`, `list`, `status`, `show`, `setup`,
  `remove` (credentials only with the typed name). Precedence for a new tab: project pin > the tab's profile > the
  default. Menu → Claude → Profile lists the profiles; the bar and `tmux-find` show `⬢label` for a custom one.
- `~/.local/lib/ws-profile.sh`: the one function that computes a tab's environment (`CLAUDE_CONFIG_DIR`,
  `AZURE_CONFIG_DIR`, `GH_CONFIG_DIR`, `KUBECONFIG`, `AZURE_TOKEN_CREDENTIALS=AzureCliCredential` for the Azure MCP
  server, `WS_PROFILE`, `WS_MEMORY`), used by `accounts.sh` for every new shell and typed as
  `eval "$(ws-profile --export NAME)" &&` by `tmux-level`, `tmux-claude-restart`, `tmux-solo`, `tmux-swarm` and
  `ws-profile tab`.
- Profile fence: `claude-resume` starts Claude with `tmux-level --fenced`, a copy of the level settings that denies
  sandboxed reads and the Read tool on the other profiles' conversations and on every profile's Claude login.
  `claude-resume --new` starts a new conversation.
- `ws-audit` pillar «Profiles» (`ws-profile audit`): two profiles with the same tenant and subscription, an isolated
  profile that links conversations, credentials the sandbox could read, tabs running with a missing profile.
- `tests/profiles.sh`, profile cases in `tests/guard.sh` and `ws-test` (tab switch, isolation, memory off, label).

### Changed

- `install.sh` re-registers by itself a registration that runs the same server without the kit's current wrappers
  (`ws-mcp-keepalive`, `ws-mcp-jail`); other differences still need `--mcp-refresh`. `lib.sh` gains `mcp_unwrap`;
  `mcp_want`, `mcp_unwrap_merge` (export.sh) and the managed allow list know the keepalive form.
- The guard protects `~/.local/bin/ws-mcp-keepalive` and `~/.local/state/ws-mcp` (keepalive logs and jail state) as
  hard roots: an agent cannot plant a link there or erase a restart record.

- Solo mode (ADR 0022, amends 0016): every solo profile is generated by `tmux-level --settings-file
  solo|solo-net|solo-unsandboxed` from `~/.config/claude-solo/settings.json`, which now also sets
  `allowUnsandboxedCommands: false`; the normal level's excluded commands become `ask` rules in all three, and
  `solo.json` excludes nothing; `--unsandboxed` is built by the same code instead of a hand-written file; `ws-audit`
  fails on a solo profile that lets a command out without asking.
- Git gate (ADR 0023): repositories under `/tmp` or `/var/tmp` without any remote skip Conventional Commits and lint
  at commit time (said once); a push from a repository under the temp dir re-checks every pushed message; secrets,
  forbidden files, size and `Co-authored-by` apply everywhere.
- The guard also protects `~/.local/bin/ws-mcp-jail`, `~/.local/bin/ws-gate` and `~/.config/ws-mcp`.
- CI installs bubblewrap for the suites job, so the live part of `tests/mcp-jail.sh` runs where the runner allows
  unprivileged user namespaces.
- `claude-account` is a wrapper of `ws-profile` (`work` and `personal` are its built-in profiles) with the same
  commands and messages; its settings moved to `~/.config/ws-profiles/` (`migrate.sh`, idempotent, dry-run aware).
  `claude-work` and `claude-personal` are shell functions now, next to `claude-as NAME`.
- MemPalace per profile: `memory-filter.sh` hands nothing to the MemPalace hooks in a tab with `memory=off` and, with
  `memory=wing:W`, a transcript copy whose cwd files it into wing W; `memory-gate.sh` blocks every MemPalace tool with
  memory off and forces the wing with `wing:W`. The recall hook is unaffected.
- `tmux-level --agent NAME` is the credentials-only case of the profile NAME; a level change, a restart and solo mode
  keep the tab's profile.
- The Windows-side mirrors (`%UserProfile%\.claude-wsl-backup` from `ws-backup`, `.tmux-resurrect-backup` from
  `tmux-backup`) are encrypted per file with age to the light backup's keys (WS-SEC-013), stay incremental, and seal
  the clear copies left by earlier versions; without a key they stay in clear and `ws-audit` fails on it. Expiry in
  `ws-backup-lite` handles the `.age` copies.
- The git gate requires osv-scanner on a push that changes a lock file or manifest, and checkov on one that changes
  Terraform, Bicep, a Dockerfile, a Kubernetes manifest or a CI workflow (WS-SEC-004); `ws-gate bypasses` and
  `ws-audit` report the new opt-outs.
- ws-tools installs GitHub binaries at their pinned version and sha256 instead of the latest release checked
  against its own checksum file, verifies tflint's cosign signature (installing the pinned cosign first) and fails
  closed; `WS_TOOLS_ALLOW_UNVERIFIED=1` overrides, logged and audited (WS-SEC-016).
- Telegram approvals, denials, PIN checks and ▶ Run commands (redacted) are recorded in the audit hash chain as
  `telegram` events (WS-SEC-011). ▶ Run stays refused in solo tabs, now with the reason in the code.
- `ws-audit` fails on a registered MCP server (user, local or approved project scope, both accounts) that is not in
  `files/mcp-servers.json`, and reads the kit's drop-in `managed-settings.d/50-ws-kit.json` next to
  `managed-settings.json` (valid, root-owned, floor intact, guard current) (WS-AI-010, WS-AI-002).
- The Azure MCP server moves to `@azure/mcp` 4.0.0-beta.9 (supersedes Dependabot's bump): there is still no stable
  4.x, and the reason is recorded in the lock.
- CI: the "Clean install (Ubuntu 24.04)" job is no longer `continue-on-error` (WS-SEC-017).
- **Breaking: the user settings are strict.** `sandbox.excludedCommands` moved from `settings.json` to
  `~/.config/claude-levels/normal-adds.json`; the normal level is `claude-resume --settings normal.json` on top of
  every settings source, every kit launcher starts at normal, and a `claude` typed by hand runs with no exclusions
  ([ADR 0019](docs/adr/0019-strict-base-and-level-profiles.md)).
- **Breaking: solo mode runs inside the sandbox** (`autoAllowBashIfSandboxed`), expires after 4 hours (`@csolo_hours`,
  `--hours N`) and opens a worktree by default in a git repository (`--here` keeps the folder);
  `tmux-solo this --unsandboxed` is the audited exception, marked 🔓
  ([ADR 0016](docs/adr/0016-solo-mode-inside-the-sandbox.md)).
- **Breaking: more prompts.** Every MemPalace write tool and `mempalace` shell command asks, and so does any command
  that names a `.exe`; `ws-kit-update --allow-unsigned`, `ws-telegram approve` and `ws-telegram run no-pin` ask too.
- **Breaking: `ws-kit-update` installs only signed release tags.** It fetches `vX.Y.Z` tags, verifies them with
  `git verify-tag` against the installed `~/.config/ws-kit/allowed_signers` and moves with `merge --ff-only`; the
  branch tip is ignored. A refused release exits 11 and raises a Telegram alert.
- **Breaking: the git gate requires gitleaks.** A missing gitleaks blocks the commit unless the repository opts out
  with `ws.gate.allowNoGitleaks` (each such commit is logged in `~/.local/state/ws-gate/opt-outs.log`).
- The audit log is a hash chain across lines and days, with the day's head hash written to an anchor file on the
  Windows side when a session ends; it records the URL (without its query string), the search query and a redacted
  summary of MCP input inside the chain. Retention goes from 90 to 395 days.
- The guard fails closed even when the hook itself is missing or crashes (`onFailure: block`), and blocks agent
  writes to persistent configuration: always for settings, hooks, `~/.claude.json`, plugins, profiles, the guard's
  lists, git hooks, `/etc/claude-code`, the kit's keys and pins, the Telegram configuration and the audit log; for
  `CLAUDE.md`, commands, agents and skills outside a 30-minute window the owner opens
  (`~/.config/ws-guard/allow-config-writes`, each write audited).
- The guard blocks naming a credential store in a command (one list shared with the sandbox,
  `~/.local/lib/ws-credential-paths.txt`), `gh auth token`, `kubectl config view --raw`, running `ws-learn` or the
  write commands of `ws-memory`, clearing the emergency stop, overriding a hard budget and MemPalace's own write
  commands; `claude mcp add|add-json|remove` and `claude plugin install|enable|marketplace add` are denied.
- Telegram: approving a risky dialog (an MCP tool, an ask rule or excluded command, a blocked command) needs the PIN
  (`ws-telegram approve pin` asks it for every approval); "don't ask again" and other persistent allows are never
  offered as buttons; ▶ Run is offered only for read-only commands of an allow list, with the block lists as a second
  check; nothing is sent or run while the emergency stop is on.
- The Azure MCP server runs from a pinned install (`@azure/mcp` 4.0.0-beta.7, `npm ci --ignore-scripts`) instead of
  `npx -y`; `install.sh` replaces the old registration and refuses servers whose pin does not match.
- `ws-update` verifies the pinned packages (`ws-pinned verify --online`) and keeps the prerelease suffix when it
  compares versions.
- Light backups are encrypted when a recipient exists (`age-recipients` or `ws-backup-cloud`'s key) and logged as
  `UNENCRYPTED` with a loud warning otherwise; Windows-side copies whose original is gone expire after 30 days
  (`WS_BACKUP_COPY_DAYS`); the backup carries a copy of the audit anchors.
- Swarm agents start at the full level with `git push` and `gh pr create|merge` denied, and the swarm refuses to start
  without `--setting-sources` (`WS_SWARM_LEVEL=normal` is the audited exception).
- `ws-learn commands` checks each proposal, previews the full prompt and quotes the description; `ws-learn` and the
  write commands of `ws-memory` refuse to run inside Claude.
- `ws-audit` fails on gate bypasses, an unencrypted last light backup and a pinned package or local MCP executable
  that does not verify; it checks that the user settings exclude no command and that the solo profile keeps the
  sandbox, and warns about repositories whose `.claude` settings widen every level.
- `permissions.disableBypassPermissionsMode` is `disable` in the user settings, the `bare` profile and the managed
  drop-in; `enableAllProjectMcpServers` is `false`; WebFetch is allowed without a prompt only for five
  documentation and registry hosts.
- CI and CodeQL pin GitHub's actions by commit SHA, CodeQL no longer persists checkout credentials, and Dependabot
  also updates the pinned npm packages, with a 7-day cooldown.

### Fixed

- `ws-update` checked the registered command of each local MCP server, which for a jailed server was `ws-mcp-jail`
  itself; it now checks the server's own executable behind the kit's wrappers.

- The local OpenTelemetry collector decompressed a gzip body without a bound: a small request could expand into
  gigabytes; it now stops past the 16 MiB body limit with 413 (WS-SEC-012).
- `read-convert.sh` wrote its error output to a predictable `/tmp/ws-tomd.err.<pid>`; it uses `mktemp` and removes
  it on exit (WS-SEC-027).
- `ws-audit` counted any upgradable package whose line contained "security"; it counts the security pocket only.
- A test or scratch repository under the temp dir no longer fails on the owner's global hooks with `git commit -m v1`.
- `ws-restore-lite --test` ended silently (no FAIL line, no verdict) on a backup without `~/.claude/projects`.
- `ws-test` read the machine's `/tmp/claude-burn-<uid>/limits` (your real plan usage) in its Telegram alert case, so
  "alerts are not repeated" failed whenever your weekly usage was at 90 %; `ws-telegram` now honours `WS_BURN_DIR`
  like `statusline.sh`, and the test points it at its own folder.
- Stale comments in `ws-runtime-gate.sh` (ws-anomaly also counts denials and sandbox hits) and `ws-telegram` (solo
  runs inside the sandbox).

- `ws-restore-lite` could not extract an encrypted (`.age`) backup; it now also reads the cloud key from the Credential
  Manager when `--identity` is not given.
- `export.sh` deleted `files/mcp-servers.lock.json` and `files/etc/` and replaced the kit's MCP definitions with the
  machine's; it now keeps them and merges the user's servers into the kit's.
- `ws-learn` wrote a model-written description verbatim into a command's frontmatter, so a description could add
  frontmatter keys such as `allowed-tools`.

### Security

- Profiles: `~/.claude-profiles/*/.credentials.json` denied to sandboxed reads (glob, which Claude Code expands on
  Linux, plus literal paths in every tab's fence), to the Read tool and in the guard's credential list (glob lines
  expanded per call); the profiles' az, gh and kube folders live under `~/.config/ws-agent`, denied as a whole. The
  guard blocks, in a custom profile's tab, changing `CLAUDE_CONFIG_DIR`, the credential variables or
  `AZURE_TOKEN_CREDENTIALS`, `env -i`, `az login|logout`, `gh auth login|logout|switch|refresh|setup-git` and
  `claude auth login|logout|setup-token`; in every tab, `WS_PROFILE`/`WS_MEMORY` and the `ws-profile` and
  `claude-account` commands that switch or create profiles; `~/.config/ws-profiles`, the profiles' Claude settings
  and `~/.local/lib/ws-profile.sh` are hard-protected (and Edit-denied in `settings.json` and the managed policy).
- Security model, residual risks and the agentic (ASI01–ASI10) cross-reference updated in
  [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) and [SECURITY.md](SECURITY.md).

## [3.0.1] - 2026-11-25

### Fixed

- The SAST job (bandit) failed on the SQL view of `ws-telemetry sql`; the two queries are built only from the
  kit's own data path and quoted column names and values, and are marked as reviewed.
- `ws-test` failed five tests on CI runners, which set `XDG_CONFIG_HOME`: its wrapper now unsets the XDG folders so
  every script uses the isolated home.

## [3.0.0] - 2026-11-24

This is a breaking release. Commands, options, variables, folders and stored values change name; see
[Upgrading from 2.x names](docs/USAGE.md#18-upgrading-from-2x-names).

### Added

- The tmux save that is in force gets its date refreshed on every check, so `tmux-recover` shows when each save was
  last confirmed and `ws-health` fails when no save was confirmed in the last 5 minutes.
- Personal folder roots for `tmux-open` in `~/.config/ws-local/roots.txt`, which the installer never replaces.
- **Favorite tabs** (`tmux-favorites`): `Ctrl+b *` adds or removes the current tab's folder, which shows a ★ in the
  status bar, and `Ctrl+b F` lists the favorites, open or not (the favorites view of the finder, below); Enter goes to
  the tab or opens the folder with Claude in its group, and `Ctrl+X` removes it from the list. The mark belongs to the
  folder, so it survives closing the tab and restarting tmux; it is kept in `~/.config/tmux-claude/favorites`.
  `tmux-open --dir <folder>` opens a folder without asking.
- **Unified finder** (`tmux-find`): one list for open tabs, the tabs active now, favorite folders and recent Claude
  conversations, as four views (`Tab` and `Shift+Tab` cycle, `Alt+1`…`Alt+4` jump). `Ctrl+b f` and `Alt+s` open the
  view all, `Ctrl+b a` active, `Ctrl+b F` favorites and `Ctrl+b j` recent.
  - **Conversation pane**: the right side is the same in every view. An open tab shows its live screen; a favorite
    folder or a conversation without a tab shows your latest requests and Claude's last answer, redacted.
  - **Quick reply** (`Ctrl+S`): one line typed in the finder is sent to that tab's Claude. The input box is cleared
    first unless Claude is working; nothing is typed into a permission dialog or into a tab without Claude.
  - **Approve and reject** (`Alt+Y`, `Alt+N`): answer the permission dialog of a tab from the list, only while the
    tab is in the "approve" state.
  - **Open here** (`Ctrl+O`): use the tab inside the finder window through a temporary linked session; your own view
    does not move and `Ctrl+b d` comes back to the list.
  - `tmux-recent --open <file.jsonl>` resumes a conversation in a new tab of its group and `tmux-recent --latest
    <folder>` prints a folder's latest conversation.
- **Language selector** (`ws-lang en|es`) and **language packs** (`~/.local/lib/ws-lang/en.conf`, `es.conf`, and
  `rules.es.conf` for the routing rules). `en` recognizes English in prompts and answers; `es` recognizes English and
  Spanish and asks Claude to write reports and handoffs in Spanish. The setting is `~/.config/tmux-claude/lang`
  (`WS_LANG` overrides it) and the Workstation menu switches it. `cr --test` has one task set per language
  ([ADR 0015](docs/adr/0015-english-names-and-language-selector.md)).
- **Installer migration** from the names used before 3.0 (`migrate.sh`, `renames.tsv`): your data and settings are
  moved to the new names and never overwritten, old commands and hooks are replaced by wrappers that call the new
  names, and old kit files are set aside in `~/.local/share/ws-kit/pre-english.<date>/`. `install.sh --dry-run`
  previews it; a migrated installation is set to `ws-lang es`.
- `install.sh --remove-shims` deletes the wrappers left under the old command names.
- **`ws-verify` checks the running tmux server**, not only isolated ones (`ws-verify --live` runs these checks
  alone): `~/.local/bin` is in the server's `PATH`, the save was confirmed in the last 5 minutes, the save has the
  open tabs, no `find-peek-*` session was left without a client, every script the status bar, the key bindings and
  the hooks call is installed, and no stale tmux sockets remain. Each failure prints its remedy.
- `ws-verify --clean-sockets` deletes the tmux socket files no server answers on (test servers, old popups); it
  never touches `default` or a socket with a live server.
- `install.sh --prune-backups` moves the `<file>.bak.<date>` copies that earlier versions left next to each kit file
  into `~/.local/share/ws-kit/backup.legacy/` (`--dry-run` shows what it would move).
- `ws-personal` lists `~/.config/ws-local/roots.txt` (your own folder roots) by name in its default `include.txt`.
- Menu "Usage and reports" has a submenu "Reports ›" (`menu-usage-reports.tmux`).

### Changed

- **Breaking: every name is now English.** The interface (menus, status labels, messages, notifications), the code
  comments and the documentation were translated, and commands, subcommands, options, environment variables, tmux
  options, configuration and state folders, stored values (protection levels `full` and `bare`, account `work`, themes,
  scene names, tab phases) and telemetry field names were renamed. The old and new names are listed in
  [Upgrading from 2.x names](docs/USAGE.md#18-upgrading-from-2x-names). Entries below this one keep the names that
  existed when they were written.
- CSV exports and JSON output (`ws-telemetry export`, `ws-telemetry estimate --csv` and `--json`, `ws-report --json`)
  use English column and key names. Telemetry recorded before the upgrade is still read: old records are translated
  when loaded and the files are not rewritten.
- Regular expressions and word lists that match Spanish prompts and answers moved out of the scripts into the Spanish
  language pack; they are active only with `ws-lang es`.
- After upgrading, restart the tmux server (`tmux kill-server`, then open the session again).
- **Installer backups moved out of your folders.** `install.sh` (and `ws-personal restore`) copies each file it
  replaces to `~/.local/share/ws-kit/backup.<date>/<same path>` instead of leaving `<file>.bak.<date>` next to it,
  prints that folder once, and keeps the newest 10 backup folders. The Windows notification handler keeps its
  side-by-side backup, because it lives outside WSL.
- `ws-telemetry sql`: the `traces` view exposes only the English column names and values; the Spanish columns of
  days recorded before the upgrade are folded into them.
- CI job names are English: `SAST and secrets (bandit, gitleaks)`, `Kit tests`, `Clean install (Ubuntu 24.04)`.
  Update branch-protection rules that list required checks.
- The documentation follows a shared structure: the same files, sections and order as the owner's other repositories.
  New `docs/DIAGRAMS.md` collects every diagram; `docs/adr/` gains an index, a template and the records 0008 to 0010,
  written retroactively.

- **The four pickers became views of the finder.** `tmux-active`, `tmux-favorites` and `tmux-recent` keep their
  non-interactive modes (`--list`, `--toggle`, `--mark`, `--bar`, `--remove`, `--show`) and, run without a mode, open
  `tmux-find` on their view. `Ctrl+b j` is bound again (recent conversations). The popups of the finder are 92 % wide.
- **Menu entries merged**, so each thing is in one place:
  - Main menu, "Go to": "Active now", "Favorites ★" and "Find a tab by name" are one entry, "Find: tabs, active,
    favorites, recent" (`f`).
  - Solo mode: "Solo Claude in a new tab" and "Solo Claude in a new worktree" moved from "Claude in this tab" to its
    "Protection" submenu (`t`, `w`), next to solo mode for this tab.
  - "Claude in this tab" has a section "Tasks and subagents" with `/tasks` (`T`), the Claude task list (`d`), live
    subagents (`A`) and stop background subagents (`K`); the last three left "More Claude commands" and "Views".
  - "Tabs and session": "Restore saved session" and "Recover tabs from an earlier save" are one entry, "Restore tabs
    from a save…" (`R`), which lists the saves with the latest first (`tmux-recover`).
  - "Tabs and session": "Bring recent conversations into tmux" is now "Bring many conversations at once…" (the
    finder's recent view opens one), and "Groups and tabs" left the menu: the finder lists them, and `Ctrl+b S`
    still opens the tree of groups.
  - "Usage and reports": the full report, the quick report and the report for last week are behind one entry,
    "Reports ›" (`i`).
  - The right-click menu of a tab no longer has "Live subagents", which is not about the clicked tab (`Ctrl+b A`
    and the Claude menu keep it).

### Deprecated

- The wrappers under the old command and hook names (`tmux-nivel`, `ws-telemetria`, `ws-trazas.sh` and the rest of
  the table in `docs/USAGE.md`) and the `claude-trabajo` shell alias. They are removed in the next major version.
- The compatibility readers for old names: `tmux-level completo|puro`, the Spanish scene names, `ws-cache --tope`,
  `WS_OTEL_CONTENIDO`, `WS_OTEL_PUERTO`, `WS_OTEL_RETENCION_DIAS`, the Spanish keys in `appearance`, `settings`,
  `settings.conf`, `cloud.conf` and the Telegram settings, the `age-respaldo` credential, the OneDrive folder
  `Respaldos\estacion-wsl` and the personal repository `~/code/estacion-personal`. They are removed in the next major
  version.

### Removed

- `docs/README.es.md`.
- `tmux-pick`: the finder replaces it. The installer leaves a wrapper under the old name that calls `tmux-find`.

### Fixed

- `ws-check` reported a registered MCP server that failed to connect as `MISSING`; it now says "registered, not
  connected".
- Restarting Claude from the menus (protection level, solo mode, account switch, restart in all tabs) now clears the
  input box first and falls back to `Ctrl+C` twice when Claude does not exit.
- `tmux-level` no longer fails when the tmux server's `PATH` lacks `~/.local/bin`, or when error output was captured
  into the command it types.
- The favorites test in `ws-test` no longer depends on the owner's own favorites.
- The tmux session was saved only when the tabs changed: the per-minute save of continuum was not running (it
  hooks into `status-right`, which the kit rewrites, and stays off while another tmux server exists, such as the
  one of the popups). `tmux-background` now saves once a minute by itself.
- `tmux-open` failed with "invalid session" for a folder outside every root (the group name came out empty); such
  folders now open in the group `other`.
- After a tmux restart the tabs were not restored when the last save was more than 24 hours old, which is the normal
  case when the tabs did not change (identical saves are discarded). The automatic restore now depends on the save
  having been marked at this startup, not on its age.
- A tmux server started without `~/.local/bin` in `PATH` (from Windows Terminal, without a login shell) made scripts
  that call each other by name fail (`ws-redact: command not found`); `.tmux.conf` now adds it to the server.
- Changing the protection level, solo mode or the account of a tab where Claude never received a message ended
  with "No conversation found to continue" and left the tab marked while no Claude ran. `tmux-level`, `tmux-solo`
  and `claude-account` now start Claude through `claude-resume`, which continues the folder's conversation when
  there is one and starts a new one otherwise, with the same flags.
- The tmux message log (`tmux show-messages`) filled with `invalid option: @cdet`, `@clast`, `@csub`, `@cts`,
  `@cmain`, `@cmainc`, `@cpane`, `@cphase`: the state hook and `ws-audit` read unset user options without `-q`.
- Test servers and popups left dead socket files in `/tmp/tmux-<uid>/`: `ws-verify` and `tmux-popup-run` remove
  their own socket when their server ends (`ws-test` keeps its sockets in its temporary folder).
- `ws-health` counted the tabs of linked sessions (monitor 2, the finder's "open here") twice when it compared the
  save with the open tabs.
- `ws-telemetry estimate --by` accepts the values from before the rename (`rama`, `proyecto`) and rejects an
  unknown one instead of grouping by project.
- The sandbox recreated the pre-3.0 folders it was told to deny; `denyRead` lists only the current paths, and the
  migration removes an empty leftover instead of reporting a conflict.

### Security

- The `deny` rules cover the copilot credentials and the OpenTelemetry store under both their new and their old
  paths (`~/.config/anthropic-copiloto`, `~/.local/share/ws-telemetria/otel`), so Claude's own tools stay blocked
  during the migration. The sandbox `denyRead` list names only the new paths: a sandbox mount of the old ones
  would recreate the folders the migration has just moved.

## [2.7.0] - 2026-11-23

First release of the public repository. The history before it lives in the private archive.

### Added

- Screensaver: seven more scenes built on the shading engine: `boreal` (aurora over mountains, reflected in a lake),
  `nubes` (flight over a sea of clouds), `agujero` (black hole with its gas disc), `estanque` (raindrops under the
  moon), `fuego`, `tunel` and `fractal`.
- Screensaver: **`galeria`** scene, which shows your images and animated GIFs converted to characters with `chafa` (true
  color). Put the files in `~/.config/tmux-claude/galeria`; if there are images and `chafa` is installed, it also joins
  the random rotation. `ws-tools` now offers to install `chafa` and `numpy`.
- **Shading engine for the screensaver** (`tmux-arte`, needs `python3-numpy`): it computes each scene as a color image
  at a higher resolution than the terminal and converts it to characters; the light picks the character (with dithering)
  and edges are traced with `| / - \`. Five scenes: `oceano` (sunset with the sun's glitter on the waves), `planeta`
  (ringed gas giant), `dona`, `lava` and `vuelo` (over mountains and lakes). Without numpy the other thirteen keep
  working and these stay out of the random rotation.
- **Animated ASCII art screensaver** (`tmux-arte`): thirteen original scenes that adapt to the terminal size and use
  true color: `cumbres` (mountain range, moon, lake with reflection, shooting stars), `aurora` (northern lights over a
  snowy forest), `nevada` (cabin with lit windows, smoke and snow), `velero` (a sailboat under the moon), `peces`
  (seabed with fish, jellyfish and seaweed), `fogata`, `cerezo` (in bloom, with petals in the wind), `lluvia` (city at
  night with lightning), `tuberias`, `batalla` (two fleets in space), `galaxia`, `nebulosa` and `hiperespacio`.
  «Aleatoria» ("Random") now picks among these; the pixel art ones remain available by name in Menú → Apariencia →
  «Elegir escena» ("Choose scene").
- **Exit and re-enter Claude in every tab**: `tmux-claude-restart --todas` (Menú → Estación → «Reiniciar Claude en todas
  las pestañas libres», "Restart Claude in all idle tabs"). Each tab resumes its conversation and picks up the new
  configuration. It does not touch tabs that are working or have a dialog open, respects each tab's protection level and
  leaves solo-mode tabs as they are; `--lista` shows what it would do and `--tambien-ocupadas` includes the busy ones.
- `ws-hooks`: how long Claude Code hooks take. With no arguments it summarizes, per event, what Claude measured (via
  `ws-otel`); `ws-hooks tiempo SessionStart` runs each hook separately to see which one is slow.
- **Claude account per project**: `claude-cuenta proyecto trabajo|personal [folder]` (or Menú → Claude → «Este proyecto
  siempre con la cuenta de esta pestaña», "This project always with this tab's account") pins the account for a repo and
  its worktrees. Every new tab opened there uses that account, regardless of the default account; `claude-cuenta
  proyectos` lists them and `proyecto quitar` releases it. The tab records which account it started with.
- **Local OpenTelemetry collector** (`ws-otel`, ADR-014): receives on `127.0.0.1` the metrics, events and traces Claude
  Code emits and stores them in `~/.local/share/ws-telemetria/otel/` (0600). Everything Claude sends is stored,
  including the text of prompts, responses and tools, with secrets masked; `WS_OTEL_CONTENIDO=0` leaves it without
  content. Nothing leaves the machine. The tmux watcher keeps it running. Commands: `ws-otel estado`, `resumen`,
  `iniciar`, `detener`.
- Dashboard and report: **API, permissions and active time** section with what arrives over OpenTelemetry: API calls
  with typical duration, p95 and first token; errors by code and exhausted retries; cost by call origin; who decides
  each permission and which tools get rejected; your active time and Claude's; lines, commits and PRs; how long hooks
  take; compactions; subagents; MCP connections and skills.
- Dashboard and report: **ratios for estimating** (30 days): your words and Claude's per turn, tokens per word, model
  calls and tools per turn, output speed, cost per turn, per thousand words, per million tokens and per active hour, and
  CPU, disk and RAM per token and per turn. Each ratio states how much data it was computed from.
- **👉 te toca** ("your turn") status: when Claude ends its turn leaving you a question or something to do (run a
  command, decide, confirm, give it a piece of data), the tab no longer stays at «✔ listo» ("done"): it is marked in
  red, the bar counts it under ⚠, it comes first in Activas and in the finder, and you get a single reminder. Previously
  only permission dialogs and formal questions were marked. It is decided from the last message, without storing it;
  `WS_TETOCA=0` turns it off.
- `ws-informe` uses everything that is already recorded: **what to improve and what to create** (ideas with their
  evidence, by fixed rules and without AI), last 7 days versus the previous 7, weekly trend, **tokens and words**
  (input, cache, output, reasoning; your words and Claude's), **machine resources** (CPU, peak RAM, disk operations and
  MB read/written per day and per project), **basis for estimating** (active hours, turns, tokens, words, lines, CPU and
  cost per project, with cost per hour and per 100 lines), operations (tools with errors, median and p95; terminal by
  type; MCP; skills; errors) and **what Claude has learned about you** (memories by type and new ones, your own
  commands, skills and agents). The HTML adds charts for cost, turns, p90, RAM, CPU and disk.
- Usage dashboard: **Trends** section with the full turn history (not just 30 days): last 7 days versus the previous 7
  (cost, turns, sessions, cost per turn, cache, median and p90 duration, subagent share), cost per week and project (12
  weeks), projects that changed the most, models per week (% of cost, by family), hour map, turn duration per week,
  turns and sessions per week, cache and reasoning per day and output per turn. SVG charts with no libraries.

### Changed

- **The kit no longer names any company.** The Claude work account is called `trabajo` (`claude-cuenta usar
  trabajo|personal`, alias `claude-trabajo`); anything saved under the previous name keeps working. The standards the
  kit installs are generic (`~/.claude/estandares.md`); your organization's go in your personal configuration. The cloud
  backup finds the organization's OneDrive by its shape («OneDrive - …»), with no fixed name. `ws-auditoria` checks that
  telemetry only goes to the local collector.
- **Faster session startup**: the MemPalace health check (5.5 s measured) and the recall startup (1.3 s) no longer make
  every session wait. They run through `ws-cache`: the session gets the last result instantly and the full check runs
  behind it. If the last result is more than 30 minutes old, it runs and waits as before, so the «búsqueda caída»
  ("search down") warning is never older than that. The `mempalace-ops` and `recall` scripts do not change. `ws-cache`
  gains `--max` (maximum age of what is stored) and `--tope` (limit for each run).
- `ws-informe`: fixed navigation by section, the detail grouped (Claude, week, projects and models, estimation,
  operation, machine, memory) in two columns, and bars per project, model, agent, tool, command type, errors and routing
  instead of text lists. The headings Claude writes no longer split the report into loose sections.
- «Trabajos recientes» ("Recent jobs") leaves the main menu and `Ctrl+b j` (the `tmux-recientes` command is still
  installed).
- `ws-informe`: the HTML is no longer a flat dump. Key figures in cards with the change versus the previous week, «qué
  mejorar y qué crear» ("what to improve and what to create") as cards by type, visible hour map, charts in a grid,
  tables with aligned numbers and Claude's text with headings, lists and bold.
- Repo aligned with the other public repos (such as `recall`): `LICENSE` Apache-2.0, `NOTICE`, `CITATION.cff`,
  `CODE_OF_CONDUCT`, `CONTRIBUTING`, `GOVERNANCE`, `SECURITY`, `SUPPORT`, `CODEOWNERS`, issue and PR templates,
  `.editorconfig`, `.gitattributes` and CodeQL analysis. New `README.md` in English with badges, table of contents and
  four Mermaid diagrams (context, per-tab states, gates, telemetry); the Spanish README lives in `docs/README.es.md`.
- Menus without duplicates: each action lives in a single place. `/permissions` and `/sandbox` stay only in Claude →
  Protección (no longer in «Más comandos», "More commands"); «Reiniciar» ("Restart") moves to Protección, next to the
  other restarts; Anterior, Siguiente, Última, Mover and Recargar configuración (Previous, Next, Last, Move and Reload
  configuration) leave Pestañas y sesión (they remain on Alt+arrows, Alt+0, right click and Ctrl+b r); «Salir» ("Exit")
  leaves the main menu (Ctrl+b d). From 146 to 137 options.
- Generic example tickets (`ABC-123`) in the tests, instead of a client's prefix.

### Fixed

- Menus that flickered now and then: while a menu is open the status bar stops refreshing (it was its refresh, every 15
  s, that redrew over the menu) and goes back to its rhythm when the menu closes. If it were ever left paused, switching
  tabs restores it.
- «Elegir escena de una lista» ("Choose scene from a list", Menú → Apariencia) did not save the choice: the screensaver
  kept showing the previous scene. It is now saved; also from the terminal with `tmux-saver --fijar <scene>`
  (`aleatoria` to have it change every time).
- `ws-test`: the two tests for «Reiniciar Claude en todas las pestañas» failed because of the test itself (the simulated
  Claude looked like a terminal without Claude). `ws-hooks` names each hook by its script, not by `pwsh.exe`.
- The screensaver had stopped appearing: it was cancelled if any tab was in «👉 te toca», which, since that status
  exists, is almost always. Now only an open permission dialog holds it back.
- Dashboard: the OpenTelemetry section now reads what the real Claude Code sends: events arrive without the
  `claude_code.` prefix, several numbers arrive as text and the first token comes inside each call. It adds the time
  spent waiting for your approval as measured by the traces.
- Menus, after reviewing the 137 options one by one: «Abrir carpeta con Opus» ("Open folder with Opus") did nothing (the
  function it calls did not exist); «Guardar esta pestaña como plantilla» ("Save this tab as a template") saved an empty
  template if the name had spaces and gave no warning; the tab log (`Ctrl+b H`) failed silently if `~/logs` did not
  exist; the help advertised retired shortcuts; «Ir a la siguiente que te espera» ("Go to the next one waiting for you")
  now switches group and tab explicitly and its label says what it does; automatic routing warns that it applies to all
  tabs. `ws-test` adds a menu consistency check.
- Active hours: a turn left open no longer counts as days of work. Each turn contributes at most one hour, and a Claude
  response that arrives more than 30 minutes after the last activity goes into a separate turn. Previously 28 turns
  added up to 562 hours and a project with 63 turns showed 292.
- `ws-informe`: the MemPalace diary is now split by day and respects the period (the log only carries the time; the day
  is reconstructed approximately). MemPalace and recall appear in tables, not as dictionaries.
- «Ir directo a la que te espera» ("Go straight to the one waiting for you") now jumps to the next tab waiting for you
  (it used to pick the first one, which was often the one already in front of you, and did not switch group).
- `ws-informe --ia`: Claude's findings no longer come out as a dump of the prompt and the JSON. Model routing blocked
  the query with no screen to ask on, and the report pasted that block as if it were the answer. Now the kit's `claude
  -p` calls (report, learn, handoff, quick question and swarm) run outside the tab's hooks, and a block is reported as a
  failure.
- Menus and floating windows no longer flicker while Claude works in the tab: the status is only written to tmux when it
  changes (previously every tool event rewrote eight options and each one redrew the bar).
- Traces: **commits per session** are now recorded. Previously they were almost always empty (git takes more than 1 s on
  `/mnt/c` and many sessions close without their start event). Now the start waits 3 s for git, the close uses the time
  of the conversation's first message when there is no starting commit, and each command records the `git commit`s it
  ran; the estimate takes the larger of the two counts.
- Telemetry: **only your messages open a turn**. Previously local command output, system inputs, background task notices
  and compaction summaries counted as your turns (the count came out almost double and «palabras tuyas» ("your words")
  more than four times too high). That work now goes into **automatic turns**: it adds cost and tokens, is reported
  separately and does not count as your turn; two consecutive messages of yours with no response are a single turn.
  Total cost does not change. The history is recalculated on its own at the next `ws-telemetria build`.
- Usage dashboard: embedded data escapes `</`, so a branch or file name containing `</script>` no longer injects code
  into the page.
- `ws-informe`: the «prompts que se repiten» ("recurring prompts") no longer count the automatic continued-session
  summary or the interruption notice.
- Usage dashboard: «Hoy» ("Today") and the per-day bars group by **local** date (previously UTC: after 18:00 today's
  activity fell under "tomorrow").
- `ws-verify`: the visibility check accepts the public kit when `git config ws.kit.publico` is `true` (and warns if the
  flag and GitHub disagree); without the flag it still expects a private repo.

### Removed

- Screensaver: the earlier scenes are retired: the pixel art ones (`invasion`, `criaturas`, `coloso`, `synthwave`,
  `ciudad`, `fuegos`, `acuario`, `serpiente`), the epic ones (`fortaleza`, `expedicion`, `gigantes`, script
  `tmux-escenas`), `arrecife` (script `tmux-arrecife`) and the shortcuts to `cmatrix` and `cbonsai`. All scenes are now
  drawn by `tmux-arte`. If you had a retired scene saved, the screensaver falls back to random. The installer does not
  delete files: `tmux-escenas` and `tmux-arrecife` stay in `~/.local/bin` until you delete them.

### Security

- **Telegram: «▶ Ejecutar» now asks for your PIN** (ADR-013, phase 2). The button no longer runs anything: the bot asks
  you to reply with the PIN (5 minutes, the reply is deleted from the chat) and only then runs the command. Three wrong
  PINs in an hour cancel the pending commands and alert you. It is on by default and uses the same PIN as text replies
  (`ws-telegram texto pin`); `ws-telegram ejecutar sin-pin` goes back to the direct button.
- **`install.sh` turns on the git gate**: it points git's global hooks path at the kit hooks when none is configured, so
  a fresh install has the secret scan, the message check and the push gate from the first commit. It does not replace a
  hooks path you already use; `--no-git-hooks` skips it.
- **Full (`completo`) level: sandboxed commands only read the tab's project.** The profile is now built per project: it
  denies reads of the folders where your other repositories and documents live (the roots in `roots.txt` and the Windows
  `Documents`, `Desktop`, `Downloads` and OneDrive folders) and re-allows the project and its worktrees. A prompt
  injection in one repository can no longer read another client's code. If Claude needs to look at another repository,
  use the normal level; `WS_COMPLETO_LECTURA=0` turns it off.
- **MCP tools that send, delete, change or can read secrets always ask**, whatever was allowed before: Azure tools that
  mutate or reach Key Vault, App Configuration, storage and databases; every Microsoft 365 tool that sends, replies,
  deletes, moves or edits; and MemPalace deletions. MCP tools do not run inside the sandbox, so permission rules are the
  only control there. Windows shells (`pwsh.exe`, `powershell.exe`, `cmd.exe`, `wsl.exe`) also always ask.
- **Guard hook:** blocks PowerShell with an encoded command or a download-and-run pattern, and any write to `.git/hooks`
  or `.git/config` (Claude Code already makes them read-only for sandboxed commands; the guard also covers the file
  tools).
- **Sandbox blocks are now visible** (`ws-sandbox-aviso.sh`): when the sandbox stops a network connection, a read of a
  credential path or a write outside the project, the tab shows a notice and the event is recorded (type, target,
  program and project; never the full command). `ws-sandbox-aviso.sh --resumen` lists them. Claude Code has no
  documented sandbox-violation event, so detection is based on the command result and is approximate.
- **The sandbox now also hides the Windows-side credentials.** It already blocked reads of `~/.ssh`, `~/.aws`,
  `~/.azure`, `~/.kube` and the like in the Linux home, but the same folders in the Windows profile are visible from WSL
  under `/mnt/c/Users/<user>` and were readable by sandboxed commands (git credentials, kubeconfig, SSH keys, the GitHub
  CLI token, browser profiles). They are now in `sandbox.filesystem.denyRead` and in the `Read(...)` deny rules,
  together with `~/.gnupg`, `~/.netrc`, `~/.npmrc`, `~/.pypirc`, `~/.git-credentials`, `~/.terraform.d`, the Telegram
  configuration, the shell history and the local OpenTelemetry store (which holds prompt text).
- «Completo» ("Full") now really keeps every command inside the sandbox. It used to pass an empty list of excluded
  commands, but Claude Code merges the lists from all sources, so `az`, `gh`, `git push`, `kubectl` and the rest still
  left the sandbox just as in «normal». It now starts without loading user settings (`--setting-sources project,local`)
  and with a profile that carries everything except that list.
- **Protection floor (ADR-013, phase 1)**, which no level turns off:
  - `guard.sh` rewritten: fails closed if it cannot read the action; detects force push in its variants (`-fu`,
    `+refspec`), push to `main` with `refs/heads/…`, `git -C` or while on that branch, `--no-verify`, changes to
    `core.hooksPath` and `ws.gate.*`, `sh <(curl …)`, `ws-secret get` and `az`, `kubectl` and `helm` mutations against
    production named in the command; it no longer blocks text inside quotes. Tests in `tests/guard.sh` (44 cases),
    within `tests/run.sh` and CI.
  - New `deny` rules: SSH keys, Azure and GnuPG profile, `ws-secret get`, Azure connection strings and keys, and
    bypassing the git gate. Wildcard `allow` rules are out (`az * show*`, `az * list*`): enumerated reads remain.
  - «Puro» ("Pure") no longer keeps the kit's `allow`/`ask` permissions but does keep the floor (`deny` and `guard.sh`):
    previously it ended up more open than Claude without the kit.
  - Telegram: does not offer or run commands in tabs without a sandbox (solo or pure mode); second blocklist
    (credentials, `kubectl -n … delete`, `git -C … push`, uploading data with curl, local scripts, deleting on GitHub);
    output also goes through `ws-redactar`.
  - The lint-on-edit hook no longer runs the repository's `eslint` or `prettier` (they run outside the sandbox); they
    remain in the pre-commit.
  - tmux bar: the tab's path is escaped in the branch command (a folder with `$(…)` in its name no longer executes
    anything).
- ADR-013 (accepted): minimum protection floor that no mode turns off, following the adversarial review of the completo,
  normal, puro and solo levels.

## [2.6.0] - 2026-11-20

### Added

- `ws-traspaso` (Menú → Claude → E): package for another Claude to continue a tab's work: Claude's summary (goal,
  status, decisions, pending items, files, how to continue, risks) built from the redacted conversation, plus branch,
  changes, commits, diff against the base, task list and touched files; with `--conversacion`, the transcript for
  `claude --resume`. It is left in %UserProfile%\ws-telemetria\traspasos and on the clipboard.
- `ws-aprender hechos` (Menú → Consumo → a): Claude reviews MemPalace (read-only) and proposes stable facts about you;
  only the ones you choose are saved to the graph.
- `ws-aprender comandos` (Menú → Consumo → k): from the requests you repeat, Claude proposes your own «/» commands; only
  the ones you choose are created in ~/.claude/commands (it never overwrites).

## [2.5.0] - 2026-11-20

### Added

- `ws-informe` (Menú → Consumo → i/j): report on the last 30 days in HTML and Markdown. Usage and work pattern (hour and
  day map, turn duration, turns per session, your wait), projects, models and routing, **agents** (which, how much, in
  which projects, with which model, how long they take), tools and MCP, **recurring prompts** (candidates for a command
  or skill) and «/» commands, **MemPalace** (diary saved/failed, mined, Hub restarts and errors, size) and **recall**
  (decisions, threshold, latency).
- `--ia`: Claude reads only the aggregated metrics and writes findings, suggestions and the 5 highest-value actions;
  `--ia-memoria`: it also queries MemPalace through its MCP (duplicate wings, graph) and recommends cleanup.

## [2.4.0] - 2026-11-20

### Added

- Claude protection in three levels per tab (`tmux-nivel`, Menú → Claude → Protección, ADR-012): **completo** (sandbox
  with no escape hatches + the kit's rules), **normal** (your configuration) and **puro** (no sandbox and none of the
  kit's ask/deny/guard; only what comes from your organization and the repo). The bar shows 🔒/🔓.

## [2.3.0] - 2026-11-20

### Added

- **Activas** ("Active") window (`Ctrl+b a`): what is waiting for you, what is working and what finished recently,
  across all groups; Enter goes to the tab; it refreshes on its own (`tmux-activas`).
- Compute monitor on the second line of the bar (`Ctrl+b v`): CPU, RAM and network with sparklines, C: disk, $/h and
  Claudes working/waiting/done (`tmux-hud`).
- Screensaver scene picker as a list, with the current one marked and an immediate preview (`tmux-escena`).

### Changed

- Menus reorganized with sections and titles: Ir a · Esta pestaña · Herramientas · Ayuda (Go to · This tab · Tools ·
  Help). «Navegar» and «Sesión» merge into «Pestañas y sesión» ("Tabs and session"); «Vistas y utilidades» ("Views and
  utilities") and «Consumo e informes» ("Usage and reports") are new submenus; floating windows have a title. Menus and
  floating windows with rounded borders and colors (tmux ≥ 3.3/3.4).
- This tab's model: the menu marks the current one (✓) and also opens Claude's picker.

### Fixed

- Changing the model from the menu no longer interrupts Claude if it is working.

### Removed

- `menu-nav.tmux` and `menu-demos.tmux` (their content moved to «Pestañas y sesión» and «Vistas»).

## [2.2.0] - 2026-11-19

### Added

- Screensaver: «arrecife» scene (Arrecife de Coralia, "Coralia Reef"), a showy, original aquarium. Gradient water with
  moving light rays, waves, seaweed with swaying leaves, corals, silver shoals, 12 species of tropical fish drawn with
  half cells and wagging their tails (clownfish, surgeonfish, angelfish, mandarinfish, neon, parrotfish, betta, lemon,
  butterflyfish, barracuda, lionfish, Napoleon wrasse), manta ray, pulsing jellyfish, turtle, crab, starfish, chest with
  bubbles and sparkles in the sand. True color (24-bit) if the terminal supports it; otherwise 256 colors
  (`tmux-arrecife`; `WS_ARRECIFE_COLOR=24|256` forces it). It only redraws what changes.

## [2.1.0] - 2026-11-19

### Added

- Detailed Claude status with its elapsed time in the bar, the dashboard, the summary, the menus and Telegram: 🧠
  pensando 42s · 🔧 Bash 2m · ✋ aprobar Bash 5m · ❓ te pregunta · 📦 compactando · 🐝 3 agentes · ✔ listo hace 12m · ⏳ sin
  avance 11m · ⛔ interrumpido · ✖ error API (`tmux-estado`; thinking, tool running, approve, asking you, compacting,
  agents, done, no progress, interrupted, API error).
- Dashboard (`Ctrl+b D`): columns ESTADO, QUÉ HACE (Bash: npm test) and TURNO (status, what it is doing, turn).
- PreCompact hook → `tmux-state.sh compact`.

### Changed

- `tmux-state.sh`: phase, start and detail per tab (@cfase, @cdesde, @cdet, @cturno); @cmain does not change (the
  watcher and the alerts work as before).

## [2.0.0] - 2026-11-19

Major version because of the size of the change (1.25 → 1.32.2): the workstation goes from "tmux with Claude" to an
environment with telemetry, model routing, remote control and parallel work. It does not break compatibility:
`ws-actualizar` upgrades from any 1.x.

### Added

- Personal configuration versioned in a private repo: `ws-personal` (init, daily sync, restore) — ADR-011.
- Summary of 1.25–1.32: traces of everything Claude does, estimation per ticket, weekly report and budgets; command
  palette, adjacent pane → Claude, notify me when done, extract from the screen, quick question, labels, focus mode,
  logs with alarm, second monitor and mirror; CI/PR/ticket in the bar, tab templates, pane recording, searchable history
  and a swarm of Claudes; personal bar segments; tab groups and import of Windows conversations; encrypted backup to
  OneDrive; Telegram with buttons, commands, PIN-protected replies and alerts.

### Changed

- `tmux-fondo` syncs your personal configuration once a day.

## [1.32.2] - 2026-11-19

### Fixed

- Routing: when accepting the model change, `/model` was typed on top of the prompt Claude Code leaves in the input box
  and "<text>/model …" was sent as a message, without changing the model; the hook asked again and the text was
  repeated. Now the box is cleared (Ctrl+C) before `/model`, and the hook does not ask in the 2 min after the change or
  if the text carries a pasted `/model`.

## [1.32.1] - 2026-11-19

### Added

- Personal segments in the bar: `~/.config/ws-local/barra-extra.conf` (not part of the kit). `tmux-fondo` keeps them
  present exactly once even if the theme changes or you reload the configuration.
- `ws-cache <seconds> <command>`: cached output for slow bar segments; refreshes in the background.

### Changed

- `tmux-fondo`: repairs the bar on every refresh (cheap) and leaves the network work for once a minute; `--barra` when
  loading the configuration.

## [1.32.0] - 2026-11-19

### Added

- Bar: CI (✔ ✖ ●), PR (#12 ✓ ✎ 📝) and ticket for each tab, from GitHub (`gh`) or Azure DevOps (`az`), with a 3 min cache
  (`tmux-rama`, `tmux-fondo`; `@rama_barra off` turns it off).
- `tmux-plantilla`: open a folder with panes already laid out (Claude + live tests + git); 5 templates (node-api,
  dotnet, python, terraform, qa) and "save this tab as a template". Menú → T · Sesión → G.
- `tmux-grabar`: records an already open pane to `.cast` (asciinema) + redacted `.txt` (+ `.gif` with agg) in
  Videos\Claude. Menú → g → r.
- `tmux-historial` (off by default): search over what went through all panes, redacted, 30 days. Sesión → y / h.
- `tmux-enjambre`: several Claudes in parallel, one subtask per worktree and branch, progress dashboard and integration
  with merge --no-ff that you approve; never push. Menú → Claude → Z.

## [1.31.0] - 2026-11-19

### Added

- `Ctrl+b e`: sends Claude the output of the adjacent pane (redacted, pasted without Enter).
- `Ctrl+b Space`: command palette with every menu option and its key path.
- `Ctrl+b N`: notify me when this pane's command finishes (Windows + Telegram, ✅/❌ and last lines).
- `Ctrl+b u`: extract URLs, paths, hashes, IPs, GUIDs, Azure IDs, tickets and images from the screen.
- `Ctrl+b ?`: quick question to Claude (Haiku, no tools or session); «+p» includes the screen.
- `Ctrl+b E`: tab labels (bloqueada, revisión, esperando, pruebas, lista: blocked, review, waiting, tests, ready) in the
  bar and the dashboard.
- Menu: broadcast the same text to several tabs with Claude, live logs with alarm (k8s, App Service, Docker, file),
  focus mode, second monitor and read-only mirror for screen sharing.
- `ws-aviso` (Windows toast + Telegram, with click to the tab) and `ws-redactar` (secret filter) for all scripts.

### Changed

- `tmux-dash`: label column; linked sessions from the second monitor are not repeated.

## [1.30.0] - 2026-11-19

### Added

- Traces of everything Claude does (`~/.claude/hooks/ws-trazas.sh`, 13 events): per tool (summarized action, duration
  without your wait, your wait to approve, error by type, bytes, lines +/−, extension, MCP and method, skill, subagent
  and requested model), prompts (size, command, question, code), turns, notices, denied permissions, subagents,
  compactions and sessions (commits and diff since the start). Never content. `~/.local/share/ws-telemetria/trazas/`,
  gzip after 35 days, 13 months.
- `ws-telemetria trazas | estimar | semana | presupuestos | exportar`; `trazas` view in `ws-telemetria sql`.
- Dashboard: tools (time, errors, approx. cost), Bash by type of work, code by language and file, MCP/subagents/skills,
  estimation per ticket and budgets.
- Telegram: weekly summary (Mondays from 9) and budget notices at 80 and 100 %
  (`~/.config/ws-telemetria/presupuestos.conf`).

## [1.23.0] - 2026-11-18

### Fixed

- Telegram: the service uses a PID file instead of a lock; child processes inherited the lock and, if they stayed alive,
  the service would not start again (text replies were lost without a trace).
- Telegram: every message you write to the bot is logged, with the reason if it was not sent.
- Telegram: the service started by tmux failed with "sin token" ("no token"; PATH without ~/.local/bin or Windows);
  ws-telegram sets its PATH and ws-secret finds PowerShell at its standard path.

## [1.22.0] - 2026-11-18

### Fixed

- Telegram: Reply with text works on any notice from a Claude tab in the last hour (finished, question, command, alert),
  not only on questions marked ↩; without Reply, it goes to the only open question if there is exactly one. If that tab
  has a dialog with options, it does not type (use the buttons). The confirmation says which tab it reached.

## [1.21.0] - 2026-11-18

### Added

- Telegram alerts, checked every minute and rate-limited (`~/.config/ws-telegram/ajustes`):
  - Claude stopped because of an error or a usage limit, with a button to switch the tab to the other account (same
    conversation).
  - Reminder every 3 min while a permission is still waiting for your decision.
  - Stuck tab: working without writing to its transcript (or its subagents') for more than 10 min.
  - High usage: more than $15/h equivalent over the last 10 min (`ws-telemetria ritmo`).
  - Context ≥ 80 %, with a /compact button.
  - Security: someone other than you used the bot; wrong PIN.
  - Workstation: less than 50 GB on C:, light backup older than one day, kit CI failed.
- Daily summary (20:00 by default): usage, Telegram activity, `ws-health` and what is being done in each tab
  (`tmux-resumen --texto`). Try it: `ws-telegram resumen`. Turn alerts off: `ws-telegram alertas off`.

## [1.20.0] - 2026-11-18

### Fixed

- Telegram: the same command in the same tab arrives only once every 30 min (it used to repeat on every turn that
  mentioned it).
- Telegram: if Claude says "anteponle `!`", "con ! al inicio" ("prefix it with `!`", "with ! at the start") or similar,
  the commands that follow count even if the tool is not in the known list; the list grew (aws, gcloud, azd, func, apt,
  brew, winget, fnm, prisma, trivy, gitleaks, wsl.exe, powershell.exe…).

## [1.19.0] - 2026-11-18

### Fixed

- Telegram: all the commands Claude asks for now arrive. The whole text of the turn is taken (intermediate messages too,
  not just the final one) and commands without `!` are recognized: ```bash/sh/console``` blocks and `commands` after
  "ejecuta/corre/run" if they start with a known tool (git, npm, az, kubectl, docker, terraform…); blocks in other
  languages, paths and heredocs are discarded.
- Notices for turns that continue without a new prompt (previously lost) when they carry commands or questions.

## [1.18.0] - 2026-11-18

### Added

- Telegram: reply with text to Claude's open questions. Only with Reply on the question (↩), starting with your PIN (4
  to 6 digits, in the Windows Credential Manager); single use, 15 min; your message is deleted from the chat; it reaches
  Claude as `[Respuesta desde Telegram] …`. 3 wrong PINs in 1 h turn the feature off. Off by default: `ws-telegram texto
  on` or Menú → Estación.

### Fixed

- Telegram: the `!` commands in a long response did not arrive (only the last 1200 characters were examined); they are
  now extracted from the full message (up to 8).

## [1.17.0] - 2026-11-18

### Changed

- Routing: moving down a model is only proposed with little context (< 30 %, `bajar_max_ctx` in
  `~/.config/ws-ruteo/ajustes.conf`). With more context, changing the model re-reads everything without cache and costs
  more than it saves: the hook does not block and suggests the cheap subagent to Claude (`sql-rapido` for SQL,
  `explorador` for searches). Moving up a model still always asks.
- Telegram: the service restarts on its own when a patch updates `ws-telegram`.

### Fixed

- CI: the tmux step starts a single server with retries and `TERM` set; it used to fail sometimes with "server exited
  unexpectedly".

## [1.16.0] - 2026-11-18

### Added

- Telegram: each `!` command Claude asks you for arrives in its own message (copied with one tap) with ▶ Ejecutar
  ("Run"). It runs only that command, in that tab, as a Claude `!` (Claude sees the output), and the result arrives
  redacted as a reply. Single use, 10 min.
- Never run from Telegram (they arrive without a button, "hazlo en la PC", "do it on the PC"): sudo, recursive deletes,
  `curl | sh`, terraform apply/destroy, kubectl delete/apply/exec, helm install/upgrade, `az` changes, `git push`,
  docker run/exec/rm and commands that carried a secret.

## [1.15.0] - 2026-11-18

### Added

- `Ctrl+b o` (tmux-open): → enters the subfolders of the highlighted folder, ← goes up one level and Enter opens; the
  first line of each level opens the folder itself.

### Changed

- The tab summary runs as an interactive floating window (scroll, copy, search), like the others.

## [1.14.0] - 2026-11-18

### Added

- Summary of each tab: double click on the tab, `Ctrl+b i` or Menú → Sesión → Resumen. It shows folder, branch, changes,
  last commit, Claude's status and model, tasks in progress (what we are doing) and the last exchange (where we left
  off); `r` adds a 3-line summary with Haiku.
- Telegram: the routing prompt arrives with buttons (Cambiar · Enviar con el actual · Editar: Switch · Send with the
  current one · Edit) and waits 2 min; whichever answers first, the PC or the phone, wins.

### Changed

- Notices (Windows and Telegram) also when Claude ends a short turn asking you for something: a question or a command
  for you.
- Inside a floating window, Telegram reads the screen and sends the key to the floating window, not to the tab outside.

## [1.13.0] - 2026-11-18

### Added

- Word telemetry: per turn, how many words you write and how many Claude answers (only the count, never the text); in
  the dashboard, average per turn, ratio and output tokens per visible word, per project.
- Network telemetry: WSL bytes every minute (measured) and Claude traffic per project estimated from tokens; "Red (24
  h)" ("Network (24 h)") card in the dashboard.

## [1.12.0] - 2026-11-18

### Added

- CI on GitHub (`.github/workflows/ci.yml`): lint (shellcheck, Python, JSON, tmux configuration and menus) → SAST and
  secrets (bandit, gitleaks with verified checksum) → kit tests. No third-party actions; read-only permissions.
  Dependabot for `actions/checkout`.
- Usage dashboard: cards for model routing (suggestions accepted or rejected per rule) and for Telegram (notices,
  replies, unauthorized attempts, errors).
- `install.sh` adds the terminal (`shell.sh`) and account lines to `.bashrc`; it recognizes the ones that already exist
  even if they are written with `$HOME`.

### Changed

- The light backup includes telemetry, routing rules, Telegram configuration (without token) and the solo-mode profile.

### Fixed

- `ws-telegram configurar` no longer shows an error when saving the first `offset`.
- `ws-telemetria`: bandit findings (sha1 only for cache names; DuckDB view with a fixed path).

## [1.11.0] - 2026-11-18

### Added

- Claude notices over Telegram (`ws-telegram`, ADR-010). They arrive when Claude asks for your decision or finishes a
  long turn, with the question redacted (no tokens, keys or passwords) and `1 · 2 · 3 · Cancelar` buttons that are sent
  to that tab.
- Security: token in the Windows Credential Manager (`ws-secret`), never in argv. Only buttons from your chat.
  Single-use code that expires in 10 min. The screen is read again before sending (if the dialog changed, it does not
  send). Only closed options. Log in `~/.local/share/ws-telemetria/telegram/`.
- Menú → Estación → Telegram (turn on or off); `ws-telegram configurar | estado | prueba | olvidar`.

### Fixed

- `ws-secret` without PowerShell's CLIXML noise ("Preparing modules for first use").

## [1.10.0] - 2026-11-18

### Added

- Model routing per task (ADR-009, R1), always with your confirmation. A single rule table
  (`~/.config/ws-ruteo/reglas.conf`) for the Claude hook and for `cr`. If a rule says the task belongs to a different
  tier than the tab's model, a popup asks: switch and send, send with the current one or edit. The text is not lost and
  your default model does not change.
- `cr "task"`: classifies, explains (`--explica`), simulates (`--dry-run`), forces a tier (`-t`) and sends to the tab's
  Claude with the right model, or opens it with `--model`. With no rule, it asks Haiku (redacted text); with confidence
  < 0.7 it goes up one tier. `cr --probar`: 20 labeled tasks.
- Menú → Claude → Modelo de esta pestaña: Fable 5.2, Opus 5.5, Sonnet 5.5, Haiku 5.5, and turning routing on or off.
- Subagents `depurador` (Opus 5.5, medium) and `sql-rapido` (Sonnet 5.5, low); `arquitecto` moves to Fable 5.2 (high)
  and `explorador` to Haiku 5.5 (low).
- `fallbackModel`: Opus 5.5 → Sonnet 5.5 if the main model is overloaded or down (that turn only).
- Routing decisions in the telemetry (`~/.local/share/ws-telemetria/ruteo/`), without the text of the tasks.

## [1.9.0] - 2026-11-18

### Added

- Clicking a Claude Windows notification (or its "Ir a la pestaña" ("Go to the tab") button) brings Windows Terminal to
  the front and takes tmux to the tab and pane that raised it. `ws-claude://` protocol registered per user (no
  administrator); `tmux-foco` only accepts a pane number and only switches tabs.

## [1.8.1] - 2026-11-18

### Security

- The bash history no longer stores lines with credentials (`HISTIGNORE`) or lines that start with a space.
- `ws-historial`: finds possible secrets in the history without showing them and deletes them with confirmation;
  `ws-auditoria` uses the same pattern (it now includes `client_secret=`, tokens and `Bearer`).

### Fixed

- `ws-auditoria`: read-only Docker commands outside the sandbox are no longer flagged as a failure; only `docker *`,
  `run`, `exec`, `cp`, `build`, `pull`, `push` and `compose up/run/exec`.

### Changed

- The terminal opens ~1.7 s faster: nvm is loaded only when used (fnm handles Node). Local change in `~/.bashrc`.

## [1.8.0] - 2026-11-17

### Added

- Local Claude telemetry (`ws-telemetria`, ADR-008): exact tokens per response (input, output, cache written and read,
  reasoning) from the transcripts, grouped by turn, session, project, branch and model; responses repeated by streaming
  are counted once; subagents and the copilot included. Cost equivalent at API prices (editable table in
  `~/.config/ws-telemetria/precios.json`).
- Resources of the Claude process per project (CPU, RAM, disk operations and bytes), sampled every minute from `/proc`.
- HTML dashboard that is regenerated every minute and reloads on its own (`%UserProfile%\ws-telemetria\tablero.html`);
  Menú → Estación → Consumo de Claude. `ws-telemetria resumen` and `ws-telemetria sql` (DuckDB, optional).
- No text of prompts or responses; 13-month retention; 0700 permissions.

## [1.7.0] - 2026-11-14

### Added

- `ws-test`: deterministic tests of the whole workstation in an isolated environment (simulated HOME, tmux and Claude):
  configuration and menus, solo mode, accounts, persistence and auto-restore, floating windows, backup, screensaver,
  terminal and copilot, sandbox limits. `ws-test --ia`: non-deterministic smoke test with the real Claude and API
  (tolerant, only warns). `ws-verify` runs `ws-test`.
- Interactive floating windows (`tmux-flot-run` + `flot.conf`): each floating window runs in its own tmux session with
  scroll, selection and copy to the Windows clipboard (`ws-copiar`), search and `Ctrl+b d` to close; the internal
  scripts keep controlling the outer tmux.
- AI suggestions in gray as you type (ble.sh) with the Anthropic API directly (Haiku, ~0.5 s): one query in flight,
  minimum 0.8 s between queries, secret redaction and circuit breaker (3 failures → 5 min pause). `Alt+a/e/x` use the
  API if there is a key and, if not, `claude -p`.
- Screensaver: three original epic scenes in the style of the bonsai (they grow step by step): `fortaleza` (Valdrun and
  Kaelen), `expedicion` (the caravan of Ostvar) and `gigantes` (the moss giants and Nim), in `tmux-escenas`.
- `ws-secret`: secrets in the Windows Credential Manager (DPAPI) from WSL; the API key is read once per shell and lives
  only in memory.

## [1.6.0] - 2026-11-14

### Added

- `tmux-recuperar` (Menú → Sesión → Recuperar pestañas): lists the saves with time, number and names of tabs and
  restores the chosen one in one step.
- Backup restore at startup: `.tmux.conf` marks the last save before loading plugins and, if the session ends up empty,
  restores it on its own.
- `docs/runbook.md`: troubleshooting and recovery (tabs, conversations, backups, WSL, accounts, copilot, sandbox,
  patches).

### Fixed

- `tmux-save-now` does not save during the server's first 3 minutes: on restart it overwrote the last save with an empty
  session and the tabs were not restored.
- `claude-cuenta estado` was cut short when reading the account status.

## [1.5.0] - 2026-11-14

### Added

- Two Claude accounts on the same workstation (`claude-cuenta`, Menú → Claude): the work one in `~/.claude` and the
  personal one in `~/.claude-personal`, each with its own login (`CLAUDE_CONFIG_DIR`). They share setup, conversations,
  history and work state, so a tab switches accounts while resuming the same conversation (for example, when one runs
  out of usage). Each organization's policies (`remote-settings.json`, `policy-limits.json`) and the login stay
  separate. Personal tabs are marked with `·P`.

## [1.4.0] - 2026-11-14

### Added

- Terminal: Tab completion (`bash-completion` + `ws-completions` for kubectl, helm, gh, az, aws, terraform, docker, fnm,
  cargo…), fzf (`Ctrl+R`, `Ctrl+T`, `Alt+C`, `**<Tab>`) and ble.sh pinned to a commit (gray suggestions from history and
  syntax colors). Turned off with `touch ~/.config/tmux-claude/sin-ble`.
- AI copilot in the terminal (`ai-shell.sh`): `Alt+a` turns what you type in Spanish into a command, `Alt+e` explains
  the command on the line, `Alt+x` fixes the last one that failed. Claude Haiku with no tools, hooks, MCP or saved
  session; it redacts secrets before sending; it never executes: the suggestion stays on the line.

## [1.3.0] - 2026-11-13

### Added

- Solo mode (`tmux-solo`, Menú → Claude): Claude in auto mode **without sandbox** for unattended work; the auto-mode
  classifier reviews each command instead of asking you (profile `~/.config/claude-solo/settings.json`, only in that
  session). It is enabled in the current tab resuming the conversation, in a new tab or in a worktree
  `<repo>.wt/solo-<date>`, and you go back to normal from the same menu. `ask` rules still ask; `deny`, `guard.sh` and
  dangerous `rm`s stay blocked.

## [1.2.0] - 2026-11-13

### Added

- `ws-backup-lite`: daily light backup of Claude's and the workstation's data (conversations including subagents',
  todos, plans, `/rewind`, history, memory, audit, tmux saves, MemPalace) plus an inventory for reinstalling. No
  credentials or caches; verified with SHA-256, atomic write, rotation (14) and optional encryption with age. It
  triggers on its own once a day from the tmux save.
- `ws-restore-lite`: `--probar` checks in a temporary folder that everything can be recovered and that it carries no
  credentials; `--restaurar` extracts into `$HOME` without overwriting (`.~N~`).
- Menú → Estación: "Respaldar Claude ahora" ("Back up Claude now") and "Probar el último respaldo" ("Test the last
  backup").

### Changed

- `ws-health`: accepts the light backup (<2 days) in place of the full snapshot; on C: it requires 50 GB free instead of
  15 %.

## [1.1.0] - 2026-11-13

### Added

- Kit for the team: `export.sh` stores personal paths and users as a template (`@WINHOME@`, `@WIN_USER@`, `@HOME@`,
  `@LINUX_USER@`) and `install.sh` replaces them with those of the target machine; `--win-user` and `--repos` options.
- Clickable menu (`Ctrl+b m`, `≡ menú`, right click on a tab) organized in submenus: navigation, Claude, panes, session,
  tests/recording/presentation, appearance and workstation.
- Navigation without prefix: `Alt+←/→`, `Alt+0`, `Alt+s` (finder with priority ⚠ ! ⏳), `Alt+Shift+←/→` (move while
  keeping focus).
- Subagents: record per tab, `Ctrl+b A` live and `v` to view their transcript with reasoning (`showThinkingSummaries`).
- Windows notifications (`win-notify.sh`) and the `tmux-watch` watcher: usage traffic light, pending approvals,
  inactivity and reminders.
- Quality and security gate `ws-gate` in the global git hooks, lint on edit for Claude and a full repo report.
- Conversion of PDF, Office, CSV, RTF, ODT and EPUB to Markdown with images (`ws-tomd` + `read-convert.sh` hook),
  isolated with no network.
- `ws-tools`: inventory and installer by groups (base, nube, aws, contenedores, calidad, python, web, rust, sql, dev).
- `ws-health`, `devsnapshot` and `devrestoretest` (resilience); tmux save when tabs or panes change.
- `ws-verify`: test of the whole setup before pushing (patches, shellcheck, tmux and theme loading, scenes, Claude
  settings and hooks, `ws-check`/`ws-health`, kit tests, personal data, secrets and remote). Read-only.
- Playwright with visible windows (WSLg), tab recording to GIF, presentation mode and persistent floating shell.
- Dark, light or automatic theme (follows Windows) for tmux, Windows Terminal and Claude statuses.
- Pixel art screensaver with its own scenes: invasion, creatures, colossus, synthwave, city at night, fireworks,
  aquarium and snake.
- starship prompt with production context and WSL ↔ Windows bridge (`wopen`, `wexp`, `wpath`, `wcopy`, `wpaste`).
- Versioned PowerShell profile (`windows/profile.ps1`, `windows/instalar.ps1`).

### Changed

- `install.sh` skips MCP servers whose executable does not exist on the machine.
- Conversation backup to Windows every 15 minutes (previously, every hour).
- WSL networking in NAT: mirrored mode was tried and it blocked internet access on corporate machines.

### Security

- Permission rules for AWS (secrets forbidden, mutations with confirmation), databases and destructive Docker.
- Sandbox with no way out (`allowUnsandboxedCommands: false`) and `~/.kube`, `~/.aws` out of reach of sandboxed
  commands.
- No Trivy (compromise of its supply chain, CVE-2026-33634); osv-scanner and Docker Scout are used.

### Fixed

- `ws-tools`: false FALTA ("missing") results caused by `pipefail`, the Node check with the field separator and an `&1`
  file created by a badly escaped redirection.
- `fnm` fails if `/run/user/$UID` does not exist when WSL starts: it uses `/tmp/fnm-$UID`.
- The kit's "sin usuario de Windows" ("no Windows user") test: it no longer depends on `cmd.exe` being available.

## [1.0.0] - 2026-11-12

### Added

- `export.sh`: captures the real configuration (manifest, user MCP, `.wslconfig`) and blocks secrets.
- `install.sh`: applies without overwriting (backup of what changes, `--dry-run`, idempotent), tmux plugins and missing
  MCP servers.
- `tests/run.sh`: export, secret blocking, clean install, idempotency and backup.
- Configuration for phases 1 and 2: persistent tmux, agent status, audit, guardrails, intent-based routing, MemPalace
  and recall on WSL, Microsoft Learn, Release Communications and Azure MCP servers, sandbox.
