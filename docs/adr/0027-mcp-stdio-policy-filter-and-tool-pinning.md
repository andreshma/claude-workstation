# 0027. A policy filter in the stdio path of every local MCP server, with tool-definition pinning

- Status: Accepted
- Date: 2026-11-26

## Context and problem statement

Referred to in code and changelog as ADR-027. It builds on [0024](0024-mcp-server-confinement-and-allow-list.md) (the
jail, `mcp_want`, the managed allow list by exact command) and [0025](0025-mcp-server-keepalive.md) (the keepalive is
already a stdio proxy in front of every local server).

Three gaps of the catalogue had the same root. MemPalace and recall are Windows executables reached through WSL
interop: bubblewrap cannot confine them (ADR 0024), so the only guards on their use were Claude Code's permission
rules and the `memory-gate.sh` hook, whose provenance stamp depends on Claude Code honouring `updatedInput` together
with `ask` (not verified at runtime; WS-AI-012, high risk). Nothing limited which MemPalace tools a tab at the full
level or in solo mode could call, how large an argument or a result could be, or what a result could carry back
(WS-AI-011). And no MCP server's tool list was pinned: a server could change a tool's description, the text the
model reads as instructions, or widen its input schema at any time, the rug pull of OWASP MCP Top 10 `MCP03`, Red
Teaming Manual §4.5.1 and ATLAS `AML.T0110` (WS-AI-031, missing).

Every byte between Claude Code and a local server already passes through a process the kit owns. MCP stdio framing is
one JSON-RPC message per line, so a filter can read requests and answers without understanding the server. The
Claude Code documentation (code.claude.com/docs/en/mcp, read 2026-11-26) says that on a `list_changed` notification
Claude Code fetches the updated list, documents no pinning of tool definitions and sets `CLAUDE_PROJECT_DIR` in the
environment of a stdio server; the environment of the session's shell (here `WS_LEVEL`, `WS_PROFILE`, `WS_MEMORY`,
`CLAUDECODE`) reaches the server, which the tests confirm.

## Decision drivers

- Something deterministic must stand between the agent and MemPalace, independent of hook behaviour the kit cannot
  verify, for the Windows servers that no namespace can confine.
- A changed tool definition must be withheld, not only reported, and only the owner may accept it, never Claude.
- Nothing may break the daily use: an unchanged server, a restart by the keepalive and a kit update that moves a pin
  must keep working without the owner doing anything.
- Python 3 standard library only; fail closed on a broken policy only as far as the built-in policy goes (nothing is
  hidden by mistake, pins stay on).

## Considered options

- **A. A sibling stdio filter, `ws-mcp-filter`, inside the keepalive.** Keepalive → filter → [jail →] server. The
  filter is per server generation and stateless across restarts (its state is on disk), so the keepalive's replay of
  the handshake goes through it unchanged.
- **B. The same logic inside `ws-mcp-keepalive`.** One process fewer, but the keepalive's restart and replay logic
  and the filter's policy would share one 700-line file and one failure mode.
- **C. Hooks only (PreToolUse and PostToolUse on `mcp__.*`).** No new process, but a hook cannot change `tools/list`
  (the changed definition would still reach the model), and output replacement for MCP tools is a hook feature the kit
  would again depend on without a runtime check.
- **D. A Windows-side restriction of MemPalace through a job object or a restricted token, via a PowerShell
  launcher.** It would limit the process itself, but it cannot be tested from the kit's CI or from inside Claude
  Code's sandbox, and MemPalace's own hooks would still run unrestricted.

## Decision

Option A, with a hook for the servers that are not in the stdio path.

- `ws-mcp-filter` (Python, stdlib) is registered by `install.sh` for every stdio server unless `mcp-servers.json` says
  `"filter": false`. It removes from `tools/list`, and refuses calls to, the tools the policy does not allow for this
  tab: `~/.config/ws-mcp/filter.json` (the kit's) and `filter.local.json` (the owner's, which `install.sh` never
  touches), by server, by protection level (`WS_LEVEL`, now set by `tmux-level`, `tmux-solo` and `tmux-swarm`) and by
  profile (`WS_PROFILE`); every allow list that applies must match and deny lists add up, so a level or a profile can
  only narrow. Memory servers honour `WS_MEMORY` (off hides every tool, `wing:W` forces the wing). It caps arguments
  and results, masks the secret shapes of `ws-redact` both ways (never inside image or blob data), refuses `<private>`
  content in memory writes and stamps provenance itself in the fields the tool's input schema has. MemPalace's
  `hook_settings`, `mine` and bulk deletes never pass; at full and solo it is read-only.
- Pinning: the sha256 of each tool (name, title, description, input and output schema, annotations) is kept per
  server in `~/.local/share/ws-kit/mcp-tools.lock.json`, with the kit lock identity of the server's code (the
  package-lock of an npm pin, the trust sha256 of a local executable). The first listing is pinned on first use. A tool
  that is new or changed while the identity stays the same is withheld and its calls refused; the change is stored as
  pending, audited (`mcp_tools_changed`) and notified once. A new identity (the kit moved the pin, or the owner
  re-pinned with `install.sh --mcp-accept`) re-pins, audited. Only `ws-mcp-tools approve NAME`, in a terminal, outside
  Claude, after showing the diff, accepts a change; the guard blocks it from Claude. `pinTools: warn` and `off` exist,
  in the owner's file.
- Remote servers do not pass through the filter: `mcp-pin-gate.sh` runs `ws-mcp-tools check-remote` (MCP Streamable
  HTTP, `tools/list`) in the background at session start and, as a PreToolUse hook on `mcp__.*`, denies a changed tool
  of any server until it is approved. `ws-audit` reports servers without the filter, pending changes and the remote
  check.
- Option D is not built; MemPalace's upstream steps are recorded in WS-AI-012 and WS-AI-013.

## Consequences

- Positive: WS-AI-031 is implemented; WS-AI-012 and WS-AI-011 no longer depend on unverified hook behaviour for the
  MCP path; a full or solo tab cannot write memory at all; recall's and MemPalace's answers are capped and redacted.
- Positive: the policy is data, with an owner layer that survives kit updates and a Settings entry to edit it.
- Negative: one more process per local server and one JSON parse per message (negligible next to the server); the
  allow list of the managed drop-in matches the new command line, so it must be reinstalled after this update.
- Negative: the first listing of a server is trusted; a remote server that changes mid-session is caught at the next
  session start; a server that changes its definitions on every start (none of the kit's do) would need `warn`.
- Maintained from now on: `filter.json` when a server adds tools; the tests in `tests/mcp-filter.sh`.
