# 0020. Agent-scoped identities per tab

- Status: Accepted (the commit trailer part is open); amended by [0021](0021-per-tab-profiles.md): an identity is also the credential part of a profile
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-020.

At the normal level the commands excluded from the sandbox (az, gh, kubectl, remote git…) run with the owner's own
sessions: every subscription, repository and cluster the owner can reach is reachable from any normal tab, and in the
cloud and git logs an agent's actions look exactly like the owner's. The compliance assessment
([docs/compliance/assessment.md](../compliance/assessment.md)) rated this WS-AI-026 (partial, medium risk, large
effort) and asked for an ADR on the identity model and on an optional commit trailer.

The question: how can a tab run with credentials scoped to its task, so that both the reach and the attribution of an
agent differ from the owner's, without a new account system in the kit?

## Decision drivers

- Least privilege for non-human identities (OWASP ASI03; OWASP NHI5, NHI8–NHI10; CIS 5.4, 6.8).
- The CLIs already support a configuration folder per process (`AZURE_CONFIG_DIR`, `GH_CONFIG_DIR`, `KUBECONFIG`):
  reuse that rather than proxy credentials.
- The kit must never create, hold or rotate the reduced-scope identities: the owner does, in each provider.
- An agent must not be able to switch back to the owner's credentials from inside the tab.
- The organization's policy forbids `Co-authored-by`; any attribution must use another trailer.

## Considered options

- **A. Nothing in the kit; rely on cloud RBAC only.** No work; the agent keeps the owner's full reach.
- **B. A separate Linux user per agent.** Strong isolation; breaks tmux, the hooks, the kit's paths and the owner's
  daily flow.
- **C. A per-tab identity folder set by `tmux-level`, enforced by the guard (chosen).** Small, uses the CLIs' own
  mechanisms; the strength depends on the scope the owner gives each identity.
- **D. Short-lived tokens minted per task by a broker.** Best practice for fleets; needs infrastructure a single
  workstation does not have.

## Decision

Option **C**, small version.

- `tmux-level full|normal|bare [PANE] --agent NAME` (and `tmux-level --command LEVEL [folder] --agent NAME`) prefixes
  the start command with `WS_AGENT=NAME AZURE_CONFIG_DIR=~/.config/ws-agent/NAME/azure
  GH_CONFIG_DIR=~/.config/ws-agent/NAME/gh KUBECONFIG=~/.config/ws-agent/NAME/kube/config`. The name must match
  `^[a-z0-9][a-z0-9_-]{0,31}$` and the folder must exist. The tab remembers it in the window option `@cagent` for later
  level changes; `--agent none` drops it.
- The owner creates the folder and logs in there, in a plain shell, with a reduced-scope identity (a service
  principal or a user with limited RBAC, a fine-grained GitHub token, a namespaced kubeconfig).
- `guard.sh`, when `WS_AGENT` is set, blocks setting, exporting or unsetting `AZURE_CONFIG_DIR`, `GH_CONFIG_DIR`,
  `KUBECONFIG`, the GitHub and Azure token variables, `--kubeconfig`, `az login` and `gh auth login|switch|refresh|
  setup-git`.
- `~/.config/ws-agent` is in `sandbox.filesystem.denyRead`, in the credential list the guard reads and among the
  hard-protected paths, so a sandboxed command cannot read those logins and no agent can write them.
- **Open:** the optional `Agent-Session: <id>` commit trailer from a `prepare-commit-msg` step in `ws-gate` is not
  built. Until it is, commits from an agent tab are attributed only through the identity used to push and the
  kit's local audit log.

## Consequences

- Positive: a tab started with `--agent` reaches only what its identity is allowed to, and its cloud and GitHub
  actions appear under that identity in the providers' logs.
- Positive: the agent cannot switch the CLIs back to the owner's folders through the commands the guard parses.
- Negative: AWS and database clients are not covered; git over SSH still uses the owner's SSH agent and keys.
- Negative: the owner must create and maintain each identity and its expiry; the kit does not check scopes or age.
- Negative: indirection the guard does not parse (a script that sets the variables) can still reach the owner's
  default folders where the sandbox does not hide them; at the normal level `~/.azure` and `~/.config/gh` are hidden
  only from sandboxed commands, not from the excluded ones.
- Negative: new tabs, solo mode and swarms do not take `--agent` yet; it is applied through `tmux-level`.
