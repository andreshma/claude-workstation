#!/usr/bin/env bash
#
# ws-ruteo-hook.sh — Claude Code UserPromptSubmit hook: model routing with your confirmation (ADR-009).
#
# If a rule in ~/.config/ws-ruteo/reglas.conf says the task belongs to a different level than the tab's
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
source "$HOME/.local/lib/ws-ruteo.sh" 2>/dev/null || exit 0
entrada="$(cat)"
texto="$(jq -r '.prompt // empty' <<<"$entrada" 2>/dev/null)"
p="$TMUX_PANE"; n="${p#%}"

(( ${#texto} >= 12 )) || exit 0
[[ "$texto" =~ ^[[:space:]]*[/!#] ]] && exit 0
[[ "$(tmux show -gqv @cruteo)" == off ]] && exit 0

# Resubmission you already confirmed in the popup or with `cr`: goes through without asking.
if [[ -f "$WS_RUTEO_RUN/pass-$n" ]]; then
  h="$(cat "$WS_RUTEO_RUN/pass-$n")"; rm -f "$WS_RUTEO_RUN/pass-$n"
  [[ "$h" == "$(ruteo_huella "$texto")" ]] && exit 0
fi

# No loops: do not ask if routing has just changed this tab's model (2 min) or if the text carries a pasted
# «/model claude-…» (a sign that the switch was typed on top of your text).
si="$(tmux show -wqv -t "$p" @cruteo_si 2>/dev/null)"
if [[ "${si#*:}" =~ ^[0-9]+$ ]] && (( $(date +%s) - ${si#*:} < 120 )); then exit 0; fi
[[ "$texto" == *"/model claude-"* ]] && exit 0

read -r nivel regla <<<"$(ruteo_clasificar "$texto")"
actual="$(ruteo_nivel_de "$(tmux show -wqv -t "$p" @cmodel 2>/dev/null)")"
[[ -n "$actual" && "$regla" != defecto ]] || exit 0
if [[ "$nivel" == "$actual" ]]; then ruteo_registrar hook "$nivel" "$regla" "$actual" igual "${#texto}"; exit 0; fi

no="$(tmux show -wqv -t "$p" @cruteo_no 2>/dev/null)"   # "nivel:epoch" of the last rejection
if [[ "${no%%:*}" == "$nivel" && "${no#*:}" =~ ^[0-9]+$ ]] && (( $(date +%s) - ${no#*:} < 1800 )); then
  ruteo_registrar hook "$nivel" "$regla" "$actual" silenciado "${#texto}"; exit 0
fi

# Switching to a lower model with a lot of context costs more than it saves (the first answer re-reads everything
# without cache). With context ≥ bajar_max_ctx (30 % by default, ~/.config/ws-ruteo/ajustes.conf) the model is not
# changed: delegating to the cheap subagent is suggested to Claude (without blocking) or, if that rule has none,
# nothing is asked.
orden() { case "$1" in haiku) echo 0 ;; sonnet) echo 1 ;; opus) echo 2 ;; fable) echo 3 ;; *) echo 2 ;; esac; }
if (( $(orden "$nivel") < $(orden "$actual") )); then
  ctx="$(tmux show -wqv -t "$p" @cctx 2>/dev/null)"; ctx="${ctx%%[!0-9]*}"
  max="$(sed -n 's/^bajar_max_ctx=//p' "$HOME/.config/ws-ruteo/ajustes.conf" 2>/dev/null | head -1)"; max="${max:-30}"
  if [[ -n "$ctx" ]] && (( ctx >= max )); then
    sub=""
    case "$nivel:$regla" in sonnet:sql) sub=sql-rapido ;; haiku:*) sub=explorador ;; esac
    if [[ -n "$sub" ]]; then
      ruteo_registrar hook "$nivel" "$regla" "$actual" subagente "${#texto}"
      jq -nc --arg c "Routing (context ${ctx}%): this task is level ${nivel}. Delegate the main part to the ${sub} subagent (model ${nivel}) instead of solving it with this conversation's model; that way the cache is not lost." \
        '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
    else
      ruteo_registrar hook "$nivel" "$regla" "$actual" sin_bajar "${#texto}"
    fi
    exit 0
  fi
fi

( umask 077; mkdir -p "$WS_RUTEO_RUN"; printf '%s' "$texto" > "$WS_RUTEO_RUN/prompt-$n" )
if [[ -z "${WS_RUTEO_SIN_POPUP:-}" ]]; then
  setsid "$HOME/.local/bin/ws-ruteo-confirmar" "$p" "$nivel" "$regla" "$actual" >/dev/null 2>&1 </dev/null &
fi
jq -nc --arg r "Routing: this task looks like level ${nivel} (rule: ${regla}) and this tab uses ${actual}. Choose in the popup; your text is not lost." \
  '{decision: "block", reason: $r}'
exit 0
