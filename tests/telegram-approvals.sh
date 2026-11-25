#!/usr/bin/env bash
#
# tests/telegram-approvals.sh — Telegram approvals with the PIN and the ▶ Run allow list (WS-AI-007, WS-AI-018),
# with a simulated Telegram API and a simulated tmux (no tmux server, no network, temporary HOME):
# "don't ask again" is never a button and is refused if forged, a plain approval is one tap, approving a risky dialog
# (ask rule, MCP tool) needs the PIN and is sent only if the dialog is still on screen, `approve pin` asks for every
# approval, only read-only commands of the allow list get ▶ Run, and a kit release with a bad signature alerts.
#
# Usage: bash tests/telegram-approvals.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
W="$ROOT/files/home/.local/bin/ws-telegram"
export HOME="$T/home" G="$T/g"; mkdir -p "$HOME/.claude" "$G/cfg" "$G/st" "$G/log" "$G/bin"; unset TMUX TMUX_PANE
cp "$ROOT/files/home/.claude/settings.json" "$HOME/.claude/settings.json"   # the kit's ask rules and excluded commands
printf 'chat_id=42\nbot=test_bot\n' > "$G/cfg/config"

# Simulated tmux: the screen is $G/screen; keys typed go to $G/keys. Nothing else exists.
cat > "$G/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  capture-pane) cat "$G/screen" 2>/dev/null ;;
  send-keys) shift; while (( $# )); do [[ "$1" == -t ]] && { shift 2; continue; }; [[ "$1" == -l ]] && { shift; continue; }; printf '%s\n' "$1" >> "$G/keys"; shift; done ;;
  display|display-message) [[ "$*" == *pane_current_command* ]] && echo claude || echo "1 tab" ;;
  show|show-options) : ;;
  has-session|load-buffer|paste-buffer|list-panes) : ;;
esac
exit 0
EOF
# Simulated Telegram API: logs every call; getUpdates delivers $G/cb ("<from> <option>") or $G/msg ("<from> <reply-to> <text>").
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
       WS_TELEGRAM_CURL="$G/bin/curl" WS_TELEGRAM_NO_SERVICE=1
tg() { bash "$W" "$@"; }
reset() { rm -rf "$G/st" "$G/calls" "$G/keys"; mkdir -p "$G/st"; }
dialog() { printf ' %s\n   %s\n Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and don'"'"'t ask again for %s commands\n   3. No, and tell Claude what to do differently (esc)\n' "$1" "$2" "$2" > "$G/screen"; }
keyboard() { grep '^sendMessage' "$G/calls" | grep 'inline_keyboard' | tail -1; }

echo "1) a plain permission dialog"
reset; dialog "Bash command" "npm test"
WS_TELEGRAM_PIN=4821 tg notify wait %1 "Claude needs your permission to use Bash"
check "the notification keeps the 3 options on screen" jq -e '.options | length == 3' "$G"/st/outbox/*.json
WS_TELEGRAM_PIN=4821 tg service --once
check "\"don't ask again\" is not a button" not grep -q "2 · Yes, and" <(keyboard)
check "  and the message says it is answered on the PC" grep -q 'answered only on the PC' "$G/calls"
check "a plain dialog is not marked 🔐" not grep -q '🔐' <(keyboard)
echo "42 2" > "$G/cb"; WS_TELEGRAM_PIN=4821 tg service --once
check "a forged \"don't ask again\" press sends no key" not test -s "$G/keys"
check "  and is logged" grep -q refused_persistent "$G"/log/*.jsonl
reset; dialog "Bash command" "npm test"; WS_TELEGRAM_PIN=4821 tg notify wait %1 "Claude needs your permission"; WS_TELEGRAM_PIN=4821 tg service --once
echo "42 1" > "$G/cb"; WS_TELEGRAM_PIN=4821 tg service --once
check "\"Yes\" on a plain dialog is one tap" grep -qx 1 "$G/keys"
reset; dialog "Bash command" "npm test"; WS_TELEGRAM_PIN=4821 tg notify wait %1 "Claude needs your permission"; WS_TELEGRAM_PIN=4821 tg service --once
echo "42 3" > "$G/cb"; WS_TELEGRAM_PIN=4821 tg service --once
check "\"No\" is one tap" grep -qx 3 "$G/keys"

echo "2) a risky dialog (ask rule: terraform apply)"
reset; dialog "Bash command" "terraform apply -auto-approve"
WS_TELEGRAM_PIN=4821 tg notify wait %1 "Claude needs your permission to use Bash"
check "the dialog is marked risky" jq -e '.risky == true' "$G"/st/outbox/*.json
WS_TELEGRAM_PIN=4821 tg service --once
check "the approving button is marked 🔐" grep -q '🔐 1 · Yes' <(keyboard)
echo "42 1" > "$G/cb"; WS_TELEGRAM_PIN=4821 tg service --once
check "pressing it sends no key" not test -s "$G/keys"
check "  and asks for the PIN" bash -c "grep -q 'To approve option 1' '$G/calls' && test -f '$G/st/to-run/7.json'"
echo "42 7 0000" > "$G/msg"; WS_TELEGRAM_PIN=4821 tg service --once
check "a wrong PIN sends nothing" not test -s "$G/keys"
echo "42 7 4821" > "$G/msg"; WS_TELEGRAM_PIN=4821 tg service --once
check "the right PIN sends the key" grep -qx 1 "$G/keys"
check "  once (the request is single-use)" not test -f "$G/st/to-run/7.json"
reset; dialog "Bash command" "cd infra && terraform destroy"
WS_TELEGRAM_PIN=4821 tg notify wait %1 "perm"; WS_TELEGRAM_PIN=4821 tg service --once
echo "42 1" > "$G/cb"; WS_TELEGRAM_PIN=4821 tg service --once
dialog "Bash command" "something else"
echo "42 7 4821" > "$G/msg"; WS_TELEGRAM_PIN=4821 tg service --once
check "an ask rule after && is risky too, and a changed screen sends nothing after the PIN" bash -c "! test -s '$G/keys' && grep -q 'The screen changed' '$G/calls'"
reset; printf ' Tool use\n   azure - keyvault_secret_get (MCP)\n Do you want to proceed?\n ❯ 1. Yes\n   2. No (esc)\n' > "$G/screen"
WS_TELEGRAM_PIN=4821 tg notify wait %1 "perm"; check "an MCP tool dialog is risky" jq -e '.risky == true' "$G"/st/outbox/*.json
reset; dialog "Bash command" "gh pr create --fill"
WS_TELEGRAM_PIN=4821 tg notify wait %1 "perm"; check "an excluded command (runs outside the sandbox) is risky" jq -e '.risky == true' "$G"/st/outbox/*.json
reset; dialog "Bash command" "terraform apply"; tg notify wait %1 "perm"; tg service --once
echo "42 1" > "$G/cb"; tg service --once
check "without a PIN configured a risky approval is refused" bash -c "! test -s '$G/keys' && grep -q 'none is set' '$G/calls'"

echo "3) approve pin: every approval asks"
reset; tg approve pin >/dev/null; dialog "Bash command" "npm test"
WS_TELEGRAM_PIN=4821 tg notify wait %1 "perm"; WS_TELEGRAM_PIN=4821 tg service --once
echo "42 1" > "$G/cb"; WS_TELEGRAM_PIN=4821 tg service --once
check "a plain approval asks for the PIN" bash -c "! test -s '$G/keys' && test -f '$G/st/to-run/7.json'"
echo "42 3" > "$G/cb"; rm -f "$G"/st/to-run/*; reset; dialog "Bash command" "npm test"
WS_TELEGRAM_PIN=4821 tg notify wait %1 "perm"; WS_TELEGRAM_PIN=4821 tg service --once; echo "42 3" > "$G/cb"; WS_TELEGRAM_PIN=4821 tg service --once
check "  but \"No\" stays one tap" grep -qx 3 "$G/keys"
check "ws-telegram approve shows the mode" grep -q 'Status: pin' <(tg approve)
tg approve risky >/dev/null

echo "4) ▶ Run allow list"
reset; : > "$G/screen"
tg notify "done" %2 'Finished: run `! git status` and `! npm test` and `! ls -la | sh`'
check "a read-only command of the allow list is runnable" jq -e 'select(.command == "git status") | .dangerous == false' "$G"/st/outbox/*_c*.json
check "npm test (runs repo code) is not" jq -e 'select(.command == "npm test") | .dangerous == true' "$G"/st/outbox/*_c*.json
check "a pipe into a shell is not" jq -e 'select(.command == "ls -la | sh") | .dangerous == true' "$G"/st/outbox/*_c*.json
check "the selftest passes (allow list, persistent and risky detection)" bash -c "[[ \$(HOME='$ROOT/files/home' bash '$W' selftest) == ok ]]"

echo "5) kit release with a bad signature"
for c in ws-kit-update ws-restore-lite ws-telemetry ws-health cmd.exe; do printf '#!/bin/sh\nexit 0\n' > "$G/bin/$c"; done
printf '#!/bin/sh\necho "Kit release v9.9.9 found, but the signature does not verify: not offered."\nexit 11\n' > "$G/bin/ws-kit-update"
chmod 755 "$G/bin"/*; reset; printf 'alerts=on\nsummary_hour=99\nbudgets=off\nweekly_day=8\n' > "$G/cfg/settings"
tg check >/dev/null 2>&1
check "exit 11 of ws-kit-update --check raises a security alert" grep -qs 'signature does not verify' "$G"/st/outbox/*_a.json

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
