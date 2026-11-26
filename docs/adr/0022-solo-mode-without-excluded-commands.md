# 0022. Solo mode keeps every command in the sandbox; network tools are an audited, time-boxed opt-in that asks

- Status: Accepted
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-022. It amends [0016](0016-solo-mode-inside-the-sandbox.md), which put solo
mode inside the sandbox but generated its profile with the normal level's excluded commands
(`~/.config/claude-levels/normal-adds.json`: `az`, `azd`, `gh`, `git push`, `git fetch`, `kubectl`, `terraform`,
`helm`, the database clients, `pwsh.exe`…). In solo the auto-mode classifier approves on its own whatever no `ask`
rule covers, and Claude Code documents that an excluded command "goes through the regular permission flow … in auto
mode, the classifier reviews other excluded commands" ([sandboxing](https://code.claude.com/docs/en/sandboxing.md)).
So in the least supervised mode, `gh`, `az` and `git push` ran outside the sandbox with the owner's credentials, and
only the classifier stood between an injected instruction and them. The compliance assessment kept WS-AI-004 and
WS-SEC-003 open (high risk) for that reason. `tmux-solo --unsandboxed` built its profile separately
(`{"sandbox":{"enabled":false}}` on top of the user settings), so its rules drifted from the other solo profiles.

The question: what should a solo tab do with the commands that normal lets out of the sandbox, without making solo
useless for the work that needs them?

## Decision drivers

- Solo must not self-approve a credentialed network action (OWASP ASI02, ASI03; MCSB v2 AI-5 human-in-the-loop).
- Commands that work inside the sandbox must keep running without prompts, or solo loses its purpose.
- When a solo task truly needs `az` or `gh`, the exception must be explicit, visible, audited and short.
- One generator for every solo variant, so the three cannot drift.

## Considered options

- **A. Keep the exclusions (0016 as written).** No friction; the classifier remains the only control.
- **B. No exclusions in solo, and nothing else.** Network tools fail inside the sandbox; a task that needs them
  must leave solo.
- **C. No exclusions by default, every excluded command an `ask` rule in every solo variant, and an audited,
  time-boxed `--with-network-tools` opt-in that brings the exclusions back.** `ask` rules apply to excluded commands
  in auto mode (the permissions page: "Commands that won't run sandboxed, such as excluded commands, respect the bare
  Bash ask rule as usual"), so the classifier can never approve them.

## Decision

Option **C**.

- `files/home/.config/claude-solo/settings.json` is now `{"sandbox": {"enabled": true, "autoAllowBashIfSandboxed":
  true, "allowUnsandboxedCommands": false}}`: the unsandboxed retry (`dangerouslyDisableSandbox`) is ignored in solo.
- `tmux-level --settings-file solo|solo-net|solo-unsandboxed` generates every variant from that file. Each turns every
  `excludedCommands` entry of `normal-adds.json` into an `ask` rule (`az *` → `Bash(az *)`):
  - `solo.json` (default): no `excludedCommands`. `az`, `gh`, `git push`… run inside the sandbox, where the
    credential folders are hidden and the network is the allow list; if one is attempted, it also asks.
  - `solo-net.json` (`tmux-solo this|new --with-network-tools`): normal's exclusions come back, each one asking.
    1 hour by default, 4 hours at most (`--hours`, `WS_SOLO_NET_HOURS`), the tab is marked 🌐 and `@csolo_net`, and
    `solo-network-tools` is written to the audit log. It cannot be combined with `--unsandboxed`.
  - `solo-unsandboxed.json` (`--unsandboxed`, unchanged otherwise): the sandbox off, the same `ask` rules.
- `ws-profile` and `tmux-level` keep and clear `@csolo_net` like the other solo marks; `tmux-watch` expires it with
  the tab.
- `ws-audit` expects the new solo file exactly and fails when a generated `solo.json` excludes a command or a
  `solo-net.json` excludes one without its `ask` rule.

## Consequences

- Positive: in solo, no credentialed network tool runs without a human, whatever the classifier decides; the default
  solo tab leaves the sandbox for nothing (WS-AI-004 and WS-SEC-003 lose their main gap).
- Positive: the three variants come from one generator and one test (`tests/solo-sandbox.sh`).
- Negative (breaking): a solo task that used `gh pr create`, `az` or `git push` without a prompt now fails inside the
  sandbox or asks; use `--with-network-tools` or the normal level.
- Negative: WebFetch, MCP servers and hooks keep their own egress in solo (see
  [0024](0024-mcp-server-confinement-and-allow-list.md) for the MCP part); a repository's `.claude/settings.json`
  can still add excluded commands, which `ws-audit` reports.
