#!/usr/bin/env bash
#
# tests/telegram-audit.sh — remote decisions from Telegram land in the Claude audit hash chain (WS-SEC-011), with a
# simulated Telegram API and tmux (no tmux server, no network, temporary HOME and audit folder): an approval, a
# denial, a PIN approval, a wrong PIN, a press from someone else and a ▶ Run are each one «telegram» line written by
# audit.sh, the run command is recorded (redacted by audit.sh), neither the PIN nor the text of your messages ever
# reaches the audit log, and ws-audit --verify-log accepts the chain (and catches an edited Telegram line).
#
# Usage: bash tests/telegram-audit.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
W="$ROOT/files/home/.local/bin/ws-telegram"
export HOME="$T/home" G="$T/g" CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt"
mkdir -p "$HOME/.claude/hooks" "$G/cfg" "$G/st" "$G/log" "$G/bin"; unset TMUX TMUX_PANE
cp "$ROOT/files/home/.claude/settings.json" "$HOME/.claude/settings.json"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/audit.sh"; chmod 755 "$HOME/.claude/hooks/audit.sh"
printf 'chat_id=42\nbot=test_bot\n' > "$G/cfg/config"

# Simulated tmux and Telegram API: the same as tests/telegram-approvals.sh.
cat > "$G/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  capture-pane) cat "$G/screen" 2>/dev/null ;;
  send-keys) shift; while (( $# )); do [[ "$1" == -t ]] && { shift 2; continue; }; [[ "$1" == -l ]] && { shift; continue; }; printf '%s\n' "$1" >> "$G/keys"; shift; done ;;
  display|display-message) [[ "$*" == *pane_current_command* ]] && echo claude || echo "/tmp" ;;
  *) : ;;
esac
exit 0
EOF
cat > "$G/bin/curl" <<'EOF'
#!/usr/bin/env bash
cfg=""; while (( $# )); do [[ "$1" == -K ]] && cfg="$2"; shift; done
m="$(sed -n 's|.*/bot[^/]*/\([A-Za-z]*\)".*|\1|p' "$cfg")"; body="$(cat)"
printf '%s %s\n' "$m" "$body" >> "$G/calls"
case "$m" in
  sendMessage) echo '{"ok":true,"result":{"message_id":7}}' ;;
  getUpdates)
    if [[ -f "$G/msg" ]]; then read -r from rmid txt < "$G/msg"; rm -f "$G/msg"
      jq -nc --argjson f "$from" --argjson r "$rmid" --arg t "$txt" '{ok: true, result: [{update_id: 9, message: {message_id: 99, from: {id: $f}, chat: {id: $f}, text: $t, reply_to_message: {message_id: $r}}}]}'
    elif [[ -f "$G/cb" ]]; then read -r from opt < "$G/cb"; rm -f "$G/cb"
      n="$(basename "$(ls "$G"/st/pending/*.json 2>/dev/null | head -1)" .json)"
      printf '{"ok":true,"result":[{"update_id":5,"callback_query":{"id":"c1","from":{"id":%s},"message":{"chat":{"id":%s}},"data":"%s:%s"}}]}\n' "$from" "$from" "$n" "$opt"
    else echo '{"ok":true,"result":[]}'; fi ;;
  *) echo '{"ok":true,"result":true}' ;;
esac
EOF
chmod 755 "$G/bin"/*
export PATH="$G/bin:$PATH" WS_TELEGRAM_CFG="$G/cfg" WS_TELEGRAM_ST="$G/st" WS_TELEGRAM_LOG="$G/log" WS_TELEGRAM_TOKEN=test \
       WS_TELEGRAM_CURL="$G/bin/curl" WS_TELEGRAM_NO_SERVICE=1 WS_TELEGRAM_PIN=4821 WS_TELEGRAM_NO_CLAUDE_CHECK=1 WS_TELEGRAM_WAIT=4
tg() { bash "$W" "$@"; }
reset() { rm -rf "$G/st" "$G/calls" "$G/keys"; mkdir -p "$G/st"; }
dialog() { printf ' %s\n   %s\n Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and don'"'"'t ask again for %s commands\n   3. No, and tell Claude what to do differently (esc)\n' "$1" "$2" "$2" > "$G/screen"; }
press() { tg notify wait %1 "Claude needs your permission"; tg service --once; echo "$1" > "$G/cb"; tg service --once; }
lines() { cat "$T"/audit/*.jsonl 2>/dev/null | jq -c 'select(.ev == "telegram")'; }
has() { lines | jq -e --arg r "$1" 'select(.reason | test($r))' >/dev/null; }

echo "1) dialogs answered from the phone"
reset; dialog "Bash command" "npm test"; press "42 1"
check "an approval is one audit line, ev telegram" has '^reply %1 1 approve$'
reset; dialog "Bash command" "npm test"; press "42 3"
check "a denial is recorded as deny" has '^reply %1 3 deny$'
check "  written by audit.sh: chained with prev and carrying the user" bash -c "$(declare -f lines); T='$T'; lines | tail -1 | jq -e '(.prev | length) == 64 and .user != null and .tool == \"Telegram\"'"

echo "2) a risky dialog with the PIN"
reset; dialog "Bash command" "terraform apply -auto-approve"; press "42 1"
check "the PIN request is recorded" has '^approve_asks_pin %1'
echo "42 7 0000 my-private-note" > "$G/msg"; tg service --once
check "a wrong PIN is recorded" has '^pin_wrong 1 run$'
echo "42 7 4821" > "$G/msg"; tg service --once
check "the right PIN is recorded" has '^approve_authorized pin$'
check "  and the approval it sent" has '^reply %1 1 approve pin$'
check "neither the PIN nor the text of your messages is in the audit log" bash -c "! grep -rqE '4821|0000|my-private-note' '$T/audit'"

echo "3) someone else and ▶ Run"
reset; dialog "Bash command" "npm test"; tg notify wait %1 "perm"; tg service --once; echo "99 1" > "$G/cb"; tg service --once
check "a press from another chat is recorded" has '^unauthorized from=99$'
reset; : > "$G/screen"; tg run no-pin >/dev/null
tg notify "done" %2 'Finished: run `! git log --oneline -3`'; tg service --once; echo "42 r" > "$G/cb"; tg service --once
for _ in $(seq 1 30); do has '^run %2' && break; sleep 0.5; done
check "a ▶ Run is recorded with its tab" has '^run %2$'
check "  and with the command, as tool_input.command" bash -c "$(declare -f lines); T='$T'; lines | jq -e 'select(.reason == \"run %2\") | .cmd == \"git log --oneline -3\"'"
check "audit.sh redacts a secret in a recorded command" bash -c "
  jq -nc '{tool_name: \"Telegram\", tool_input: {command: \"git log --grep token=abc123secret\"}}' \
    | (cd / && '$HOME/.claude/hooks/audit.sh' telegram 'run %9'); grep -q 'token=\*\*\*' '$T'/audit/*.jsonl && ! grep -q abc123secret '$T'/audit/*.jsonl"
sleep 5   # the background ▶ Run finishes and writes its result line

echo "4) the chain"
check "ws-audit --verify-log accepts the log with the Telegram lines" python3 "$ROOT/files/home/.local/bin/ws-audit" --verify-log "$T/audit"
cp -a "$T/audit" "$T/audit2"; f="$(ls "$T"/audit2/*.jsonl | head -1)"; sed -i '0,/approve/s//deny/' "$f"
check "  and catches an edited Telegram decision" not python3 "$ROOT/files/home/.local/bin/ws-audit" --verify-log "$T/audit2"
check "the Telegram log keeps its own events (unchanged format)" bash -c "grep -h '\"event\":\"reply\"' '$G'/log/*.jsonl | jq -e 'has(\"ts\") and has(\"detail\")'"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
