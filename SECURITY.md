# Security policy

claude-workstation configures tmux, Claude Code hooks and helper scripts on a developer workstation (WSL2 on Windows).
This document explains which versions are supported, how to report a vulnerability and the security model.

## Supported versions

| Version | Security fixes |
|---|---|
| 3.x | Yes |
| 2.x | Security fixes only, until the wrappers for the old command names are removed (the next major version) |
| < 2.0 | No; upgrade with `ws-kit-update` |

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.** Use GitHub's private vulnerability reporting:
<https://github.com/andreshma/claude-workstation/security/advisories/new>. Include the affected version or commit, the
impact and reproduction steps (describe the class of problem; no weaponized exploit). The maintainer (GitHub:
andreshma) aims to acknowledge within **5 business days**, agrees a disclosure date with you and credits you unless
you prefer otherwise.

## Security model

The full analysis, with residual risks and a cross-reference to the OWASP agentic Top 10, is in
[docs/THREAT_MODEL.md](docs/THREAT_MODEL.md). The controls are mapped to the frameworks in
[docs/compliance/](docs/compliance/assessment.md), and the policy, the AI bill of materials and the incident playbooks
are in [docs/governance/](docs/governance/README.md).

- **Protection levels** per tab ([ADR 0012](docs/adr/0012-per-tab-protection.md),
  [ADR 0013](docs/adr/0013-minimum-protection-floor.md), [ADR 0019](docs/adr/0019-strict-base-and-level-profiles.md)):
  the user settings are strict (no command leaves the sandbox); `normal`, which every kit launcher starts, adds the
  commands excluded from the sandbox (az, gh, git push…) from `~/.config/claude-levels/normal-adds.json`; `full` keeps
  them inside the sandbox; `bare` is Claude almost as it ships. Solo mode runs in auto mode **inside** the sandbox and
  expires after 4 hours; `--unsandboxed` is an audited exception
  ([ADR 0016](docs/adr/0016-solo-mode-inside-the-sandbox.md)).
- **The floor** stays at every level: the `deny` rules and `guard.sh`, which fails closed (also when the hook itself
  is missing, `onFailure: block`). `bash install.sh --managed` can install it as a root-owned managed drop-in.
  Bypass-permissions mode is disabled.
- **Agent configuration is protected** ([ADR 0017](docs/adr/0017-defence-in-depth-for-agent-configuration.md)): the
  guard blocks agent writes to settings, hooks, `~/.claude.json`, plugins, profiles, git hooks, the kit's keys and
  pins, the audit log and the Telegram configuration, and MCP or plugin registration. `CLAUDE.md`, commands, agents
  and skills can be written only inside a 30-minute window the owner opens
  (`date -d '+30 min' +%s > ~/.config/ws-guard/allow-config-writes`); each write is audited, and `config-change.sh`
  logs every configuration change.
- **Untrusted content** from web fetches, web searches, MCP tools and network commands is labelled as data and
  screened for injection markers (`untrusted-content.sh`); hits go to the audit log. The screen is heuristic.
- **Prompts that carry a secret** are blocked before they reach the model (`prompt-screen.sh`); `#allow-secret` at
  the start of the prompt sends it anyway and is audited.
- **Memory**: every MemPalace write asks, with provenance stamped by the hook (`memory-gate.sh`); text inside
  `<private>…</private>` never reaches MemPalace or recall (`memory-filter.sh`).
- **Production** subscriptions and kube contexts are recognised by name and, more reliably, from
  `~/.config/ws-guard/production.conf` (`subscription <id or name>`, `context <name>`); mutating commands and Azure
  MCP tools against them are blocked.
- **Agent identities**: `tmux-level … --agent NAME` runs a tab with the az, gh and kubectl logins under
  `~/.config/ws-agent/NAME`, and the guard refuses to switch them
  ([ADR 0020](docs/adr/0020-agent-scoped-identities.md)).
- **Per-tab profiles** (`ws-profile`): a client's tab runs with that client's Claude organisation, Azure tenant, gh and
  kubectl logins and, by default, its own conversations and no MemPalace; no tab can read another profile's logins or
  conversations, and the agent cannot switch or change profiles ([ADR 0021](docs/adr/0021-per-tab-profiles.md)).
- **Secrets** live only in the Windows Credential Manager (`ws-secret`, DPAPI). Tokens are passed to tools through file
  descriptors, never argv. The repository contains no credentials; exports are scanned before every commit, and the
  git gate refuses commits when gitleaks is missing (opt-out per repository, logged).
- **Audit**: `~/.claude/audit` is a hash chain with anchors on the Windows side, kept 395 days; `ws-audit
  --verify-log` checks it. `ws-anomaly` flags sessions with repeated blocks and denials, and `ws-stop-all` is the
  emergency stop for every agent.
- **Spend**: budgets alert, and `hard=1` in `budgets.conf` holds work in a project over its budget until an audited
  override.
- **Telemetry is local** (`~/.local/share/ws-telemetry`, 0700). Usage data built from transcripts and hooks holds
  counts, timings and tool names. The local OpenTelemetry collector (`ws-otel`,
  [ADR 0014](docs/adr/0014-local-opentelemetry-collector.md)) listens only on `127.0.0.1` and also stores the text of
  prompts, responses and tool calls, with recognizable secrets masked; `WS_OTEL_CONTENT=0` turns content off. That
  folder must stay out of unencrypted backups and cloud sync. What goes to Telegram or into Claude summaries is
  redacted first (`ws-redact`).
- **Telegram control** answers only the owner's chat, with one-time codes that expire in 10 minutes and closed
  options. Approving a risky dialog needs the PIN, "don't ask again" is never offered, ▶ Run is offered only for
  read-only commands of an allow list, and nothing is sent or run during an emergency stop.
- **Backups**: light backups are encrypted when a recipient exists and reported by `ws-audit` when they are not;
  Windows-side copies whose original is gone expire after 30 days.
- **Supply chain** ([ADR 0018](docs/adr/0018-supply-chain-pinning-and-signed-releases.md)): MCP servers and agent
  tools are pinned by version and integrity (`ws-pinned`, `files/mcp-servers.lock.json`), local MCP executables by
  sha256 on first use; `ws-kit-update` installs only release tags signed by a key in
  `~/.config/ws-kit/allowed_signers`. CI pins GitHub's actions by commit SHA, checks the workflows with zizmor, builds
  a CycloneDX SBOM and refuses an unsigned release tag; gitleaks is verified by checksum; Dependabot watches the
  actions and the pinned npm packages.
- **Continuous evidence**: `ws-audit --compliance` runs the read-only checks of the control catalogue on a
  workstation; `tests/compliance.sh` and `tests/ai-bom.sh` keep the catalogue, the coverage tables and the AI bill of
  materials consistent in CI, and a monthly workflow re-runs them and checks the framework editions.
- **Upgrades from 2.x**: the installer moves data to the English names without overwriting, and the `deny` rules
  cover the credential and telemetry folders under both their old and their new paths while the old ones may still
  exist (the sandbox `denyRead` list names only the new paths).
