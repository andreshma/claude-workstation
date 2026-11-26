# 0025. Local MCP servers restarted by a stdio keepalive proxy (ws-mcp-keepalive)

- Status: Accepted
- Date: 2026-11-26

## Context and problem statement

Referred to in code and changelog as ADR-025. It builds on [0024](0024-mcp-server-confinement-and-allow-list.md)
(the jail, `mcp_want`, the managed allow list by exact command) and [0018](0018-supply-chain-pinning-and-signed-releases.md)
(what runs is pinned).

On the owner's machine MemPalace (`mempalace-mcp.exe`) and recall (a Windows venv `python.exe -I -m recall`), both
Windows processes reached through WSL interop over stdio, closed at the same time in the middle of a session. Claude
Code logged no error and did not start them again: they stayed down until `/mcp` → Reconnect or a new session, while
the remote servers came back by themselves. Claude Code's documentation (code.claude.com/docs/en/mcp, «Stdio servers
that exit or fail to start», checked 2026-11-26 against Claude Code 2.1.332) says exactly that: in an interactive
session a stdio server whose process exits mid-session is marked as failed and is started again only from `/mcp`;
`claude -p` and the Agent SDK start it again on the next tool call; remote servers are reconnected with up to five
attempts and exponential backoff, then retried for up to about a day. It documents no setting, environment variable
or health check that restarts a stdio server (the MCP variables are timeouts, batch sizes, the discovery cache and the
protocol revision); `/mcp reconnect all` (2.1.284 or later) is an interactive command, not something a hook or a
script can send to a running session.

The logs Claude Code keeps per server (`~/.cache/claude-cli-nodejs/<project>/mcp-logs-<server>/`, read for this
decision without their conversations) show the failure mode: the drop leaves no line in the stdio server's log, and
on 2026-11-26 at 03:28 local time every running session wrote to its azure and recall logs within 300 ms and those
writes never reached the disk (NUL-filled tails, the audit log too), the signature of the WSL VM stopping uncleanly.
Interop servers are also the first to go when Windows sleeps or WSL interop is interrupted. Nothing in the kit stops
both servers: no script kills processes by name, `tmux-background` and `ws-health` do not touch MCP servers,
`.wslconfig` has `instanceIdleTimeout=-1`. The kit cannot prevent the drop; it can make it recover by itself.

## Decision drivers

- Recover without the owner: a server that can drop must come back within seconds, in every tab at once.
- Never leave Claude Code waiting: a request lost with the old process must be answered (with an error).
- Visible failure: a server in a crash loop must end as failed in `/mcp`, with a reason, not restart forever.
- The wrapper must not hide what runs: the lock, the managed allow list and `ws-update` keep checking the real server.
- Works for Linux servers inside `ws-mcp-jail` and for Windows executables alike; no shell, no new environment.

## Considered options

- **A. Rely on `/mcp` → Reconnect.** Nothing to maintain; but every drop needs the owner in every tab, and nothing
  tells them it happened.
- **B. A transparent stdio keepalive proxy registered as the command (`ws-mcp-keepalive`).** It keeps Claude Code's
  stdio connection open, restarts the process behind it, replays the recorded handshake and announces
  `list_changed`. Works with any stdio server and with the jail; costs one Python process per server and depends on
  the client honouring `list_changed` (documented) and accepting a re-initialised server behind the same connection.
- **C. systemd user services with a socket or a TCP/HTTP bridge.** systemd restarts a crashed process, but Claude
  Code speaks stdio to a process it starts; a bridge would turn local servers into network services (a port to
  protect, one server shared by every tab and profile, against ADR 0021), and WSL does not always run systemd.
- **D. A per-server restart setting in Claude Code.** Not offered (see the context); to be preferred if it appears.

## Decision

Option **B**, as the default for every stdio server of `files/mcp-servers.json` (`"keepalive": true`; `false`
registers a server as before). HTTP servers are unchanged: Claude Code reconnects them.

- `~/.local/bin/ws-mcp-keepalive --name N [--max-restarts 5] [--window 300] [--backoff-max 30] [--notify giveup|all|none]
  -- CMD…` (Python 3, standard library). Newline-delimited JSON-RPC is forwarded byte for byte; the only change is in
  the first `initialize` answer, where the server's tools/prompts/resources capabilities are marked `listChanged`
  so that Claude Code honours the refresh it sends after a restart.
- On an unexpected exit: every request in flight gets a JSON-RPC error (`-32000`, "stopped … being restarted: retry
  the call"); answers of the client to requests of the dead server are dropped; the server starts again after 1 s,
  2 s, 4 s … up to 30 s (reset after 60 s of uptime); the recorded `initialize` is replayed under the proxy's own id
  and its answer swallowed, then `notifications/initialized`, then `notifications/tools/list_changed` (and prompts,
  resources when offered); what the client sent meanwhile is delivered once the new process is ready. If the client's
  own `initialize` was in flight, it is resent as it is instead. Servers on the newer stateless protocol revision
  have no handshake to replay; their held-open notification stream is a request in flight and gets the error, which
  makes Claude Code reopen it.
- More than 5 restarts within 300 s: give up, answer what is pending, `ws-notify`, exit 1 (the server shows as failed).
- The executable behind the wrappers is checked before each restart (device, inode, size, modification time); a
  changed one is restarted only when `ws-pinned local-check` vouches for it, otherwise it gives up (`refused`).
- stderr of the server goes, redacted with the shapes of `ws-redact`, to `~/.local/state/ws-mcp/<name>.log` (0600 in
  a 0700 folder, opened without following links, 1 MiB plus one rotated copy) and to the proxy's stderr (Claude Code's
  own MCP log). Every start, restart, give-up and refusal is a line there; every restart is an `mcp_restart` event and
  a give-up an `mcp_giveup` event in the audit hash chain (through `audit.sh`, metadata only).
- Shutdown: stdin EOF (or SIGINT, SIGTERM, SIGHUP) closes the server's stdin, waits up to 5 s (2 s on a signal; a
  second signal ends it at once), then sends SIGTERM and SIGKILL to its process group and to every descendant; the
  proxy is a child subreaper, so orphans of the server come back to it and are ended. A Windows executable's Linux
  side is ended the same way; its Windows side exits when its stdin closes.
- Composition: `ws-mcp-keepalive --name N -- ws-mcp-jail --name N … -- server` for Linux servers,
  `ws-mcp-keepalive --name N -- server.exe` for Windows ones (`lib.sh` `mcp_want`). `mcp_unwrap` and
  `mcp_unwrap_merge` strip both wrappers (export.sh, install.sh, ws-update). `install.sh` re-registers by itself a
  registration whose unwrapped server is the one the kit wants (no `--mcp-refresh` needed). The lock check stays on
  the server's own command of `mcp-servers.json`; `ws-update` checks the real binary behind the wrappers; the managed
  allow list carries the whole command, wrappers and server included.
- `ws-audit` warns about a stdio server registered without the keepalive and reports the restarts and give-ups of the
  last 24 h from the logs; `ws-health` fails on both; the guard protects `~/.local/bin/ws-mcp-keepalive` and
  `~/.local/state/ws-mcp` (logs and jail state) as hard roots.

## Consequences

- Positive: a server that drops (interop interruption, a crash, an OOM kill) is back within seconds in every tab; the
  call it lost fails visibly instead of hanging; each drop is recorded with its exit status and uptime, which is the
  evidence that was missing for this incident.
- Positive: the jail, the lock and the allow list see the same server as before; nothing reaches the server that was
  not in Claude Code's environment.
- Negative: state the server kept per connection (open resources, subscriptions, a half-done long task) is lost on a
  restart; the error for the lost call says to retry, and a server that cannot be re-initialised with the same
  `initialize` will give up after its retries.
- Negative: one Python process per local server per tab (about 16 MB resident each, measured): with 13 tabs and
  three local servers, some 600 MB; and a small delay at start. `"keepalive": false` on a server gives it back.
- Negative: after the re-registration the managed allow list must be regenerated (`sudo bash install.sh --managed
  --mcp-allowlist`), or Claude Code blocks the new form; `ws-audit` says so.
- Negative: a Windows server's own children are outside Linux's reach; if one does not exit on stdin EOF it is left
  to Windows.
- Negative: not verified live against the real MemPalace and recall (WSL interop is not reachable from the
  implementer's sandbox); the tests use a fake server.

## Alternatives revisited

If Claude Code gains a documented restart policy for stdio servers, switch to it (option D) and set `"keepalive":
false`; keep the logs and the audit events if the new mechanism has none.
