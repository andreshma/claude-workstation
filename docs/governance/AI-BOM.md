# AI bill of materials

Every model, agent, MCP server, agent tool, hook, instruction file and external service that the kit installs or
calls and that touches AI data, with its version or pin, the data it handles and its risk. Taken from the repository
after phase 2 of the hardening (kit 3.0.1 plus the `[Unreleased]` changes); the live machine was not inspected. The
accountable owner of every entry is the workstation owner; the "Upstream" column says who publishes the component.
Risk levels come from the controls cited in [controls.yaml](../compliance/controls.yaml).

## Contents

- [How to regenerate](#how-to-regenerate)
- [Models](#models)
- [Agents](#agents)
- [MCP servers](#mcp-servers)
- [Agent tools](#agent-tools)
- [Hooks](#hooks)
- [Instructions, plugins and skills](#instructions-plugins-and-skills)
- [External services](#external-services)
- [Known gaps](#known-gaps)

## How to regenerate

The inventory tables between `<!-- ai-bom:begin … -->` and `<!-- ai-bom:end … -->` markers are generated from the
files they describe by [.github/scripts/ai_bom.py](../../.github/scripts/ai_bom.py); the data, risk and upstream
tables next to them are written by hand. CI runs `bash tests/ai-bom.sh` in the suites job and in the monthly
compliance workflow: it fails when a generated table differs from the committed one, and when a generated row (a
model, agent, server, npm package, hook or plugin) has no hand-written entry in its section.

```bash
python3 .github/scripts/ai_bom.py --write     # after changing settings.json, an agent, mcp-servers.json or a lock
bash tests/ai-bom.sh                          # what CI runs
```

| Section | Generated columns | Source file | Field or expression |
|---|---|---|---|
| Models | Model, set in | `files/home/.claude/settings.json`; `files/home/.claude/agents/*.md`; `files/home/.local/lib/ws-routing.sh`; kit scripts | `.model`, `.fallbackModel[]`, `.modelSettings`; front matter `model`; `case` in `routing_model()`; `--model <x>`, `"--model", "<x>"`, `*_MODEL:-<x>`, `"model":` in request bodies (`ws-test` excluded) |
| Agents | Agent, model, effort, tool limits | `files/home/.claude/agents/*.md` | Front matter `model`, `effort`, `tools`, `disallowedTools` |
| MCP servers | Server, transport, command or URL, pin, opt-in, always-ask rules | `files/mcp-servers.json`; `files/mcp-servers.lock.json`; `settings.json` | Keys, `.type`, `.command` and `.args` or `.url`; `.servers.<name>` (`source`, `package`, `version`, `prerelease`, `optIn`); `.permissions.ask[]` starting with `mcp__<name>__` |
| Agent tools | Package, version, lock, use | `files/home/.local/lib/ws-npm/*/package.json`; `files/mcp-servers.lock.json` | `.dependencies`; the lock's `npm` field |
| Hooks | Script and what it wraps, events, matcher, timeout | `settings.json` | `.hooks.<Event>[].matcher`, `.hooks[].command`, `.args`, `.if`, `.timeout`, `.onFailure` |
| Plugins | Plugin or marketplace | `settings.json` | `.enabledPlugins`, `.extraKnownMarketplaces` |
| All | Data handled, upstream, risk | Script headers; [THREAT_MODEL.md](../THREAT_MODEL.md); [controls.yaml](../compliance/controls.yaml) | By hand: `risk` of the cited control |
| External services | Retention, terms | Provider pages | By hand |

Maps to: WS-GOV-002, WS-GOV-005 (NIST-AI-RMF:GOVERN-1.6, CSF:ID.AM-02, CIS-v8:2.1, OWASP-MCP3P:governance-workflows).

## Models

All models are Anthropic models reached through Claude Code or the `ant` CLI. Whatever the model, it receives the
conversation: prompts, files read, tool output and the instruction files.

<!-- ai-bom:begin models -->
| Model | Set in |
|---|---|
| `claude-fable-5-2` | `settings.json` `.model` (default); agent `architect`; routing level `fable` |
| `claude-haiku-5-5` | agent `explorer`; routing level `haiku`; scripts `ai-shell.sh`, `ws-audit`, `ws-copilot` |
| `claude-opus-5-5` | `.fallbackModel[0]`; `.modelSettings` (effortLevel high); agent `debugger`; routing level `opus` |
| `claude-sonnet-5-5` | `.fallbackModel[1]`; agent `sql-quick`; routing level `sonnet` |
| `haiku` | scripts `ai-shell.sh`, `tmux-ask` |
| `opus` | scripts `functions.sh`, `tmux-swarm` |
| `sonnet` | scripts `ws-handoff`, `ws-learn`, `ws-memory` |
<!-- ai-bom:end models -->

| Model | Role | Data sent | Risk |
|---|---|---|---|
| `claude-fable-5-2` | Default session model; `architect` subagent; routing level `fable` | Conversation | Medium (WS-AI-022) |
| `claude-opus-5-5` | First fallback, effort `high`; `debugger` subagent; routing level `opus` | Conversation | Medium (WS-AI-022) |
| `claude-sonnet-5-5` | Second fallback; `sql-quick` subagent; routing level `sonnet` | Conversation | Medium (WS-AI-022) |
| `claude-haiku-5-5` | `explorer` subagent; routing level `haiku`; `ws-audit --ai` escape tests; copilot API default (`ai-shell.sh`); `ws-copilot test` | Fixed test prompts; the command line, redacted by `_ai_redact` | Low |
| `sonnet` (alias, resolved by Claude Code) | `ws-learn` fact and command proposals; `ws-memory` approved saves and reviews; `ws-handoff` summaries | Recent sessions and diary through MemPalace read tools; the approved facts; a redacted handoff of the tab | Medium (WS-AI-017) |
| `opus` (alias) | `tmux-swarm` task split; `two` (open a tab with Opus, `functions.sh`) | Up to 400 file names of the repository and the goal; a full session | Low |
| `haiku` (alias) | `tmux-ask` default (`WS_ASK_MODEL`); copilot fallback through `claude -p` (`AI_SHELL_MODEL`) | The question, plus 60 redacted pane lines with `+p`; the command line | Low |

`ws-telemetry` also lists model IDs, but only in its price table; it calls no model.

Maps to: WS-GOV-002, WS-AI-020 (NIST-AI-RMF:MANAGE-3.2, NIST-AI-RMF:MAP-4.1, ISO42001:A.4, CSF:ID.AM-02).

## Agents

Subagents shipped in [files/home/.claude/agents/](../../files/home/.claude/agents/). None sets `tools`, so each
inherits the session's tools minus `disallowedTools`.

<!-- ai-bom:begin agents -->
| Agent | Model | Effort | Tool limits |
|---|---|---|---|
| `architect` | `claude-fable-5-2` | high | `disallowedTools: Edit, Write, NotebookEdit` |
| `debugger` | `claude-opus-5-5` | medium | None (inherits the session) |
| `explorer` | `claude-haiku-5-5` | low | `disallowedTools: Edit, Write, NotebookEdit` |
| `sql-quick` | `claude-sonnet-5-5` | low | None (inherits the session) |
<!-- ai-bom:end agents -->

| Agent | Data | Risk |
|---|---|---|
| `architect` | Reads the repository; can run commands the session allows | Low |
| `debugger` | Reads and edits the repository; runs tests | Low (WS-AI-016) |
| `explorer` | Reads the repository | Low |
| `sql-quick` | Queries and schema; database clients are in `permissions.ask` (a tools allow list is still open, WS-AI-016) | Low (WS-AI-016) |

Swarm agents started by `tmux-swarm` are ordinary Claude sessions in their own worktrees, started at the `full` level
with `git push` and `gh pr create|merge` denied (WS-AI-015).

Maps to: WS-GOV-002, WS-AI-016 (NIST-AI-RMF:GOVERN-1.6, OWASP-ASI:ASI03, ISO42001:A.4).

## MCP servers

Registered at user scope by `install.sh` from [files/mcp-servers.json](../../files/mcp-servers.json), after checking
each one against [files/mcp-servers.lock.json](../../files/mcp-servers.lock.json): npm servers are installed by
`ws-pinned` from a committed lock (`npm ci --ignore-scripts`, exact version and npm integrity), local executables are
pinned by sha256 on first registration, and a server missing from the lock or with a mismatch is skipped. An opt-in
server is registered only with `install.sh --mcp-opt-in <name>`. MCP servers run **outside** the sandbox with the
user's network and files ([THREAT_MODEL.md, Sandbox](../THREAT_MODEL.md#sandbox)); their output is labelled untrusted
by `untrusted-content.sh` (WS-AI-001).

<!-- ai-bom:begin mcp -->
| Server | Transport | Command or URL | Pin | Opt-in | Confinement | Always-ask rules |
|---|---|---|---|---|---|---|
| `mempalace` | stdio | `@WINHOME@/.local/bin/mempalace-mcp.exe` | sha256 pinned on first registration (`~/.local/share/ws-kit/mcp-trust.tsv`) | No | not confined (Windows executable reached through WSL interop) | 15 |
| `recall` | stdio | `@WINHOME@/source/repos/recall/.venv/Scripts/python.exe -I -m recall mcp` | sha256 pinned on first registration (`~/.local/share/ws-kit/mcp-trust.tsv`) | No | not confined (Windows Python (.venv/Scripts/python.exe) reached through WSL interop) | 0 |
| `microsoft-learn` | http | `https://learn.microsoft.com/api/mcp` | URL only (server side) | No | remote (runs at the provider) | 0 |
| `azure` | stdio | `@HOME@/.local/share/ws-kit/npm/azure-mcp/node_modules/.bin/azmcp server start` | `@azure/mcp@4.0.0-beta.9`, npm sha512 in the lock (prerelease) | No | ws-mcp-jail, network, own Azure config | 31 |
| `ms-release-comms` | http | `https://www.microsoft.com/releasecommunications/mcp` | URL only (server side) | No | remote (runs at the provider) | 0 |
| `chrome-devtools` | stdio | `@HOME@/.local/share/ws-kit/npm/chrome-devtools-mcp/node_modules/.bin/chrome-devtools-mcp --isolated --no-usage-statistics --no-performance-crux --redact-network-headers` | `chrome-devtools-mcp@1.14.0`, npm sha512 in the lock | Yes | ws-mcp-jail, network | 0 |
<!-- ai-bom:end mcp -->

| Server | Upstream | Hosts it needs | Credentials reachable | Data | Risk |
|---|---|---|---|---|---|
| `mempalace` | External repository, not inspected | None expected (`HF_HUB_OFFLINE=1`); not verifiable from the repo | The user's, on the Windows side | Reads and writes the memory store: drawers, knowledge graph, diary. Every write asks through `memory-gate.sh`, which stamps provenance and blocks `<private>` text (WS-AI-012) | High (WS-AI-012, WS-AI-009) |
| `recall` | External repository, not inspected | None expected (`HF_HUB_OFFLINE=1`) | The user's, on the Windows side | Search queries; returns passages of the local book corpus | Medium (WS-AI-009, WS-AI-024) |
| `microsoft-learn` | Microsoft | `learn.microsoft.com` | None | Search queries and URLs chosen by the agent; returns untrusted text | Medium (WS-AI-001) |
| `azure` | Microsoft | The Azure endpoints of the tools called (not listed in the repo); no registry access at start | Only the tab's Azure CLI login (`AZURE_CONFIG_DIR`, the one folder `ws-mcp-jail --azure-config` binds); no other credential, profile or Windows path (ADR 0024) | Tool arguments; returns subscription and resource data. Mutating tools and the `keyvault`, `role`, `storage`, `sql`, `cosmos` and other data tools always ask; mutating tools against a production subscription are blocked by the guard (WS-SEC-006) | High (WS-AI-009, WS-AI-011) |
| `ms-release-comms` | Microsoft | `www.microsoft.com` | None | Queries; returns untrusted text | Medium (WS-AI-001) |
| `chrome-devtools` | Google (Chrome DevTools team) | The pages the agent opens, in a Chrome reachable from WSL | None with `--isolated` (its own temporary profile); a Windows Chrome attached through a debugging port exposes whatever that profile holds | Page content, network and console of the pages it drives, as untrusted text; usage statistics and update checks off | Medium (WS-AI-011) |

`ws-update` and `ws-pinned verify --online` report a newer pinned package or a changed local executable but never
apply it. Microsoft 365 tools come from a connector of the Claude account, not from this file; the kit only adds
always-ask rules for them (see [External services](#external-services)).

Maps to: WS-GOV-002, WS-AI-009, WS-AI-011 (OWASP-ASI:ASI04, OWASP-MCP3P:governance-workflows,
NIST-600-1:Value Chain and Component Integration, CIS-v8:2.1, CAF:secure.protect-resources).

## Agent tools

npm packages the kit pins and installs with `ws-pinned` (`ws-tools install agent-browser`,
`ws-tools install chrome-devtools-mcp`, and `install.sh` for the MCP servers).

<!-- ai-bom:begin tools -->
| Package folder | Package and version | Lock | Used as |
|---|---|---|---|
| `agent-browser` | `agent-browser@0.44.0` | `files/home/.local/lib/ws-npm/agent-browser/package-lock.json` | CLI tool |
| `azure-mcp` | `@azure/mcp@4.0.0-beta.9` | `files/home/.local/lib/ws-npm/azure-mcp/package-lock.json` | MCP server `azure` |
| `chrome-devtools-mcp` | `chrome-devtools-mcp@1.14.0` | `files/home/.local/lib/ws-npm/chrome-devtools-mcp/package-lock.json` | MCP server `chrome-devtools` |
<!-- ai-bom:end tools -->

| Package folder | Upstream | Data | Risk |
|---|---|---|---|
| `agent-browser` | Vercel Labs (Apache-2.0) | Pages opened by the agent through the kit's wrapper `~/.local/bin/agent-browser`: localhost-only domain allow list plus `allowed-domains.local.txt`, eval, download and upload denied, output wrapped as untrusted and capped. No usage telemetry found in 0.44.0; it checks for outdated Chrome. These are defaults, not a boundary: the binary can be called directly | Medium (WS-AI-011) |
| `azure-mcp` | Microsoft | The `azure` MCP server above | High (WS-AI-009) |
| `chrome-devtools-mcp` | Google | The `chrome-devtools` MCP server above (opt-in) | Medium (WS-AI-011) |

Maps to: WS-GOV-002, WS-AI-009 (OWASP-ASI:ASI04, CIS-v8:2.1, NIST-600-1:Value Chain and Component Integration).

## Hooks

From `.hooks` in [settings.json](../../files/home/.claude/settings.json); scripts in
[files/home/.claude/hooks/](../../files/home/.claude/hooks/). Hooks run outside the sandbox at every level; the
pipeline order is in [architecture.md](../architecture.md).

<!-- ai-bom:begin hooks -->
| Hook | Events (matcher) | Timeout (s) |
|---|---|---|
| `audit.sh` | PermissionDenied; PreToolUse; SessionEnd; SessionStart; UserPromptSubmit | - |
| `config-change.sh` | ConfigChange | 5 |
| `guard.sh` | PreToolUse; onFailure `block` | - |
| `intent-route.sh` | UserPromptSubmit | - |
| `lint-on-edit.sh` | PostToolUse (`Edit\|Write\|MultiEdit`) | 30 |
| `memory-filter.sh` → `win-hook.sh` → `mempalace.exe` | SessionEnd; SessionStart; Stop; PreCompact | 20, 30, 45 |
| `memory-filter.sh` → `win-hook.sh` → `python.exe` → `recall_hook.py` | UserPromptSubmit | 5 |
| `memory-gate.sh` | PreToolUse (`mcp__.*mempalace.*`); UserPromptSubmit | 5, 10 |
| `prompt-screen.sh` | UserPromptSubmit | 5 |
| `read-convert.sh` | PreToolUse (`Read`) | 180 |
| `tmux-state.sh` | Notification; PostToolUse; PostToolUseFailure; PreCompact; PreToolUse; SessionEnd; SessionStart; Stop; StopFailure; SubagentStart; SubagentStop; UserPromptSubmit | - |
| `untrusted-content.sh` | PostToolUse (`^(WebFetch\|WebSearch\|mcp__.*)$`); PostToolUse (`Bash`) if the command starts with `curl`, `wget`, `gh api`, `gh issue view`, `gh pr view`, `gh pr diff`, `gh run view`, `gh release view`, `gh search` | 5 |
| `win-notify.sh` | Notification; Stop; UserPromptSubmit | - |
| `ws-cache` → `pwsh.exe` → `mempalace-health.ps1` | SessionStart | 25 |
| `ws-cache` → `pwsh.exe` → `start-recall.ps1` | SessionStart | 10 |
| `ws-routing.sh` | UserPromptSubmit | 5 |
| `ws-runtime-gate.sh` | PreToolUse; UserPromptSubmit | 5 |
| `ws-sandbox-notice.sh` | PostToolUse (`Bash`); PostToolUseFailure (`Bash`) | 5 |
| `ws-traces.sh` | Notification; PermissionDenied; PostToolUse; PostToolUseFailure; PreCompact; PreToolUse; SessionEnd; SessionStart; Stop; StopFailure; SubagentStart; SubagentStop; UserPromptSubmit | 5 |
<!-- ai-bom:end hooks -->

| Hook | What it reads | What it writes or sends | Risk |
|---|---|---|---|
| `memory-filter.sh` (in front of `win-hook.sh` for MemPalace and recall) | The hook JSON with the prompt or the transcript path | Removes `<private>…</private>` spans; MemPalace gets a redacted copy of the transcript, recall a redacted prompt; what MemPalace stores from the rest is decided outside the repo | High (WS-AI-012) |
| `memory-gate.sh` | MemPalace tool input; the prompt | Asks on every memory write, stamps provenance, blocks `<private>` content; audit line with the input hash | Medium (WS-AI-012, WS-AI-013) |
| `ws-cache` (`mempalace-health.ps1`, `start-recall.ps1`) | - | Starts or checks the Windows-side services; scripts not in the repo | Low |
| `untrusted-content.sh` | Tool results of WebFetch, WebSearch, MCP tools and network commands | A context label naming the source; on injection markers a warning and an `injection-suspect` audit line | Low (WS-AI-001) |
| `prompt-screen.sh` | The prompt | Blocks a prompt that seems to carry a secret (`#allow-secret` overrides, audited); the prompt is never logged | Low (WS-AI-022) |
| `ws-runtime-gate.sh` | The stop marker and the budget flag | Holds prompts and tools during an emergency stop or over a hard budget; audit `held` line | Low (WS-AI-025, WS-AI-019) |
| `config-change.sh` | The changed settings or skill file path | Audit `config-change` line | Low (WS-AI-014) |
| `ws-routing.sh` | The prompt, `rules.conf` | Holds the text in `$XDG_RUNTIME_DIR/ws-routing/` (0600) until the owner answers | Low (WS-AI-020) |
| `intent-route.sh` | The prompt, language packs | A context note suggesting a subagent | Low |
| `guard.sh` | Tool input | Blocks with exit 2 and logs the block; fails closed, also when it is missing (`onFailure: block`) | Low (WS-SEC-005) |
| `audit.sh` | Tool input, prompt length | `~/.claude/audit/*.jsonl`: commands redacted, URLs without query string, search queries, 500 redacted characters of MCP input; hash chain with anchors on the Windows side; 395 days | Medium (WS-SEC-010, WS-SEC-011) |
| `read-convert.sh` | Office and PDF files | Converted Markdown, announced as document data | Low |
| `lint-on-edit.sh` | The edited file | Findings as context | Low |
| `ws-sandbox-notice.sh` | Command result | `~/.local/share/ws-telemetry/raw/sandbox-*.jsonl` | Low |
| `win-notify.sh` | Event, pane text | Windows notification; calls `ws-telegram notify`, which sends redacted text to Telegram | Medium (WS-AI-007, WS-SEC-009) |
| `tmux-state.sh`, `ws-traces.sh` | Event metadata | tmux options; trace lines without content | Low |

Maps to: WS-GOV-002, WS-AI-012, WS-AI-024 (NIST-AI-RMF:MAP-4.1, CSF:ID.AM-07, NSA-AIDATA:BP1, ISO42001:A.7).

## Instructions, plugins and skills

<!-- ai-bom:begin plugins -->
| Plugin or marketplace | Setting | Value |
|---|---|---|
| `claude-security@claude-plugins-official` | `enabledPlugins` | enabled |
<!-- ai-bom:end plugins -->

| Item | Source | Notes | Risk |
|---|---|---|---|
| `~/.claude/CLAUDE.md` | [files/home/.claude/CLAUDE.md](../../files/home/.claude/CLAUDE.md) | Imports `standards.md` and a Windows-side `CLAUDE.md` that is not in the repo. The guard lets Claude write it only inside an owner-opened 30-minute window, each write audited (WS-AI-014) | Medium (WS-AI-014) |
| `~/.claude/standards.md` | [files/home/.claude/standards.md](../../files/home/.claude/standards.md) | Working standards loaded into every session | Medium (WS-AI-014) |
| `claude-security@claude-plugins-official` | `settings.json` `.enabledPlugins` | Anthropic's official security-review plugin. `enabledPlugins` enables it but does not download it: the owner installs it in a plain shell (`claude plugin install …`; the guard blocks plugin installs from Claude). Its own sandbox mode does not support WSL2 | Low |
| Skills and slash commands | `files/home/.claude/` | None shipped. `ws-learn commands` writes model-proposed commands to `~/.claude/commands/` after the owner reads and picks them; it refuses to run inside Claude | Medium (WS-AI-014) |
| Shared between accounts | `claude-account` | Skills, plugins, agents, hooks and commands are linked into the personal account | Low (WS-SEC-025) |

tmux plugins and CLI tools are not AI components; they are in the CycloneDX SBOM (`.github/scripts/sbom.py`,
WS-SEC-018).

Maps to: WS-GOV-002, WS-AI-014 (OWASP-ASI:ASI04, CSF:ID.AM-02, CIS-v8:2.1).

## External services

Retention and terms are not in the repository; they are filled in by hand at the monthly review
([REVIEW-CADENCE.md](REVIEW-CADENCE.md)).

| Service | Used by | Endpoint (source) | Data sent | Credential | Retention, terms | Risk |
|---|---|---|---|---|---|---|
| Anthropic, Claude Code | Every session, subagents, `claude -p` in scripts | Managed by Claude Code | The conversation | Claude login per account (`~/.claude/.credentials.json`, denied to agents) | Those of the account's plan: to fill | Medium (WS-AI-022) |
| Anthropic API, `ant` CLI 2.10.0 (`ws-copilot`, SHA-256 verified) | Terminal copilot | Managed by `ant` | The command line, redacted | Console login in `~/.config/anthropic-copilot` (denied to agents) | To fill | Low |
| Telegram Bot API | `ws-telegram` | `api.telegram.org` (`ws-telegram`) | Redacted notifications, command output, summaries | `ws/telegram-bot-token`, PIN `ws/telegram-pin` | Telegram stores the text ([THREAT_MODEL.md](../THREAT_MODEL.md#telegram-remote-control)); terms to fill | Medium (WS-AI-007) |
| Microsoft Learn MCP | `microsoft-learn` | `learn.microsoft.com/api/mcp` (`mcp-servers.json`) | Agent queries | None | To fill | Low |
| Microsoft release communications MCP | `ms-release-comms` | `www.microsoft.com/releasecommunications/mcp` (`mcp-servers.json`) | Agent queries | None | To fill | Low |
| Azure | `azure` MCP; `az` (excluded from the sandbox at the normal level) | Not in the repo | Tool and command arguments | The user's Azure CLI login, or an agent identity under `~/.config/ws-agent/<name>` (`tmux-level --agent`) | Governed by the subscription owner | High (WS-AI-011, WS-SEC-006) |
| npm registry | `ws-pinned install` and `verify --online` | `registry.npmjs.org` | Package requests for the pinned versions | None | - | Medium (WS-AI-009: integrity-checked against the lock) |
| Microsoft 365 connector | Claude account connector, not installed by the kit | Not in the repo | Mail, calendar and files the agent reads or sends | The account's connector login | Governed by the tenant | Medium (WS-AI-005: writes always ask) |
| Cloud sync folder | `ws-backup-cloud` | A OneDrive folder on the Windows side | Backups, encrypted with `age` | `ws/age-backup` | 7 copies kept | Low (WS-SEC-013) |
| GitHub | `ws-kit-update`, `install.sh` (TPM) | `github.com` | Git fetch of release tags | Optional | - | Medium (WS-SEC-015: only tags signed by a key in `allowed_signers` are installed) |

Hugging Face Hub is not contacted at run time (`HF_HUB_OFFLINE=1` for `mempalace` and `recall`).

Maps to: WS-GOV-008, WS-GOV-002 (NIST-AI-RMF:GOVERN-6.1, NIST-AI-RMF:MANAGE-3.1, NIST-600-1:Data Privacy,
CSF:ID.AM-04, CSF:GV.SC-05, CIS-v8:15.1, ISO42001:A.10).

## Known gaps

- The generator checks that every generated row has a hand-written entry, not that the hand-written data and risk
  are still right: those are reviewed monthly (WS-GOV-002).
- MemPalace and recall internals, the Windows-side `CLAUDE.md` and the recall corpus are outside this repository
  (WS-AI-012, WS-AI-024).
- Retention and terms of each external service are not recorded (WS-GOV-008).
- Model aliases in scripts resolve to whatever Claude Code maps them to.
- MCP servers are not confined (no `ws-mcp-jail` yet, WS-AI-011).

Maps to: WS-GOV-002, WS-GOV-008 (NIST-AI-RMF:MANAGE-3.2, CSF:ID.AM-02).
