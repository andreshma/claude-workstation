# 0028. Network egress per protection level, an egress proxy for jailed MCP servers, and a Settings menu

- Status: Accepted
- Date: 2026-11-26

## Context and problem statement

Referred to in code and changelog as ADR-028. It amends [0019](0019-strict-base-and-level-profiles.md) (the level
profiles) and [0022](0022-solo-mode-without-excluded-commands.md) (solo mode), and extends
[0024](0024-mcp-server-confinement-and-allow-list.md) (`ws-mcp-jail --net`).

WS-SEC-003 (high risk) was partial: every level had the same sandbox allow list, including `github.com` and
`*.github.com`, hosts that accept data with a token typed into a command (a gist, an issue, a release upload, a push
to an attacker's repository); a host outside the list was prompted for, also in solo mode where nobody is watching;
and a jailed MCP server registered with `--net` (azure) shared the whole network. Claude Code's sandboxing
documentation (code.claude.com/docs/en/sandboxing, read 2026-11-26, Claude Code 2.1.332 installed) documents
`sandbox.network.deniedDomains` ("blocks specific domains even when a broader allowedDomains wildcard would otherwise
permit them", "refused in every permission mode") and `sandbox.network.strictAllowlist` (2.1.219 or later: a host
outside the allow list is refused instead of prompted; it takes effect from managed, `--settings` or user settings, not
from a repository); `deniedDomains` and `strictAllowlist` given with `--settings` are locks a repository cannot lift.
Excluded commands run "outside the sandbox, which means no filesystem restrictions and no network proxy", by design.

Separately, the owner asked that every setting that needs a command be doable from the tmux menu.

## Decision drivers

- Narrow egress where nobody is watching (solo) or where the owner chose the strictest level (full), without breaking
  the normal level the owner works in every day.
- A jailed server's network must be a boundary, not advisory proxy variables; start in audit so nothing breaks.
- Every menu action is an owner action the guard forbids to Claude; secrets never pass through tmux or argv.

## Considered options

- **A. Per-level `deniedDomains` and `strictAllowlist` in the generated profiles, a base deny list in settings.json,
  and for jailed servers an unshared network with a filtering proxy outside the jail.** Uses documented Claude Code
  keys; the jail gets a real boundary.
- **B. A local proxy for every excluded command (`HTTPS_PROXY` in the normal profile).** Excluded commands leave the
  sandbox by design and a variable is advisory: tools that ignore it would still connect.
- **C. Remove `github.com` from the base allow list.** The strongest, but `git fetch` and package installs from GitHub
  inside the sandbox would fail at the normal level every day.

## Decision

Option A, and a Settings submenu backed by one script.

- `settings.json` denies `gist.github.com`, `gist.githubusercontent.com` and `uploads.github.com` at every level.
  `~/.config/claude-levels/network.json` adds, in the profiles `tmux-level` generates: full → `strictAllowlist` and
  `github.com`, `api.github.com`, `codeload.github.com`, `objects.githubusercontent.com` denied; solo and solo-net →
  `strictAllowlist` and `github.com`, `api.github.com` denied (git with the network stays the `--with-network-tools`
  opt-in of ADR 0022). normal adds nothing. Every start also carries `WS_LEVEL=<level>` for the MCP filter (ADR 0027).
- `ws-mcp-jail --egress` (azure in `mcp-servers.json`): the server gets no network of its own (only a loopback); a
  `ws-egress-proxy serve` outside the jail, on a Unix socket in the server's state folder, accepts CONNECT and
  absolute http:// requests for the hosts of `~/.config/ws-mcp/egress.json` (the owner's `egress.local.json` wins);
  `ws-egress-proxy bridge` inside forwards 127.0.0.1 to that socket and sets the proxy variables (and
  `NODE_USE_ENV_PROXY=1`). A client that ignores them cannot connect at all. azure ships in **audit**: unlisted hosts
  pass and are logged as would-deny until the owner switches to enforce after `ws-egress-proxy report`.
  chrome-devtools keeps the shared network (it drives a browser; not verified in the jail with a real Chrome).
- The level of new tabs is `normal` unless the owner chooses `full` (`tmux-level default`, never `bare`).
- `ws-settings` changes one setting per subcommand and publishes current values as `@ws_set_*` options; the menu
  `menu-settings.tmux` (Menu → Settings, `S`) shows them. Owner choices live in files `install.sh` never overwrites
  (`filter.local.json`, `egress.local.json`, `overrides.json`, `copy-days`, the level default). Every changing
  subcommand refuses to run inside Claude, and the guard blocks `ws-settings`, `ws-mcp-tools approve|forget`,
  `tmux-level default|bare`, `tmux-solo`, `ws-telegram`'s settings, `ws-lang` changes, `ws-kit-update` and
  `ws-backup-cloud setup` from Claude, plus writes to the new files. Entries that lower protection or remove something
  confirm first; the backup key and the Telegram PIN are typed only in a terminal popup.
- The menus pass untrusted names on as formats (`##W`, `##{pane_current_path}`, `##{q:pane_current_path}`): a tab or
  folder name can no longer become tmux or shell syntax (WS-SEC-028).

## Consequences

- Positive: egress at full and solo is a strict list a repository cannot widen; azure's network is a real boundary
  once enforced; the owner reaches every setting from the menu.
- Negative: at full and solo, git and package installs from GitHub fail inside the sandbox (by design; normal or
  `--with-network-tools` are the ways out); Claude Code older than 2.1.219 prompts instead of refusing (ws-audit says
  so).
- Negative: still open (WS-SEC-003): excluded commands at the normal level, `github.com` at normal, chrome-devtools, the
  Windows MCP servers, hooks and bare or `--unsandboxed`.
- Maintained from now on: the azure host list, from the egress reports; `network.json` when a level's needs change.
