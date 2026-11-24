#!/usr/bin/env bash
#
# tmux-state.sh <evento> — publica el estado de Claude Code en su pestaña tmux.
# Lo invocan los hooks de ~/.claude/settings.json.
#
# Opciones de ventana que escribe:
#   @cmain/@cmainc  estado del hilo principal (texto y color)
#   @csub           subagentes activos (los cuenta del registro)
#   @cts            hora (epoch) del último evento; tmux-watch la usa para detectar inactividad
#   @cs/@csc        lo que muestra la barra; lo pinta tmux-estado con su tiempo (🧠 pensando 42s, 🔧 Bash 2m,
#                   ✋ aprobar Bash 5m, ✔ listo hace 12m…). Sin tmux-estado: "te necesita", "agentes (N)" o @cmain.
#   @cfase/@cdesde/@cdet  fase (pensando|herramienta|permiso|pregunta|tetoca|compactando|listo|error), desde cuándo
#                   y qué hace («Bash: npm test»); @cturno inicio del turno; @cultimo última herramienta; @cpane
#                   el panel de Claude. (Parche 56: estado detallado.)
#
# Registro de subagentes (lo lee tmux-agents): /tmp/claude-agents-<uid>/<pane>/
#   a-<agent_id>  una línea: tipo<TAB>inicio<TAB>última actividad<TAB>hora<TAB>agent_id
#   done.log      últimos 10 terminados: hora<TAB>tipo<TAB>resumen de su respuesta<TAB>agent_id
# Con el agent_id, tmux-agents abre la transcripción del subagente (razonamiento incluido).
# Los eventos de herramientas que traen agent_id son de un subagente y actualizan su
# actividad; sin agent_id son del hilo principal.
# «Te toca»: al terminar un turno (Stop) se mira el ÚLTIMO mensaje de Claude; si termina en pregunta o te pide hacer
# algo (correr un comando, decidir, confirmar, pasarle un dato), la pestaña queda en 👉 te toca y el vigía la cuenta
# en ⚠, en lugar de ✔ listo. Solo se decide con el texto; no se guarda ni sale de la máquina. WS_TETOCA=0 lo apaga.
# Silencioso y siempre exit 0: nunca bloquea a Claude ni le agrega contexto.

# pide <transcripción> [último mensaje] — 0 si el último mensaje de Claude te deja algo por hacer o responder.
pide() {
  local txt="${2:-}" cola ultima
  if [[ -z "$txt" && -f "${1:-}" ]]; then
    txt="$(tail -c 400000 "$1" | jq -rnR '[inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not))
            | [.message.content[]? | select(.type == "text") | .text] | join("\n") | select(length > 0)] | last // ""' 2>/dev/null)"
  fi
  [[ -n "$txt" ]] || return 1
  cola="$(tail -c 900 <<<"$txt")"
  ultima="$(grep -v '^[[:space:]]*$' <<<"$cola" | tail -1 | sed -E 's/[[:space:]*_`)"»]+$//')"
  [[ "$ultima" == *"?" ]] && return 0                                  # termina preguntando
  grep -q '¿[^?]*?' <<<"$cola" && return 0                              # una pregunta en el cierre
  grep -Eiq '(^|[^[:alpha:]])(corre|c[oó]rrelo|ejecuta|ejec[uú]talo|p[eé]game|dime|conf[ií]rmame|confirma|decide|elige|p[aá]same|av[ií]same|necesito que|te toca|falta que|aplica|reinicia|abre|run this|run it|let me know|tell me|please (confirm|run|share|paste))([^[:alpha:]]|$)' <<<"$cola"
}
# Modo prueba, sin tmux: tmux-state.sh --pide <transcripción>  → sale con 0 si te toca.
[[ "${1:-}" == --pide ]] && { pide "${2:-}" "${3:-}"; exit $?; }
[[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null || exit 0
umask 077
input="$(cat)"
win="$TMUX_PANE"
reg="/tmp/claude-agents-$(id -u)/${win#%}"
mkdir -p "$reg" 2>/dev/null

opt() { tmux show -wv -t "$win" "$1" 2>/dev/null; }
# pon <opción> <valor> — escribe la opción solo si cambia. Cada escritura hace que tmux redibuje la barra, y con un
# menú o una flotante abiertos ese redibujo se ve como parpadeo; una herramienta dispara varios eventos por segundo.
pon() { [[ "$(opt "$1")" == "$2" ]] || tmux set -w -t "$win" "$1" "$2" 2>/dev/null; }
# tcolor <nombre> <por defecto> — color semántico del tema activo (@t_ok, @t_think…; ver tmux-theme).
tcolor() { local v; v="$(tmux show -gqv "@t_$1" 2>/dev/null)"; echo "${v:-$2}"; }
js()  { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
now() { date +%s; }
one() { tr '\n\t' '  ' | sed 's/ *$//' | cut -c1-"$1"; }

# nsub — subagentes activos según el registro.
nsub() { find "$reg" -maxdepth 1 -name 'a-*' 2>/dev/null | wc -l; }

# render — calcula @cs/@csc/@csub a partir del estado principal y del registro.
render() {
  local m c n
  local t0; t0="$(opt @cts)"
  # La hora del último evento solo la usa el vigía (inactividad en minutos): con refrescarla cada 5 s alcanza.
  [[ -n "$t0" ]] && (( $(now) - t0 < 5 )) || tmux set -w -t "$win" @cts "$(now)" 2>/dev/null
  m="$(opt @cmain)"; c="$(opt @cmainc)"; n="$(nsub)"
  if (( n > 0 )); then pon @csub "$n"; elif [[ -n "$(opt @csub)" ]]; then tmux set -wu -t "$win" @csub 2>/dev/null; fi
  if [[ -x "$HOME/.local/bin/tmux-estado" && -n "$(opt @cfase)" ]]; then
    "$HOME/.local/bin/tmux-estado" --pintar "$win"
  elif [[ "$m" == "te necesita" || "$m" == "te toca" || "$m" == "error API" ]] || (( n == 0 )); then
    tmux set -w -t "$win" @cs "${m:-listo}" \; set -w -t "$win" @csc "${c:-colour82}" 2>/dev/null
  else
    tmux set -w -t "$win" @cs "agentes ($n)" \; set -w -t "$win" @csc "$(tcolor agent colour177)" 2>/dev/null
  fi
}

# main <texto> <color> — fija el estado del hilo principal y vuelve a pintar.
main() { pon @cmain "$1"; pon @cmainc "$2"; render; }

# fase <código> [detalle] — fase detallada (tiempo desde que cambió). Se llama ANTES de main(), que repinta.
fase() {
  local antes; antes="$(opt @cfase)"
  pon @cfase "$1"; pon @cdet "${2:-}"; pon @cpane "$win"
  [[ "$antes" == "$1" && "$1" != herramienta ]] || tmux set -w -t "$win" @cdesde "$(now)" 2>/dev/null
}

# activity — "Herramienta: detalle" a partir del evento (comando, archivo, patrón, URL…).
activity() {
  local t d
  t="$(js .tool_name | sed -E 's/^mcp__([^_]+)__(.*)/mcp:\1 \2/')"
  d="$(js .tool_input.file_path)"
  if [[ -n "$d" ]]; then d="${d##*/}"
  else d="$(js '.tool_input.command // .tool_input.pattern // .tool_input.url // .tool_input.query // .tool_input.description' | one 70)"; fi
  printf '%s%s' "${t:-tool}" "${d:+: $d}"
}

# agent_file — archivo del subagente del evento (vacío si el evento es del hilo principal).
aid()        { local id; id="$(js .agent_id)"; echo "${id//[^A-Za-z0-9_-]/_}"; }
agent_file() { local id; id="$(aid)"; [[ -n "$id" ]] && echo "$reg/a-$id"; }

case "${1:-}" in
  start)    if [[ "$(js .source)" == compact ]]; then   # tras compactar: si fue automática, Claude sigue trabajando
              if [[ "$(opt @ccomp)" == auto ]]; then fase pensando "tras compactar"; main "pensando" "$(tcolor think colour39)"
              else fase listo "compactada"; main "listo" "$(tcolor ok colour82)"; fi
            else rm -f "$reg"/a-* "$reg"/done.log; fase listo ""; main "listo" "$(tcolor ok colour82)"; fi
            # Con qué cuenta arrancó este Claude (la del proyecto, la de la pestaña o la de por defecto).
            if [[ "${CLAUDE_CONFIG_DIR:-}" == */.claude-personal ]]; then pon @ccuenta personal; else pon @ccuenta trabajo; fi ;;
  prompt)   tmux set -w -t "$win" @cturno "$(now)" 2>/dev/null; tmux set -wu -t "$win" @cturno_txt 2>/dev/null
            fase pensando ""; main "pensando" "$(tcolor think colour39)" ;;
  tool|posttool)
    f="$(agent_file)"
    if [[ -n "$f" ]]; then
      [[ "$1" == tool && -f "$f" ]] && IFS=$'\t' read -r ty st _ _ id < "$f" &&
        printf '%s\t%s\t%s\t%s\t%s\n' "$ty" "$st" "$(activity)" "$(now)" "$id" > "$f"
      render
    elif [[ "$1" == tool ]]; then
      t="$(js .tool_name)"
      a="$(activity)"; pon @cultimo "$a"; fase herramienta "$a"
      if [[ "$t" == Task || "$t" == Agent ]]; then main "lanzando agente" "$(tcolor agent colour177)"
      else main "$(sed -E 's/^mcp__([^_]+)__.*/mcp:\1/' <<<"${t:-tool}" | cut -c1-14)" "$(tcolor tool colour214)"; fi
    else fase pensando "tras $(js .tool_name | sed -E 's/^mcp__([^_]+)__.*/mcp:\1/')"; main "pensando" "$(tcolor think colour39)"; fi ;;
  wait)     case "$(js .notification_type)" in
              idle_prompt) : ;;   # Claude terminó y espera tu siguiente mensaje: sigue «listo»
              permission_prompt) fase permiso "$(js .message | sed -nE 's/.*permission to use ([A-Za-z0-9_:.-]+).*/\1/p'): $(js .message | one 60)"
                                 main "te necesita" "$(tcolor alert colour196)" ;;
              *) fase pregunta "$(js .message | one 60)"; main "te necesita" "$(tcolor alert colour196)" ;;
            esac ;;
  done)     t0="$(opt @cturno)"
            [[ -n "$t0" ]] && tmux set -w -t "$win" @cturno_txt "$("$HOME/.local/bin/tmux-estado" --dur $(( $(now) - t0 )) 2>/dev/null)" 2>/dev/null
            tmux set -wu -t "$win" @cturno 2>/dev/null
            if [[ "${WS_TETOCA:-1}" != 0 ]] && pide "$(js .transcript_path)" "$(js .last_assistant_message)"; then
              fase tetoca "te dejó algo por hacer o responder"; main "te toca" "$(tcolor alert colour196)"
            else
              fase listo "$(u="$(opt @cultimo)"; [[ -n "$u" ]] && echo "último: $u")"; main "listo" "$(tcolor ok colour82)"
            fi ;;
  error)    fase error "$(js '.error // .error_type // .reason' | one 60)"; main "error API" "$(tcolor alert colour196)" ;;
  compact)  tmux set -w -t "$win" @ccomp "$(js .trigger)" 2>/dev/null
            fase compactando "$(js .trigger)"; main "pensando" "$(tcolor think colour39)" ;;
  substart)
    f="$(agent_file)"; f="${f:-$reg/a-anon-$(date +%s%N)}"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(js .agent_type)" "$(now)" "arrancando" "$(now)" "$(aid)" > "$f"
    render ;;
  substop)
    f="$(agent_file)"
    [[ -z "$f" || ! -f "$f" ]] && f="$(find "$reg" -maxdepth 1 -name 'a-anon-*' -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d" " -f2-)"
    if [[ -n "$f" && -f "$f" ]]; then
      IFS=$'\t' read -r ty _ _ _ id < "$f"; rm -f "$f"
      printf '%s\t%s\t%s\t%s\n' "$(date +%H:%M)" "${ty:-agente}" "$(js .last_assistant_message | one 90)" "$id" >> "$reg/done.log"
      tail -n 10 "$reg/done.log" > "$reg/done.tmp" && mv "$reg/done.tmp" "$reg/done.log"
    fi
    render ;;
  end)      rm -rf "$reg"
            for o in @cs @csc @cmain @cmainc @csub @cctx @cctxc @cts @cstall @cfase @cdesde @cdet @cturno @cturno_txt @cultimo @cpane @ccomp; do tmux set -wu -t "$win" "$o" 2>/dev/null; done ;;
esac
exit 0
