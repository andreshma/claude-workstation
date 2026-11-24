# 0012. Three per-tab protection levels for Claude

- Status: Accepted
- Date: 2026-11-20

## Context and problem statement

Referred to in code and changelog as ADR-012. This record is partly superseded by
[0013](0013-minimum-protection-floor.md), which changes what the full and pure levels keep.

The kit adds its own rules on top of Claude Code: the sandbox, an `ask` list
(terraform, kubectl, cloud, databases, docker…), a `deny` list (reading
credentials, deleting repositories…) and the `guard.sh` hook. There was a need
to raise protection to the maximum for delicate work and, in other cases, to
work with Claude as it ships, without the kit's restrictions. Until then only
solo mode (auto mode without sandbox) existed, and it keeps
ask/deny/guard.

## Decision drivers

- Delicate work needs protection raised to the maximum.
- Other work needs Claude as it ships, without the kit's restrictions.
- The switch must affect one tab, not every tab, and must not require editing a file.
- Changing the level must not change the account or the credentials.

## Considered options

- **A. Three levels per tab, switched with `tmux-level`.**
- **B. A global switch in `~/.claude/settings.json`.** Affects every tab and
  forces editing the file.
- **C. Only `--settings` for the pure level.** The ask/deny lists are merged
  across sources, so they cannot be removed that way.
- **D. Another `CLAUDE_CONFIG_DIR`.** Would also change the account and the
  credentials.

## Decision

Option **A**. Three levels per tab with `tmux-level`, which restarts Claude and
resumes the conversation (`claude -c`):

- **Full (`full`):** user configuration + `--settings` with
  `sandbox.enabled=true`, `allowUnsandboxedCommands=false` and no
  `excludedCommands` (no escape hatches). ask/deny/guard remain.
- **Normal:** the user configuration as is.
- **Pure (`bare`):** `--setting-sources project,local` (does not load the user
  rules) + `--settings` with everything else from the user configuration
  EXCEPT `permissions.ask`, `permissions.deny`, the `guard.sh` hook and the
  sandbox. Hooks that do not restrict are kept (status, traces, notifications,
  MemPalace, recall, status bar). The organization's managed settings and the
  repository's `.claude/settings*.json` always apply.

The profiles are generated on every switch from `~/.claude/settings.json`
(always up to date), in `~/.config/claude-levels/` (0600). The status bar
shows 🔒 (full) or 🔓 (pure).

## Consequences

- Positive: one clear switch per tab; the other tabs are untouched; going back
  to normal is one more click.
- Positive: the pure level does not stop measuring: status, traces and
  notifications continue.
- Negative: changing level restarts Claude (it resumes the conversation, but
  whatever was in progress is lost).
- Negative: the pure level depends on `--setting-sources`; if the installed
  Claude version lacks it, the level is not activated and a warning is shown.
- Negative: in the pure level Claude can read credentials or run destructive
  commands if they are approved: this is on purpose.
