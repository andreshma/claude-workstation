#!/usr/bin/env bash
#
# tests/otel-collector.sh — the local OpenTelemetry collector's input limits (WS-SEC-012): a gzip body that would
# expand past the 16 MB limit is refused with 413 before it is held in memory, a normal gzip export is stored, and a
# plain body over the limit is refused. The collector runs on a free loopback port with a temporary data folder.
#
# Usage: bash tests/otel-collector.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; PID=""
trap '[[ -n "$PID" ]] && kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }

command -v curl >/dev/null || { echo "skip: curl is missing"; exit 0; }
PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
export HOME="$T/home" WS_OTEL_PORT="$PORT" WS_OTEL_DIR="$T/otel" XDG_RUNTIME_DIR="$T/run"; mkdir -p "$HOME" "$T/run"
python3 -I "$ROOT/files/home/.local/bin/ws-otel" serve >"$T/log" 2>&1 & PID=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
post() { curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' "$@" "http://127.0.0.1:$PORT/v1/logs"; }

echo '{"resourceLogs":[]}' | gzip -c > "$T/ok.gz"
python3 -c 'import gzip, sys; sys.stdout.buffer.write(gzip.compress(b" " * (40 * 1024 * 1024)))' > "$T/bomb.gz"
head -c $((17 * 1024 * 1024)) /dev/zero | tr '\0' ' ' > "$T/big.json"
check "the gzip bomb is small on the wire" test "$(stat -c %s "$T/bomb.gz")" -lt 200000
check "a gzip body expanding past 16 MB is refused with 413" test "$(post -H 'Content-Encoding: gzip' --data-binary "@$T/bomb.gz")" = 413
check "a normal gzip export is accepted" test "$(post -H 'Content-Encoding: gzip' --data-binary "@$T/ok.gz")" = 200
check "a plain body over 16 MB is refused with 413" test "$(post --data-binary "@$T/big.json")" = 413
check "the collector is still up" kill -0 "$PID"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
