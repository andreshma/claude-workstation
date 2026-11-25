#!/usr/bin/env bash
#
# tests/audit-anomaly.sh — anomaly detection (WS-AI-030) and the emergency stop (WS-AI-025): ws-anomaly counts guard
# blocks, denials and sandbox hits per session in a window; ws-stop-all sets the marker, turns Telegram off, records
# the event and closes every Claude pane, naming the ones that do not close. tmux is simulated (no server is started),
# Telegram is a stub, logs are fixtures in a temporary HOME.
#
# Usage: bash tests/audit-anomaly.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

BIN="$ROOT/files/home/.local/bin"
export HOME="$T/home" CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors" WS_TELEMETRY_DIR="$T/tel" WS_STATE_DIR="$T/state"
mkdir -p "$HOME/.claude/hooks" "$HOME/.local/bin" "$CLAUDE_AUDIT_DIR" "$WS_TELEMETRY_DIR/raw" "$T/fake"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"

echo "1) ws-anomaly"
now="$(date -Is)"; old="$(date -Is -d '-30 minutes')"
a="$CLAUDE_AUDIT_DIR/$(date +%F).jsonl"
for _ in 1 2 3 4 5; do printf '{"ts":"%s","ev":"blocked","session":"sA","pane":"%%7","cwd":"/r/api","reason":"forced push"}\n' "$now"; done > "$a"
for _ in 1 2; do printf '{"ts":"%s","ev":"denied","session":"sB","pane":"%%8","cwd":"/r/web"}\n' "$now"; done >> "$a"
for _ in 1 2 3 4; do printf '{"ts":"%s","ev":"blocked","session":"sC","cwd":"/r/c"}\n' "$now"; done >> "$a"
for _ in 1 2 3 4 5 6; do printf '{"ts":"%s","ev":"blocked","session":"sD","cwd":"/r/d"}\n' "$old"; done >> "$a"
for _ in 1 2 3 4 5 6; do printf '{"ts":"%s","ev":"held","session":"sE","cwd":"/r/e"}\n' "$now"; done >> "$a"
for _ in 1 2 3; do printf '{"ts":"%s","type":"network","detail":"evil.example","session":"sB","project":"web"}\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"; done \
  > "$WS_TELEMETRY_DIR/raw/sandbox-$(date +%Y-%m).jsonl"
out="$(python3 "$BIN/ws-anomaly" --tsv)"
check "a session with 5 guard blocks in 10 min is reported with its pane" grep -qP '^sA\t5\tguard:5\tapi\t%7$' <<<"$out"
check "denials and sandbox hits add up per session" grep -qP '^sB\t5\t.*sandbox-network:3.*\tweb\t%8$' <<<"$out"
check "a session under the threshold is not" not grep -q '^sC' <<<"$out"
check "blocks older than the window do not count" not grep -q '^sD' <<<"$out"
check "holds by the stop or budget gate do not count" not grep -q '^sE' <<<"$out"
check "the threshold and window are options" grep -q '^sC' <<<"$(python3 "$BIN/ws-anomaly" --tsv --threshold 4)"
check "a wider window brings the old ones in" grep -q '^sD' <<<"$(python3 "$BIN/ws-anomaly" --tsv --minutes 60)"
check "quiet logs print nothing in --tsv" test -z "$(CLAUDE_AUDIT_DIR="$T/none" WS_TELEMETRY_DIR="$T/none" python3 "$BIN/ws-anomaly" --tsv)"

echo "2) ws-stop-all"
# Simulated tmux: panes listed in $F/panes; a pane in $F/claude runs Claude until it receives /exit (unless «stuck»).
F="$T/fake"; printf '%%1\tdev:1 api\n%%2\tdev:2 web\n%%3\tdev:3 shell\n%%4\tswarm-1:1 a\n' > "$F/panes"
printf '%%1 ok\n%%2 stuck\n%%4 ok\n' > "$F/claude"
cat > "$F/tmux" <<'EOF'
#!/bin/bash
F="$FAKE_DIR"; printf '%s\n' "$*" >> "$F/log"
t=""; for (( i = 1; i <= $#; i++ )); do [[ "${!i}" == -t ]] && { j=$((i + 1)); t="${!j}"; }; done
case "$1" in
  list-panes) if [[ "$*" == *"-s -t swarm-1"* ]]; then grep 'swarm-1:' "$F/panes"; else cat "$F/panes"; fi ;;
  display)
    case "${!#}" in
      *pane_current_command*) if [[ ! -e "$F/exited$t" ]] && grep -q "^$t " "$F/claude"; then echo 2.1.999; else echo bash; fi ;;
      *pane_pid*) echo 999999 ;;
      *) grep "^$t"$'\t' "$F/panes" | cut -f2 ;;
    esac ;;
  send-keys) [[ "$*" == *"-l /exit"* ]] && ! grep -q "^$t stuck" "$F/claude" && : > "$F/exited$t" ;;
esac
exit 0
EOF
printf '#!/bin/bash\necho "$*" >> "%s/telegram.log"\n' "$F" > "$HOME/.local/bin/ws-telegram"
chmod +x "$F/tmux" "$HOME/.local/bin/ws-telegram"
stopall() { env -u TMUX FAKE_DIR="$F" PATH="$F:$PATH" WS_STOP_WAIT=1 bash "$BIN/ws-stop-all" "$@" </dev/null; }
check "--list shows the panes with Claude" test "$(stopall --list | cut -f1 | paste -sd' ')" = "%1 %2 %4"
check "--status is off at first" test "$(stopall --status)" = off
out="$(stopall --yes --reason "test incident" 2>&1)"; rc=$?
check "the marker is written with the reason" grep -qx 'reason=test incident' "$WS_STATE_DIR/ws-stop-all"
check "Telegram is turned off" grep -qx off "$F/telegram.log"
check "the stop is recorded in the audit log" bash -c "grep -h '\"ev\":\"stop-all\"' '$CLAUDE_AUDIT_DIR'/*.jsonl | grep -q 'test incident'"
check "every Claude pane got Escape and /exit" bash -c "grep -c -- '-t %[124] -l /exit' '$F/log' | grep -qx 3 && grep -q -- '-t %1 Escape' '$F/log'"
check "a shell pane gets no keys" not grep -q -- 'send-keys -t %3' "$F/log"
check "the pane that did not close is named, and the exit code says so" bash -c "[[ $rc != 0 ]] && grep -q 'Still running (close them by hand): dev:2 web' <<<'$out'"
check "panes that did not close got Ctrl+C twice" grep -q -- '-t %2 C-c' "$F/log"
check "--status shows it on" grep -q '^ON since' <<<"$(stopall --status)"
check "--clear removes the marker and is audited" bash -c "stopall() { env FAKE_DIR='$F' PATH='$F:$PATH' bash '$BIN/ws-stop-all' \"\$@\"; }; stopall --clear | grep -q 'Telegram stays off' && [[ ! -e '$WS_STATE_DIR/ws-stop-all' ]] && grep -hq '\"ev\":\"stop-all-clear\"' '$CLAUDE_AUDIT_DIR'/*.jsonl"
rm -f "$F"/exited* "$F/log" "$F/telegram.log"
check "--pane stops one tab without the marker or Telegram" bash -c "env FAKE_DIR='$F' PATH='$F:$PATH' WS_STOP_WAIT=1 bash '$BIN/ws-stop-all' --pane %1 --yes </dev/null && [[ ! -e '$WS_STATE_DIR/ws-stop-all' && ! -e '$F/telegram.log' ]] && ! grep -q -- '-t %4' '$F/log'"
rm -f "$F"/exited* "$F/log"
check "--session stops only that session (a swarm)" bash -c "env FAKE_DIR='$F' PATH='$F:$PATH' WS_STOP_WAIT=1 bash '$BIN/ws-stop-all' --session swarm-1 --yes </dev/null && grep -q -- '-t %4 -l /exit' '$F/log' && ! grep -q -- '-t %1 ' '$F/log'"
check "a malformed pane id is refused" not stopall --pane 'x;y' --yes
command -v shellcheck >/dev/null && check "shellcheck ws-stop-all" shellcheck -S warning "$BIN/ws-stop-all"
check "ws-anomaly compiles" python3 -c "import ast; ast.parse(open('$BIN/ws-anomaly').read())"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
