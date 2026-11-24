#!/usr/bin/env bash
#
# win-notify.sh <prompt|wait|done> — Windows notification when a Claude on a tab you are
# not looking at needs you (permission or question) or finishes a long turn.
# Invoked by the UserPromptSubmit (prompt), Notification (wait) and Stop (done) hooks.
# tmux-watch uses it with "alert" (JSON with title and message) for reminders and usage;
# "alert" notifies even if you are looking at the tab, but respects @cnotify.
#
# · No notification if the tab is active and the terminal has the focus.
# · On finish, it only notifies if the turn lasted at least CLAUDE_NOTIFY_MIN_SECS (20 s by default).
# · Turn it off from the menu (Ctrl+b m → Workstation → Windows notifications) or with: tmux set -g @cnotify off
# · CLAUDE_NOTIFY_FORCE=1 notifies even if you are looking at the tab (for testing).
# · Uses PowerShell 5.1 with -EncodedCommand (no .ps1 files or modules; the execution policy
#   does not affect it) and runs in the background: the hook never makes Claude wait.
# Silent and always exit 0.
[[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null || exit 0
input="$(cat)"
p="$TMUX_PANE"
ts="/tmp/claude-notify-$(id -u)-${p#%}"
min="${CLAUDE_NOTIFY_MIN_SECS:-20}"
js() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
b64() { printf '%s' "$1" | base64 -w0; }
# Claude's last message: from the hook or, if it is not there, from the end of the transcript.
last_msg() {
  local m; m="$(js .last_assistant_message)"
  [[ -n "$m" ]] || m="$(tail -n 80 "$(js .transcript_path)" 2>/dev/null \
    | jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' 2>/dev/null)"
  printf '%s' "$m"
}
# All of Claude's text in this turn (since your last message): commands may come in intermediate messages.
turn_texts() {
  local tp; tp="$(js .transcript_path)"; [[ -f "$tp" ]] || return 0
  tail -n 600 "$tp" | jq -rs '
    (to_entries | map(select(.value.type == "user" and ((.value.message.content | type) == "string"
        or ([.value.message.content[]? | select(.type == "tool_result")] | length) == 0))) | last | .key) as $k
    | .[(($k // -1) + 1):] | map(select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text)
    | join("\n\n")' 2>/dev/null
}
# Is it asking you for something? A question, a command with ! or an action verb aimed at you. Then it notifies even
# if the turn was short. The verbs come from the language packs (keys notify.command, notify.asks and
# notify.question; see ws-lang): English, plus Spanish with `ws-lang es`. Without the packs only the fixed marks count.
asks_something() {
  local verbs="" closing="" question=""
  local command_re='(^|[[:space:]`])![[:space:]]*[a-z./~]|```(bash|sh|shell|zsh|console)'
  local closing_re='\?[[:space:]]*$|(^|[[:space:]`])![[:space:]]*[a-z]'
  # shellcheck source=/dev/null
  if source "$HOME/.local/lib/ws-lang.sh" 2>/dev/null; then
    # shellcheck disable=SC2016   # literal backticks of the expression, not a command substitution
    ws_lang_var verbs notify.command && command_re+="|(${verbs})"'[^`]{0,50}`[a-z./~]'
    ws_lang_var question notify.question && closing_re+="|${question}"
    ws_lang_var closing notify.asks && closing_re+="|\\b(${closing})\\b"
  fi
  { turn_texts; last_msg; } | grep -qiE -- "$command_re" \
    && return 0   # a command (with !, in a bash block or after «run») anywhere in the turn
  last_msg | tail -c 1500 | grep -qiE -- "$closing_re"
}

case "${1:-}" in
  prompt) date +%s > "$ts"; exit 0 ;;
  wait)
    [[ "$(js .notification_type)" == idle_prompt ]] && exit 0   # Stop already notified
    body="$(js .message)"; body="${body:-Needs your answer}" ;;
  done)
    start="$(cat "$ts" 2>/dev/null)"; rm -f "$ts"
    # Turn that continued without a new prompt (after a background task, for example): notifies if it asks something.
    [[ -n "$start" ]] || { asks_something || exit 0; start=$(date +%s); }
    secs=$(( $(date +%s) - start )); (( secs >= min )) || asks_something || exit 0
    msg="$(js .last_assistant_message | tr '\n\t' '  ' | cut -c1-140)"
    body="Finished in $(( secs / 60 ))m $(( secs % 60 ))s${msg:+: $msg}" ;;
  alert)
    body="$(js .message)"; atitle="$(js .title)"; CLAUDE_NOTIFY_FORCE=1 ;;
  *) exit 0 ;;
esac

# Telegram (ws-telegram, ADR-010): always; the question goes redacted and with buttons to answer.
target="$p"; [[ -n "${WS_POPUP_SESSION:-}" ]] && target="popup:$WS_POPUP_SESSION"   # Claude inside a popup
# Telegram gets the whole end of the message (commands with ! are usually at the end), not just 140 characters.
tg_body="$body"; full=""
if [[ "$1" == "done" ]]; then   # notification: end of the message; `!` commands: whole message (0600, ws-telegram deletes it)
  tg_body="${body%%:*}:"$'\n'"$(last_msg | tail -c 1200)"
  full="$(mktemp)"; turn="$(turn_texts)"; [[ -n "$turn" ]] || turn="$(last_msg)"
  printf '%s' "$turn" > "$full"
fi
setsid "$HOME/.local/bin/ws-telegram" notify "$1" "$target" "$tg_body" "$p" "$full" >/dev/null 2>&1 </dev/null &
[[ "$(tmux show -gqv @cnotify)" == off ]] && exit 0
if [[ -z "${CLAUDE_NOTIFY_FORCE:-}" && "$(tmux display -p -t "$p" '#{window_active}')" == 1 ]] &&
   tmux list-clients -F '#{client_flags}' 2>/dev/null | grep -q focused; then exit 0; fi
command -v powershell.exe >/dev/null || exit 0

title="${atitle:-Claude · $(tmux display -p -t "$p" '#{window_index} #{window_name}')}"
ps="\$d={param(\$s)[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\$s))}
\$t=& \$d '$(b64 "$title")'; \$b=& \$d '$(b64 "$body")'
\$null=[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]
\$null=[Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom.XmlDocument,ContentType=WindowsRuntime]
\$e=[Security.SecurityElement]; \$x=New-Object Windows.Data.Xml.Dom.XmlDocument
\$x.LoadXml(\"<toast activationType='protocol' launch='ws-claude://focus/${p#%}'><visual><binding template='ToastGeneric'><text>\$(\$e::Escape(\$t))</text><text>\$(\$e::Escape(\$b))</text></binding></visual><actions><action content='Go to the tab'activationType='protocol' arguments='ws-claude://focus/${p#%}'/></actions></toast>\")
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new(\$x))"
enc="$(printf '%s' "$ps" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)"
setsid powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand "$enc" \
  >/dev/null 2>&1 </dev/null &
exit 0
