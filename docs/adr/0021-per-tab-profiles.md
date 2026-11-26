# 0021. Per-tab profiles: Claude organisation, Azure tenant, credentials and memory per tab

- Status: Accepted
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-021.

The owner works for several clients at once: several Azure tenants and several Claude organisations, each client's
work in its own tmux tabs. Until now the kit knew two Claude accounts (`claude-account`: `work` in `~/.claude`,
`personal` in `~/.claude-personal`, sharing every conversation) and, separately, agent identities (`tmux-level
--agent NAME`, [ADR 0020](0020-agent-scoped-identities.md)) that swap only the `az`, `gh` and `kubectl` folders of one
Claude start. Nothing tied a tab to a client: a hand-typed `az` in a client's tab used the owner's default tenant, a
tab switched to another Claude login still read and resumed the other organisation's conversations, and the
MemPalace hooks filed every tab's transcript into one shared palace that every other tab can read back. Client A's
data could flow into client B's Claude organisation through a resume, a sandboxed `cat` of another transcript, or a
MemPalace search.

The question: how can each tab run with one client's identities end to end (Claude organisation, Azure tenant and
default subscription, gh, kubectl), with its own conversations and memory by default, without a second account
system next to agent identities and without changing how the two existing accounts behave?

## Decision drivers

- Isolation by default: a new client profile shares the kit setup, never conversations, history or memory, unless the
  owner links them explicitly.
- One concept: a profile's credential folders must BE its agent identity, not a parallel store.
- One launch path: every launcher (new tabs, splits, restarts, levels, solo, swarm, tmux-resurrect, `claude-resume`)
  must compute the tab's environment the same way, and the tab's shell must get the same variables.
- The agent must not read any profile's tokens, change a profile, switch the tab's identity or log in.
- `work` and `personal`, `claude-account`, `--agent` and today's menus keep working exactly as before.
- No tenant ids or client names in the public kit; logins stay the owner's, in a terminal.

## Considered options

- **A. Menu over `--agent` only.** Add a menu that picks an agent identity for the tab. Smallest change, but the Claude
  login, the conversations and MemPalace stay shared, so the cross-organisation flow remains.
- **B. A separate Linux user per client.** Strongest isolation; breaks tmux, the hooks, the kit's paths and the daily
  flow (the reason ADR 0020 rejected it).
- **C. One profile per client: a Claude config dir + the agent identity folder + options, selected per tab by one
  library, fenced by the generated level settings (chosen).** Uses `CLAUDE_CONFIG_DIR`, `AZURE_CONFIG_DIR`,
  `GH_CONFIG_DIR` and `KUBECONFIG`, which Claude Code and the CLIs already support; costs a library, a command and
  hooks that honour the profile.
- **D. Separate tmux servers per client.** Natural isolation of environments, but the kit's menus, finder, watcher and
  save/restore all assume one server.

## Decision

Option **C**.

- A profile is `~/.config/ws-profiles/NAME/profile.conf` (`claude_dir`, `tenant`, `subscription`,
  `share_conversations=no|PROFILE`, `memory=off|on|wing:W`, `label`, `colour`; read as data, never sourced), its Claude
  dir `~/.claude-profiles/NAME` and its credentials in `~/.config/ws-agent/NAME/{azure,gh,kube/config}`: **the agent
  identity of the same name**. `tmux-level --agent NAME` stays as the credentials-only case (the tab keeps its Claude
  account and takes NAME's az, gh and kubectl). `work` and `personal` are built in, with no file, and reproduce
  `claude-account` (shared conversations, your usual credentials); `claude-account` is now a wrapper of `ws-profile`
  with the same commands and messages, and `migrate.sh` moves `~/.config/claude-accounts/{active,projects.conf}` into
  the profiles' `default` and `projects.conf` (idempotent, dry-run aware).
- `~/.local/lib/ws-profile.sh` is the only code that knows a profile: `wsp_exports NAME` gives a shell the variables
  (`CLAUDE_CONFIG_DIR`, `AZURE_CONFIG_DIR`, `GH_CONFIG_DIR`, `KUBECONFIG`, `AZURE_TOKEN_CREDENTIALS=AzureCliCredential`
  so the Azure MCP server uses only the profile's `az` login, `WS_PROFILE`, `WS_MEMORY`), `wsp_resolve` the precedence
  for a new shell (project pin > the tab's `@cprofile` > `ws-profile use` > `work`) and `wsp_memory` the memory mode.
  `accounts.sh` applies it to every new shell; the launchers that restart a tab (`ws-profile tab`, `tmux-level`,
  `tmux-claude-restart`, `tmux-solo`, `tmux-swarm`) type `eval "$(ws-profile --export NAME)" &&` before the command,
  so the pane's shell and the Claude it starts agree; launchers that open a new tab rely on the new shell.
- `ws-profile new NAME [--tenant] [--subscription] [--share-with] [--memory]` writes the profile, links the kit setup
  and the MCP registrations into its Claude dir (`.claude.json` per dir; without MemPalace when memory is off) and guides
  each login in the owner's terminal; it refuses to run inside Claude. `ws-profile tab NAME` restarts the tab with the
  profile, keeping its level, and resumes the conversation only when both profiles share a conversation store
  (`claude-resume --new` otherwise, and it says so).
- Fence: `ws-profile --fence NAME` lists what a tab must not read: the conversation data of every other store and every
  profile's Claude login. `claude-resume` (the funnel of every kit launcher) swaps its `--settings` file for the copy
  `tmux-level --fenced` writes with those paths added to `sandbox.filesystem.denyRead` and as `Read` deny rules.
- Credentials: Claude Code 2.1.332 expands `denyRead` globs on Linux when each command starts (its binary logs
  «Expanded denyRead glob … matches -> mounts»; `Edit`/write globs are skipped on Linux). The kit does not depend on
  it: every profile's az, gh and kube folders sit under `~/.config/ws-agent`, denied as a whole; the Claude logins
  `~/.claude-profiles/*/.credentials.json` are denied by the glob in `settings.json`, the managed policy and the guard's
  credential list (the guard expands it per call) and, as literal paths, by the fence of every launched tab.
- Memory: `WS_MEMORY` (or, without it, the profile of `CLAUDE_CONFIG_DIR`, failing closed to `off` for a dir under
  `~/.claude-profiles`) is honoured by `memory-filter.sh` (`off`: the MemPalace hooks get nothing; `wing:W`: a copy of
  the transcript whose `cwd` is `/ws-profile/W`, since MemPalace names the wing after the cwd's last folder) and by
  `memory-gate.sh` (`off`: every MemPalace tool is blocked, reads too; `wing:W`: the wing is forced on the tools that
  take one and the others are blocked). The recall (books) hook is unaffected.
- Guard: in a custom profile's tab, changing `CLAUDE_CONFIG_DIR`, the credential variables or
  `AZURE_TOKEN_CREDENTIALS`, `env -i`, `az login|logout`, `gh auth login|logout|switch|refresh|setup-git` and `claude
  auth login|logout|setup-token` are blocked; in every tab, `WS_PROFILE`/`WS_MEMORY` and the mutating `ws-profile` and
  `claude-account` commands are blocked, and `~/.config/ws-profiles`, the profiles' Claude settings and the library
  are hard-protected. `ws-audit` warns on two profiles with the same tenant and subscription, an isolated profile that
  links conversations, a credential the sandbox could read and a tab whose profile is missing.
- The tab shows the label of a custom profile in the status bar (`@cprofile_label`) and in `tmux-find`; Menu → Claude
  → Profile lists the profiles (a dynamic `display-menu`) and switches the tab.

## Consequences

- Positive: a client's tab talks to that client's Claude organisation and Azure tenant only, for Claude, the Azure MCP
  server, and every `az`, `gh` and `kubectl` typed in it; its conversations and memory stay out of the other
  organisations unless the owner links them.
- Positive: agent identities and profiles are one store; `--agent` and the two accounts behave as before.
- Positive: the protection of the logins does not depend on the sandbox's glob support.
- Negative: a `claude` typed by hand (the strict base) has no fence, and a tab restored by tmux-resurrect returns to
  its folder's profile (pin or default), not to one given by `ws-profile tab`: pin client repositories.
- Negative: with `memory=wing:W` the MemPalace hooks receive a rewritten copy of every transcript on every hook; the
  copy is per session and replaced, but it costs a full read of the transcript each time.
- Negative: SSH keys, the Docker config, AWS and database clients are shared by every profile; profile isolation does
  not cover them.
- Negative: that `AZURE_TOKEN_CREDENTIALS=AzureCliCredential` pins the Azure MCP server to the profile's login, and that
  each login lands in the intended tenant and organisation, must be verified live by the owner; the tests use fakes.
- Supersedes in part [ADR 0020](0020-agent-scoped-identities.md): its "new tabs, solo mode and swarms do not take
  `--agent`" no longer holds for profiles, whose credentials reach every launcher.
