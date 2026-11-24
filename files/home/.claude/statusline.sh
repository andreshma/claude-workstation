#!/usr/bin/env bash
#
# statusline.sh — Claude Code status line: model · context traffic light · cost ·
# usage limits (if the plan exposes them) · git branch. It also publishes the context %
# on the tmux tab (@cctx, @cctxc) so it shows on every tab at once.
# It also leaves the per-session cost and the usage limits for the watcher (tmux-watch) and ws-telegram in
# /tmp/claude-burn-<uid>/ (nobody wrote them before: the usage traffic light and the limits notification had no data).
IFS=$'\t' read -r model pct cost five week dir sesion < <(jq -r '[
  (.model.display_name // "?"),
  ((.context_window.used_percentage // 0) | floor),
  (.cost.total_cost_usd // 0),
  ((.rate_limits.five_hour.used_percentage // -1) | floor),
  ((.rate_limits.seven_day.used_percentage // -1) | floor),
  (.workspace.current_dir // .cwd // ""),
  (.session_id // "sin-id")
] | @tsv')

# traffic light: <50 green · 50-79 yellow · >=80 red  (ANSI for Claude, colourN for tmux)
ansi()  { if (( $1 >= 80 )); then echo 31; elif (( $1 >= 50 )); then echo 33; else echo 32; fi; }
tcol()  { local n=ok d=colour82 v; if (( $1 >= 80 )); then n=alert d=colour196; elif (( $1 >= 50 )); then n=tool d=colour214; fi; v="$(tmux show -gqv "@t_$n" 2>/dev/null)"; echo "${v:-$d}"; }
bar()   { local f=$(( $1 / 10 )); printf '%*s' "$f" '' | tr ' ' '#'; printf '%*s' $(( 10 - f )) '' | tr ' ' '.'; }

if [[ -n "${TMUX_PANE:-}" ]]; then
  tmux set -w -t "$TMUX_PANE" @cctx "$pct" \; set -w -t "$TMUX_PANE" @cctxc "$(tcol "$pct")" 2>/dev/null
  tmux set -w -t "$TMUX_PANE" @cmodel "$model" \; set -w -t "$TMUX_PANE" @ccost "$(printf '%.2f' "$cost")" 2>/dev/null
fi

# Samples for the watcher and ws-telegram: accumulated session cost (for $/h) and usage limits.
b="${WS_BURN_DIR:-/tmp/claude-burn-$(id -u)}"
if mkdir -p "$b" 2>/dev/null && chmod 700 "$b" 2>/dev/null; then
  l="$b/${sesion//[^A-Za-z0-9-]/}.log"
  [[ "$(tail -n 1 "$l" 2>/dev/null | cut -d' ' -f2)" == "$cost" ]] || echo "$(date +%s) $cost" >> "$l"
  (( five >= 0 || week >= 0 )) && echo "$five $week" > "$b/limits"
fi

out=$(printf '%s \033[%sm[%s] %s%%\033[0m · $%.2f' "$model" "$(ansi "$pct")" "$(bar "$pct")" "$pct" "$cost")
(( five >= 0 )) && out+=$(printf ' · 5h \033[%sm%s%%\033[0m' "$(ansi "$five")" "$five")
(( week >= 0 )) && out+=$(printf ' · 7d \033[%sm%s%%\033[0m' "$(ansi "$week")" "$week")
branch="$(git -C "$dir" branch --show-current 2>/dev/null)"
[[ -n "$branch" ]] && out+=" · $branch"
printf '%s\n' "$out"
