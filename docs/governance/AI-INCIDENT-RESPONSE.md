# AI incident response

What to do when an agent, a model, memory or an AI component misbehaves on a workstation installed from this kit.
The owner is the only responder. Operational failures that are not incidents (a tab that did not come back, a broken
patch) are in the [runbook](../runbook.md). Where a control is still open, its id is named with the manual
fallback next to it ([assessment, Status after phase 2](../compliance/assessment.md#status-after-phase-2)).

## Contents

- [Severity](#severity)
- [Common steps](#common-steps)
- [Prompt injection that acted](#prompt-injection-that-acted)
- [Secret leaked to a model or memory](#secret-leaked-to-a-model-or-memory)
- [Memory poisoning](#memory-poisoning)
- [Malicious or compromised MCP server or plugin](#malicious-or-compromised-mcp-server-or-plugin)
- [Compromised kit update](#compromised-kit-update)
- [Runaway spend](#runaway-spend)
- [Agent acting outside scope](#agent-acting-outside-scope)
- [Post-incident record](#post-incident-record)

## Severity

| Severity | When | Response |
|---|---|---|
| 1 | A secret, client data or a change left the machine: a push, a cloud change, a message, a provider received a secret; or an MCP server or kit update is compromised | Now: every step, rotate credentials |
| 2 | Suspected and still local: the guard or sandbox blocked it, memory holds a bad fact, an agent changed files it should not have | Same day |
| 3 | An anomaly with no effect | Note it; handle at the next monthly review |

Maps to: WS-GOV-003 (CSF:RS.MA-01, CIS-v8:17.4, NIST-AI-RMF:MANAGE-2.3, WAF-SEC:SE:12).

## Common steps

Run them in a plain shell (`Ctrl+b g`), not inside Claude.

**1. Stop the agents.** `ws-stop-all` (also Menu → Claude → Emergency stop) writes a stop marker that holds every
prompt and tool call in every Claude, turns Telegram off, records an audit event and closes the Claude in every tmux
pane; panes still running after 20 seconds are listed by name
([runbook.md, Emergency stop](../runbook.md#emergency-stop)):

```bash
ws-stop-all --reason "suspected injection"   # everything; --kill also ends headless Claude processes
ws-stop-all --pane %12 --yes                 # one tab only (no marker, Telegram stays on)
ws-stop-all --session swarm-<id> --yes       # one swarm
ws-stop-all --status                         # is the marker on?
```

Nothing resumes on its own: `ws-stop-all --clear` removes the marker and `ws-telegram on` turns the phone back on,
both from a terminal (Claude is denied both). If `ws-stop-all` itself cannot run, the fallback is
`ws-telegram off`, `touch ~/tmux_no_auto_restore` and `tmux kill-server`
([runbook.md, Restarting the workstation cleanly](../runbook.md#restarting-the-workstation-cleanly) undoes the
no-restore marker).

**2. Preserve evidence before cleaning.** Run `ws-audit --verify-log` first: the audit log is a hash chain with anchors
on the Windows side, and the command reports any edited, deleted or reordered line without repairing it
([runbook.md, Verifying the audit log](../runbook.md#verifying-the-audit-log)). Then copy, to a folder with mode 0700
outside the repositories:

| Evidence | Where |
|---|---|
| Audit log (tool calls, blocks, denials, held prompts, injection suspects, memory writes, config changes) | `~/.claude/audit/` and `%UserProfile%\ws-telemetry\audit-anchors.txt`; summary with `claude-report <days>`, memory writes with `ws-memory log` |
| Session transcript | `~/.claude/projects/<folder>/<session>.jsonl` |
| Prompts, responses and tool content | `~/.local/share/ws-telemetry/otel/` |
| Sandbox blocks | `~/.local/share/ws-telemetry/raw/sandbox-*.jsonl`; `~/.claude/hooks/ws-sandbox-notice.sh --summary` |
| Telegram events | `~/.local/share/ws-telemetry/telegram/` |
| Facts saved by `ws-learn` and `ws-memory` | `~/.local/share/ws-telemetry/learning/` |
| Anomalies (repeated blocks, denials, sandbox hits per session) | `ws-anomaly --json` |
| Repository history | `git -C <repo> reflog`, `git -C <repo> log --all --since=<time>` |
| A second copy to compare with | `%UserProfile%\.claude-wsl-backup` (conversations and audit log, every 15 minutes) |

The `otel/` copy holds conversation text: keep it as private as the original.

**3. Check for persistence.** An agent that acted may have changed what steers later sessions. The guard blocks the
direct writes (WS-AI-014), but a script or an unsandboxed tab can get past it: look for `config-change` and
`config-write-allowed` lines in the audit log, compare the installed files with the kit and look at what the kit does
not own:

```bash
bash install.sh --dry-run                 # from the kit folder: every file that differs shows as "changed"
ws-verify && ws-audit                     # baseline and drift checks, read-only (pins, gate bypasses, audit chain)
ws-pinned verify                          # pinned npm packages still match their locks
claude mcp list                           # servers not in files/mcp-servers.json are suspect
ls -la ~/.claude/commands ~/.claude/agents .claude/ .git/hooks
```

Maps to: WS-GOV-003, WS-AI-025 (CSF:RS.MA-01, CIS-v8:17.4, NIST-AI-RMF:MANAGE-2.4, OWASP-ASI:ASI10).

## Prompt injection that acted

- **Detect.** An `injection-suspect` line in the audit log (`untrusted-content.sh` found markers in a web page, MCP
  result or network command output); the 🚨 anomaly alert in the status bar or on the phone (repeated blocks,
  denials or sandbox hits in one session); a guard block or a denial in `claude-report`; a commit, branch, push or
  cloud change nobody asked for. Plain-language instructions without markers are labelled untrusted but not flagged.
- **Contain.** [Common steps](#common-steps) 1 and 2. If something was pushed, protect or revert the remote branch
  from the web interface; if a cloud resource changed, assess it yourself with your own session.
- **Eradicate.** Find the source: the audit log keeps the WebFetch URL, the search query and 500 redacted characters of
  each MCP call's input, and the transcript has the content read just before the action. Remove or quarantine it,
  run [common step 3](#common-steps), and check memory as in [Memory poisoning](#memory-poisoning).
- **Recover.** `git revert` the commits; restore changed kit files from `~/.local/share/ws-kit/backup.<date>/` or
  rerun `bash install.sh`; rotate any credential an excluded command could use in that session (`az`, `gh`, `kubectl`
  logins). Resume work at `full` level.

Maps to: WS-GOV-003, WS-AI-001 (OWASP-LLM25:LLM01, OWASP-ASI:ASI01, ATLAS:AML.T0051, CSF:RC.RP-01).

## Secret leaked to a model or memory

- **Detect.** The guard blocked a write with a secret; gitleaks failed in the gate or in CI; `[SECRET]` appears in
  `otel/` files (the collector masked a match, so the value passed through the session); `ws-history` lists history
  lines that look like secrets; a `secret-allowed` line (a prompt sent with `#allow-secret`); the owner pasted one.
  Typed prompts are screened by `prompt-screen.sh`; files the agent reads are not (WS-AI-022).
- **Contain.** Revoke at the issuer first: the provider already has the value. Kit secrets:

  | Secret | Revoke and replace |
  |---|---|
  | Telegram bot token | `ws-telegram forget`, `/revoke` in BotFather, then `ws-telegram setup` ([runbook.md, section 13](../runbook.md#13-telegram)) |
  | Telegram PIN | `ws-telegram text pin` |
  | Backup key | Create a new key with `ws-backup-cloud setup` and keep it in the password manager ([runbook.md, Rotating secrets](../runbook.md#rotating-secrets)) |
  | Any other `ws/<name>` | Rotate at its issuer, then `ws-secret set <name>`; `ws-secret delete <name>` if no longer used |
  | Claude, copilot, cloud and source-control logins | Log out and in again (`claude-account`, `ws-copilot logout`, `az logout`, `gh auth logout`) and revoke sessions at the issuer ([runbook.md, section 5](../runbook.md#5-claude-accounts-work-and-personal)) |

- **Eradicate.** Delete the value from the session transcript, the `otel/` files, the Windows-side copies
  (`.claude-wsl-backup`, `WSL-Backups\lite`) and the Telegram chat. In MemPalace, search for a non-secret part of the
  context (the file or service name, never the value) and delete the drawer or invalidate the fact; both always ask.
  Deletion on the provider side follows the account's terms.
- **Recover.** Check the new value works (`ws-telegram test`, `ws-check`). A rotated backup key does not open older
  cloud backups: keep the old key until they expire.

Maps to: WS-GOV-003, WS-GOV-010, WS-AI-022 (OWASP-NHI:NHI2, OWASP-LLM25:LLM02, CIS-v8:6.2, NIST-AI-RMF:MANAGE-4.3).

## Memory poisoning

- **Detect.** An answer relies on a "fact" or an instruction the owner never set; a fact in MemPalace that is not in
  the `ws-learn` log (`~/.local/share/ws-telemetry/learning/`); `memory-write` lines in `ws-memory log` the owner does
  not remember approving; a fact whose provenance (`source_file` or `added_by`, stamped by `memory-gate.sh` with the
  session, project and time) points at an unexpected session.
- **Contain.** Stop the sessions that loaded it ([common step 1](#common-steps)). To keep new sessions from reading
  or writing memory while you clean, unregister the server and remove the `mempalace.exe` hook entries from
  `~/.claude/settings.json` in a plain shell:

  ```bash
  claude mcp remove mempalace --scope user
  ```

- **Eradicate.** Invalidate or delete the bad facts and drawers (these tools always ask). Find the session that wrote
  them and handle it as a [prompt injection](#prompt-injection-that-acted).
- **Recover.** `bash install.sh` registers the server again and restores the hook entries (the file it replaces is
  backed up first). Run `ws-memory review --older-than 0 --list` to see every fact saved through the approved path.

Maps to: WS-GOV-003, WS-AI-012, WS-AI-013 (OWASP-ASI:ASI06, OWASP-LLM25:LLM04, ATLAS:AML.T0080, NSA-AIDATA:BP1).

## Malicious or compromised MCP server or plugin

- **Detect.** An upstream advisory; `ws-pinned verify` or `ws-audit` reports a pinned package or a local MCP executable
  that no longer matches its pin (`install.sh` then skips it); unexpected tools or behaviour; `claude mcp list` shows a
  server that is not in [files/mcp-servers.json](../../files/mcp-servers.json) (checked by hand: `ws-audit` does not
  fail on it yet, WS-AI-010).
- **Contain.** [Common step 1](#common-steps), then remove it: `claude mcp remove <name> --scope user` (a server from a
  repository's `.mcp.json` is removed from that file). MCP servers run outside the sandbox with the user's files and
  network: revoke what they could reach (for `azure`, `az logout` and revoke the sessions at the identity provider).
  `mempalace` and `recall` run on the Windows side, so a compromise there is a Windows host incident, out of the kit's
  scope.
- **Eradicate.** Remove the installed tree (`~/.local/share/ws-kit/npm/<name>`) and, for an old `npx` registration, the
  `npx` cache (`~/.npm/_npx`); run [common step 3](#common-steps). The kit enables only the official `claude-security`
  plugin ([AI-BOM](AI-BOM.md#instructions-plugins-and-skills)); a plugin is removed with Claude Code's `/plugin` menu.
- **Recover.** Pin a known-good version in `files/home/.local/lib/ws-npm/<name>/` and `files/mcp-servers.lock.json`
  through a pull request ([runbook.md, Pinned npm packages](../runbook.md#pinned-npm-packages)), then
  `bash install.sh --mcp-refresh`; a reviewed local executable is re-pinned with `bash install.sh --mcp-accept <name>`.
  The AI-BOM tables follow (`bash tests/ai-bom.sh`).

Maps to: WS-GOV-003, WS-AI-009 (OWASP-ASI:ASI04, OWASP-MCP3P:governance-workflows, CSF:GV.SC-08,
NIST-AI-RMF:GOVERN-6.2).

## Compromised kit update

- **Detect.** `ws-kit-update` refuses a release (exit 11, a 🚨 Telegram alert): the tag is unsigned or signed by a key
  outside `allowed_signers`; an `applied UNSIGNED` line in `~/.local/state/ws-kit-update.log`; `ws-test` fails after an
  update; hooks or settings changed without a `CHANGELOG.md` entry.
- **Contain.** [Common steps](#common-steps) 1 and 2; do not run `ws-kit-update` again.
- **Eradicate.** In the kit folder, verify the last known-good tag (`git -C <kit> verify-tag <tag>` with the allowed
  signers), compare with it (`git -C <kit> diff <tag>`), check it out and rerun `bash install.sh` (and
  `install.sh --managed` if the drop-in is installed). Hooks run outside the sandbox and can call `ws-secret get`:
  rotate every `ws/<name>` as in [Secret leaked](#secret-leaked-to-a-model-or-memory). If the signing key itself is
  suspect, replace it ([runbook.md, Signing a release](../runbook.md#signing-a-release)).
- **Recover.** Restore personal changes from `~/.local/share/ws-kit/backup.<date>/`
  ([runbook.md, section 16](../runbook.md#16-upgrading)); report the compromise as in [SECURITY.md](../../SECURITY.md).

Maps to: WS-GOV-003, WS-SEC-015 (SSDF:RV.3, CSF:GV.SC-08, OWASP-ASI:ASI04).

## Runaway spend

- **Detect.** The bar's spend alert (`@cburn_warn` 5 and `@cburn_crit` 15 USD per hour in `tmux-watch`); the Telegram
  usage alert (`usage_usd_h`, 15 by default); budget alerts at 80 and 100 percent (`ws-telemetry budgets`). With
  `hard=1` in `budgets.conf`, work in a project at 100 percent is held (`held` audit lines) until
  `ws-telemetry budgets --override <project> [hours]`; a swarm started with `--budget` is stopped when it reaches it.
- **Contain.** Stop the tab or the swarm ([common step 1](#common-steps): `--pane` or `--session`); leave solo mode with
  `tmux-solo normal`.
- **Eradicate.** Find the loop with `ws-telemetry traces --days 1` (a tool failing and retrying, a hook, a swarm, a
  bigger model than the task needs: `cr --explain "<task>"`).
- **Recover.** Resume on a smaller model (`cr -t sonnet "<task>"`); set a budget in
  `~/.config/ws-telemetry/budgets.conf`
  ([runbook.md, Traces, estimation and budgets](../runbook.md#traces-estimation-and-budgets)).

Maps to: WS-GOV-003, WS-AI-019 (OWASP-LLM25:LLM10, OWASP-ASI:ASI08, NIST-AI-RMF:MANAGE-2.4).

## Agent acting outside scope

- **Detect.** Edits outside the task, commands in other repositories, permission prompts for actions nobody asked
  for, guard blocks; the 🚨 anomaly alert; `ws-telemetry prompts --alerts` (a high approval rate, answers under 2
  seconds, new or broad permanent allow rules).
- **Contain.** Press `Esc` and answer no to the pending prompt, or `ws-stop-all --pane <id>`; restart the tab with
  `tmux-level full`.
- **Eradicate.** Review `git -C <repo> status`, `git -C <repo> diff` and the reflog; revert what is out of scope; run
  [common step 3](#common-steps).
- **Recover.** Narrow the next run: a worktree, `full` level, or a read-only subagent (`explorer`, `architect`).

Maps to: WS-GOV-003 (OWASP-ASI:ASI10, OWASP-LLM25:LLM06, NIST-AI-RMF:MANAGE-2.3, CIS-v8:17.4).

## Post-incident record

Within a week of a severity 1 or 2 incident:

| Outcome | Record |
|---|---|
| A control changed or a risk is now accepted | A new ADR from [the template](../adr/template.md), linked from [docs/adr/README.md](../adr/README.md) |
| A new failure mode or recovery step | An entry in [runbook.md](../runbook.md) |
| A threat or residual risk changed | [THREAT_MODEL.md](../THREAT_MODEL.md) and the control's `status`, `gap` and `evidence` in [controls.yaml](../compliance/controls.yaml) |
| A component changed | [AI-BOM.md](AI-BOM.md) |

A severity 3 note goes into the next monthly review. This procedure is rehearsed once a year with
one playbook on a test repository ([REVIEW-CADENCE.md](REVIEW-CADENCE.md)); it has not been rehearsed yet.

Maps to: WS-GOV-003, WS-GOV-006 (CIS-v8:17.8, CIS-v8:17.7, ISO42001:10, NIST-AI-RMF:GOVERN-4.3, SSDF:RV.3).
