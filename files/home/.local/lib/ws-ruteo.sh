# shellcheck shell=bash
#
# ws-ruteo.sh — model routing library (ADR-009). Loaded by `cr`, the Claude hook and the popup.
# A single rule table (~/.config/ws-ruteo/reglas.conf) and a single way to change a tab's model:
# always with your confirmation, without changing your default model and without losing the typed text.

export LC_ALL=C.UTF-8   # lowercase and [aá] work correctly with accents
WS_RUTEO_REGLAS="${WS_RUTEO_REGLAS:-$HOME/.config/ws-ruteo/reglas.conf}"
WS_RUTEO_RUN="${XDG_RUNTIME_DIR:-/tmp/ws-ruteo-$(id -u)}/ws-ruteo"
WS_RUTEO_LOG="${WS_RUTEO_LOG:-$HOME/.local/share/ws-telemetria/ruteo}"
WS_RUTEO_NIVELES=(haiku sonnet opus fable)

#######################################
# Classifies a task with the rule table.
# Arguments: $1 task text
# Outputs:   "<level> <rule-id>"; with no match "opus defecto"
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
# Full model ID of a level (never an alias: the alias may resolve to another version).
# Can be adjusted with ~/.config/ws-ruteo/modelos.conf (level=ID lines).
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
# Level from the name Claude shows (status line → @cmodel). "Opus Plan" counts as opus.
#######################################
ruteo_nivel_de() {
  local n="${1,,}"
  case "$n" in *fable*) echo fable ;; *opus*) echo opus ;; *sonnet*) echo sonnet ;; *haiku*) echo haiku ;; *) echo "" ;; esac
}

#######################################
# Goes up one level (low classifier confidence or escalation): haiku→sonnet→opus→fable.
#######################################
ruteo_subir() {
  local i; for i in "${!WS_RUTEO_NIVELES[@]}"; do
    [[ "${WS_RUTEO_NIVELES[$i]}" == "$1" ]] && { echo "${WS_RUTEO_NIVELES[$((i + 1))]:-fable}"; return; }
  done; echo opus
}

# Fingerprint of the text, to let the resubmission you confirmed through without asking.
ruteo_huella() { printf '%s' "$1" | sha256sum | cut -c1-64; }

#######################################
# Records a decision in the telemetry (no task text: only level, rule and length).
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
# Pane with Claude in the window of the given pane (the native binary is named after its version, e.g. 2.1.327).
# Outputs: pane id (%N) or nothing
#######################################
ruteo_panel_claude() {
  tmux list-panes -t "$1" -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
    | awk '$2 ~ /^([0-9]+\.){2}[0-9]+$/ || $2 == "claude" { print $1; exit }'
}

# Settings files where /model stores the default model (both accounts, without repeating links).
_ruteo_settings() {
  local f r; declare -A visto=()
  for f in "$HOME/.claude/settings.json" "$HOME/.claude-personal/settings.json"; do
    [[ -f "$f" ]] || continue; r="$(readlink -f "$f")"
    [[ -n "${visto[$r]:-}" ]] && continue; visto[$r]=1; echo "$r"
  done
}

#######################################
# Changes the tab's model with /model <ID> WITHOUT changing your default model:
# a typed /model saves the model to settings.json, so the previous value is restored right away
# (the running session does not re-read `model`; only startup reads it).
# Arguments: $1 pane with Claude, $2 level
#######################################
ruteo_cambiar() {
  local p="$1" id f antes tmp; id="$(ruteo_modelo "$2")" || return 1
  declare -A prev=()
  while read -r f; do prev[$f]="$(jq -c '.model // null' "$f" 2>/dev/null)"; done < <(_ruteo_settings)
  # Claude Code leaves the prompt the hook blocked in the input box: typing /model on top of it sent
  # «<text>/model …» as a message. Ctrl+C with text clears it; with an empty box it does nothing (Claude is
  # waiting, the hook has just blocked). Your text is pasted back afterwards (ruteo_pegar).
  # Ctrl+C only if Claude is waiting (if it is working it would interrupt it): the /model stays queued.
  tmux capture-pane -p -t "$p" 2>/dev/null | grep -qi "esc to interrupt" || { tmux send-keys -t "$p" C-c; sleep 0.4; }
  tmux send-keys -t "$p" -l "/model $id" && tmux send-keys -t "$p" Enter
  tmux set -w -t "$p" @cruteo_si "$2:$(date +%s)" 2>/dev/null   # the hook does not ask again for 2 min
  sleep 1.5
  for f in "${!prev[@]}"; do
    antes="${prev[$f]}"
    [[ "$(jq -c '.model // null' "$f" 2>/dev/null)" == "$antes" ]] && continue
    tmp="$(mktemp)"
    if [[ "$antes" == null ]]; then jq 'del(.model)' "$f" > "$tmp"; else jq --argjson m "$antes" '.model = $m' "$f" > "$tmp"; fi
    # cat > (not mv): keeps the permissions and symlinks of the personal account
    jq empty "$tmp" 2>/dev/null && cat "$tmp" > "$f"
    rm -f "$tmp"
  done
}

#######################################
# Pastes the text into the tab (bracketed paste: lines are not sent one by one) and sends it.
# Leaves the fingerprint so the hook does not ask again about this same text.
# Arguments: $1 pane, $2 file with the text, $3 "enviar" | "solo-pegar"
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
