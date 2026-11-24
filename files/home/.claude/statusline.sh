#!/usr/bin/env bash
#
# statusline.sh — status line de Claude Code: modelo · semáforo de contexto · costo ·
# límites de uso (si el plan los expone) · rama git. Además publica el % de contexto
# en la pestaña tmux (@cctx, @cctxc) para verlo en todas las pestañas a la vez.
# También deja para el vigía (tmux-watch) y para ws-telegram el costo por sesión y los límites de uso en
# /tmp/claude-burn-<uid>/ (antes nadie los escribía: el semáforo de consumo y el aviso de límites no tenían datos).
IFS=$'\t' read -r model pct cost five week dir sesion < <(jq -r '[
  (.model.display_name // "?"),
  ((.context_window.used_percentage // 0) | floor),
  (.cost.total_cost_usd // 0),
  ((.rate_limits.five_hour.used_percentage // -1) | floor),
  ((.rate_limits.seven_day.used_percentage // -1) | floor),
  (.workspace.current_dir // .cwd // ""),
  (.session_id // "sin-id")
] | @tsv')

# semáforo: <50 verde · 50-79 amarillo · >=80 rojo  (ANSI para Claude, colourN para tmux)
ansi()  { if (( $1 >= 80 )); then echo 31; elif (( $1 >= 50 )); then echo 33; else echo 32; fi; }
tcol()  { local n=ok d=colour82 v; if (( $1 >= 80 )); then n=alert d=colour196; elif (( $1 >= 50 )); then n=tool d=colour214; fi; v="$(tmux show -gqv "@t_$n" 2>/dev/null)"; echo "${v:-$d}"; }
bar()   { local f=$(( $1 / 10 )); printf '%*s' "$f" '' | tr ' ' '#'; printf '%*s' $(( 10 - f )) '' | tr ' ' '.'; }

if [[ -n "${TMUX_PANE:-}" ]]; then
  tmux set -w -t "$TMUX_PANE" @cctx "$pct" \; set -w -t "$TMUX_PANE" @cctxc "$(tcol "$pct")" 2>/dev/null
  tmux set -w -t "$TMUX_PANE" @cmodel "$model" \; set -w -t "$TMUX_PANE" @ccost "$(printf '%.2f' "$cost")" 2>/dev/null
fi

# Muestras para el vigía y ws-telegram: costo acumulado de la sesión (para $/h) y límites de uso.
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
