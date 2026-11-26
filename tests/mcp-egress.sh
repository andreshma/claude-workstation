#!/usr/bin/env bash
#
# tests/mcp-egress.sh — per-server egress for jailed MCP servers (ADR-028, WS-SEC-003, WS-AI-011), in a temporary
# HOME and without bubblewrap (the proxy and the bridge are plain processes here; the jail's part is checked through
# ws-mcp-jail --print):
#   1) the allow list: exact hosts, *.domain wildcards, default ports 443 and 80, explicit ports; a missing server or
#      a broken file is «enforce» with nothing listed
#   2) serve + bridge: a child that only knows HTTPS_PROXY reaches a listed host through CONNECT and an absolute
#      http:// request; an unlisted host gets 403, is logged (0600) and audited once; audit mode lets it through as
#      «would-deny»; the bridge exits with the child's status; report summarises the log
#   3) the jail: --net --egress with an enforce or audit entry drops --share-net and runs the server under the
#      bridge; mode off keeps --share-net; mcp_want registers azure with --egress
#
# Usage: bash tests/mcp-egress.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; T="$(realpath "$T")"
PIDS=()
cleanup() { local p; for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }

P="$ROOT/files/home/.local/bin/ws-egress-proxy"
export HOME="$T/home"; unset XDG_STATE_HOME
export CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt" WS_EGRESS_CONF="$T/egress.json"
mkdir -p "$HOME/.claude/hooks"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"; chmod 755 "$HOME/.claude/hooks/audit.sh"
STATE="$HOME/.local/state/ws-mcp"

echo "== 1. allow list"
cat > "$T/egress.json" <<'EOF'
{"srv": {"mode": "enforce", "hosts": ["login.microsoftonline.com", "*.vault.azure.net", "*.database.windows.net:1433"]}}
EOF
check "an exact host on 443 is allowed" "$P" check srv login.microsoftonline.com:443
check "a wildcard subdomain is allowed" "$P" check srv kv1.vault.azure.net
check "the bare domain of a wildcard is not" bash -c "! '$P' check srv vault.azure.net"
check "a listed host on another port is refused" bash -c "! '$P' check srv login.microsoftonline.com:8443"
check "an explicit port entry allows that port" "$P" check srv db1.database.windows.net:1433
check "…and only that port" bash -c "! '$P' check srv db1.database.windows.net:443"
check "an unlisted host is refused" bash -c "! '$P' check srv evil.example"
check "a server without an entry is enforce with nothing listed" bash -c "! '$P' check other login.microsoftonline.com"
echo '{broken' > "$T/broken.json"
check "a broken file is enforce with nothing listed" bash -c "! WS_EGRESS_CONF='$T/broken.json' '$P' check srv login.microsoftonline.com"

echo "== 2. serve + bridge"
# A local upstream that answers «hello» to anything, on 127.0.0.1 and 127.0.0.2.
cat > "$T/up.py" <<'EOF'
import socket, sys, threading
def serve(addr, out):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((addr, 0)); s.listen(8)
    open(out, "w").write(str(s.getsockname()[1]))
    while True:
        c, _ = s.accept(); c.recv(4096); c.sendall(b"HTTP/1.0 200 OK\r\n\r\nhello"); c.close()
threading.Thread(target=serve, args=("127.0.0.2", sys.argv[2]), daemon=True).start()
serve("127.0.0.1", sys.argv[1])
EOF
python3 "$T/up.py" "$T/port1" "$T/port2" & PIDS+=($!)
for _ in $(seq 50); do [[ -s "$T/port1" && -s "$T/port2" ]] && break; sleep 0.1; done
P1="$(cat "$T/port1")"; P2="$(cat "$T/port2")"
printf '{"srv": {"mode": "enforce", "hosts": ["127.0.0.1:%s"]}}\n' "$P1" > "$T/egress.json"
mkdir -p "$STATE"
# The jail uses a Unix socket; a sandbox that forbids creating one (Claude Code's own) gets the loopback TCP
# transport, which runs the same proxy code.
SOCK="$STATE/egress.sock"
if python3 -c 'import socket; socket.socket(socket.AF_UNIX)' 2>/dev/null; then
  python3 "$P" serve --name srv --socket "$SOCK" & PIDS+=($!)
  for _ in $(seq 50); do [[ -S "$SOCK" ]] && break; sleep 0.1; done
  check "serve listens on a 0600 Unix socket" bash -c "[[ -S '$SOCK' && \$(stat -c %a '$SOCK') == 600 ]]"
else
  echo "  note Unix sockets are not permitted here: the loopback TCP transport is used for this section"
  SOCK="tcp:127.0.0.1:$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  python3 "$P" serve --name srv --socket "$SOCK" & PIDS+=($!)
  for _ in $(seq 50); do python3 -c "import socket,sys; socket.create_connection(('127.0.0.1', int(sys.argv[1])), 1)" "${SOCK##*:}" 2>/dev/null && break; sleep 0.1; done
fi
# The child: what a server does through HTTPS_PROXY (CONNECT, then a request inside the tunnel) and HTTP_PROXY.
cat > "$T/child.py" <<'EOF'
import os, socket, sys
u = os.environ["HTTPS_PROXY"].rsplit(":", 1)
def connect(target):
    s = socket.create_connection((u[0].split("//")[1], int(u[1])), timeout=10)
    s.sendall(f"CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n\r\n".encode())
    head = s.recv(4096).decode()
    if " 200 " not in head.split("\r\n")[0]:
        return head.split("\r\n")[0]
    s.sendall(b"GET / HTTP/1.0\r\n\r\n")
    return s.recv(4096).decode().split("\r\n\r\n")[-1]
def plain(url):
    s = socket.create_connection((u[0].split("//")[1], int(u[1])), timeout=10)
    s.sendall(f"GET {url} HTTP/1.1\r\nHost: x\r\n\r\n".encode())
    return s.recv(4096).decode().split("\r\n\r\n")[-1]
print("connect-listed", connect(f"127.0.0.1:{sys.argv[1]}"))
print("connect-unlisted", connect(f"127.0.0.2:{sys.argv[2]}"))
print("plain-listed", plain(f"http://127.0.0.1:{sys.argv[1]}/x"))
print("node", os.environ.get("NODE_USE_ENV_PROXY"))
sys.exit(7)
EOF
python3 "$P" bridge --socket "$SOCK" -- python3 "$T/child.py" "$P1" "$P2" > "$T/child.out" 2>&1; rc=$?
check "a listed host is reached through CONNECT" grep -q '^connect-listed hello$' "$T/child.out"
check "an unlisted host gets 403" grep -q '^connect-unlisted HTTP/1.1 403 Forbidden$' "$T/child.out"
check "an absolute http:// request to a listed host is forwarded" grep -q '^plain-listed hello$' "$T/child.out"
check "Node is told to use the proxy variables" grep -q '^node 1$' "$T/child.out"
check "the bridge exits with the server's status" test "$rc" == 7
check "decisions are logged (0600)" bash -c "[[ \$(stat -c %a '$STATE/srv.egress.log') == 600 ]] && grep -q ' allow 127.0.0.1:$P1' '$STATE/srv.egress.log' && grep -q ' deny 127.0.0.2:$P2' '$STATE/srv.egress.log'"
check "the denial is in the audit chain" grep -rqs mcp_egress_denied "$T/audit"
printf '{"srv": {"mode": "audit", "hosts": ["127.0.0.1:%s"]}}\n' "$P1" > "$T/egress.json"
python3 "$P" bridge --socket "$SOCK" -- python3 "$T/child.py" "$P1" "$P2" > "$T/child.out" 2>&1
check "audit mode: the unlisted host passes" grep -q '^connect-unlisted hello$' "$T/child.out"
check "…and is logged as would-deny" grep -q " would-deny 127.0.0.2:$P2" "$STATE/srv.egress.log"
check "report lists the hosts with their decisions" bash -c "'$P' report srv | grep -q '127.0.0.2:$P2.*would-deny'"
check "the bridge without a command is a usage error" bash -c "'$P' bridge --socket /x; [[ \$? == 2 ]]"

echo "== 3. the jail"
J="$ROOT/files/home/.local/bin/ws-mcp-jail"
mkdir -p "$T/srv"; printf '#!/bin/sh\nexit 0\n' > "$T/srv/server"; chmod 755 "$T/srv/server"
printf '{"azure": {"mode": "enforce", "hosts": []}}\n' > "$T/egress.json"
out="$(bash "$J" --print --name azure --net --egress -- "$T/srv/server")"
check "egress enforce: no --share-net (only a loopback)" bash -c "[[ '$out' != *--share-net* ]]"
check "egress enforce: the server runs under the bridge on the state socket" bash -c "[[ '$out' == *ws-egress-proxy\ bridge\ --socket\ */ws-mcp/azure/egress.sock\ --\ $T/srv/server* ]]"
printf '{"azure": {"mode": "off"}}\n' > "$T/egress.json"
out="$(bash "$J" --print --name azure --net --egress -- "$T/srv/server")"
check "egress off: the network is shared as before" bash -c "[[ '$out' == *--share-net* && '$out' != *ws-egress-proxy* ]]"
out="$(bash "$J" --print --name azure --net -- "$T/srv/server")"
check "without --egress: shared network (chrome-devtools)" bash -c "[[ '$out' == *--share-net* ]]"
# shellcheck source=../lib.sh
source "$ROOT/lib.sh" 2>/dev/null
w="$(mcp_want "$ROOT/files/mcp-servers.json" azure /h)"
check "azure is registered with --egress" bash -c "jq -e '.args | index(\"--egress\")' <<<'$w'"
check "the kit ships an egress list for azure in audit mode" jq -e '.azure.mode == "audit" and (.azure.hosts | index("login.microsoftonline.com"))' "$ROOT/files/home/.config/ws-mcp/egress.json"
check "ws-egress-proxy and the jail are shellcheck/py_compile clean" bash -c "shellcheck -S warning '$J' && python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' '$P'"

echo
echo "Result: $PASS ok · $FAIL failed"
(( FAIL == 0 ))
