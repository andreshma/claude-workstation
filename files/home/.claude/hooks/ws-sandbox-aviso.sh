#!/usr/bin/env bash
#
# ws-sandbox-aviso.sh — PostToolUse / PostToolUseFailure hook (Bash): tells you when the sandbox stopped something.
# The sandbox blocks silently: the command just «fails». This hook makes it visible: it records the hit and shows
# a message in tmux, to tell a legitimate block (a missing domain, another level is needed) from an odd attempt
# (reading credentials, reaching a site nobody asked for).
#   red        the output carries «deny network-outbound host:port» or the proxy answered 403
#   lectura    the command names a credentials path and the output says it does not exist or permission is denied
#   escritura  «Read-only file system» (writing outside the project, or to .git/hooks and .git/config)
# Claude Code does not document a «sandbox violation» event: this goes by the text of the result, so it is
# an approximate detection. It never blocks or fails (exits 0).
# Log: ~/.local/share/ws-telemetria/raw/sandbox-YYYY-MM.jsonl (tipo, detalle, programa, proyecto; without the full
# command or the output). Message in tmux at most every 5 min per detail. WS_SANDBOX_AVISO=0 turns the message off.
# Usage: called by Claude Code · ws-sandbox-aviso.sh --resumen [days]   hits by type and detail (30 days)
set -uo pipefail
DIR="${WS_TELEMETRIA_DIR:-$HOME/.local/share/ws-telemetria}/raw"

if [[ "${1:-}" == --resumen ]]; then
  dias="${2:-30}"; desde="$(date -d "-$dias days" +%Y-%m-%d)"
  cat "$DIR"/sandbox-*.jsonl 2>/dev/null | jq -r --arg d "$desde" 'select(.ts >= $d) | "\(.tipo)\t\(.detalle)"' 2>/dev/null \
    | sort | uniq -c | sort -rn | awk 'BEGIN { n = 0 } { n++; print } END { if (!n) print "No sandbox hits in the period." }'
  exit 0
fi

command -v jq >/dev/null || exit 0
entrada="$(cat)"
[[ "$(jq -r '.tool_name // ""' <<<"$entrada" 2>/dev/null)" == Bash ]] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$entrada")"
# Everything that is not the command: the tool response or the error, whichever field it comes in.
resto="$(jq -r 'del(.tool_input) | tostring' <<<"$entrada" 2>/dev/null)"
tipo=""; detalle=""
SECRETOS='\.ssh|\.aws|\.azure|\.kube|\.gnupg|\.git-credentials|\.netrc|\.npmrc|\.pypirc|\.docker/config|\.credentials\.json|GitHub CLI|User Data|ws-telemetria/otel'
if host="$(grep -oE 'deny network-outbound [^ \\"]+' <<<"$resto" | head -1 | awk '{ print $3 }')" && [[ -n "$host" ]]; then
  tipo=red; detalle="$host"
elif grep -qE 'CONNECT tunnel failed, response 403|blocked by (the )?sandbox' <<<"$resto"; then
  tipo=red; detalle="$(grep -oE 'https?://[^/ \\"'"'"']+' <<<"$cmd" | head -1 | sed -E 's#https?://##')"; detalle="${detalle:-destination not allowed}"
elif ruta="$(grep -oE "$SECRETOS" <<<"$cmd" | head -1)" && [[ -n "$ruta" ]] && grep -qE 'No such file or directory|Permission denied|Operation not permitted' <<<"$resto"; then
  tipo=lectura; detalle="$ruta"
elif grep -q 'Read-only file system' <<<"$resto"; then
  tipo=escritura; detalle="$(grep -oE '[^ :\\"]+: Read-only file system' <<<"$resto" | head -1 | sed -E 's/: Read-only file system//; s#.*/(\.git/[^/]+).*#\1#; s#^/.*/##')"; detalle="${detalle:-outside the project}"
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
    red) m="🛡 The sandbox blocked the connection to $detalle" ;;
    lectura) m="🛡 The sandbox blocked a credentials read ($detalle)" ;;
    *) m="🛡 The sandbox blocked a write ($detalle)" ;;
  esac
  tmux display-message -d 6000 -t "$TMUX_PANE" "$m · $(tmux display -p -t "$TMUX_PANE" '#W' 2>/dev/null)" 2>/dev/null
fi
exit 0
