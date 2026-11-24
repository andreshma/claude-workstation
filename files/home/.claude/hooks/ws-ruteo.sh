#!/usr/bin/env bash
#
# ws-ruteo-hook.sh — hook UserPromptSubmit de Claude Code: ruteo de modelos con tu confirmación (ADR-009).
#
# Si una regla de ~/.config/ws-ruteo/reglas.conf dice que la tarea es de otro nivel que el modelo de la
# pestaña (p. ej. SQL en Opus → Sonnet), detiene el envío, guarda el texto (0600, se borra al usarlo) y abre
# una ventana emergente: [s] cambiar y enviar · [n] enviar con el actual · [x] devolver el texto sin enviar.
# Sin regla que coincida, no pregunta. Nunca cambia nada sin tu respuesta; sin respuesta en 30 s envía
# con el modelo actual.
#
# Bajar de modelo solo se pregunta con poco contexto (< 30 %); con más, se sugiere a Claude el subagente barato.
# No pregunta si: no hay tmux, el texto empieza con / ! #, es muy corto, el ruteo está apagado
# (Menú → Claude → Modelo → Ruteo automático), o rechazaste ese mismo nivel en esta pestaña hace < 30 min.
# Silencioso y siempre exit 0 (un fallo del hook nunca bloquea a Claude).
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

# Reenvío que ya confirmaste en la ventana emergente o con `cr`: pasa sin preguntar.
if [[ -f "$WS_RUTEO_RUN/pass-$n" ]]; then
  h="$(cat "$WS_RUTEO_RUN/pass-$n")"; rm -f "$WS_RUTEO_RUN/pass-$n"
  [[ "$h" == "$(ruteo_huella "$texto")" ]] && exit 0
fi

# Sin bucles: no preguntar si el ruteo acaba de cambiar el modelo de esta pestaña (2 min) ni si el texto trae un
# «/model claude-…» pegado (señal de que el cambio se escribió encima de tu texto).
si="$(tmux show -wqv -t "$p" @cruteo_si 2>/dev/null)"
if [[ "${si#*:}" =~ ^[0-9]+$ ]] && (( $(date +%s) - ${si#*:} < 120 )); then exit 0; fi
[[ "$texto" == *"/model claude-"* ]] && exit 0

read -r nivel regla <<<"$(ruteo_clasificar "$texto")"
actual="$(ruteo_nivel_de "$(tmux show -wqv -t "$p" @cmodel 2>/dev/null)")"
[[ -n "$actual" && "$regla" != defecto ]] || exit 0
if [[ "$nivel" == "$actual" ]]; then ruteo_registrar hook "$nivel" "$regla" "$actual" igual "${#texto}"; exit 0; fi

no="$(tmux show -wqv -t "$p" @cruteo_no 2>/dev/null)"   # "nivel:epoch" del último rechazo
if [[ "${no%%:*}" == "$nivel" && "${no#*:}" =~ ^[0-9]+$ ]] && (( $(date +%s) - ${no#*:} < 1800 )); then
  ruteo_registrar hook "$nivel" "$regla" "$actual" silenciado "${#texto}"; exit 0
fi

# Bajar de modelo con mucho contexto cuesta más de lo que ahorra (la primera respuesta vuelve a leer todo sin caché).
# Con contexto ≥ bajar_max_ctx (30 % por defecto, ~/.config/ws-ruteo/ajustes.conf) no se cambia el modelo:
# se sugiere a Claude delegar en el subagente barato (sin bloquear) o, si no hay uno para esa regla, no se pregunta.
orden() { case "$1" in haiku) echo 0 ;; sonnet) echo 1 ;; opus) echo 2 ;; fable) echo 3 ;; *) echo 2 ;; esac; }
if (( $(orden "$nivel") < $(orden "$actual") )); then
  ctx="$(tmux show -wqv -t "$p" @cctx 2>/dev/null)"; ctx="${ctx%%[!0-9]*}"
  max="$(sed -n 's/^bajar_max_ctx=//p' "$HOME/.config/ws-ruteo/ajustes.conf" 2>/dev/null | head -1)"; max="${max:-30}"
  if [[ -n "$ctx" ]] && (( ctx >= max )); then
    sub=""
    case "$nivel:$regla" in sonnet:sql) sub=sql-rapido ;; haiku:*) sub=explorador ;; esac
    if [[ -n "$sub" ]]; then
      ruteo_registrar hook "$nivel" "$regla" "$actual" subagente "${#texto}"
      jq -nc --arg c "Ruteo (contexto ${ctx}%): esta tarea es de nivel ${nivel}. Delega la parte principal en el subagente ${sub} (modelo ${nivel}) en lugar de resolverla con el modelo de esta conversación; así no se pierde la caché." \
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
jq -nc --arg r "Ruteo: esta tarea parece de nivel ${nivel} (regla: ${regla}) y esta pestaña usa ${actual}. Elige en la ventana emergente; tu texto no se pierde." \
  '{decision: "block", reason: $r}'
exit 0
