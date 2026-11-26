# 0019. Strict base settings with level profiles and an optional managed drop-in

- Status: Accepted, amended by [0028](0028-network-per-level-mcp-egress-and-settings-menu.md) (network per level)
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-019. It implements two items that
[0013](0013-minimum-protection-floor.md) decided and left pending in its phase 2: the strict user base with levels
that add, and the managed policy carrying the floor. 0013 itself is not superseded.

Until now `normal` was the user settings as written, including `sandbox.excludedCommands` (az, gh, aws, terraform,
kubectl, remote git, obsidian, database clients…): any Claude, including one typed by hand, ran those commands outside
the sandbox with the owner's credentials. The floor (the `deny` rules and `guard.sh`) lived only in user settings and
in the generated profiles, which the owner's own files, and an agent that could write them, could change. The
compliance assessment ([docs/compliance/assessment.md](../compliance/assessment.md)) rated this WS-AI-003 (missing)
and WS-AI-002 (partial).

Claude Code merges list settings across every source it loads, so a level cannot remove entries by passing an empty
list; it can only add, or not load a source (`--setting-sources project,local`, as `full` and `bare` already do).

## Decision drivers

- The configuration that loads by default must be the strictest one in daily use (least privilege, OWASP ASI02, ASI03).
- The owner's daily work (az, gh, git push from a normal tab) must keep working without extra steps.
- The floor should survive a user-writable file being changed, where the owner accepts a one-time `sudo`.
- An organization's own managed policy must not be overwritten.

## Considered options

- **A. Keep the excluded commands in user settings.** Nothing changes; every Claude, by hand or not, gets the way out.
- **B. Strict base; `normal` adds the exclusions through `--settings` on top of every source (chosen).** Uses the merge
  rule instead of fighting it; a hand-typed `claude` is strict.
- **C. Strict base; `normal` starts with `--setting-sources project,local` and a full generated profile.** Works, but
  then `normal` no longer loads the user settings live, and every change needs a regeneration, as `full` does.
- **D. Managed policy as the only home of the floor.** Strongest, but requires `sudo` on every machine and every
  guard update; it cannot be the default for a public kit.

## Decision

Option **B**, plus an optional managed drop-in.

- `files/home/.claude/settings.json` has no `sandbox.excludedCommands`. They live in
  `files/home/.config/claude-levels/normal-adds.json`, a hard-protected path for `guard.sh` and the `Edit` deny rules.
- `tmux-level --settings-file normal` writes `~/.config/claude-levels/normal.json` (0600) from that file;
  `claude-resume` adds `--settings <normal.json>` whenever the caller passed no `--settings` or `--setting-sources`,
  and every kit launcher starts at normal: through `claude-resume` (new tab, `claude-account`, `tmux-resurrect`,
  `tmux-level normal`, `tmux-bring`, `tmux-recent`, `tmux-claude-restart`, `tmux-template`) or with the same
  `--settings` (`cr`). A `claude` typed by hand loads only the strict base.
- Solo mode uses a generated `solo.json` (the solo settings plus normal's additions,
  [0016](0016-solo-mode-inside-the-sandbox.md)); `full` and `bare` are unchanged: `--setting-sources project,local`
  and a profile generated from `settings.json`.
- `ws-audit` warns when the user settings exclude any command and when a repository's `.claude/settings*.json` adds
  `excludedCommands` or `allow` rules that widen every level.
- **Managed drop-in.** `bash install.sh --managed [--dry-run]` prints every `sudo` command, asks y/N, and installs, as
  root: `/etc/claude-code/managed-settings.d/50-ws-kit.json` (the deny floor, `disableBypassPermissionsMode`,
  `enableAllProjectMcpServers: false` and the guard hook with `onFailure: "block"`), `/etc/claude-code/hooks/guard.sh`
  and `/etc/claude-code/ws-credential-paths.txt`. An existing `/etc/claude-code/managed-settings.json` (an
  organization's) is left alone. A normal install warns when the root copy of the guard is older than the kit's.
- `permissions.disableBypassPermissionsMode: "disable"` is in the user settings, the `bare` profile and the drop-in.

## Consequences

- Positive: only tabs the kit starts at normal (or solo) can run commands outside the sandbox; `full`, `bare` and a
  hand-typed `claude` cannot.
- Positive: with the drop-in installed, the floor no longer depends on files the owner or an agent can write.
- Negative (breaking): a `claude` typed by hand runs strict: az, gh and git push fail inside the sandbox until it is
  started through the kit (`claude-resume`, a new tab, `tmux-level normal`). Tabs running before the upgrade keep the
  old settings in memory and lose the exclusions only when they restart; restart them all through the kit.
- Negative: with the drop-in, the guard runs twice per tool call (user and managed copies, about 40 ms more), and the
  root copy must be refreshed with `install.sh --managed` after each kit update that changes `guard.sh`.
- Negative: a repository's own `.claude/settings*.json` is still loaded in every level; `ws-audit` only warns.
- Unverified at runtime: that `--settings` deep-merges as documented in the installed Claude Code, and the drop-in
  as root (both checked against the documentation and `claude doctor`, not in a live root install).
