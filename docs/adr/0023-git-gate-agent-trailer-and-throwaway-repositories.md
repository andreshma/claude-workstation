# 0023. Git gate: an Agent-Session trailer on agent commits, and throwaway repositories

- Status: Accepted
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-023. It closes the open part of
[0020](0020-agent-scoped-identities.md) (the commit trailer) and changes the commit-time checks of the git gate
(`ws-gate`, run by the global hooks of `~/.config/git/hooks`).

Two problems. First, a commit made by an agent looked exactly like the owner's: the organisation forbids
`Co-authored-by`, and 0020 left an `Agent-Session` trailer as future work (WS-AI-026). Second, the gate rejected
commits that are not work at all: a test that creates a temporary repository and commits `v1` failed on the
Conventional Commits check, because the owner's global hooks apply to every repository on the machine. Disabling the
gate for such repositories must not become a way for an agent to bypass it for real work.

## Decision drivers

- Attribution without `Co-authored-by` (organisation policy); owner commits from a plain shell stay as they are.
- Conventional Commits must still hold on every commit an agent makes in real repositories.
- Skipping a check must be impossible for a repository with a remote, outside the temp dir, or at push time.
- Secrets, forbidden files and the `Co-authored-by` rule apply everywhere.

## Considered options

- **A. Trailer from `prepare-commit-msg`** (0020's sketch). Runs before the editor, and not for every commit path.
- **B. Trailer from `commit-msg`.** Runs for `-m`, `-F` and the editor, after the message is final; the gate already
  checks the message there.
- **C. Throwaway rule by an environment variable** (a test sets `WS_GATE_SKIP_MSG=1`). Simple, but any agent could
  set it.
- **D. Throwaway rule by location and remotes.** A repository whose working tree and git directory both live under
  `/tmp` or `/var/tmp` and that has no remote at all; at push time every message is checked again.

## Decision

Options **B** and **D**.

- **Trailer.** When the commit runs from a Claude Code session (Claude Code sets `CLAUDE_CODE_CHILD_SESSION=1` in the
  commands it starts; `CLAUDE_CODE_SESSION_ID` carries the session id), `ws-gate commit-msg` adds
  `Agent-Session: <profile>/<session id>` and, under an agent identity, `Agent: <WS_AGENT>`. The profile is
  `WS_PROFILE`, else the one of `CLAUDE_CONFIG_DIR`; values outside `[A-Za-z0-9_-]` become `unknown`. Any existing
  `Agent` or `Agent-Session` line is removed first, so a forged one does not survive (`git interpret-trailers` matches
  keys by prefix, which is why the gate removes and adds instead of replacing). The trailer is added only after the
  message passed, never to the subject. `ws.gate.agentTrailer=false` turns it off in one repository and is logged;
  the guard blocks the agent from setting any `ws.gate.*`.
- **Throwaway repositories.** At commit time, a repository under the temp dir with no remote skips the Conventional
  Commits and lint checks, saying so once per repository (a marker in its git directory). A worktree whose common git
  directory is elsewhere, a repository with any remote, or one outside `/tmp` and `/var/tmp` is never a throwaway.
  `WS_GATE_TEMP_ROOTS` exists for tests and can only narrow the roots (an entry outside `/tmp` or `/var/tmp` is
  ignored). A push from any repository under the temp dir re-checks the message of every pushed commit (and
  `Co-authored-by`), so a scratch repository cannot launder commits into a remote.

## Consequences

- Positive: commits by agents are attributable in `git log` (profile and session, which the audit log and
  transcripts can be joined on), without `Co-authored-by` (WS-AI-026, OWASP ASI03, AIVSS "Agent Untraceability").
- Positive: tests and scratch repositories no longer trip over the owner's hooks; real work keeps every check.
- Negative: the trailer is attribution, not a boundary: a process that unsets the variables commits without it.
  `CLAUDE_CODE_SESSION_ID` is observed in Claude Code's environment but not described in the pages of its
  documentation read on 2026-11-25; without it the trailer says `unknown`.
- Negative: removing existing `Agent:` lines also removes a body line that starts with `Agent:`.
- Tests: `tests/gate-commit-msg.sh`.
