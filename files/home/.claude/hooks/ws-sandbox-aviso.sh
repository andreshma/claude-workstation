#!/usr/bin/env bash
#
# ws-sandbox-aviso.sh — hook PostToolUse / PostToolUseFailure (Bash): avisa cuando la sandbox frenó algo.
# La sandbox bloquea en silencio: el comando solo «falla». Este hook lo vuelve visible: registra el choque y te
# avisa en tmux, para distinguir un bloqueo legítimo (falta un dominio, hace falta otro nivel) de un intento raro
# (leer credenciales, salir a un sitio que nadie pidió).
#   red        la salida trae «deny network-outbound host:puerto» o el proxy respondió 403
#   lectura    el comando nombra una ruta de credenciales y la salida dice que no existe o no hay permiso
#   escritura  «Read-only file system» (escribir fuera del proyecto, o en .git/hooks y .git/config)
# Claude Code no documenta un evento de «violación de sandbox»: esto se guía por el texto del resultado, así que
# es una detección aproximada. Nunca bloquea ni falla (sale 0).
# Registro: ~/.local/share/ws-telemetria/raw/sandbox-AAAA-MM.jsonl (tipo, detalle, programa, proyecto; sin el comando
# completo ni la salida). Aviso en tmux como mucho cada 5 min por detalle. WS_SANDBOX_AVISO=0 apaga el aviso.
# Uso: lo llama Claude Code · ws-sandbox-aviso.sh --resumen [días]   choques por tipo y detalle (30 días)
set -uo pipefail
DIR="${WS_TELEMETRIA_DIR:-$HOME/.local/share/ws-telemetria}/raw"

if [[ "${1:-}" == --resumen ]]; then
  dias="${2:-30}"; desde="$(date -d "-$dias days" +%Y-%m-%d)"
  cat "$DIR"/sandbox-*.jsonl 2>/dev/null | jq -r --arg d "$desde" 'select(.ts >= $d) | "\(.tipo)\t\(.detalle)"' 2>/dev/null \
    | sort | uniq -c | sort -rn | awk 'BEGIN { n = 0 } { n++; print } END { if (!n) print "Sin choques con la sandbox en el periodo." }'
  exit 0
fi

command -v jq >/dev/null || exit 0
entrada="$(cat)"
[[ "$(jq -r '.tool_name // ""' <<<"$entrada" 2>/dev/null)" == Bash ]] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$entrada")"
# Todo lo que no es el comando: la respuesta de la herramienta o el error, venga en el campo que venga.
resto="$(jq -r 'del(.tool_input) | tostring' <<<"$entrada" 2>/dev/null)"
tipo=""; detalle=""
SECRETOS='\.ssh|\.aws|\.azure|\.kube|\.gnupg|\.git-credentials|\.netrc|\.npmrc|\.pypirc|\.docker/config|\.credentials\.json|GitHub CLI|User Data|ws-telemetria/otel'
if host="$(grep -oE 'deny network-outbound [^ \\"]+' <<<"$resto" | head -1 | awk '{ print $3 }')" && [[ -n "$host" ]]; then
  tipo=red; detalle="$host"
elif grep -qE 'CONNECT tunnel failed, response 403|blocked by (the )?sandbox' <<<"$resto"; then
  tipo=red; detalle="$(grep -oE 'https?://[^/ \\"'"'"']+' <<<"$cmd" | head -1 | sed -E 's#https?://##')"; detalle="${detalle:-destino no permitido}"
elif ruta="$(grep -oE "$SECRETOS" <<<"$cmd" | head -1)" && [[ -n "$ruta" ]] && grep -qE 'No such file or directory|Permission denied|Operation not permitted' <<<"$resto"; then
  tipo=lectura; detalle="$ruta"
elif grep -q 'Read-only file system' <<<"$resto"; then
  tipo=escritura; detalle="$(grep -oE '[^ :\\"]+: Read-only file system' <<<"$resto" | head -1 | sed -E 's/: Read-only file system//; s#.*/(\.git/[^/]+).*#\1#; s#^/.*/##')"; detalle="${detalle:-fuera del proyecto}"
fi
[[ -n "$tipo" ]] || exit 0

mkdir -p "$DIR" 2>/dev/null && chmod 700 "$DIR" 2>/dev/null
f="$DIR/sandbox-$(date +%Y-%m).jsonl"
prog="$(awk '{ print $1; exit }' <<<"$cmd")"; prog="${prog##*/}"
jq -nc --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg tipo "$tipo" --arg d "${detalle:0:120}" --arg p "${prog:0:40}" \
   --arg proy "$(basename "$(jq -r '.cwd // ""' <<<"$entrada")")" --arg s "$(jq -r '.session_id // ""' <<<"$entrada")" \
   '{ts: $ts, tipo: $tipo, detalle: $d, programa: $p, proyecto: $proy, sesion: $s}' >> "$f" 2>/dev/null
chmod 600 "$f" 2>/dev/null

[[ "${WS_SANDBOX_AVISO:-1}" != 0 && -n "${TMUX_PANE:-}" ]] || exit 0
marca="${XDG_RUNTIME_DIR:-/tmp}/ws-sandbox-$(id -u)-$(printf '%s' "$tipo$detalle" | md5sum | cut -c1-10)"
if [[ ! -f "$marca" || $(( $(date +%s) - $(stat -c %Y "$marca" 2>/dev/null || echo 0) )) -ge 300 ]]; then
  : > "$marca" 2>/dev/null
  case "$tipo" in
    red) m="🛡 La sandbox bloqueó la salida a $detalle" ;;
    lectura) m="🛡 La sandbox bloqueó la lectura de credenciales ($detalle)" ;;
    *) m="🛡 La sandbox bloqueó una escritura ($detalle)" ;;
  esac
  tmux display-message -d 6000 -t "$TMUX_PANE" "$m · $(tmux display -p -t "$TMUX_PANE" '#W' 2>/dev/null)" 2>/dev/null
fi
exit 0
