# 0013. A minimum protection floor that no mode turns off

- Status: Accepted
- Date: 2026-11-20

## Context and problem statement

Referred to in code and changelog as ADR-013. This record partly supersedes
[0012](0012-per-tab-protection.md), per-tab protection, and is implemented in phases; see
[Implementation status](#implementation-status).

An adversarial review of the kit (2026-11-20) compared Claude's four start
modes (full, normal, pure and solo mode) with what the code
actually does. ADR-012 starts from a permissive user configuration and each
profile tries to *subtract* permissions with `--settings`. Three promises do
not hold that way:

| Promise | What happens | Why |
|---|---|---|
| The full level is stricter than normal | Very likely they are the same | The profile passes an empty list of commands excluded from the sandbox; lists from different sources are combined, not replaced. Still to be confirmed in a real tab with `/sandbox` |
| The pure level is Claude without the kit | It is more permissive than Claude without the kit | The `deny` and `ask` rules are removed, but the broad `allow` rules are kept |
| There is always a safety net | No control survives every mode | In the pure level nothing of the kit remains; the Telegram channel, the hooks and `!` mode run outside the sandbox at any level |

Other findings from the same review that this ADR must resolve or put on
track:

- The PreToolUse guard fails open (without `jq`, on invalid JSON or on
  timeout) and is evaded with variants of the same command; it also blocks
  harmless quoted text.
- `allow` rules with a wildcard in the middle authorize reading cloud
  credentials without asking.
- Local credentials are protected only by the sandbox: without the sandbox no
  rule prevents reading them.
- The git gate is not active on a fresh install and can be bypassed from the
  agent itself.
- The lint-on-edit hook runs the repository's tools outside the sandbox.
- The tmux status bar and menus interpolate the tab's path and name into shell
  commands.
- Telegram offers to execute commands proposed by the model with a blocklist
  and no PIN.
- Backups and screenshots of the panes are stored in clear text and with no
  expiry.

The per-file, per-line detail is in the review report; only what is needed to
decide is kept here.

## Decision drivers

- What each protection level promises must hold and must be testable.
- At least one control must survive every mode.
- The guard must fail closed and must not be evaded with variants of the same command.
- Credentials must be protected by rules, not only by the sandbox.
- The per-tab switch of ADR-012 must be kept.

## Considered options

| Option | For | Against |
|---|---|---|
| Invert the model: a strict base, and profiles that add (chosen) | See Consequences | See Consequences |
| Keep ADR-012 and only fix the pure level (also remove `allow`) and the documentation of the full level | Little work | The full level still cannot remove exclusions and there is no floor |
| One Claude configuration directory per level | Real isolation | Changes account and credentials; already discarded in ADR-012 |
| Managed policy only, without profiles | The strongest floor | The per-tab switch is lost |

## Decision

Invert the model: the base is strict and the profiles *add*.

1. **Strict user base**: sandbox with no excluded commands and no `allow`
   rules with a wildcard in the middle.
2. **Floor** that goes in the team's managed policy and, as a fallback, in the
   `--settings` of every profile:
   - `deny` on reading credentials (SSH keys, cloud, Kubernetes, GitHub,
     Claude, `ws-secret get`);
   - `deny` on force push, push to `main`, `--no-verify`, changing
     `core.hooksPath` and `ws.gate.*`;
   - `deny` or `ask` on destructive deletions: local, cloud and
     infrastructure;
   - fail-closed production guard (subscription, Kubernetes context,
     workspace);
   - secrets guard when writing files; auditing always on; git gate with
     mandatory gitleaks.
3. **Normal and solo mode add** sandbox exclusions and `allow` rules through
   `--settings`. **The pure level is the floor and nothing else from the
   kit**, with no `allow`.
4. **Telegram**: executing and replying with text require a PIN, use a
   read-only allowlist and are turned off when the tab has no sandbox.
5. **The status bar indicator** is derived from the effective configuration,
   not from a tmux option.
6. **Every promise has its test** in `ws-test`: guard evasions, fail-closed
   behavior, floor present in every profile, folders and tabs with malicious
   names, Telegram allowlist, gate without gitleaks.

## Consequences

- Positive: what each level promises can be tested and no longer depends on
  how the lists are combined.
- Positive: the pure level stops being worse than Claude without the kit.
- Positive: it serves as evidence for the least-privilege, secure
  configuration and human oversight controls of OWASP LLM Top 10, NIST SSDF,
  NIST SP 800-53, CIS Controls and ISO/IEC 27001 that today stand at
  "partial".
- Negative: normal now starts with `--settings`, like the others; a `claude`
  launched by hand ends up in strict.
- Negative: the managed policy requires `sudo` at install time.
- Negative: more permission dialogs until the enumerated `allow` rules are
  tuned.

### Implementation status

- **Phase 1, done:** fail-closed guard and its tests; the floor's `deny`
  rules and no wildcard `allow`; the pure level (`bare`) keeps the floor and
  not the kit's permissions; Telegram does not execute without a sandbox and
  blocks more; lint-on-edit does not run code from the repository; the tab
  path is escaped in the status bar.
- **Full level (`full`), done:** confirmed against the documentation that
  lists are merged across sources; the full level now starts without the
  user settings and with a profile that has no excluded commands.
- **Phase 2, partly done (2026-11-23):** a PIN to execute from Telegram
  (on by default); `install.sh` sets the git hooks path when none is
  configured; per-project reads in the full level; always-ask rules for MCP
  tools; Windows-side credentials hidden from the sandbox.
- **Phase 2, still pending:** managed policy; a read-only allow list for
  commands run from Telegram; escaped paths in the menus; encrypted backups
  with expiry; a status bar indicator derived from the effective
  configuration; a stricter normal level.
