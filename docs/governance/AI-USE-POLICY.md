# AI use policy

How AI is used on a workstation installed from this kit: what data may reach a model or memory, which models and modes
are approved, what always needs a person, and what is not allowed. The owner of the workstation is the owner of this
policy. Facts about the kit link to the file that implements them; what is still open is named with its control id and
listed in the [assessment](../compliance/assessment.md#status-after-phase-2). The owner confirmed the decisions in this
policy on 2026-11-25; a new decision still to confirm is marked "owner to confirm".

## Contents

- [Purpose and scope](#purpose-and-scope)
- [Data: what may go to models and memory](#data-what-may-go-to-models-and-memory)
- [Approved models and providers](#approved-models-and-providers)
- [Human in the loop](#human-in-the-loop)
- [Protection levels: when to use each](#protection-levels-when-to-use-each)
- [Prohibited uses](#prohibited-uses)
- [Generated code and intellectual property](#generated-code-and-intellectual-property)
- [Impact assessment](#impact-assessment)
- [Review](#review)

## Purpose and scope

- **System.** One owner's WSL2 workstation configured by this kit: Claude Code in every tab and protection level, the
  subagents in [files/home/.claude/agents/](../../files/home/.claude/agents/), the kit scripts that call a model, the
  MCP servers registered from [files/mcp-servers.json](../../files/mcp-servers.json), the hooks that pass session data
  to MemPalace and recall, and the Telegram channel. The full inventory is the [AI-BOM](AI-BOM.md).
- **Out of scope.** AI tools used outside this workstation, and the security of Claude Code, the Claude API and the MCP
  servers themselves ([THREAT_MODEL.md, Out of scope](../THREAT_MODEL.md#out-of-scope)).
- **Precedence.** Law, then the client's contract and policies, then the organisation's policies, then this policy
  ([files/home/.claude/standards.md](../../files/home/.claude/standards.md)). Where a client or organisation AI policy
  is stricter, it applies.

Maps to: WS-GOV-001, WS-GOV-011 (NIST-AI-RMF:MAP-1.1, NIST-AI-RMF:MAP-3.3, NIST-AI-RMF:GOVERN-1.1, ISO42001:5,
ISO42001:A.2, CSF:GV.PO-01, CAF:govern.document-policies, SSDF:PO.1).

## Data: what may go to models and memory

| Class | Examples | May go to | Never goes to |
|---|---|---|---|
| Secrets | Tokens, keys, passwords, connection strings, the Telegram PIN, the backup key | The Windows Credential Manager through `ws-secret` only | Any prompt, model, memory, MCP server, Telegram, telemetry, file in a repository or backup |
| Client confidential | Client code, data, documents, tickets, architecture | What the client's contract allows. If the contract was not checked: the work Claude account only | Anything the contract does not allow. If it was not checked: the personal account, remote MCP queries, memory, Telegram |
| Personal data | Names, e-mails, identifiers of people | Same as client confidential | Same as client confidential |
| Internal | The owner's own code, notes and kit configuration | Any destination in the [AI-BOM](AI-BOM.md#external-services) | - |
| Public | Open-source code, public docs | Any destination | - |

What the kit enforces, and where the owner is the control:

- Secrets: the `deny` rules and the guard stop `ws-secret get` and reads of credential stores; the guard and gitleaks
  stop secrets written to files and commits; `ws-redact` masks text sent to Telegram
  ([THREAT_MODEL.md, Secrets](../THREAT_MODEL.md#secrets)). Typed prompts are screened by
  [prompt-screen.sh](../../files/home/.claude/hooks/prompt-screen.sh): a prompt that seems to carry a secret is blocked
  before it reaches the model; starting it with `#allow-secret` sends it anyway and the audit log records that (never
  the prompt). Files the agent reads are not screened (WS-AI-022), and detection is by pattern: it does not recognise
  personal data.
- Memory: MemPalace receives the transcript path on SessionStart, Stop, PreCompact and SessionEnd, and recall receives
  every prompt (`hooks` in [settings.json](../../files/home/.claude/settings.json), through
  [memory-filter.sh](../../files/home/.claude/hooks/memory-filter.sh) and
  [win-hook.sh](../../files/home/.claude/hooks/win-hook.sh)). What MemPalace keeps from the transcript is decided
  outside this repository. Treat everything typed or read in a session as reaching memory, except what is marked
  private.
- `<private>` tag: wrap text that must not be stored in `<private>…</private>`. `memory-filter.sh` removes those spans
  from what the MemPalace and recall hooks receive (MemPalace gets a redacted copy of the transcript), `memory-gate.sh`
  blocks a memory write that contains the tag, and Claude is told not to store or quote that part. Limits: a
  paraphrase of private text is not recognised (`WS_MEMORY_PRIVATE=skip` keeps such a session out of MemPalace
  altogether), and MemPalace's own miners do not know the tag. Contract-restricted data stays out of the session.
- Memory writes by the agent: every MemPalace write asks, also after "do not ask again" and in solo's auto mode
  ([memory-gate.sh](../../files/home/.claude/hooks/memory-gate.sh) and the ask rules), and the hook stamps the session,
  project and time as provenance. Facts the owner approved go through `ws-learn` and `ws-memory save-facts`, which
  refuse to run inside Claude; `ws-memory review --older-than 90` is the periodic review (WS-AI-012, WS-AI-013).
- Client work and Telegram: notification text leaves the machine redacted but is stored by Telegram. When the contract
  does not allow that provider, run `ws-telegram off` for the duration of that work.
- Local stores: prompts, responses and tool content are kept on disk in `otel/` and in Claude Code transcripts
  ([ADR 0014](../adr/0014-local-opentelemetry-collector.md)). Set `WS_OTEL_CONTENT=0` when a contract forbids keeping
  client content.

Maps to: WS-GOV-001, WS-AI-012, WS-AI-022, WS-AI-023 (NIST-600-1:Data Privacy, MS-RAI:Privacy and Security,
NSA-AIDATA:BP5, WAF-SEC:SE:03, OWASP-LLM25:LLM02, OWASP-ASI:ASI06).

## Approved models and providers

- **Provider.** Anthropic, through Claude Code with the account pinned per project by `claude-account` (`work` in
  `~/.claude`, `personal` in `~/.claude-personal`; [architecture.md, Accounts and profiles](../architecture.md#accounts-and-profiles)). The
  terminal copilot uses a Claude Console login of its own (`ws-copilot login`, kept apart from Claude Code's
  credentials) or falls back to `claude -p`
  ([runbook.md, section 10](../runbook.md#10-floating-windows-ai-in-the-terminal-and-tests)).
- **Models.** Only the models listed in the [AI-BOM](AI-BOM.md#models). Adding a model, a provider or an MCP server
  means an AI-BOM entry first, then the change.
- **Routing.** The first rule in `~/.config/ws-routing/rules.conf` that matches the prompt names a level (`fable`,
  `opus`, `sonnet`, `haiku`); `routing_model` in [ws-routing.sh](../../files/home/.local/lib/ws-routing.sh) turns the
  level into a full model ID (overridable in `~/.config/ws-routing/models.conf`). The hook asks before switching and
  never switches without an answer; it proposes a cheaper model only below `downgrade_max_ctx` (30 %) context
  ([ADR 0009](../adr/0009-model-routing-with-confirmation.md)). `intent-route.sh` only suggests a subagent; subagent
  models are fixed in their front matter.

Maps to: WS-AI-020, WS-GOV-002 (NIST-AI-RMF:MAP-2.1, NIST-600-1:Human-AI Configuration, CAF:govern.document-policies,
ISO42001:A.9).

## Human in the loop

These always need the owner's answer, at every protection level:

| Action | How it is enforced |
|---|---|
| Mutating cloud, IaC, cluster, database, container and Windows-shell commands | `permissions.ask` in [settings.json](../../files/home/.claude/settings.json) |
| Mutating Azure MCP tools; Microsoft 365 send, delete, create, update, move | `permissions.ask` |
| Any memory write (add, update, delete, invalidate…) | `memory-gate.sh` asks every time; `permissions.ask` as a second layer |
| Changing the model of a tab | `ws-routing.sh` confirmation |
| Saving learned facts and generated slash commands | `ws-learn` lists them and the owner picks |
| Running a command from the phone | ▶ Run is offered only for read-only commands of an allow list, needs the PIN and is never offered in `bare` or solo tabs |
| Approving a risky permission dialog from the phone | The PIN (all approvals with `ws-telegram approve pin`); "don't ask again" is never offered as a button |
| Clearing the emergency stop, overriding a hard budget | The owner in a terminal: `ws-stop-all --clear`, `ws-telemetry budgets --override` (denied to Claude) |
| Push to `main`/`master`, forced push, gate bypass, production changes by name | Blocked by `guard.sh`; the owner does them by hand if at all |
| Editing settings, hooks, plugins, profiles, MCP and plugin registrations | Blocked by `guard.sh` and the `Edit` deny rules; the owner does it in a plain shell |
| Editing `CLAUDE.md`, commands, agents and skills | Blocked unless the owner opens a 30-minute window (`date -d '+30 min' +%s > ~/.config/ws-guard/allow-config-writes`); each write is audited |

Owner rules: read the command before approving; prefer answering permission dialogs for `ask` actions on the PC; set
a Telegram PIN (`ws-telegram text pin`), without which risky approvals from the phone are refused; do not approve "do
not ask again" for MCP write tools; merge generated changes only through review on the remote.

Maps to: WS-AI-005, WS-GOV-001 (NIST-AI-RMF:MAP-3.5, NIST-AI-RMF:GOVERN-3.2, NIST-600-1:Human-AI Configuration,
OWASP-ASI:ASI09, MS-RAI:Accountability, ISO42001:A.9).

## Protection levels: when to use each

What each level does is in [USAGE.md, section 11](../USAGE.md#11-protection-levels) and
[THREAT_MODEL.md](../THREAT_MODEL.md#protection-levels-and-the-floor).

| Level | Use it for | Do not use it for |
|---|---|---|
| `full` | Unfamiliar or third-party repositories, reviewing pull requests from others, tasks that read much web or MCP content | Work that needs `az`, `gh`, `git push` or the network |
| `normal` | Daily work on the owner's and the client's repositories; the only level where `az`, `gh`, `git push` and the other excluded commands leave the sandbox | Repositories of unknown origin |
| `bare` | Comparing with stock Claude Code, debugging the kit | Client code; anything unattended |
| Solo mode | Time-boxed work on the owner's own code: auto mode inside the sandbox, in a worktree by default (`tmux-solo new`), back to normal after 4 hours (`@csolo_hours`) | Client code; untrusted repositories; sessions with production credentials loaded |
| Solo `--unsandboxed` | Short, attended work the sandbox cannot do; audited and marked 🔓 in the tab name | Anything else |

Client code runs only in `full` or `normal`. Solo mode still lets the normal level's excluded
commands out of the sandbox, decided by the auto-mode classifier (WS-AI-004); return the tab with `tmux-solo normal`
when the task ends rather than waiting for the expiry. A tab started with `tmux-level … --agent NAME` uses that agent
identity's `az`, `gh` and `kubectl` logins instead of the owner's (WS-AI-026).

Maps to: WS-GOV-012, WS-AI-004 (NIST-AI-RMF:GOVERN-2.2, NIST-AI-RMF:MAP-2.2, NSA-DAISS:Ensure user awareness and
training, ISO42001:A.9).

## Prohibited uses

- Offensive security tooling (exploits, scanners against third parties, credential attacks, command and control,
  malware) except inside an authorised engagement with written scope, and then in an isolated environment without
  this workstation's credentials. The kit's own escape tests (`ws-audit --ai`) are allowed.
- Asking an agent to read credential stores, print secrets, or bypass the `deny` rules, the guard or the git gate.
- Client data on an account, provider or MCP server the client's contract does not allow.
- Agents acting on production; registering an MCP server, plugin or hook that is not in the AI-BOM.
- Using model output to make decisions about people.

Maps to: WS-GOV-001 (NIST-AI-RMF:MAP-1.5, NIST-AI-RMF:GOVERN-1.3, WAF-AI:responsible-ai, MS-RAI:Accountability,
OWASP-ASI:ASI02).

## Generated code and intellectual property

- Generated code is the owner's work: reviewed like any pull request
  ([standards.md](../../files/home/.claude/standards.md)), scanned by `ws-gate`, merged through review on the remote.
- The kit takes no position on ownership of inputs and outputs: the terms of the Claude account in use and the
  client's contract decide it. Check the contract before sending client code to a provider.
- Passages from the recall corpus are reference material: cite them; do not paste them in bulk into deliverables.

Maps to: WS-GOV-001, WS-AI-021 (NIST-600-1:Intellectual Property, SSDF:PW.7, MS-RAI:Accountability).

## Impact assessment

| Item | Assessment |
|---|---|
| Intended use | One developer's coding, review, analysis and operations assistance |
| Benefits | Faster search, code and review; parallel agents on separate branches |
| Cost of wrong output | Confabulated or insecure code merged; a wrong command against a cloud resource; client data sent where the contract forbids; poisoned memory steering later sessions; spend |
| Controls | Review and `ws-gate`; `ask` rules, guard and the production pattern; the data rules above; budgets and alerts |
| Residual risk | [THREAT_MODEL.md, Accepted risks](../THREAT_MODEL.md#accepted-risks) and the open gaps in [controls.yaml](../compliance/controls.yaml) |
| Impact on clients | They receive code reviewed by the owner; AI assistance is disclosed where the contract requires it |
| Decision | Proceed with these controls; reassess at each quarterly review |

Maps to: WS-GOV-011 (NIST-AI-RMF:MAP-3.1, NIST-AI-RMF:MAP-3.2, NIST-AI-RMF:MANAGE-1.1, NIST-AI-RMF:MANAGE-1.4,
ISO42001:4, ISO42001:8, ISO42001:A.5, CAF:govern.assess-risks, MS-RAI:Transparency).

## Review

| Item | Value |
|---|---|
| Owner | The workstation owner |
| Last review | 2026-11-25 |
| Next review | Quarterly, and on the triggers in [REVIEW-CADENCE.md](REVIEW-CADENCE.md) |

Maps to: WS-GOV-001 (NIST-AI-RMF:GOVERN-1.4, ISO42001:A.2).
