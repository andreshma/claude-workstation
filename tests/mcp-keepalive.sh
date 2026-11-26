#!/usr/bin/env bash
#
# tests/mcp-keepalive.sh — ws-mcp-keepalive restarts a local stdio MCP server that exits mid-session (ADR-025,
# WS-GOV-015), in a temporary HOME, with a fake MCP server (Python) that answers initialize, tools/list and tools/call
# and can be told to crash, to crash at start, to die on initialize, to ask the client something or to leave a
# grandchild behind:
#   1) restart: the in-flight request gets a JSON-RPC error, the handshake is replayed (its answer swallowed),
#      tools/prompts list_changed reach the client, a request sent while the server is down is delivered after the
#      restart, a stale answer to the old server is dropped, an orphaned grandchild is ended, initialize answered
#      with listChanged, a line from the server reaches the client byte for byte
#   2) shutdown: stdin EOF stops the server and its tree and exits 0; SIGTERM too
#   3) crash loop: exponential backoff, then give-up (exit 1) with errors for what was pending and a notification
#   4) the executable changed under the session: refused (exit 1) unless ws-pinned vouches for it
#   5) a server that dies while answering the client's own initialize: the client's initialize is resent, not failed
#   6) the log (0600, redacted, never through a link) and the audit chain (mcp_restart, mcp_giveup; still verifies)
#   7) usage: no command (2), missing command (127); jail composition when bubblewrap works here
#   8) registration: mcp_want for every server of files/mcp-servers.json, keepalive opt-out, unwrap round trip,
#      the managed allow list, install.sh's automatic re-registration of a same-server registration
#   9) ws-audit (registered without keepalive, restarts and give-ups of the last 24 h, jail still recognised) and
#      ws-health (an unwrapped server and a give-up fail)
#
# Usage: bash tests/mcp-keepalive.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(realpath "$T")"
PASS=0 FAIL=0 SKIP=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
skip()  { SKIP=$((SKIP+1)); echo "  skip $1"; }
not()   { ! "$@"; }
# tally <file> — counts the driver's «ok <desc>» / «FAIL <desc>» lines.
tally() {
  local s d
  while IFS=$'\t' read -r s d; do
    case "$s" in
      ok) PASS=$((PASS+1)); echo "  ok   $d" ;;
      FAIL) FAIL=$((FAIL+1)); echo "  FAIL $d" ;;
    esac
  done < "$1"
}

K="$ROOT/files/home/.local/bin/ws-mcp-keepalive"
export HOME="$T/home"; unset XDG_STATE_HOME TMUX_PANE
export CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt"
mkdir -p "$HOME/.claude/hooks" "$T/bin" "$T/ctl"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"; chmod 755 "$HOME/.claude/hooks/audit.sh"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/notify.log"\n' "$T" > "$T/bin/ws-notify"; chmod 755 "$T/bin/ws-notify"
export PATH="$T/bin:$PATH"
STATE="$HOME/.local/state/ws-mcp"

# The fake MCP server. Control files in $FAKE_CTL: «crash-at-start» (exits 3 at once), «die-on-init» (exits on the
# next initialize, once). Every start and every message it receives goes to $FAKE_CTL/events.
S="$T/srv/fake-mcp"
mkdir -p "$T/srv"
cat > "$S" <<'EOF'
#!/usr/bin/env python3
import json, os, subprocess, sys, time
ctl = os.environ["FAKE_CTL"]
def ev(t):
    try:
        with open(os.path.join(ctl, "events"), "a") as f:
            f.write(f"{time.monotonic():.3f} {os.getpid()} {t}\n")
    except OSError:
        pass   # inside ws-mcp-jail the control dir is not there
ev("start")
sys.stderr.write("fake server starting token=supersecretvalue123\n"); sys.stderr.flush()
if os.path.exists(os.path.join(ctl, "crash-at-start")):
    sys.exit(3)
def out(m, raw=False):
    sys.stdout.write((m if raw else json.dumps(m)) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    try:
        m = json.loads(line)
    except ValueError:
        ev("nonjson"); continue
    if "method" not in m:
        ev(f"response {m.get('id')}"); continue
    ev(f"recv {m['method']} {m.get('id')}")
    if m["method"] == "initialize":
        f = os.path.join(ctl, "die-on-init")
        if os.path.exists(f):
            os.remove(f); os._exit(9)
        out({"jsonrpc": "2.0", "id": m["id"], "result": {"protocolVersion": "2025-11-25", "serverInfo": {"name": "fake", "version": "1"},
             "capabilities": {"tools": {}, "prompts": {"listChanged": False}}}})
    elif "id" not in m:
        pass
    elif m["method"] == "tools/list":
        out('{"jsonrpc": "2.0",  "id": %s, "result": {"tools": [{"name": "echo", "inputSchema": {"type": "object"}}], "pid": %d}}'
            % (json.dumps(m["id"]), os.getpid()), raw=True)
    elif m["method"] == "tools/call":
        name = m["params"]["name"]
        if name == "crash":
            os._exit(7)
        if name == "orphan":
            subprocess.Popen(["bash", "-c", f"exec -a {m['params']['arguments']['marker']} sleep 300"], start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if name == "ask":
            out({"jsonrpc": "2.0", "id": "s1", "method": "roots/list"})
        out({"jsonrpc": "2.0", "id": m["id"], "result": {"content": [{"type": "text", "text": str(os.getpid())}]}})
    else:
        out({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "no"}})
ev("eof")
EOF
chmod 755 "$S"

# The driver: plays Claude Code against ws-mcp-keepalive and prints «ok|FAIL<TAB>description» lines.
D="$T/driver.py"
cat > "$D" <<'EOF'
import json, os, queue, signal, subprocess, sys, threading, time
scenario, K, S, ctl = sys.argv[1:5]
extra = sys.argv[5:]
def res(ok, d): print(("ok" if ok else "FAIL") + "\t" + d, flush=True)
def events():
    try: return open(os.path.join(ctl, "events")).read().splitlines()
    except OSError: return []
def alive(marker):
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                if marker.encode() in open(f"/proc/{d}/cmdline", "rb").read(): return True
            except OSError: pass
    return False
cmd = [sys.executable, K, "--name", "fake"] + extra + ["--", S]
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
q = queue.Queue()
def rd():
    for line in iter(p.stdout.readline, b""): q.put(line)
    q.put(None)
threading.Thread(target=rd, daemon=True).start()
def send(m): p.stdin.write((json.dumps(m) + "\n").encode()); p.stdin.flush()
def req(i, method, params=None): send({"jsonrpc": "2.0", "id": i, "method": method, **({"params": params} if params else {})})
seen = []
def wait_for(pred, t=8):
    end = time.time() + t
    while time.time() < end:
        for raw, m in seen:
            if pred(m): seen.remove((raw, m)); return m, raw
        try: line = q.get(timeout=0.1)
        except queue.Empty: continue
        if line is None: break
        try: seen.append((line, json.loads(line)))
        except ValueError: seen.append((line, {}))
    return None, None
def by_id(i): return lambda m: m.get("id") == i and "method" not in m
def note(n): return lambda m: m.get("method") == n
def handshake():
    req(1, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}})
    r, _ = wait_for(by_id(1))
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    return r

if scenario == "restart":
    r = handshake()
    res(r is not None and "result" in r, "the client's initialize is answered through the proxy")
    caps = (r or {}).get("result", {}).get("capabilities", {})
    res(caps.get("tools", {}).get("listChanged") is True and caps.get("prompts", {}).get("listChanged") is True,
        "  with tools and prompts marked listChanged (so the refresh after a restart is honoured)")
    req(2, "tools/list"); r2, raw2 = wait_for(by_id(2))
    p1 = (r2 or {}).get("result", {}).get("pid")
    res(raw2 is not None and raw2.startswith(b'{"jsonrpc": "2.0",  "id": 2,'), "a server line reaches the client byte for byte")
    req(3, "tools/call", {"name": "crash", "arguments": {}})
    e3, _ = wait_for(by_id(3))
    res(e3 is not None and e3.get("error", {}).get("code") == -32000 and "restarted" in e3["error"]["message"],
        "the request in flight when the server died gets a JSON-RPC error (the client never waits)")
    req(4, "tools/list")   # sent while the server is down (backoff): held and delivered after the restart
    t, _ = wait_for(note("notifications/tools/list_changed"))
    pr, _ = wait_for(note("notifications/prompts/list_changed"))
    rs, _ = wait_for(note("notifications/resources/list_changed"), t=0.5)
    res(t is not None and pr is not None and rs is None, "tools and prompts list_changed after the restart (resources: not offered, not sent)")
    r4, _ = wait_for(by_id(4))
    p2 = (r4 or {}).get("result", {}).get("pid")
    res(p1 and p2 and p1 != p2, "a request sent while the server was down is answered by the new server")
    ev = events()
    starts = [l for l in ev if l.endswith(" start")]
    rep = [l for l in ev if "recv initialize ws-mcp-keepalive-2" in l]
    ini = [i for i, l in enumerate(ev) if l.endswith("recv notifications/initialized None")]
    res(len(starts) == 2 and rep and len(ini) == 2 and ini[1] > ev.index(rep[0]),
        "the new server got the recorded initialize (the proxy's own id), then notifications/initialized")
    ghost, _ = wait_for(by_id("ws-mcp-keepalive-2"), t=0.3)
    res(ghost is None, "the answer to the replayed initialize is swallowed")
    req(5, "tools/call", {"name": "ask", "arguments": {}})
    a, _ = wait_for(lambda m: m.get("method") == "roots/list")
    wait_for(by_id(5))
    req(6, "tools/call", {"name": "crash", "arguments": {}}); wait_for(by_id(6))
    wait_for(note("notifications/tools/list_changed"))
    send({"jsonrpc": "2.0", "id": "s1", "result": {"roots": []}})   # the answer to a server that is gone
    req(7, "tools/list"); wait_for(by_id(7))
    res(a is not None and not any(l.endswith("response s1") for l in events()),
        "an answer to a request of the old server is dropped, not sent to the new one")
    marker = f"ws-ka-orphan-{os.getpid()}"
    req(8, "tools/call", {"name": "orphan", "arguments": {"marker": marker}}); wait_for(by_id(8))
    res(alive(marker), "  (the fake server left a grandchild in its own session)")
    req(9, "tools/call", {"name": "crash", "arguments": {}}); wait_for(by_id(9))
    wait_for(note("notifications/tools/list_changed"))
    time.sleep(0.3)
    res(not alive(marker), "the orphaned grandchild of the dead server is ended (subreaper, whole tree)")
    req(10, "tools/call", {"name": "orphan", "arguments": {"marker": marker + "b"}}); wait_for(by_id(10))
    p.stdin.close()
    try: rc = p.wait(timeout=10)
    except subprocess.TimeoutExpired: rc = None
    res(rc == 0, "stdin EOF: the proxy stops the server and exits 0")
    res(events()[-1].endswith(" eof"), "  the server saw EOF on its stdin (the MCP shutdown)")
    time.sleep(0.2)
    res(not alive(marker + "b"), "  and no process of the server's tree is left")
elif scenario == "sigterm":
    handshake()
    marker = f"ws-ka-term-{os.getpid()}"
    req(2, "tools/call", {"name": "orphan", "arguments": {"marker": marker}}); wait_for(by_id(2))
    p.send_signal(signal.SIGTERM)
    try: rc = p.wait(timeout=8)
    except subprocess.TimeoutExpired: rc = None
    time.sleep(0.2)
    res(rc == 0 and not alive(marker), "SIGTERM: the proxy ends the server's tree and exits 0")
elif scenario == "crashloop":
    handshake()
    open(os.path.join(ctl, "crash-at-start"), "w").close()
    t0 = time.monotonic()
    req(2, "tools/call", {"name": "crash", "arguments": {}})
    e2, _ = wait_for(by_id(2))
    req(3, "tools/list")   # waits through the backoff; answered with an error on give-up
    e3, _ = wait_for(by_id(3), t=15)
    try: rc = p.wait(timeout=10)
    except subprocess.TimeoutExpired: rc = None
    res(rc == 1, "a crash loop gives up and exits 1 (Claude Code shows the server as failed)")
    res(e3 is not None and "is down" in e3.get("error", {}).get("message", ""), "  what was waiting gets an error that says the server is down")
    st = [float(l.split()[0]) for l in events() if l.endswith(" start")]
    gaps = [round(b - a, 2) for a, b in zip(st, st[1:])]
    ok = len(st) == 4 and all(g >= 0.9 * w for g, w in zip(gaps, [0.2, 0.4, 0.8])) and gaps[1] > gaps[0] and gaps[2] > gaps[1]
    res(ok, f"  after 3 restarts with exponential backoff (gaps {gaps}, expected about 0.2, 0.4, 0.8 s)")
elif scenario in ("changed", "changed-ok"):
    handshake()
    st = os.stat(S); os.utime(S, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))
    req(2, "tools/call", {"name": "crash", "arguments": {}})
    e2, _ = wait_for(by_id(2))
    if scenario == "changed-ok":   # with a ws-pinned that vouches for it
        req(3, "tools/list"); r3, _ = wait_for(by_id(3))
        res(p.poll() is None and r3 is not None and "result" in r3,
            "an executable that changed is restarted when ws-pinned local-check vouches for it")
        p.stdin.close(); p.wait(timeout=10)
    else:
        try: rc = p.wait(timeout=10)
        except subprocess.TimeoutExpired: rc = None
        starts = [l for l in events() if l.endswith(" start")]
        res(rc == 1 and len(starts) == 1, "an executable that changed under the session is not restarted (exit 1)")
elif scenario == "dieinit":
    open(os.path.join(ctl, "die-on-init"), "w").close()
    r = handshake()
    res(r is not None and "result" in r, "a server that dies while answering the client's initialize: the initialize is resent and answered")
    p.stdin.close(); p.wait(timeout=10)
EOF

run() {   # run <scenario> [extra keepalive options] — fresh control dir per scenario
  local rc=0
  rm -rf "$T/ctl"; mkdir -p "$T/ctl"
  FAKE_CTL="$T/ctl" WS_MCP_KEEPALIVE_BACKOFF_MIN=0.2 timeout 90 python3 -I "$D" "$1" "$K" "$S" "$T/ctl" "${@:2}" \
    > "$T/out.$1" 2>&1 || rc=$?
  tally "$T/out.$1"
  if (( rc )); then FAIL=$((FAIL+1)); echo "  FAIL the $1 driver stopped (exit $rc):"; tail -5 "$T/out.$1" | sed 's/^/       /'; fi
}

echo "1) restart, replayed handshake, list_changed, in-flight errors, orphans; 2) shutdown"
run restart
run sigterm
echo "3) crash loop: backoff and give-up"
: > "$T/notify.log"
run crashloop --max-restarts 3 --window 60 --backoff-max 0.8
check "  and the owner is notified (ws-notify)" grep -q 'MCP fake is down' "$T/notify.log"
echo "4) the executable changed under the session"
run changed --backoff-max 0.5
check "  the log says why" grep -q ' refused .*changed since this session started it' "$STATE/fake.log"
printf '#!/bin/sh\n[ "$1" = local-check ] && exit 0\nexit 1\n' > "$T/bin/ws-pinned"; chmod 755 "$T/bin/ws-pinned"
run changed-ok --backoff-max 0.5
rm -f "$T/bin/ws-pinned"
echo "5) the client's own initialize in flight"
run dieinit

echo "6) log and audit"
L="$STATE/fake.log"
check "the log is ~/.local/state/ws-mcp/<name>.log, mode 600, in a 700 folder" \
  bash -c "[[ \$(stat -c %a '$L') == 600 && \$(stat -c %a '$STATE') == 700 ]]"
check "every restart is a line in the log (name, exit status, uptime, delay)" grep -qE ' restart name=fake n=[0-9]+ exit=7 uptime=[0-9]+s delay=' "$L"
check "the server's stderr is in the log, redacted" bash -c "grep -q 'fake server starting token=\*\*\*' '$L' && ! grep -q supersecretvalue123 '$L'"
check "a give-up is a line in the log" grep -q ' giveup name=fake' "$L"
check "restarts are mcp_restart events in the audit chain (metadata only)" \
  bash -c "cat '$T/audit'/*.jsonl | jq -e -s 'map(select(.ev == \"mcp_restart\")) | length >= 3 and all(.[]; (.reason | startswith(\"fake n=\")) and (has(\"cmd\") | not))'"
check "a give-up is an mcp_giveup event" bash -c "cat '$T/audit'/*.jsonl | jq -e -s 'any(.[]; .ev == \"mcp_giveup\")'"
check "the audit chain still verifies (ws-audit --verify-log)" python3 -I "$ROOT/files/home/.local/bin/ws-audit" --verify-log "$T/audit"
rm -f "$L"; ln -s "$T/target" "$L"
FAKE_CTL="$T/ctl" python3 -I "$K" --name fake -- "$S" </dev/null >/dev/null 2>&1
check "a log planted as a link is never written through" test ! -e "$T/target"
rm -f "$L"
dd if=/dev/zero of="$L" bs=1024 count=1100 status=none; chmod 600 "$L"
FAKE_CTL="$T/ctl" python3 -I "$K" --name fake -- "$S" </dev/null >/dev/null 2>&1
check "the log is capped: over 1 MiB it rotates to <name>.log.1" bash -c "[[ -s '$L.1' && \$(stat -c %s '$L') -lt 100000 ]]"

echo "7) usage and composition"
python3 -I "$K" --name fake </dev/null >/dev/null 2>&1; rc=$?
check "no server command: usage error (exit 2)" test "$rc" -eq 2
python3 -I "$K" --name fake -- "$T/none" </dev/null >/dev/null 2>&1; rc=$?
check "a command that does not exist: exit 127 at once, no restart loop" test "$rc" -eq 127
python3 -I "$K" --name 'Bad Name!' -- "$S" </dev/null >/dev/null 2>&1; rc=$?
check "an invalid name is refused (exit 2)" test "$rc" -eq 2
check "no shell anywhere (shell=False only)" not grep -nE 'shell=True|os\.system|os\.popen' "$K"
check "the environment is passed as given (no env= on the server's Popen)" \
  bash -c "! sed -n '/class Child/,/def _stdout/p' '$K' | grep -q 'env='"
J="$ROOT/files/home/.local/bin/ws-mcp-jail"
if bash "$J" --probe 2>/dev/null; then
  mkdir -p "$HOME/.local/share/ws-kit/npm/fake/node_modules/.bin" "$HOME/.local/lib"
  cp "$S" "$HOME/.local/share/ws-kit/npm/fake/node_modules/.bin/fake"
  cp "$ROOT/files/home/.local/lib/ws-credential-paths.txt" "$HOME/.local/lib/"
  r="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
       | FAKE_CTL="$T/ctl" python3 -I "$K" --name fake -- "$J" --name fake -- "$HOME/.local/share/ws-kit/npm/fake/node_modules/.bin/fake" 2>/dev/null)"
  check "keepalive outside, jail inside: the jailed server answers through both" grep -q '"serverInfo"' <<<"$r"
else
  skip "keepalive around ws-mcp-jail: bubblewrap cannot create namespaces here (nested sandbox?)"
fi
check "python3 -m py_compile ws-mcp-keepalive" python3 -c "import py_compile, sys; py_compile.compile(sys.argv[1], cfile='$T/k.pyc', doraise=True)" "$K"

echo "8) registration (lib.sh mcp_want, install.sh, export.sh)"
want() { bash -c 'source "$1/lib.sh"; mcp_want "$2" "$3" "$4"' _ "$ROOT" "${2:-$ROOT/files/mcp-servers.json}" "$1" /home/u; }
M="$ROOT/files/mcp-servers.json"
for n in $(jq -r 'keys[]' "$M"); do
  w="$(want "$n")"
  if [[ "$(jq -r --arg n "$n" '.[$n].type // "stdio"' "$M")" == stdio ]]; then
    inner="$(jq -r --arg n "$n" 'if (.[$n].jail | type) == "object" then "/home/u/.local/bin/ws-mcp-jail" else .[$n].command end' "$M")"
    check "$n: registered through ws-mcp-keepalive --name $n -- ws-mcp-filter --name $n -- $(basename "$inner")" \
      jq -e --arg n "$n" --arg i "$inner" '.command == "/home/u/.local/bin/ws-mcp-keepalive" and .args[0:3] == ["--name", $n, "--"]
        and .args[3] == "/home/u/.local/bin/ws-mcp-filter" and .args[4:7] == ["--name", $n, "--"] and .args[7] == $i' <<<"$w"
  else
    check "$n: an HTTP server is registered as written (Claude Code reconnects it itself)" \
      jq -e --arg n "$n" --slurpfile k "$M" '. == $k[0][$n] and (has("command") | not)' <<<"$w"
  fi
  check "$n: the kit's keys (jail, jailOptOut, keepalive) are not passed to claude mcp add-json" \
    jq -e 'has("jail") or has("jailOptOut") or has("keepalive") | not' <<<"$w"
done
check "every stdio server says keepalive: true or false; HTTP servers carry no keepalive key" \
  jq -e 'all(.[]; if (.type // "stdio") == "stdio" then (.keepalive | type) == "boolean" else has("keepalive") | not end)' "$M"
check "the jailed server keeps its jail inside the keepalive (azure: --net --azure-config)" \
  jq -e '.args[7:] | .[0] == "/home/u/.local/bin/ws-mcp-jail" and index("--net") and index("--azure-config") and (.[index("--") + 1] | endswith("azmcp"))' <<<"$(want azure)"
jq '.mempalace.keepalive = false' "$M" > "$T/m.json"
check "\"keepalive\": false registers the server without the keepalive (the filter stays)" \
  jq -e '(.command | endswith("/ws-mcp-filter")) and (.args[3] | endswith("mempalace-mcp.exe"))' <<<"$(want mempalace "$T/m.json")"
all="$(for n in $(jq -r 'keys[]' "$M"); do jq -c --arg n "$n" '{($n): .}' <<<"$(want "$n")"; done | jq -s 'add | {mcpServers: .}')"
printf '%s\n' "$all" > "$T/claude.json"
m="$(bash -c 'source "$1/lib.sh"; mcp_unwrap_merge "$2" "$3"' _ "$ROOT" "$M" "$T/claude.json" | sed 's#/home/u/#@HOME@/#g')"
check "export.sh unwraps every registration (keepalive, then jail) back to mcp-servers.json, keys kept" \
  jq -e --slurpfile k "$M" '. == $k[0]' <<<"$m"
check "mcp_unwrap gives the server's own command behind both wrappers" \
  bash -c "source '$ROOT/lib.sh'; mcp_unwrap <<<'$(want azure)' | jq -e '.command | endswith(\"azmcp\")'"
old="$(jq -c '.args = .args[4:] | .command = "/home/u/.local/bin/ws-mcp-jail"' <<<"$(want azure)")"
check "install.sh re-registers a jail-only registration of the same server by itself (same server inside)" \
  bash -c "source '$ROOT/lib.sh'; [[ \$(mcp_unwrap <<<'$old' | jq -cS .) == \"\$(mcp_unwrap <<<'$(want azure)' | jq -cS .)\" ]]"
check "  install.sh has that branch (no --mcp-refresh needed)" grep -q 'mcp_same "$(mcp_unwrap <<<"$have")" "$(mcp_unwrap <<<"$want")"' "$ROOT/install.sh"
check "a different server inside is not taken for the same one" \
  bash -c "source '$ROOT/lib.sh'; [[ \$(mcp_unwrap <<<'$(want azure)' | jq -cS .) != \"\$(mcp_unwrap <<<'$(want recall)' | jq -cS .)\" ]]"
check "the managed allow list names the keepalive command and the real server after it, never a name" \
  bash -c "source '$ROOT/lib.sh'; mcp_allowlist '$M' /home/u | jq -e '[.allowedMcpServers[] | select(.serverCommand)] | length == 4 and all(.[]; .serverCommand[0] == \"/home/u/.local/bin/ws-mcp-keepalive\" and (.serverCommand | index(\"--\")) == 3)'"
pat='cmd="$(jq -r --arg n "$n" '"'"'.[$n].command // empty'"'"' "$MCP_FILE")"'
check "the lock still vouches for the real binary: install.sh checks .command of mcp-servers.json" grep -qF "$pat" "$ROOT/install.sh"
check "ws-update checks the real binary behind the wrappers" grep -q 'unwrap | .command' "$ROOT/files/home/.local/bin/ws-update"
check "the manifest installs ws-mcp-keepalive" grep -qx '.local/bin/ws-mcp-keepalive' "$ROOT/manifest.txt"

echo "9) ws-audit and ws-health"
arun() {
  python3 -I - "$ROOT/files/home/.local/bin/ws-audit" "$1" <<'EOF'
import importlib.machinery, importlib.util, json, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("ws_audit", sys.argv[1])
spec = importlib.util.spec_from_loader("ws_audit", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
kit = json.loads(Path(m.H / "kit.json").read_text())
servers = json.loads(Path(m.H / ".claude.json").read_text())["mcpServers"]
if sys.argv[2] == "confinement":
    m.mcp_confinement(kit)
else:
    m.mcp_keepalive(kit, servers)
for r in m.R:
    print("\t".join((r["status"], r["what"], r["detail"], r["reco"])))
EOF
}
cp "$M" "$HOME/kit.json"
rm -rf "$STATE"; mkdir -p "$STATE"
jq '.mcpServers |= with_entries(if .value.command then .value.command |= sub("/home/u"; env.HOME) else . end)' "$T/claude.json" > "$HOME/.claude.json"
arun keepalive > "$T/a"
check "ws-audit: every kit stdio server kept alive passes" grep -q '^ok.*ws-mcp-keepalive): 4, not: 0' "$T/a"
check "ws-audit: no restarts in the last 24 h passes" grep -q '^ok.*restarts in the last 24 h: 0' "$T/a"
arun confinement > "$T/a"
check "ws-audit: a jailed server behind the keepalive still counts as confined; Windows ones named" \
  grep -q '^ok.*confined by ws-mcp-jail: 2, not confined: 2.*mempalace (Windows process' "$T/a"
jq --arg h "$HOME" '.mcpServers.azure = {type: "stdio", command: ($h + "/.local/bin/ws-mcp-jail"), args: ["--name", "azure", "--", "/x/azmcp"]}' \
  "$HOME/.claude.json" > "$T/c" && cp "$T/c" "$HOME/.claude.json"
arun keepalive > "$T/a"
check "ws-audit: a stdio server registered without keepalive warns, with the fix" \
  grep -q '^warn.*ws-mcp-keepalive): 3, not: 1.*azure.*install.sh' "$T/a"
jq '.mempalace.keepalive = false' "$M" > "$HOME/kit.json"
jq '.mcpServers.mempalace.command = "/mnt/c/x/mempalace-mcp.exe" | .mcpServers.mempalace.args = []' "$HOME/.claude.json" > "$T/c" && cp "$T/c" "$HOME/.claude.json"
check "ws-audit: an opted-out server (keepalive: false) is named as such" \
  bash -c "$(declare -f arun); ROOT='$ROOT'; arun keepalive | grep -q 'mempalace (keepalive: false)'"
now="$(date +%Y-%m-%dT%H:%M:%S%z)" old="$(date -d '2 days ago' +%Y-%m-%dT%H:%M:%S%z)"
printf '%s restart name=recall n=1 exit=0 uptime=4000s delay=1s\n%s restart name=recall n=2 exit=1 uptime=3s delay=2s\n' "$now" "$now" > "$STATE/recall.log"
printf '%s restart name=azure n=1 exit=1 uptime=3s delay=1s\n%s stderr noise\n' "$old" "$now" > "$STATE/azure.log"
arun keepalive > "$T/a"
check "ws-audit: restarts of the last 24 h are reported per server with the last exit" \
  grep -qE '^warn.*restarts in the last 24 h: 2.*recall 2× \(last: name=recall n=2 exit=1' "$T/a"
check "  older restarts are not counted" not grep -q 'azure 1×' "$T/a"
printf '%s giveup name=mempalace restarts=5 reason=6 exits within 300 s (exit 1)\n' "$now" > "$STATE/mempalace.log"
check "ws-audit: a give-up in the last 24 h is reported (the server is down)" \
  bash -c "$(declare -f arun); ROOT='$ROOT'; arun keepalive | grep -q '^warn.*gave up: mempalace.*/mcp → Reconnect'"
H2="$T/h2"; mkdir -p "$H2/.local/state/ws-mcp" "$H2/code/claude-workstation/files"
cp "$M" "$H2/code/claude-workstation/files/"
cp "$HOME/.claude.json" "$H2/.claude.json"; cp "$STATE/mempalace.log" "$H2/.local/state/ws-mcp/"
# ws-health asks tmux for the open tabs: a socket folder of its own, so it never reaches a real tmux server.
hrun() { env -u TMUX HOME="$H2" TMUX_TMPDIR="$T/notmux" bash "$ROOT/files/home/.local/bin/ws-health" > "$T/h" 2>&1; }
mkdir -p "$T/notmux"; hrun
check "ws-health: a stdio server without keepalive fails, by name" grep -qE 'restart when they exit +FAIL.*azure' "$T/h"
check "ws-health: a give-up in the last 24 h fails, with the next step" grep -qE 'given up \(24 h\) +FAIL +mempalace.*/mcp' "$T/h"
jq '.mcpServers |= with_entries(select(.key != "azure" and .key != "mempalace"))' "$HOME/.claude.json" > "$H2/.claude.json"
rm -f "$H2/.local/state/ws-mcp/mempalace.log"
hrun
check "ws-health: all kept alive and nothing given up passes" \
  bash -c "grep -qE 'restart when they exit +OK' '$T/h' && grep -qE 'given up \(24 h\) +OK' '$T/h'"
if command -v shellcheck >/dev/null; then
  check "shellcheck ws-health, ws-update, lib.sh, install.sh" \
    shellcheck -S warning "$ROOT/files/home/.local/bin/ws-health" "$ROOT/files/home/.local/bin/ws-update" "$ROOT/lib.sh" "$ROOT/install.sh"
fi

printf '\n%d ok, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
