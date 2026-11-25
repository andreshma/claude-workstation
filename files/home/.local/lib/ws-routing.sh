# shellcheck shell=bash
#
# ws-routing.sh — model routing library (ADR-009). Loaded by `cr`, the Claude hook and the popup.
# A single rule table (~/.config/ws-routing/rules.conf, plus rules.es.conf with `ws-lang es`) and a single way to
# change a tab's model: always with your confirmation, without changing your default model and without losing the typed text.

export LC_ALL=C.UTF-8   # lowercase and [aá] work correctly with accents
WS_ROUTING_RULES="${WS_ROUTING_RULES:-$HOME/.config/ws-routing/rules.conf}"
WS_ROUTING_RUN="${XDG_RUNTIME_DIR:-/tmp/ws-routing-$(id -u)}/ws-routing"
WS_ROUTING_LOG="${WS_ROUTING_LOG:-$HOME/.local/share/ws-telemetry/routing}"
WS_ROUTING_LEVELS=(haiku sonnet opus fable)
# Language selector (ws-lang). Without the library the rules stay English only.
# shellcheck source=/dev/null
source "$HOME/.local/lib/ws-lang.sh" 2>/dev/null || ws_lang() { echo en; }

#######################################
# Classifies a task with the rule table. With `ws-lang es` a rule also matches through the Spanish expression
# of its id in rules.es.conf (next to the rule table: ${WS_ROUTING_RULES%.conf}.es.conf), in the same rule order.
# Arguments: $1 task text
# Outputs:   "<level> <rule-id>"; with no match "opus default"
#######################################
routing_classify() {
  local t="${1,,}" level id re es_file="${WS_ROUTING_RULES%.conf}.es.conf"
  local -A es_re=()
  t="${t//$'\n'/ }"
  if [[ "$(ws_lang)" == es && -r "$es_file" ]]; then
    while IFS='|' read -r id re; do
      [[ -z "$id" || "$id" == \#* || -z "$re" ]] && continue
      es_re[$id]="$re"
    done < "$es_file"
  fi
  while IFS='|' read -r level id re; do
    [[ -z "$level" || "$level" == \#* ]] && continue
    if [[ "$t" =~ $re ]]; then echo "$level $id"; return 0; fi
    re="${es_re[$id]:-}"
    if [[ -n "$re" && "$t" =~ $re ]]; then echo "$level $id"; return 0; fi
  done < "$WS_ROUTING_RULES"
  echo "opus default"
}

#######################################
# Full model ID of a level (never an alias: the alias may resolve to another version).
# Can be adjusted with ~/.config/ws-routing/models.conf (level=ID lines).
#######################################
routing_model() {
  local f="$HOME/.config/ws-routing/models.conf" v=""
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
routing_level_of() {
  local n="${1,,}"
  case "$n" in *fable*) echo fable ;; *opus*) echo opus ;; *sonnet*) echo sonnet ;; *haiku*) echo haiku ;; *) echo "" ;; esac
}

#######################################
# Goes up one level (low classifier confidence or escalation): haiku→sonnet→opus→fable.
#######################################
routing_up() {
  local i; for i in "${!WS_ROUTING_LEVELS[@]}"; do
    [[ "${WS_ROUTING_LEVELS[$i]}" == "$1" ]] && { echo "${WS_ROUTING_LEVELS[$((i + 1))]:-fable}"; return; }
  done; echo opus
}

# Fingerprint of the text, to let the resubmission you confirmed through without asking.
routing_fingerprint() { printf '%s' "$1" | sha256sum | cut -c1-64; }

#######################################
# Records a decision in the telemetry (no task text: only level, rule and length).
# Arguments: source level rule current decision chars
#######################################
routing_log() {
  mkdir -p "$WS_ROUTING_LOG" 2>/dev/null && chmod 700 "$WS_ROUTING_LOG" 2>/dev/null
  jq -nc --arg o "$1" --arg n "$2" --arg r "$3" --arg a "$4" --arg d "$5" --argjson c "${6:-0}" \
     --arg p "$(basename "${PWD:-}")" --arg m "$(routing_model "$2" 2>/dev/null)" \
     '{ts: (now | todate), source: $o, level: $n, model: $m, rule: $r, current: $a, decision: $d, chars: $c, project: $p}' \
     >> "$WS_ROUTING_LOG/$(date +%F).jsonl" 2>/dev/null || true
}

#######################################
# Pane with Claude in the window of the given pane (the native binary is named after its version, e.g. 2.1.327).
# Outputs: pane id (%N) or nothing
#######################################
routing_claude_pane() {
  tmux list-panes -t "$1" -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
    | awk '$2 ~ /^([0-9]+\.){2}[0-9]+$/ || $2 == "claude" { print $1; exit }'
}

# Settings files where /model stores the default model (both accounts, without repeating links).
_routing_settings() {
  local f r; declare -A seen=()
  for f in "$HOME/.claude/settings.json" "$HOME/.claude-personal/settings.json"; do
    [[ -f "$f" ]] || continue; r="$(readlink -f "$f")"
    [[ -n "${seen[$r]:-}" ]] && continue; seen[$r]=1; echo "$r"
  done
}

#######################################
# Changes the tab's model with /model <ID> WITHOUT changing your default model:
# a typed /model saves the model to settings.json, so the previous value is restored right away
# (the running session does not re-read `model`; only startup reads it).
# Arguments: $1 pane with Claude, $2 level
#######################################
routing_switch() {
  local p="$1" id f before tmp; id="$(routing_model "$2")" || return 1
  declare -A prev=()
  while read -r f; do prev[$f]="$(jq -c '.model // null' "$f" 2>/dev/null)"; done < <(_routing_settings)
  # Claude Code leaves the prompt the hook blocked in the input box: typing /model on top of it sent
  # «<text>/model …» as a message. Ctrl+C with text clears it; with an empty box it does nothing (Claude is
  # waiting, the hook has just blocked). Your text is pasted back afterwards (routing_paste).
  # Ctrl+C only if Claude is waiting (if it is working it would interrupt it): the /model stays queued.
  tmux capture-pane -p -t "$p" 2>/dev/null | grep -qi "esc to interrupt" || { tmux send-keys -t "$p" C-c; sleep 0.4; }
  tmux send-keys -t "$p" -l "/model $id" && tmux send-keys -t "$p" Enter
  tmux set -w -t "$p" @croute_yes "$2:$(date +%s)" 2>/dev/null   # the hook does not ask again for 2 min
  sleep 1.5
  for f in "${!prev[@]}"; do
    before="${prev[$f]}"
    [[ "$(jq -c '.model // null' "$f" 2>/dev/null)" == "$before" ]] && continue
    tmp="$(mktemp)"
    if [[ "$before" == null ]]; then jq 'del(.model)' "$f" > "$tmp"; else jq --argjson m "$before" '.model = $m' "$f" > "$tmp"; fi
    # cat > (not mv): keeps the permissions and symlinks of the personal account
    jq empty "$tmp" 2>/dev/null && cat "$tmp" > "$f"
    rm -f "$tmp"
  done
}

#######################################
# Pastes the text into the tab (bracketed paste: lines are not sent one by one) and sends it.
# Leaves the fingerprint so the hook does not ask again about this same text.
# Arguments: $1 pane, $2 file with the text, $3 "send" | "paste-only"
#######################################
routing_paste() {
  local p="$1" f="$2"
  [[ -s "$f" ]] || return 0
  mkdir -p "$WS_ROUTING_RUN" && chmod 700 "$WS_ROUTING_RUN"
  routing_fingerprint "$(cat "$f")" > "$WS_ROUTING_RUN/pass-${p#%}"
  tmux load-buffer -b ws-routing "$f" && tmux paste-buffer -p -d -b ws-routing -t "$p"
  [[ "${3:-send}" == send ]] && { sleep 0.3; tmux send-keys -t "$p" Enter; }
  rm -f "$f"
}
