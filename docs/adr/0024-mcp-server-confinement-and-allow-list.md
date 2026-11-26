# 0024. Local MCP servers in bubblewrap (ws-mcp-jail) and a managed MCP allow list

- Status: Accepted
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-024. It extends [0018](0018-supply-chain-pinning-and-signed-releases.md)
(MCP servers pinned by integrity) and [0019](0019-strict-base-and-level-profiles.md) (the managed drop-in).

Claude Code starts stdio MCP servers outside its sandbox: each one runs with the owner's whole filesystem (SSH keys,
cloud logins, other profiles' credentials, the audit log, the Windows drives) and network, at every protection level
(WS-AI-011, WS-AI-009, WS-SEC-003). Pinning proves which code runs, not what it can reach. Separately, any server a
user, a repository or a plugin registers runs; `ws-audit` found an unlisted server only after the fact (WS-AI-010).
Two of the kit's servers, MemPalace and recall, are Windows executables started through WSL interop.

## Decision drivers

- A compromised or prompt-injected server must not read credentials or other profiles' data (OWASP MCP01, MCP04,
  ASI04; OWASP GenAI Red Teaming Manual 1.0 §4.5.1 "local configuration and credential exposure"; MCSB v2 AI-4).
- Fail closed: a server that should be confined must not start unconfined.
- Honesty: a Windows process cannot be confined by Linux namespaces; say so instead of pretending.
- An allow list must not be widenable by a repository, and must not match by name (Claude Code: "A serverName entry,
  in either list, is not a security control", [managed MCP](https://code.claude.com/docs/en/managed-mcp.md)).

## Considered options

- **A. Run servers inside Claude Code's sandbox.** Not offered by Claude Code for MCP servers.
- **B. A bubblewrap wrapper registered as the server's command.** Works with any stdio server; needs user namespaces.
- **C. Containers (Docker) per server.** Heavier, needs Docker Desktop or a daemon, and network setup per server.
- **D. `allowedMcpServers` by `serverName`.** Easy, but a name can be reused by any command.

## Decision

Options **B** and an allow list by command and URL.

- `~/.local/bin/ws-mcp-jail [--name N] [--net|--no-net] [--azure-config] [--ro P] [--rw P] [--keep-env V] -- CMD…`
  builds the server's view from nothing: read-only system dirs, the kit (`~/.local/bin`, `~/.local/lib`,
  `~/.local/share/ws-kit`), the Linux PATH directories and the server's own package; writable only its state dir
  `~/.local/state/ws-mcp/<name>`; an empty tmpfs HOME, private `/tmp`, `/dev`, `/proc` and `/run` (no WSL interop,
  tmux or SSH agent sockets). Never bound, even when asked with `--ro`/`--rw`: the credential stores of
  `ws-credential-paths.txt`, `~/.ssh`, `~/.claude*`, the audit log, `~/.config/ws-agent`, `~/.config/ws-telegram`,
  telemetry and the Windows drives. `--azure-config` binds only `AZURE_CONFIG_DIR` (`~/.azure` or the tab's own
  `~/.config/ws-agent/<name>/azure`). Token-like environment variables are removed. Network only with `--net`.
- A Windows executable (`.exe` or a PE header) is refused with exit 126; a machine where bubblewrap cannot create
  namespaces refuses to start the server (exit 125).
- `files/mcp-servers.json` carries the policy per server: `"jail": {"net": true, "azureConfig": true}` (azure),
  `"jail": {"net": true}` (chrome-devtools, opt-in), `"jail": false` with a `"jailOptOut"` reason (mempalace and
  recall: Windows executables). `install.sh` registers the wrapped form (`lib.sh` `mcp_want`; `--mcp-refresh`
  replaces an older registration); `export.sh` unwraps it. `ws-audit` warns about a registered local server that is
  neither jailed nor opted out, names the Windows ones as unconfinable, and probes bubblewrap.
- `install.sh --managed --mcp-allowlist` installs `managed-settings.d/55-ws-mcp-allow.json`, generated from
  `mcp-servers.json` (`lib.sh` `mcp_allowlist`): `allowedMcpServers` with the exact `serverCommand` install.sh
  registers or the exact `serverUrl`, and `allowManagedMcpServersOnly: true`, so user, project and local allow lists
  are ignored. Because Claude Code applies it to the claude.ai connectors and plugin servers too, it is opt-in, the
  owner lists the ones they keep in `~/.config/ws-mcp/allow-extra.json`, and the generated list is printed before
  `sudo` asks. `ws-audit` reports a missing list, a widenable one and registered servers it would block.

## Consequences

- Positive: the Azure MCP server and chrome-devtools no longer see SSH keys, other profiles' logins, Claude's
  conversations or the Windows drives (`tests/mcp-jail.sh` proves it with a fake server); registrations outside the
  kit are blocked before they run when the managed list is installed.
- Negative: MemPalace and recall stay unconfined until they run as Linux processes; their risk is accepted and
  reported.
- Negative: `--net` is all or nothing: a jailed server can still reach any host (per-host egress needs a proxy).
- Negative: chrome-devtools under bubblewrap was not verified with a real Chrome; if Chrome does not start, opt it
  out with a reason.
- Negative: the allow list must be regenerated after a kit update that changes an MCP definition; `ws-audit` says
  when.
