#!/usr/bin/env bash
#
# ws-routing.sh — Claude Code UserPromptSubmit hook: model routing with your confirmation (ADR-009).
#
# If a rule in ~/.config/ws-routing/rules.conf says the task belongs to a different level than the tab's
# model (e.g. SQL on Opus → Sonnet), it stops the submission, saves the text (0600, deleted once used) and opens
# a popup: [y] switch and send · [n] send with the current one · [x] give the text back without sending.
# With no matching rule, it does not ask. It never changes anything without your answer; with no answer in 30 s
# it sends with the current model.
#
# Switching to a lower model is only asked with little context (< 30 %); with more, the cheap subagent is suggested
# to Claude. It does not ask if: there is no tmux, the text starts with / ! #, it is very short, routing is off
# (Menu → Claude → Model → Automatic routing), or you rejected that same level on this tab < 30 min ago.
# Silent and always exit 0 (a failure in the hook never blocks Claude).
set -uo pipefail
[[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null && command -v jq >/dev/null || exit 0
# shellcheck source=/dev/null
source "$HOME/.local/lib/ws-routing.sh" 2>/dev/null || exit 0
input="$(cat)"
text="$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null)"
p="$TMUX_PANE"; n="${p#%}"

(( ${#text} >= 12 )) || exit 0
[[ "$text" =~ ^[[:space:]]*[/!#] ]] && exit 0
[[ "$(tmux show -gqv @croute)" == off ]] && exit 0

# Resubmission you already confirmed in the popup or with `cr`: goes through without asking.
if [[ -f "$WS_ROUTING_RUN/pass-$n" ]]; then
  h="$(cat "$WS_ROUTING_RUN/pass-$n")"; rm -f "$WS_ROUTING_RUN/pass-$n"
  [[ "$h" == "$(routing_fingerprint "$text")" ]] && exit 0
fi

# No loops: do not ask if routing has just changed this tab's model (2 min) or if the text carries a pasted
# «/model claude-…» (a sign that the switch was typed on top of your text).
yes="$(tmux show -wqv -t "$p" @croute_yes 2>/dev/null)"
if [[ "${yes#*:}" =~ ^[0-9]+$ ]] && (( $(date +%s) - ${yes#*:} < 120 )); then exit 0; fi
[[ "$text" == *"/model claude-"* ]] && exit 0

read -r level rule <<<"$(routing_classify "$text")"
current="$(routing_level_of "$(tmux show -wqv -t "$p" @cmodel 2>/dev/null)")"
[[ -n "$current" && "$rule" != default ]] || exit 0
if [[ "$level" == "$current" ]]; then routing_log hook "$level" "$rule" "$current" same "${#text}"; exit 0; fi

no="$(tmux show -wqv -t "$p" @croute_no 2>/dev/null)"   # "level:epoch" of the last rejection
if [[ "${no%%:*}" == "$level" && "${no#*:}" =~ ^[0-9]+$ ]] && (( $(date +%s) - ${no#*:} < 1800 )); then
  routing_log hook "$level" "$rule" "$current" muted "${#text}"; exit 0
fi

# Switching to a lower model with a lot of context costs more than it saves (the first answer re-reads everything
# without cache). With context ≥ downgrade_max_ctx (30 % by default, ~/.config/ws-routing/settings.conf) the model is not
# changed: delegating to the cheap subagent is suggested to Claude (without blocking) or, if that rule has none,
# nothing is asked.
rank() { case "$1" in haiku) echo 0 ;; sonnet) echo 1 ;; opus) echo 2 ;; fable) echo 3 ;; *) echo 2 ;; esac; }
if (( $(rank "$level") < $(rank "$current") )); then
  ctx="$(tmux show -wqv -t "$p" @cctx 2>/dev/null)"; ctx="${ctx%%[!0-9]*}"
  max="$(sed -nE 's/^(downgrade|bajar)_max_ctx=//p' "$HOME/.config/ws-routing/settings.conf" 2>/dev/null | head -1)"; max="${max:-30}"
  if [[ -n "$ctx" ]] && (( ctx >= max )); then
    sub=""
    case "$level:$rule" in sonnet:sql) sub=sql-quick ;; haiku:*) sub=explorer ;; esac
    if [[ -n "$sub" ]]; then
      routing_log hook "$level" "$rule" "$current" subagent "${#text}"
      jq -nc --arg c "Routing (context ${ctx}%): this task is level ${level}. Delegate the main part to the ${sub} subagent (model ${level}) instead of solving it with this conversation's model; that way the cache is not lost." \
        '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
    else
      routing_log hook "$level" "$rule" "$current" no_downgrade "${#text}"
    fi
    exit 0
  fi
fi

( umask 077; mkdir -p "$WS_ROUTING_RUN"; printf '%s' "$text" > "$WS_ROUTING_RUN/prompt-$n" )
if [[ -z "${WS_ROUTING_NO_POPUP:-}" ]]; then
  setsid "$HOME/.local/bin/ws-routing-confirm" "$p" "$level" "$rule" "$current" >/dev/null 2>&1 </dev/null &
fi
jq -nc --arg r "Routing: this task looks like level ${level} (rule: ${rule}) and this tab uses ${current}. Choose in the popup; your text is not lost." \
  '{decision: "block", reason: $r}'
exit 0
