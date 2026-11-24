#!/usr/bin/env bash
#
# win-notify.sh <prompt|wait|done> — notificación de Windows cuando un Claude de una pestaña
# que no estás viendo te necesita (permiso o pregunta) o termina un turno largo.
# Lo invocan los hooks UserPromptSubmit (prompt), Notification (wait) y Stop (done).
# tmux-watch lo usa con "alert" (JSON con title y message) para recordatorios y consumo;
# "alert" avisa aunque estés viendo la pestaña, pero respeta @cnotify.
#
# · No avisa si la pestaña está activa y la terminal tiene el foco.
# · Al terminar, solo avisa si el turno duró al menos CLAUDE_NOTIFY_MIN_SECS (20 s por defecto).
# · Se apaga desde el menú (Ctrl+b m → Avisos de Windows) o con: tmux set -g @cnotify off
# · CLAUDE_NOTIFY_FORCE=1 avisa aunque estés viendo la pestaña (para probar).
# · Usa PowerShell 5.1 con -EncodedCommand (sin archivos .ps1 ni módulos; no le afecta la
#   política de ejecución) y corre en segundo plano: el hook nunca hace esperar a Claude.
# Silencioso y siempre exit 0.
[[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null || exit 0
input="$(cat)"
p="$TMUX_PANE"
ts="/tmp/claude-notify-$(id -u)-${p#%}"
min="${CLAUDE_NOTIFY_MIN_SECS:-20}"
js() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
b64() { printf '%s' "$1" | base64 -w0; }
# Último mensaje de Claude: del hook o, si no viene, del final de la transcripción.
ultimo_msg() {
  local m; m="$(js .last_assistant_message)"
  [[ -n "$m" ]] || m="$(tail -n 80 "$(js .transcript_path)" 2>/dev/null \
    | jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' 2>/dev/null)"
  printf '%s' "$m"
}
# Todo el texto de Claude en este turno (desde tu último mensaje): los comandos pueden venir en mensajes intermedios.
textos_turno() {
  local tp; tp="$(js .transcript_path)"; [[ -f "$tp" ]] || return 0
  tail -n 600 "$tp" | jq -rs '
    (to_entries | map(select(.value.type == "user" and ((.value.message.content | type) == "string"
        or ([.value.message.content[]? | select(.type == "tool_result")] | length) == 0))) | last | .key) as $k
    | .[(($k // -1) + 1):] | map(select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text)
    | join("\n\n")' 2>/dev/null
}
# ¿Te pide algo? Una pregunta, un comando con ! o un verbo de acción para ti. Entonces avisa aunque el turno sea corto.
pide_algo() {
  { textos_turno; ultimo_msg; } \
    | grep -qiE '(^|[[:space:]`])![[:space:]]*[a-z./~]|```(bash|sh|shell|zsh|console)|(ejecuta|ejecútalo|corre|córrelo|run|lanza)[^`]{0,50}`[a-z./~]' \
    && return 0   # un comando (con !, en bloque bash o tras ejecuta/corre) en cualquier parte del turno
  ultimo_msg | tail -c 1500 | grep -qiE \
    '\?[[:space:]]*$|¿|(^|[[:space:]`])![[:space:]]*[a-z]|\b(ejecuta|ejecútalo|ejecutalo|corre|córrelo|correlo|pega|confirma|autoriza|aprueba|run|paste|confirm)\b'
}

case "${1:-}" in
  prompt) date +%s > "$ts"; exit 0 ;;
  wait)
    [[ "$(js .notification_type)" == idle_prompt ]] && exit 0   # ya avisó el Stop
    body="$(js .message)"; body="${body:-Necesita tu respuesta}" ;;
  done)
    start="$(cat "$ts" 2>/dev/null)"; rm -f "$ts"
    # Turno que siguió sin un prompt nuevo (tras una tarea en segundo plano, por ejemplo): avisa si te pide algo.
    [[ -n "$start" ]] || { pide_algo || exit 0; start=$(date +%s); }
    secs=$(( $(date +%s) - start )); (( secs >= min )) || pide_algo || exit 0
    msg="$(js .last_assistant_message | tr '\n\t' '  ' | cut -c1-140)"
    body="Terminó en $(( secs / 60 ))m $(( secs % 60 ))s${msg:+: $msg}" ;;
  alert)
    body="$(js .message)"; atitle="$(js .title)"; CLAUDE_NOTIFY_FORCE=1 ;;
  *) exit 0 ;;
esac

# Telegram (ws-telegram, ADR-010): siempre; la pregunta va redactada y con botones para responder.
objetivo="$p"; [[ -n "${WS_FLOT_SESION:-}" ]] && objetivo="flot:$WS_FLOT_SESION"   # Claude dentro de una flotante
# A Telegram va el final completo del mensaje (los comandos con ! suelen estar al final), no solo 140 caracteres.
cuerpo_tg="$body"; completo=""
if [[ "$1" == "done" ]]; then   # aviso: el final del mensaje; comandos `!`: el mensaje completo (0600, lo borra ws-telegram)
  cuerpo_tg="${body%%:*}:"$'\n'"$(ultimo_msg | tail -c 1200)"
  completo="$(mktemp)"; turno="$(textos_turno)"; [[ -n "$turno" ]] || turno="$(ultimo_msg)"
  printf '%s' "$turno" > "$completo"
fi
setsid "$HOME/.local/bin/ws-telegram" avisar "$1" "$objetivo" "$cuerpo_tg" "$p" "$completo" >/dev/null 2>&1 </dev/null &
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
\$x.LoadXml(\"<toast activationType='protocol' launch='ws-claude://foco/${p#%}'><visual><binding template='ToastGeneric'><text>\$(\$e::Escape(\$t))</text><text>\$(\$e::Escape(\$b))</text></binding></visual><actions><action content='Ir a la pestaña' activationType='protocol' arguments='ws-claude://foco/${p#%}'/></actions></toast>\")
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new(\$x))"
enc="$(printf '%s' "$ps" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)"
setsid powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand "$enc" \
  >/dev/null 2>&1 </dev/null &
exit 0
