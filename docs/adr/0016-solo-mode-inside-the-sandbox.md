# 0016. Solo mode inside the sandbox, with an expiry

- Status: Accepted
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-016. This record supersedes the part of
[0012](0012-per-tab-protection.md) that defines solo mode as "auto mode without sandbox". The three protection levels
of 0012 and the floor of [0013](0013-minimum-protection-floor.md) are unchanged.

Solo mode (`tmux-solo`) lets Claude work on its own: `--permission-mode auto`, so the auto-mode classifier decides
everything that is not in an `ask` or `deny` rule. Until now its profile turned the sandbox off. The compliance
assessment ([docs/compliance/assessment.md](../compliance/assessment.md), control WS-AI-004, high risk) found that solo
had no egress control, no filesystem confinement beyond the optional worktree, no time limit and no spend cap: the
mode with the least human supervision was also the one with the fewest technical limits. WS-SEC-003 (network egress
per level) had the same gap.

The question: how can solo keep working without prompts while staying inside the same technical limits as a normal
tab, and how can it stop being permanent by accident?

## Decision drivers

- The least supervised mode must not be the least confined one (OWASP ASI02, ASI10; NIST AI RMF MANAGE-1.3).
- Solo must still run commands without a prompt for each one, or it loses its purpose.
- `ask` rules, `deny` rules and `guard.sh` must keep applying (the floor of 0013).
- A tab left in solo mode must return to normal by itself.
- Work that truly needs the sandbox off must remain possible, but visible and audited.

## Considered options

- **A. Keep solo without sandbox** (0012 as written). No friction; the risk stays high and the classifier is the only
  control between an injected instruction and the network or the credentials the sandbox would hide.
- **B. Remove solo mode.** No autonomous mode at all; the owner loses the workflow and would use `bare` or approve
  every command instead, which is worse.
- **C. Solo inside the sandbox with `autoAllowBashIfSandboxed`, an expiry and an audited unsandboxed exception.**
  Commands run without prompts but inside bubblewrap and the network allow list; the excluded commands keep going
  through the classifier; a tmux option sets the expiry.

## Decision

Option **C**.

- `files/home/.config/claude-solo/settings.json` is `{"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true}}`.
  `tmux-level --settings-file solo` merges it with the normal level's additions
  (`~/.config/claude-levels/normal-adds.json`, see [0019](0019-strict-base-and-level-profiles.md)) into
  `~/.config/claude-levels/solo.json` (0600), and `tmux-solo` starts `claude --permission-mode auto --settings <that
  file>`. The excluded commands (az, gh, git push, kubectl…) still run outside the sandbox, decided by the classifier.
- The `ask` rules still ask (terraform, kubectl, cloud, databases, git push, memory writes, `.exe` commands); `deny`
  and `guard.sh` stay.
- **Expiry.** `tmux-solo` sets `@csolo_until` to now plus `@csolo_hours` (default 4, `--hours N` or `WS_SOLO_HOURS`,
  1 to 24). `tmux-watch` returns a tab whose expiry passed to normal (`tmux-solo normal`).
- **Worktree by default.** `tmux-solo new` in a git repository opens a worktree `<repo>.wt/solo-<date>` on branch
  `solo/<date>`; `--here` keeps the old behaviour.
- **Exception.** `tmux-solo this --unsandboxed` generates `solo-unsandboxed.json` (`sandbox.enabled: false`), marks
  the tab `@csolo_nosb` and 🔓 in its name, and records `solo-unsandboxed` in the audit log (`solo-on` otherwise).
- `ws-audit` fails when the solo profile turns the sandbox off and warns when it differs from the shipped one.
- Telegram still offers and runs nothing in a solo tab, sandboxed or not (`ws-telegram` treats `@csolo` like `bare`).

## Consequences

- Positive: in solo mode, commands that are not excluded cannot reach the network outside the allow list or read the
  credential folders; a forgotten tab expires.
- Positive: the unsandboxed variant leaves a trace (audit line, tab name), so it is an exception rather than a habit.
- Negative (breaking): work that relied on the sandbox being off in solo (network to hosts outside the allow list,
  writes outside the project) now fails until the tab is switched or `--unsandboxed` is used.
- Negative: the excluded commands still leave the sandbox in solo after only the classifier's review; WebFetch and MCP
  egress are not confined by this decision (residual in [docs/THREAT_MODEL.md](../THREAT_MODEL.md)).
- Negative: the expiry depends on `tmux-watch` running; without it the tab stays in solo until it is switched back or
  the workstation restarts.
