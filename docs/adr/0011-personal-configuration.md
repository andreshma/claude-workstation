# 0011. Personal configuration versioned outside the kit

- Status: Accepted
- Date: 2026-11-19

## Context and problem statement

Referred to in code and changelog as ADR-011.

The `claude-workstation` kit belongs to the team: it must not carry one
person's paths, settings or scripts. Personal material (status bar segments,
budgets, routing and Telegram settings, personal templates, the user-level
CLAUDE.md) lived only in `~`. On 19 November `mempalace-tmux.sh` was lost: it
sat uncommitted in a repository and disappeared without a trace.

## Decision drivers

- The kit belongs to the team and must not carry one person's paths, settings or scripts.
- Personal material must not be lost again: it needs history and diffs, not only a backup.
- Nothing that looks like a secret may be committed.
- No new dependency for a small case.

## Considered options

- **A. One private git repository per person, managed by `ws-personal`.**
- **B. Put personal material in the kit as templates.** Mixes one person's data
  with the team's, and it would leak on export.
- **C. Only the encrypted backup (`ws-respaldo-nube`).** Good for recovery, but
  gives no history and no diffs.
- **D. chezmoi/yadm.** Good tools, but one more dependency for a small case;
  `ws-personal` reuses the secrets gate that already exists.

## Decision

Option **A**. One PRIVATE git repository per person
(`<user>/estacion-personal`), managed by `ws-personal`:

- `incluir.txt` lists which paths under `~` are versioned; the copy lives in
  `home/` with its permissions.
- Before every commit: gitleaks (if installed) and `ws-redactar`; if anything
  looks like a secret, there is no commit and a warning is raised.
- Never credentials (`.credentials.json`, `ws-telegram/config`, keys, `.env`).
- `tmux-fondo` syncs once a day; `ws-personal restaurar` brings it back on
  another PC (with a `.bak` backup).
- Personal status bar material lives in `~/.config/ws-local/` (the kit does not
  export it).

## Consequences

- Positive: nothing personal is lost; a new PC ends up identical with
  `install.sh` (team) + `ws-personal restaurar` (yours).
- Positive: the kit stays neutral and suitable for the whole team.
- Negative: one more repository per person; the daily sync depends on the `gh`
  session and on the network.
- Negative: the paths in `incluir.txt` have to be maintained
  (`ws-personal agregar`).
