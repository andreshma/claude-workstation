# Review cadence

What the owner reviews, when, how, and what each review leaves behind as evidence. The machine-checkable part runs on
its own: `tests/compliance.sh` and `tests/ai-bom.sh` on every push, the monthly workflow
`.github/workflows/compliance-monthly.yml` (catalogue, AI-BOM and the OWASP LLM and agentic editions), and
`ws-audit --compliance` on the workstation for the checks that need it (WS-GOV-005). The rest is manual; each review's
evidence is a commit and a line in the [review log](#review-log). The cadences below are the owner's decisions,
confirmed on 2026-11-25.

## Contents

- [Calendar](#calendar)
- [Monthly](#monthly)
- [Quarterly](#quarterly)
- [On every major Claude Code release](#on-every-major-claude-code-release)
- [Yearly](#yearly)
- [On events](#on-events)
- [Review log](#review-log)

## Calendar

| Cadence | What | Evidence |
|---|---|---|
| Monthly | `ws-audit --compliance`, [AI-BOM](AI-BOM.md), version pins, spend, approvals, memory | The monthly workflow run; `~/.local/share/ws-telemetry/compliance.json`; commit `docs(governance): monthly review YYYY-MM`; review log line |
| Quarterly | [Threat model](../THREAT_MODEL.md), [frameworks' editions](../compliance/frameworks.md), [controls.yaml](../compliance/controls.yaml) statuses, [AI use policy](AI-USE-POLICY.md) | "Review" table of the threat model; `assessed` date in `controls.yaml`; review log line |
| Major Claude Code release | Settings schema, hook contract, CLI flags the kit depends on | `ws-test` and `ws-audit` reports; fixes in a pull request; review log line |
| Yearly | Incident response rehearsal, secret rotation | Rehearsal notes in the review log; rotation dates |

Maps to: WS-GOV-004, WS-GOV-005 (NIST-AI-RMF:GOVERN-1.5, NIST-AI-RMF:MEASURE-1.2, CSF:GV.OV-01, CSF:ID.IM-01,
ISO42001:9, CAF:govern.monitor-risks).

## Monthly

1. **Compliance.** Check the last run of the monthly workflow (a red run names a regressed control or a new framework
   edition, with an issue-ready summary); run `ws-audit --compliance` on the workstation for the `live` checks
   (`ws-test`, `ws-audit --verify-log`, `ws-pinned verify`, `ws-gate bypasses`) and keep `compliance.json`.
2. **AI-BOM.** The tables are generated and checked in CI; review the hand-written columns
   ([AI-BOM.md, How to regenerate](AI-BOM.md#how-to-regenerate)) and fill in retention and terms of the external
   services.
3. **Pins.** Run `ws-update` and `ws-pinned verify --online`: they report newer pinned packages and changed local
   executables; read the changelog before moving a pin through a pull request
   ([runbook.md, Pinned npm packages](../runbook.md#pinned-npm-packages)). Check `VERSION_DEF` of `ant` in
   `ws-copilot`; Dependabot proposes the actions and npm updates. tmux plugins are still cloned unpinned (WS-SEC-016).
4. **Spend.** `ws-telemetry budgets` and `ws-telemetry week`; adjust `budgets.conf` (`hard=1` holds work at 100 %).
5. **Approvals and blocks.** `ws-telemetry prompts` (approvals per hour, answers under 2 seconds, permanent and broad
   allow rules), `claude-report 30`, `ws-anomaly --minutes 43200 --threshold 1 --json` for the month and
   `~/.claude/hooks/ws-sandbox-notice.sh --summary 30`.
6. **Memory.** `ws-memory review --older-than 90` (the weekly report also counts the facts that are due) and
   `ws-memory log --days 30`; invalidate stale or unknown facts.
7. **Notes.** Close severity 3 notes from [AI-INCIDENT-RESPONSE.md](AI-INCIDENT-RESPONSE.md#severity).

Maps to: WS-GOV-002, WS-GOV-008, WS-AI-009, WS-AI-013 (NIST-AI-RMF:MANAGE-3.1, NIST-AI-RMF:MANAGE-3.2, CSF:GV.SC-07,
CIS-v8:15.6, CSF:DE.CM-06).

## Quarterly

1. **Threat model.** Walk [THREAT_MODEL.md](../THREAT_MODEL.md) against the code and the open gaps, including the
   MemPalace and recall assets and the
   [OWASP agentic Top 10 cross-reference](../THREAT_MODEL.md#owasp-agentic-top-10-cross-reference); update its
   [Review](../THREAT_MODEL.md#review) table.
2. **Frameworks' editions.** The monthly workflow checks the OWASP LLM and agentic lists; re-verify every other row of
   [frameworks.md, Sources](../compliance/frameworks.md#sources): a new edition (for example a final SSDF 1.2, an AI
   RMF revision) updates the version notes and, where items change, the `maps_to` entries.
3. **Control statuses.** Re-check `status`, `evidence` and `gap` in `controls.yaml` for every control touched since
   the last review; update `assessed`; regenerate the tables with
   `python3 files/home/.local/lib/ws_compliance.py --write-assessment` (CI fails while they are stale).
4. **Policy.** Re-read [AI-USE-POLICY.md](AI-USE-POLICY.md) against current contracts, confirm the decisions marked
   "owner to confirm", and update its review table.

Maps to: WS-GOV-004, WS-GOV-001, WS-GOV-011 (NIST-AI-RMF:MANAGE-1.2, CSF:ID.RA-03, CIS-v8:16.14, SSDF:PW.2,
ISO42001:6, WAF-SEC:SE:11).

## On every major Claude Code release

`ws-update` runs `claude update`; `claude --version` shows the result. When the major version changes (the same
trigger is in the threat model's review section):

1. **Settings schema.** Check that every key the kit sets still exists and means the same: `model`, `fallbackModel`,
   `modelSettings`, `permissions.allow|ask|deny`, `sandbox` (`failIfUnavailable`, `allowUnsandboxedCommands`,
   `network.allowedDomains`, `filesystem.denyRead`, `autoAllowBashIfSandboxed`),
   `permissions.disableBypassPermissionsMode`, `enableAllProjectMcpServers`, `enabledPlugins`, `hooks` and their events (including `ConfigChange`), `env`,
   `cleanupPeriodDays`, `attribution`, and the managed drop-in folder `managed-settings.d`. Run `claude doctor`.
2. **Hook contract.** The fields the hooks read (`tool_input`, `tool_response`, `prompt`, `transcript_path`, `cwd`),
   exit code 2 as a block, `onFailure`, the per-handler `if`, PostToolUse `additionalContext`, PreToolUse
   `permissionDecision` with `updatedInput`, and UserPromptSubmit `decision: block` (the guard fails closed if input
   changes).
3. **CLI flags.** `--setting-sources` and `--settings` and how `--settings` merges with the other sources (the
   protection levels depend on them), `--permission-mode auto` (solo mode), `-p`, `--tools`,
   `--no-session-persistence` (kit scripts).
4. **Run** `ws-test`, `ws-audit --ai` and `ws-audit --compliance`; keep the reports
   (`~/.local/share/ws-telemetry/audit.md`, `compliance.json`).

Maps to: WS-GOV-005, WS-AI-002 (CSF:ID.IM-01, CIS-v8:4.1, WAF-SEC:SE:01, SSDF:PO.4).

## Yearly

- **Incident rehearsal** (yearly). Run one playbook of
  [AI-INCIDENT-RESPONSE.md](AI-INCIDENT-RESPONSE.md) end to end on a test repository (for example a planted README
  that asks for a push), including `ws-stop-all` and `ws-audit --verify-log`; note the time taken and what was
  missing. Not rehearsed yet.
- **Secret rotation** (Telegram bot token and PIN yearly; backup key only on suspicion). Commands in
  [runbook.md, Rotating secrets](../runbook.md#rotating-secrets); keep an old backup key until every backup encrypted
  with it has expired. Rotate at once when a device or phone is lost. A `ws-audit` warning for old secrets is not
  built yet (WS-GOV-010).

Maps to: WS-GOV-003, WS-GOV-010 (CIS-v8:17.7, OWASP-NHI:NHI7, CIS-v8:6.2, WAF-SEC:SE:12).

## On events

| Event | Review |
|---|---|
| A new model, MCP server, hook, plugin or external service | AI-BOM entry before the change merges |
| A change to a permission rule, the sandbox, the guard, the gate, Telegram, telemetry or backups | The threat model, as [CONTRIBUTING.md](../../CONTRIBUTING.md#documentation) requires |
| A severity 1 or 2 incident | [Post-incident record](AI-INCIDENT-RESPONSE.md#post-incident-record) |
| A client contract that restricts AI use | The data rules of the [AI use policy](AI-USE-POLICY.md#data-what-may-go-to-models-and-memory) |

Maps to: WS-GOV-004, WS-GOV-002 (NIST-AI-RMF:GOVERN-1.5, CSF:ID.RA-05, ISO42001:A.6).

## Review log

| Date | Review | Result | Evidence |
|---|---|---|---|
| 2026-11-25 | Initial | Governance documents written (Phase 3 of the hardening) | This folder |
| 2026-11-25 | Phases 2 to 4 closed | Documents brought in line with the phase 2 code; continuous evidence built (Phase 4); 35 implemented, 32 partial, 2 missing, 1 not applicable | `docs/compliance/assessment.md`, `tests/compliance.sh` |
| 2026-11-25 | Owner decisions | Confirmed: client code only in `full` or `normal`; quarterly policy review; yearly incident rehearsal; Telegram token and PIN rotated yearly, backup key on suspicion | `AI-USE-POLICY.md`, this file |

Maps to: WS-GOV-005 (NIST-AI-RMF:MANAGE-4.2, ISO42001:10).
