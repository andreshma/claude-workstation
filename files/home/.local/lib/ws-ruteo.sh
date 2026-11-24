# shellcheck shell=bash
#
# ws-ruteo.sh — biblioteca del ruteo de modelos (ADR-009). La cargan `cr`, el hook de Claude y el popup.
# Una sola tabla de reglas (~/.config/ws-ruteo/reglas.conf) y una sola forma de cambiar el modelo de una
# pestaña: siempre con tu confirmación, sin cambiar tu modelo por defecto y sin perder el texto escrito.

export LC_ALL=C.UTF-8   # minúsculas y [aá] correctos con acentos
WS_RUTEO_REGLAS="${WS_RUTEO_REGLAS:-$HOME/.config/ws-ruteo/reglas.conf}"
WS_RUTEO_RUN="${XDG_RUNTIME_DIR:-/tmp/ws-ruteo-$(id -u)}/ws-ruteo"
WS_RUTEO_LOG="${WS_RUTEO_LOG:-$HOME/.local/share/ws-telemetria/ruteo}"
WS_RUTEO_NIVELES=(haiku sonnet opus fable)

#######################################
# Clasifica una tarea con la tabla de reglas.
# Arguments: $1 texto de la tarea
# Outputs:   "<nivel> <id-de-regla>"; sin coincidencia "opus defecto"
#######################################
ruteo_clasificar() {
  local t="${1,,}" nivel id re
  t="${t//$'\n'/ }"
  while IFS='|' read -r nivel id re; do
    [[ -z "$nivel" || "$nivel" == \#* ]] && continue
    if [[ "$t" =~ $re ]]; then echo "$nivel $id"; return 0; fi
  done < "$WS_RUTEO_REGLAS"
  echo "opus defecto"
}

#######################################
# ID completo del modelo de un nivel (nunca alias: el alias puede resolver a otra versión).
# Se puede ajustar con ~/.config/ws-ruteo/modelos.conf (líneas nivel=ID).
#######################################
ruteo_modelo() {
  local f="$HOME/.config/ws-ruteo/modelos.conf" v=""
  [[ -f "$f" ]] && v="$(sed -n "s/^$1=//p" "$f" | head -1)"
  [[ -n "$v" ]] && { echo "$v"; return; }
  case "$1" in
    fable) echo claude-fable-5-2 ;; opus) echo claude-opus-5-5 ;;
    sonnet) echo claude-sonnet-5-5 ;; haiku) echo claude-haiku-5-5 ;; *) return 1 ;;
  esac
}

#######################################
# Nivel a partir del nombre que muestra Claude (status line → @cmodel). "Opus Plan" cuenta como opus.
#######################################
ruteo_nivel_de() {
  local n="${1,,}"
  case "$n" in *fable*) echo fable ;; *opus*) echo opus ;; *sonnet*) echo sonnet ;; *haiku*) echo haiku ;; *) echo "" ;; esac
}

#######################################
# Sube un nivel (confianza baja del clasificador o escalamiento): haiku→sonnet→opus→fable.
#######################################
ruteo_subir() {
  local i; for i in "${!WS_RUTEO_NIVELES[@]}"; do
    [[ "${WS_RUTEO_NIVELES[$i]}" == "$1" ]] && { echo "${WS_RUTEO_NIVELES[$((i + 1))]:-fable}"; return; }
  done; echo opus
}

# Huella del texto, para dejar pasar sin preguntar el reenvío que tú confirmaste.
ruteo_huella() { printf '%s' "$1" | sha256sum | cut -c1-64; }

#######################################
# Registra una decisión en la telemetría (sin texto de la tarea: solo nivel, regla y largo).
# Arguments: origen nivel regla actual decision chars
#######################################
ruteo_registrar() {
  mkdir -p "$WS_RUTEO_LOG" 2>/dev/null && chmod 700 "$WS_RUTEO_LOG" 2>/dev/null
  jq -nc --arg o "$1" --arg n "$2" --arg r "$3" --arg a "$4" --arg d "$5" --argjson c "${6:-0}" \
     --arg p "$(basename "${PWD:-}")" --arg m "$(ruteo_modelo "$2" 2>/dev/null)" \
     '{ts: (now | todate), origen: $o, nivel: $n, modelo: $m, regla: $r, actual: $a, decision: $d, chars: $c, proyecto: $p}' \
     >> "$WS_RUTEO_LOG/$(date +%F).jsonl" 2>/dev/null || true
}

#######################################
# Panel con Claude en la ventana del panel dado (el binario nativo se llama como su versión, p. ej. 2.1.327).
# Outputs: id del panel (%N) o nada
#######################################
ruteo_panel_claude() {
  tmux list-panes -t "$1" -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
    | awk '$2 ~ /^([0-9]+\.){2}[0-9]+$/ || $2 == "claude" { print $1; exit }'
}

# Archivos de settings donde /model guarda el modelo por defecto (ambas cuentas, sin repetir enlaces).
_ruteo_settings() {
  local f r; declare -A visto=()
  for f in "$HOME/.claude/settings.json" "$HOME/.claude-personal/settings.json"; do
    [[ -f "$f" ]] || continue; r="$(readlink -f "$f")"
    [[ -n "${visto[$r]:-}" ]] && continue; visto[$r]=1; echo "$r"
  done
}

#######################################
# Cambia el modelo de la pestaña con /model <ID> SIN cambiar tu modelo por defecto:
# /model escrito guarda el modelo en settings.json, así que se restaura el valor previo enseguida
# (la sesión que corre no relee `model`; solo el arranque lo lee).
# Arguments: $1 panel con Claude, $2 nivel
#######################################
ruteo_cambiar() {
  local p="$1" id f antes tmp; id="$(ruteo_modelo "$2")" || return 1
  declare -A prev=()
  while read -r f; do prev[$f]="$(jq -c '.model // null' "$f" 2>/dev/null)"; done < <(_ruteo_settings)
  # Claude Code deja en el cuadro de entrada el prompt que el hook bloqueó: escribir /model encima mandaba
  # «<texto>/model …» como mensaje. Ctrl+C con texto lo borra; con el cuadro vacío no hace nada (Claude está
  # esperando, el hook acaba de bloquear). Tu texto se vuelve a pegar después (ruteo_pegar).
  # Ctrl+C solo si Claude espera (si está trabajando lo interrumpiría): el /model queda en cola.
  tmux capture-pane -p -t "$p" 2>/dev/null | grep -qi "esc to interrupt" || { tmux send-keys -t "$p" C-c; sleep 0.4; }
  tmux send-keys -t "$p" -l "/model $id" && tmux send-keys -t "$p" Enter
  tmux set -w -t "$p" @cruteo_si "$2:$(date +%s)" 2>/dev/null   # el hook no vuelve a preguntar en 2 min
  sleep 1.5
  for f in "${!prev[@]}"; do
    antes="${prev[$f]}"
    [[ "$(jq -c '.model // null' "$f" 2>/dev/null)" == "$antes" ]] && continue
    tmp="$(mktemp)"
    if [[ "$antes" == null ]]; then jq 'del(.model)' "$f" > "$tmp"; else jq --argjson m "$antes" '.model = $m' "$f" > "$tmp"; fi
    # cat > (no mv): conserva permisos y enlaces simbólicos de la cuenta personal
    jq empty "$tmp" 2>/dev/null && cat "$tmp" > "$f"
    rm -f "$tmp"
  done
}

#######################################
# Pega el texto en la pestaña (bracketed paste: las líneas no se envían una por una) y lo envía.
# Deja la huella para que el hook no vuelva a preguntar por este mismo texto.
# Arguments: $1 panel, $2 archivo con el texto, $3 "enviar" | "solo-pegar"
#######################################
ruteo_pegar() {
  local p="$1" f="$2"
  [[ -s "$f" ]] || return 0
  mkdir -p "$WS_RUTEO_RUN" && chmod 700 "$WS_RUTEO_RUN"
  ruteo_huella "$(cat "$f")" > "$WS_RUTEO_RUN/pass-${p#%}"
  tmux load-buffer -b ws-ruteo "$f" && tmux paste-buffer -p -d -b ws-ruteo -t "$p"
  [[ "${3:-enviar}" == enviar ]] && { sleep 0.3; tmux send-keys -t "$p" Enter; }
  rm -f "$f"
}
