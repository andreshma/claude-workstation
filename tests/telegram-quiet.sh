#!/usr/bin/env bash
#
# tests/telegram-quiet.sh — the PIN that just works and the quiet notification policy of ws-telegram (ADR 0026),
# with a simulated Telegram API (message ids that grow, updates queued as JSON, failures on request), a simulated
# tmux and a simulated ws-secret (no tmux server, no network, temporary HOME):
#   · PIN: a bare PIN as a Reply to the dialog alert or to the prompt, a plain PIN message with one request pending,
#     "pin 1234", two pending (ask to disambiguate), wrong PINs (3 cancel), expired, a PIN never counted as a wrong
#     text reply, PIN deleted from the chat, outcome on the prompt, PIN read lazily when interop was not ready,
#     "no PIN is set", the emergency stop;
#   · never silent: every message the bot does not act on gets an answer, rate-limited;
#   · policy: modes approvals|digest|all|off, quiet hours, digest content / redaction / only on change / 🔎 buttons,
#     one context alert per crossing, error_api with its reason and backoff, the settings commands and the menu.
#
# Usage: bash tests/telegram-quiet.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
W="$ROOT/files/home/.local/bin/ws-telegram"
REAL_TMUX="$(command -v tmux)"   # before the simulated tmux goes first in PATH (used only to parse the menu)
export HOME="$T/home" G="$T/g"; mkdir -p "$HOME/.claude" "$HOME/.local/bin" "$G/cfg" "$G/st" "$G/log" "$G/bin"; unset TMUX TMUX_PANE
cp "$ROOT/files/home/.claude/settings.json" "$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/hooks" "$HOME/.local/lib"; cp "$ROOT/files/home/.claude/hooks/tmux-state.sh" "$HOME/.claude/hooks/"
cp -a "$ROOT/files/home/.local/lib/ws-lang.sh" "$ROOT/files/home/.local/lib/ws-lang" "$HOME/.local/lib/"   # «waiting for you» detector
printf 'chat_id=42\nbot=test_bot\n' > "$G/cfg/config"

# Simulated tmux. Screen: $G/screen; keys typed: $G/keys; Claude panes: $G/panes (pane, window, "index name",
# command, folder); window options: $G/opt/<window>/<option>; global options set by ws-telegram: $G/tmuxset.
cat > "$G/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  capture-pane) cat "$G/screen" 2>/dev/null ;;
  send-keys) shift; while (( $# )); do [[ "$1" == -t ]] && { shift 2; continue; }; [[ "$1" == -l ]] && { shift; continue; }; printf '%s\n' "$1" >> "$G/keys"; shift; done ;;
  display|display-message) if [[ "$*" == *pane_current_command* ]]; then echo claude; elif [[ "$1" == display-message || "$*" != *-p* ]]; then printf '%s\n' "${@: -1}" >> "$G/displayed"; else echo "1 tab"; fi ;;
  list-panes) cat "$G/panes" 2>/dev/null ;;
  show|show-options) w=""; o="${*: -1}"; while (( $# )); do [[ "$1" == -t ]] && w="$2"; shift; done; cat "$G/opt/$w/$o" 2>/dev/null ;;
  set|set-option) printf '%s\n' "$*" >> "$G/tmuxset" ;;
  *) : ;;
esac
exit 0
EOF
# Simulated Telegram API. sendMessage answers with growing message ids (100, 101…). getUpdates delivers every line
# of $G/updates (one JSON update without update_id). $G/fail = net | 429 | 502 makes the next getUpdates fail.
cat > "$G/bin/curl" <<'EOF'
#!/usr/bin/env bash
cfg="" w=0; while (( $# )); do [[ "$1" == -K ]] && cfg="$2"; [[ "$1" == -w ]] && w=1; shift; done
m="$(sed -n 's|.*/bot[^/]*/\([A-Za-z]*\)".*|\1|p' "$cfg")"; body="$(cat)"
printf '%s %s\n' "$m" "$body" >> "$G/calls"
out() { printf '%s' "$1"; (( w )) && printf '\n%s' "$2"; return 0; }
case "$m" in
  sendMessage) n="$(cat "$G/mid" 2>/dev/null || echo 100)"; echo $((n + 1)) > "$G/mid"; out "{\"ok\":true,\"result\":{\"message_id\":$n}}" 200 ;;
  getUpdates)
    if [[ -f "$G/fail" ]]; then k="$(cat "$G/fail")"; rm -f "$G/fail"
      case "$k" in
        net) (( w )) && printf '\n000'; exit 28 ;;
        429) out '{"ok":false,"error_code":429,"description":"Too Many Requests: retry after 7","parameters":{"retry_after":7}}' 429 ;;
        502) out '{"ok":false,"error_code":502,"description":"Bad Gateway"}' 502 ;;
      esac
    elif [[ -s "$G/updates" ]]; then out "$(jq -sc '{ok: true, result: [to_entries[] | .value + {update_id: (.key + 1000)}]}' "$G/updates")" 200; rm -f "$G/updates"
    else out '{"ok":true,"result":[]}' 200; fi ;;
  *) out '{"ok":true,"result":true}' 200 ;;
esac
EOF
# Simulated ws-secret: $G/secret = the stored PIN; $G/interop-once = the first read fails as if Windows interop was
# not ready (has → 0, get → nothing); without $G/secret, has → 3 (not stored).
cat > "$HOME/.local/bin/ws-secret" <<'EOF'
#!/usr/bin/env bash
if [[ -f "$G/interop-once" ]]; then rm -f "$G/interop-once"; [[ "$1" == has ]] && exit 1; exit 1; fi
case "$1" in
  get) [[ -f "$G/secret" ]] && cat "$G/secret" ;;
  has) [[ -f "$G/secret" ]] || exit 3 ;;
esac
EOF
chmod 755 "$G/bin"/* "$HOME/.local/bin/ws-secret"
export PATH="$G/bin:$PATH" WS_TELEGRAM_CFG="$G/cfg" WS_TELEGRAM_ST="$G/st" WS_TELEGRAM_LOG="$G/log" WS_TELEGRAM_TOKEN=test \
       WS_TELEGRAM_CURL="$G/bin/curl" WS_TELEGRAM_NO_SERVICE=1 WS_TELEGRAM_NO_WORKSTATION=1 WS_STATE_DIR="$G/state" \
       WS_BURN_DIR="$G/burn" WS_TELEGRAM_PIN_RETRY=0
tg() { bash "$W" "$@"; }
svc() { bash "$W" service --once; }
reset() {
  rm -rf "$G/st" "$G/calls" "$G/keys" "$G/updates" "$G/log" "$G/mid" "$G/displayed" "$G/state" "$G/opt" "$G/panes"
  mkdir -p "$G/st" "$G/log"; printf '4821' > "$G/secret"; printf 'notify=all\nsummary_hour=99\n' > "$G/cfg/settings"
  rm -f "$G/cfg/text" "$G/cfg/off"; UMID=900
}
dialog() { printf ' Bash command\n   %s\n Do you want to proceed?\n ❯ 1. Yes\n   2. No, and tell Claude what to do differently (esc)\n' "$1" > "$G/screen"; }
UMID=900
msg() {   # msg <from> <reply-to or -> <text> — a message from the phone
  UMID=$((UMID + 1))
  jq -nc --argjson f "$1" --arg r "$2" --arg t "$3" --argjson id "$UMID" \
    '{message: ({message_id: $id, from: {id: $f}, chat: {id: $f}, text: $t}
               + (if $r == "-" then {} else {reply_to_message: {message_id: ($r | tonumber)}} end))}' >> "$G/updates"
}
sticker() { UMID=$((UMID + 1)); jq -nc --argjson id "$UMID" '{message: {message_id: $id, from: {id: 42}, chat: {id: 42}, sticker: {}}}' >> "$G/updates"; }
nonce_of() { local f; for f in "$G"/st/pending/*.json; do [[ "$(jq -r .mid "$f")" == "$1" ]] && basename "$f" .json; done; }
press() { jq -nc --arg d "$(nonce_of "$1"):$2" '{callback_query: {id: "c1", from: {id: 42}, message: {chat: {id: 42}}, data: $d}}' >> "$G/updates"; }
ev() { cat "$G"/log/*.jsonl 2>/dev/null | jq -r '.event'; }
has_ev() { ev | grep -qx "$1"; }
sent_after() { tail -n "$1" "$G/calls" | grep -q '^sendMessage'; }   # the last N API calls include an answer
deleted() { grep -q "^deleteMessage .*\"message_id\":$1}" "$G/calls"; }
# A risky dialog in %1 sent and its 🔐 button pressed: the notification is message 100, the PIN prompt 101.
risky_pressed() {
  dialog "terraform apply -auto-approve"; tg notify wait %1 "Claude needs your permission to use Bash"; svc
  press "$(tail -1 <<<"$(jq -r .mid "$G"/st/pending/*.json | sort -n)")" 1; svc
}

echo "1) the PIN that just works"
reset; risky_pressed
check "the 🔐 button asks for the PIN (prompt 101, a request for notification 100)" bash -c "test -f '$G/st/to-run/101.json' && grep -q 'send your PIN' '$G/calls'"
msg 42 100 "4821"; svc
check "a bare PIN as a Reply to the DIALOG ALERT approves it" grep -qx 1 "$G/keys"
check "  it is not routed to the text path (no wrong PIN, no text event)" bash -c "! (cat '$G'/log/*.jsonl | jq -r .event | grep -qE '^(pin_wrong|text_no_target|text_rejected)$')"
check "  the PIN message is deleted from the chat" deleted 901
check "  the outcome is written on the PIN prompt too" bash -c "grep '^editMessageText' '$G/calls' | grep -q '\"message_id\":101.*PIN accepted'"
check "  the request is single-use" not test -f "$G/st/to-run/101.json"
msg 42 101 "4821"; svc
check "the same PIN again on the used prompt: deleted and answered «already done», not counted" \
  bash -c "grep -q 'already done' '$G/calls' && ! test -f '$G/st/pin-fails' && grep -q '\"message_id\":902}' '$G/calls'"
reset; risky_pressed; msg 42 - "4821"; svc
check "a plain PIN message with ONE request pending approves it" grep -qx 1 "$G/keys"
reset; risky_pressed; msg 42 - "pin 4821"; svc
check "«pin 4821» works too" grep -qx 1 "$G/keys"
reset; risky_pressed; msg 42 101 "4821 ok go"; svc
check "a PIN followed by words, as a Reply to the prompt, counts as the PIN" grep -qx 1 "$G/keys"
reset; risky_pressed; msg 42 101 "yes please"; svc
check "words without the PIN on the prompt: the exact format, nothing done, not counted" \
  bash -c "! test -s '$G/keys' && grep -q 'send only your PIN' '$G/calls' && ! test -f '$G/st/pin-fails'"
reset; dialog "terraform apply"; tg notify wait %1 "perm"; tg notify wait %2 "perm"; svc
press 100 1; svc; press 101 1; svc   # two notifications (100, 101) → two prompts (102, 103)
check "two PIN requests pending" bash -c "[[ \$(ls '$G'/st/to-run/*.json | wc -l) == 2 ]]"
msg 42 - "4821"; svc
check "  a plain PIN with two pending: nothing sent, asked to Reply to the one you mean" \
  bash -c "! test -s '$G/keys' && grep -q '2 PIN requests are pending' '$G/calls' && ! test -f '$G/st/pin-fails'"
check "  and the PIN was deleted anyway" deleted 901
msg 42 103 "4821"; svc
check "  a Reply to one prompt approves that one only" bash -c "[[ \$(grep -cx 1 '$G/keys') == 1 && ! -f '$G/st/to-run/103.json' && -f '$G/st/to-run/102.json' ]]"
reset; risky_pressed; msg 42 101 "0000"; svc
check "a wrong PIN sends nothing and is counted (1 of 3)" bash -c "! test -s '$G/keys' && [[ \$(wc -l < '$G/st/pin-fails') == 1 ]] && grep -q 'Wrong PIN (1 of 3' '$G/calls'"
check "  and raises a security alert" grep -qs 'Wrong PIN while trying' "$G"/st/outbox/*_a.json
msg 42 101 "1111"; msg 42 101 "2222"; svc
check "3 wrong PINs cancel every pending request" bash -c "! ls '$G'/st/to-run/*.json && grep -q 'cancelled every pending' '$G/calls'"
reset; risky_pressed; jq '.expires = 1' "$G/st/to-run/101.json" > "$G/x" && mv "$G/x" "$G/st/to-run/101.json"
msg 42 101 "4821"; svc
check "an expired request: nothing sent, said so" bash -c "! test -s '$G/keys' && grep -q 'expired' '$G/calls'"
reset; : > "$G/screen"; : > "$G/cfg/text"
tg notify "done" %3 "Finished in 2m 0s: done, all set."; svc   # a plain notification (100), text replies on
msg 42 100 "4821"; svc
check "a bare PIN as a Reply to a text notification is NEVER a wrong text reply" \
  bash -c "! test -f '$G/st/pin-fails' && ! grep -q 'Wrong PIN in a text reply' '$G/calls' '$G'/st/outbox/*.json 2>/dev/null && ! (cat '$G'/log/*.jsonl | jq -r .event | grep -qx pin_wrong)"
check "  it is deleted and answered «no PIN request is pending»" bash -c "grep -q 'No PIN request is pending' '$G/calls' && grep -q '\"message_id\":901}' '$G/calls'"
msg 42 100 "use the opaque cursor"; svc
check "a text reply without the PIN: the exact format, not counted" \
  bash -c "grep -q 'your PIN, a space and the answer' '$G/calls' && ! test -f '$G/st/pin-fails'"
reset; risky_pressed; rm -f "$G/secret"; WS_TELEGRAM_PIN="" svc; msg 42 101 "4821"; svc
check "no PIN stored: nothing sent, the answer says «no PIN is set»" bash -c "! test -s '$G/keys' && grep -q 'no PIN is set' '$G/calls'"
reset; dialog "terraform apply"; tg notify wait %1 "perm"; svc; : > "$G/interop-once"
press 100 1; svc
check "interop not ready at the first read: the PIN is read again when needed (the 🔐 still asks)" \
  bash -c "test -f '$G/st/to-run/101.json' && grep -q loaded '$G/st/pin-status'"
reset; dialog "terraform apply"; tg notify wait %1 "perm"; svc; : > "$G/interop-once"; WS_TELEGRAM_PIN_RETRY=999 svc
check "  while it cannot be read, status says why (and never holds the PIN)" bash -c "grep -q 'did not answer' '$G/st/pin-status' && ! grep -q 4821 '$G/st/pin-status'"
check "  ws-telegram status shows «PIN in the service: no»" bash -c "bash '$W' status | grep -q 'PIN in the service: no'"
reset; risky_pressed; mkdir -p "$G/state"; : > "$G/state/ws-stop-all"; msg 42 101 "4821"; svc
check "with the emergency stop on a PIN does nothing, is deleted and the reply says why" \
  bash -c "! test -s '$G/keys' && grep -q 'emergency stop is on' '$G/calls' && grep -q '\"message_id\":901}' '$G/calls'"

echo "2) never silent"
reset; sticker; svc
check "a message without text gets an answer" grep -q 'I only read text' "$G/calls"
reset; msg 42 - "hello?"; svc
check "text with text replies off gets an answer (what to do)" grep -q 'text replies are off' "$G/calls"
reset; : > "$G/cfg/text"; msg 42 555 "4821 yes"; svc
check "a Reply to an unknown message gets an answer, and the PIN in it is deleted" bash -c "grep -q 'not a live notification' '$G/calls' && grep -q '\"message_id\":901}' '$G/calls'"
reset; msg 42 - "/help"; svc
check "/help explains the formats" grep -q 'send only your PIN' "$G/calls"
reset; msg 42 - "a"; msg 42 - "b"; msg 42 - "c"; svc
check "the answers are rate-limited (the same reason once every 20 s)" bash -c "[[ \$(grep -c 'text replies are off' '$G/calls') == 1 ]] && grep -q said_limited '$G'/log/*.jsonl"
reset; msg 99 - "4821"; svc
check "a stranger gets no answer, you get a security alert" bash -c "! grep -q '\"chat_id\":\"99\"' '$G/calls' && grep -qs 'Someone other than you' '$G'/st/outbox/*_a.json"

echo "3) modes and quiet hours"
reset; printf 'notify=approvals\ndigest=1h\n' > "$G/cfg/settings"; dialog "npm test"
tg notify wait %1 "Claude needs your permission to use Bash"
check "approvals: a permission dialog goes out at once" bash -c "ls '$G'/st/outbox/*.json"
rm -f "$G"/st/outbox/*; tg notify "done" %1 "Finished in 3m 2s: SECRETWORD all done."
check "approvals: a finished turn waits for the digest" bash -c "! ls '$G'/st/outbox/*.json && grep -q 'finished in 3m 2s' '$G/st/digest/events.jsonl'"
check "  without the conversation text" not grep -q SECRETWORD "$G/st/digest/events.jsonl"
tg notify "done" %1 "Finished in 0m 4s: Shall I use the opaque cursor?"
check "approvals: a question that blocks the tab goes out at once" bash -c "ls '$G'/st/outbox/*.json"
rm -f "$G"/st/outbox/*; tg notify "done" %1 "Finished in 1m 0s: Done. Run this and tell me the result."
check "approvals: «run this and tell me» (tmux-state.sh: waiting for you) goes out at once" bash -c "ls '$G'/st/outbox/*.json"
rm -f "$G"/st/outbox/*; tg send "you asked for this"
check "approvals: what you asked for (ws-telegram send) goes out at once" bash -c "ls '$G'/st/outbox/*_a.json"
rm -f "$G"/st/outbox/*; tg test >/dev/null
check "approvals: ws-telegram test goes out at once" bash -c "ls '$G'/st/outbox/*.json"
reset; printf 'notify=digest\n' > "$G/cfg/settings"; dialog "npm test"; tg notify wait %1 "Claude needs your permission"
check "digest: even a dialog only goes to the digest" bash -c "! ls '$G'/st/outbox/*.json && grep -q 'waited for your approval' '$G/st/digest/events.jsonl'"
reset; printf 'notify=off\n' > "$G/cfg/settings"; tg notify wait %1 "perm"; msg 99 - "x"; svc
check "off: nothing but security alerts" bash -c "! ls '$G'/st/outbox/1*[0-9].json && ls '$G'/st/outbox/*_a.json && ! test -s '$G/st/digest/events.jsonl'"
reset; tg notify "done" %1 "Finished in 2m 0s: done."
check "all: a finished turn goes out at once" bash -c "ls '$G'/st/outbox/*.json"
reset; printf 'notify=approvals\nquiet=22:00-07:00\n' > "$G/cfg/settings"; dialog "npm test"
WS_TELEGRAM_NOW_HM=23:30 tg notify wait %1 "perm"
check "quiet hours: an approval that blocks work still goes out" bash -c "ls '$G'/st/outbox/*.json"
rm -f "$G"/st/outbox/*; WS_TELEGRAM_NOW_HM=23:30 tg notify "done" %1 "Finished in 0m 4s: Shall I go on?"
check "quiet hours: a question waits for the digest" bash -c "! ls '$G'/st/outbox/*.json"
WS_TELEGRAM_NOW_HM=06:59 tg send "x"
check "quiet hours cross midnight (06:59 is quiet): what you asked for waits too" bash -c "! ls '$G'/st/outbox/*.json"
WS_TELEGRAM_NOW_HM=07:00 tg send "x"
check "  and end at 07:00" bash -c "ls '$G'/st/outbox/*_a.json"
rm -f "$G"/st/outbox/*; WS_TELEGRAM_NOW_HM=23:30 bash -c "$(declare -f msg); UMID=950; msg 99 - x"; WS_TELEGRAM_NOW_HM=23:30 svc
check "quiet hours: a security alert goes out" bash -c "ls '$G'/st/outbox/*_a.json"
mkdir -p "$G/st/digest"; echo $(( $(date +%s) - 99999 )) > "$G/st/digest/last"; echo '{"ts":1,"kind":"done","pane":"%1","text":"x"}' > "$G/st/digest/events.jsonl"
rm -f "$G"/st/outbox/*; WS_TELEGRAM_NOW_HM=23:30 tg digest tick
check "quiet hours: no digest" bash -c "! ls '$G'/st/outbox/*.json"

echo "4) the digest"
reset; printf 'notify=approvals\ndigest=1h\n' > "$G/cfg/settings"
printf '%%1\t@1\t1 api-work password=hunter2\t2.1.999\t/repos/backend\n%%2\t@2\t2 web\t2.1.999\t/repos/web\n' > "$G/panes"
mkdir -p "$G/opt/@1" "$G/opt/@2"; echo tool > "$G/opt/@1/@cphase"; echo 85 > "$G/opt/@1/@cctx"; echo 12.30 > "$G/opt/@1/@ccost"
echo "done" > "$G/opt/@2/@cphase"; echo 20 > "$G/opt/@2/@cctx"
tg notify "done" %2 "Finished in 4m 12s: SECRETWORD here"
mkdir -p "$G/st/digest"; echo $(( $(date +%s) - 3700 )) > "$G/st/digest/last"
tg digest tick
D="$(cat "$G"/st/outbox/*_a.json 2>/dev/null)"
check "a digest is queued when the period is over" jq -e '.type == "digest"' <<<"$D"
printf %s "$D" > "$G/digest.json"; jq -r .text "$G/digest.json" > "$G/digest.txt"
check "  each tab: name, project, state, context, cost" bash -c "grep -q \"1 api-work password=.* · backend — ⏳ working · ctx 85% · [$]12.30\" '$G/digest.txt' && grep -q \"2 web — 💤 idle · ctx 20%\" '$G/digest.txt'"
check "  and its last notable event" grep -q "last: ✔ finished in 4m 12s" "$G/digest.txt"
check "  no conversation text" not grep -q SECRETWORD "$G/digest.json"
check "  redacted like the rest of the kit" bash -c "grep -qF 'password=[REDACTED]' '$G/digest.txt' && ! grep -q hunter2 '$G/digest.json'"
check "  with a 🔎 button per tab" jq -e '[.options[].n] == ["d1","d2"] and (.tabs | length) == 2' <<<"$D"
svc
check "  sent with the buttons in one row" bash -c "grep '^sendMessage' '$G/calls' | grep 'Digest' | jq -R 'sub(\"^sendMessage \"; \"\") | fromjson | .reply_markup.inline_keyboard | length == 1' -r | grep -q true"
press 100 d1; svc
check "  🔎 answers with the tab's detail and the button keeps working" bash -c "grep -q '🔎 1 api-work' '$G/calls' && ls '$G'/st/pending/*.json"
rm -f "$G"/st/outbox/*; echo $(( $(date +%s) - 3700 )) > "$G/st/digest/last"; tg digest tick
check "no change since the last digest: nothing is sent" bash -c "! ls '$G'/st/outbox/*.json && grep -q digest_unchanged '$G'/log/*.jsonl"
echo thinking > "$G/opt/@2/@cphase"; echo $(( $(date +%s) - 3700 )) > "$G/st/digest/last"; tg digest tick
check "a tab that changed state: a new digest" bash -c "ls '$G'/st/outbox/*_a.json"
rm -f "$G"/st/outbox/*; echo $(( $(date +%s) - 600 )) > "$G/st/digest/last"; tg notify "done" %1 "Finished in 1m 0s: x"; tg digest tick
check "before the period is over: no digest" bash -c "! ls '$G'/st/outbox/*.json"
printf 'notify=approvals\ndigest=off\n' > "$G/cfg/settings"; rm -f "$G/st/digest/events.jsonl"; tg notify "done" %1 "Finished in 1m 0s: x"
check "digest off: what would go into it is dropped (and logged)" bash -c "! test -s '$G/st/digest/events.jsonl' && grep -q suppressed '$G'/log/*.jsonl"

echo "5) deduplication"
reset; printf '%%1\t@1\t1 api\t2.1.999\t/repos/api\n' > "$G/panes"; mkdir -p "$G/opt/@1"; echo 85 > "$G/opt/@1/@cctx"; : > "$G/screen"
printf 'notify=all\nsummary_hour=99\nusage_usd_h=999999\n' > "$G/cfg/settings"
tg check; tg check; tg check
check "a context alert once per crossing, not every 30 min" bash -c "[[ \$(grep -l 'Context at' '$G'/st/outbox/*_a.json | wc -l) == 1 ]]"
echo 60 > "$G/opt/@1/@cctx"; tg check; echo 86 > "$G/opt/@1/@cctx"; tg check
check "  after /compact (below the threshold) it can alert again" bash -c "[[ \$(grep -l 'Context at' '$G'/st/outbox/*_a.json | wc -l) == 2 ]]"
mkdir -p "$G/burn"; echo "-1 93" > "$G/burn/limits"; rm -f "$G"/st/outbox/*; tg check; tg check
check "the plan-limit alert once per crossing (it used to repeat every hour)" bash -c "[[ \$(grep -l 'Claude usage at' '$G'/st/outbox/*_a.json | wc -l) == 1 ]]"
printf 'notify=approvals\n' > "$G/cfg/settings"; rm -f "$G"/st/outbox/* "$G"/st/alerts/cross-*; tg check
check "approvals: the context alert goes into the digest" bash -c "! ls '$G'/st/outbox/*.json && grep -q 'Context at' '$G/st/digest/events.jsonl'"

echo "6) error_api: the reason and the backoff"
reset; echo net > "$G/fail"; svc
check "a network failure is logged with its reason (curl 28) and the next wait" \
  bash -c "cat '$G'/log/*.jsonl | jq -r 'select(.event == \"error_api\") | .detail' | grep -q 'curl 28.*next in 5 s'"
echo 429 > "$G/fail"; svc
check "a 429 honours retry_after" bash -c "cat '$G'/log/*.jsonl | jq -r 'select(.event == \"error_api\") | .detail' | grep -q 'HTTP 429: Too Many Requests.*next in 8 s'"
echo 502 > "$G/fail"; svc
check "a 5xx is logged as such" bash -c "cat '$G'/log/*.jsonl | jq -r 'select(.event == \"error_api\") | .detail' | grep -q 'HTTP 502: Bad Gateway'"
check "status shows the last API error" bash -c "bash '$W' status | grep -q 'Last Telegram API error: .*HTTP 502'"
check "the exponential backoff (selftest: 5 10 20 … 300, 429 = retry_after + 1, 409 = 60)" bash -c "[[ \$(HOME='$ROOT/files/home' bash '$W' selftest) == ok ]]"

echo "7) settings, status and the menu"
reset
check "notify approvals|digest|all|off is saved (one line)" bash -c "bash '$W' notify digest >/dev/null && bash '$W' notify approvals >/dev/null && [[ \$(grep -c '^notify=' '$G/cfg/settings') == 1 ]] && grep -qx notify=approvals '$G/cfg/settings'"
check "digest 30m|1h|2h|4h|off" bash -c "bash '$W' digest 2h >/dev/null && grep -qx digest=2h '$G/cfg/settings' && ! bash '$W' digest 3h >/dev/null"
check "quiet hours are validated" bash -c "bash '$W' quiet 22:00-07:00 >/dev/null && grep -qx quiet=22:00-07:00 '$G/cfg/settings' && ! bash '$W' quiet 25:00-07:00 >/dev/null && ! bash '$W' quiet '22:00-07:00;id' >/dev/null"
check "a change is published for the menu (@tg_mode, @tg_digest, @tg_quiet)" bash -c "grep -q '@tg_mode approvals' '$G/tmuxset' && grep -q '@tg_quiet 22:00-07:00' '$G/tmuxset'"
check "a change is logged as setting_changed" grep -qs setting_changed "$G"/log/*.jsonl
rm -f "$G/cfg/settings"
check "defaults: approvals, digest every 1h, no quiet hours" bash -c "bash '$W' status | grep -q 'Sends: approvals' && bash '$W' status | grep -q 'Digest: 1h' && bash '$W' status | grep -q 'quiet hours: off'"
M="$ROOT/files/home/.config/tmux-claude/menu-telegram.tmux"
check "the menu has every setting (toggle, 4 modes, 5 periods + now, quiet presets + custom + off, text, approve, run, PIN, test, status)" \
  bash -c "for c in toggle 'notify approvals' 'notify digest' 'notify all' 'notify off' 'digest 30m' 'digest 1h' 'digest 2h' 'digest 4h' 'digest off' 'digest now' \
           'quiet 22:00-07:00' 'quiet 23:00-08:00' 'quiet %1' 'quiet off' 'text toggle' 'approve #' 'run pin' 'run no-pin' 'text pin' \"ws-telegram test'\" \"ws-telegram status\"; do grep -qF \"\$c\" '$M' || { echo \"missing \$c\"; exit 1; }; done"
check "every ws-telegram subcommand of the menu exists" bash -c "grep -oE 'ws-telegram [a-z-]+' '$M' | sort -u | while read -r _ s; do grep -qE \"^  \$s\\)|^  \$s\\) |[|(]\$s[|)]\" '$W' || { echo \"no \$s\"; exit 1; }; done"
check "every script of the menu is in the kit" bash -c "grep -oE '~/.local/bin/[a-z-]+' '$M' | sort -u | while read -r s; do test -x '$ROOT/files/home/.local/bin/'\"\${s##*/}\" || { echo \"no \$s\"; exit 1; }; done"
KEYS="$(sed -nE 's/^  "([^"\\]|\\.)*" ([^ "]+) .*/\2/p' "$M" | tr '\n' ' ')"
check "the menu entries and their keys (one each, no key repeated)" test "$KEYS" == "o a d e x 3 1 2 4 0 n q w c z t p r P s S B BSpace "
check "the PIN is typed in a terminal popup, never through tmux options or argv" bash -c "grep -q \"display-popup.*'ws-telegram text pin'\" '$M' && ! grep -qE 'telegram-pin|@tg_pin' '$M'"
check "the workstation menu opens it" grep -q 'source-file ~/.config/tmux-claude/menu-telegram.tmux' "$ROOT/files/home/.config/tmux-claude/menu-workstation.tmux"
check "the menu file is in the manifest" grep -qx '.config/tmux-claude/menu-telegram.tmux' "$ROOT/manifest.txt"
# tmux parses it: on a private server in this test's own socket folder (never your tmux), where one may start.
mkdir -p "$T/sock"
ptmux() { env -u TMUX TMUX_TMPDIR="$T/sock" "$REAL_TMUX" -L wstg -f /dev/null "$@"; }
if [[ -n "$REAL_TMUX" ]] && ptmux new-session -d 2>/dev/null; then
  check "tmux parses the menu file (source-file -n)" ptmux source-file -n "$M"
  check "  and would reject a broken one" not ptmux source-file -n "$ROOT/tests/telegram-quiet.sh"
  ptmux kill-server 2>/dev/null
else echo "  skip tmux cannot start a server here (a sandbox); ws-test parses the menu on its private tmux"; fi

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
