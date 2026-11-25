#!/usr/bin/env bash
#
# ws-runtime-gate.sh — UserPromptSubmit and PreToolUse hook: holds every Claude while an emergency stop or a hard
# spend limit is in force. Exit 2 blocks the prompt or the tool and tells the reason (to you or to Claude).
#   stop-all  ~/.local/state/ws-stop-all exists (written by ws-stop-all, WS-AI-025): nothing runs in any tab until you
#             run «ws-stop-all --clear» in a terminal.
#   budget    ~/.local/state/ws-budget-over (written by «ws-telemetry build» when budgets.conf has hard=1, WS-AI-019)
#             lists the projects at or over 100 % of their monthly budget; «(total)» stands for every project. Work in
#             those projects is held until «ws-telemetry budgets --override <project> [hours]».
# Failure mode: the stop marker blocks with or without jq. The budget gate fails OPEN: a missing, unreadable or stale
# flag (older than 2 hours: the dashboard stopped updating) lets work continue, because it cannot know the spend.
# The project is the folder name of the session's cwd, the same key ws-telemetry and budgets.conf use.
# Every hold is recorded as an audit «held» event (not «blocked»: ws-anomaly counts only what the guard blocks).
# Usage: called by Claude Code with the hook JSON on stdin · WS_STATE_DIR overrides ~/.local/state (tests).
set -uo pipefail
ST="${WS_STATE_DIR:-$HOME/.local/state}"
STOP="$ST/ws-stop-all" OVER="$ST/ws-budget-over" OVR="$ST/ws-budget-override"
# Fast path, the usual case: no process is started (stdin is drained with a builtin so the writer gets no EPIPE).
[[ -e "$STOP" || -e "$OVER" ]] || { IFS= read -r -d '' _ || true; exit 0; }
input="$(cat)"
audit() { "$HOME/.claude/hooks/audit.sh" held "$1" <<<"$input" >/dev/null 2>&1; }

if [[ -e "$STOP" ]]; then
  # /exit and /quit still pass: ws-stop-all closes the tabs with them.
  grep -qE '"prompt"[[:space:]]*:[[:space:]]*"[[:space:]]*/(exit|quit)[[:space:]]*"' <<<"$input" && exit 0
  since="$(sed -n 's/^ts=//p' "$STOP" 2>/dev/null | head -1)"
  audit "stop-all switch"
  printf 'BLOCKED: the emergency stop is on (ws-stop-all%s). Do nothing else and wait: the user resumes with ' \
    "${since:+ since $since}" >&2
  printf '«ws-stop-all --clear» in a terminal.\n' >&2
  exit 2
fi

command -v jq >/dev/null || exit 0
(( $(date +%s) - $(stat -c %Y "$OVER" 2>/dev/null || echo 0) <= 7200 )) || exit 0
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"; proj="${cwd%/}"; proj="${proj##*/}"
[[ -n "$proj" ]] || exit 0
hit="$(jq -r --arg p "$proj" '[.over[]? | select(.project == $p or .project == "(total)")][0]
  | if . then "\(.project)\t\(.pct)\t\(.spent)\t\(.budget)" else empty end' "$OVER" 2>/dev/null)"
[[ -n "$hit" ]] || exit 0
IFS=$'\t' read -r key pct spent budget <<<"$hit"
now="$(date +%s)"
# Overrides: «<project> <until epoch>» per line, written by ws-telemetry budgets --override (audited there).
if awk -v p="$proj" -v k="$key" -v n="$now" '($1 == p || $1 == k || $1 == "*") && $2 > n { f = 1 } END { exit !f }' "$OVR" 2>/dev/null
then exit 0; fi
audit "budget $key $pct%"
printf 'BLOCKED: %s is at %s%% of its monthly budget ($%s of $%s) and budgets.conf has hard=1. ' "$key" "$pct" "$spent" "$budget" >&2
printf 'Stop here. To go on, the user runs «ws-telemetry budgets --override %s [hours]» in a terminal.\n' "$proj" >&2
exit 2
