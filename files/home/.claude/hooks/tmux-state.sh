#!/usr/bin/env bash
#
# tmux-state.sh <event> — publishes the state of Claude Code on its tmux tab.
# Invoked by the hooks in ~/.claude/settings.json.
#
# Window options it writes:
#   @cmain/@cmainc  state of the main thread (text and colour)
#   @csub           active subagents (counted from the registry)
#   @cts            time (epoch) of the last event; tmux-watch uses it to detect inactivity
#   @cs/@csc        what the status bar shows; tmux-estado paints it with its time (🧠 thinking 42s, 🔧 Bash 2m,
#                   ✋ approve Bash 5m, ✔ done 12m ago…). Without tmux-estado: "needs you", "N agent(s)" or @cmain.
#   @cfase/@cdesde/@cdet  phase (pensando|herramienta|permiso|pregunta|tetoca|compactando|listo|error), since when
#                   and what it is doing («Bash: npm test»); @cturno start of the turn; @cultimo last tool; @cpane
#                   Claude's pane. (Patch 56: detailed state.)
#
# Subagent registry (read by tmux-agents): /tmp/claude-agents-<uid>/<pane>/
#   a-<agent_id>  one line: type<TAB>start<TAB>last activity<TAB>time<TAB>agent_id
#   done.log      last 10 finished: time<TAB>type<TAB>summary of its answer<TAB>agent_id
# With the agent_id, tmux-agents opens the subagent's transcript (reasoning included).
# Tool events that carry an agent_id belong to a subagent and update its
# activity; without an agent_id they belong to the main thread.
# «Waiting for you»: when a turn ends (Stop) the LAST message from Claude is checked; if it ends in a question or asks
# you to do something (run a command, decide, confirm, give it a value), the tab stays at 👉 waiting for you and the
# watcher counts it in ⚠, instead of ✔ done. Decided from the text only; nothing is stored or leaves the machine.
# WS_TETOCA=0 turns it off. Silent and always exit 0: it never blocks Claude or adds context to it.

# pide <transcript> [last message] — 0 if Claude's last message leaves you something to do or answer.
# Spanish on purpose: the patterns match what Claude writes when the owner works in Spanish.
pide() {
  local txt="${2:-}" cola ultima
  if [[ -z "$txt" && -f "${1:-}" ]]; then
    txt="$(tail -c 400000 "$1" | jq -rnR '[inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not))
            | [.message.content[]? | select(.type == "text") | .text] | join("\n") | select(length > 0)] | last // ""' 2>/dev/null)"
  fi
  [[ -n "$txt" ]] || return 1
  cola="$(tail -c 900 <<<"$txt")"
  ultima="$(grep -v '^[[:space:]]*$' <<<"$cola" | tail -1 | sed -E 's/[[:space:]*_`)"»]+$//')"
  [[ "$ultima" == *"?" ]] && return 0                                  # ends with a question
  grep -q '¿[^?]*?' <<<"$cola" && return 0                              # a question in the closing lines
  grep -Eiq '(^|[^[:alpha:]])(corre|c[oó]rrelo|ejecuta|ejec[uú]talo|p[eé]game|dime|conf[ií]rmame|confirma|decide|elige|p[aá]same|av[ií]same|necesito que|te toca|falta que|aplica|reinicia|abre|run this|run it|let me know|tell me|please (confirm|run|share|paste))([^[:alpha:]]|$)' <<<"$cola"
}
# Test mode, without tmux: tmux-state.sh --pide <transcript>  → exits 0 if it is waiting for you.
[[ "${1:-}" == --pide ]] && { pide "${2:-}" "${3:-}"; exit $?; }
[[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null || exit 0
umask 077
input="$(cat)"
win="$TMUX_PANE"
reg="/tmp/claude-agents-$(id -u)/${win#%}"
mkdir -p "$reg" 2>/dev/null

opt() { tmux show -wv -t "$win" "$1" 2>/dev/null; }
# pon <option> <value> — writes the option only if it changes. Every write makes tmux redraw the status bar, and
# with a menu or a popup open that redraw shows as flicker; a tool fires several events per second.
pon() { [[ "$(opt "$1")" == "$2" ]] || tmux set -w -t "$win" "$1" "$2" 2>/dev/null; }
# tcolor <name> <default> — semantic colour of the active theme (@t_ok, @t_think…; see tmux-theme).
tcolor() { local v; v="$(tmux show -gqv "@t_$1" 2>/dev/null)"; echo "${v:-$2}"; }
js()  { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
now() { date +%s; }
one() { tr '\n\t' '  ' | sed 's/ *$//' | cut -c1-"$1"; }

# nsub — active subagents according to the registry.
nsub() { find "$reg" -maxdepth 1 -name 'a-*' 2>/dev/null | wc -l; }

# render — computes @cs/@csc/@csub from the main state and the registry.
render() {
  local m c n
  local t0; t0="$(opt @cts)"
  # Only the watcher uses the time of the last event (inactivity in minutes): refreshing it every 5 s is enough.
  [[ -n "$t0" ]] && (( $(now) - t0 < 5 )) || tmux set -w -t "$win" @cts "$(now)" 2>/dev/null
  m="$(opt @cmain)"; c="$(opt @cmainc)"; n="$(nsub)"
  if (( n > 0 )); then pon @csub "$n"; elif [[ -n "$(opt @csub)" ]]; then tmux set -wu -t "$win" @csub 2>/dev/null; fi
  if [[ -x "$HOME/.local/bin/tmux-estado" && -n "$(opt @cfase)" ]]; then
    "$HOME/.local/bin/tmux-estado" --pintar "$win"
  elif [[ "$m" == "te necesita" || "$m" == "te toca" || "$m" == "error API" ]] || (( n == 0 )); then
    # @cmain keeps its stored (Spanish) value; only the text shown is English, as tmux-estado paints it.
    case "$m" in
      "te necesita") m="needs you" ;; "te toca") m="waiting for you" ;; "error API") m="API error" ;;
      pensando) m="thinking" ;; "lanzando agente") m="launching agent" ;; listo|"") m="done" ;;
    esac
    tmux set -w -t "$win" @cs "$m" \; set -w -t "$win" @csc "${c:-colour82}" 2>/dev/null
  else
    tmux set -w -t "$win" @cs "$n agent$( (( n == 1 )) || echo s)" \; set -w -t "$win" @csc "$(tcolor agent colour177)" 2>/dev/null
  fi
}

# main <text> <colour> — sets the state of the main thread and repaints.
main() { pon @cmain "$1"; pon @cmainc "$2"; render; }

# fase <code> [detail] — detailed phase (time since it changed). Called BEFORE main(), which repaints.
fase() {
  local antes; antes="$(opt @cfase)"
  pon @cfase "$1"; pon @cdet "${2:-}"; pon @cpane "$win"
  [[ "$antes" == "$1" && "$1" != herramienta ]] || tmux set -w -t "$win" @cdesde "$(now)" 2>/dev/null
}

# activity — "Tool: detail" from the event (command, file, pattern, URL…).
activity() {
  local t d
  t="$(js .tool_name | sed -E 's/^mcp__([^_]+)__(.*)/mcp:\1 \2/')"
  d="$(js .tool_input.file_path)"
  if [[ -n "$d" ]]; then d="${d##*/}"
  else d="$(js '.tool_input.command // .tool_input.pattern // .tool_input.url // .tool_input.query // .tool_input.description' | one 70)"; fi
  printf '%s%s' "${t:-tool}" "${d:+: $d}"
}

# agent_file — file of the event's subagent (empty if the event belongs to the main thread).
aid()        { local id; id="$(js .agent_id)"; echo "${id//[^A-Za-z0-9_-]/_}"; }
agent_file() { local id; id="$(aid)"; [[ -n "$id" ]] && echo "$reg/a-$id"; }

case "${1:-}" in
  start)    if [[ "$(js .source)" == compact ]]; then   # after compacting: if it was automatic, Claude keeps working
              if [[ "$(opt @ccomp)" == auto ]]; then fase pensando "after compacting"; main "pensando" "$(tcolor think colour39)"
              else fase listo "compacted"; main "listo" "$(tcolor ok colour82)"; fi
            else rm -f "$reg"/a-* "$reg"/done.log; fase listo ""; main "listo" "$(tcolor ok colour82)"; fi
            # Which account this Claude started with (the project's, the tab's or the default one).
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
    else fase pensando "after $(js .tool_name | sed -E 's/^mcp__([^_]+)__.*/mcp:\1/')"; main "pensando" "$(tcolor think colour39)"; fi ;;
  wait)     case "$(js .notification_type)" in
              idle_prompt) : ;;   # Claude finished and waits for your next message: stays «listo»
              permission_prompt) fase permiso "$(js .message | sed -nE 's/.*permission to use ([A-Za-z0-9_:.-]+).*/\1/p'): $(js .message | one 60)"
                                 main "te necesita" "$(tcolor alert colour196)" ;;
              *) fase pregunta "$(js .message | one 60)"; main "te necesita" "$(tcolor alert colour196)" ;;
            esac ;;
  done)     t0="$(opt @cturno)"
            [[ -n "$t0" ]] && tmux set -w -t "$win" @cturno_txt "$("$HOME/.local/bin/tmux-estado" --dur $(( $(now) - t0 )) 2>/dev/null)" 2>/dev/null
            tmux set -wu -t "$win" @cturno 2>/dev/null
            if [[ "${WS_TETOCA:-1}" != 0 ]] && pide "$(js .transcript_path)" "$(js .last_assistant_message)"; then
              fase tetoca "left you something to do or answer"; main "te toca" "$(tcolor alert colour196)"
            else
              fase listo "$(u="$(opt @cultimo)"; [[ -n "$u" ]] && echo "last: $u")"; main "listo" "$(tcolor ok colour82)"
            fi ;;
  error)    fase error "$(js '.error // .error_type // .reason' | one 60)"; main "error API" "$(tcolor alert colour196)" ;;
  compact)  tmux set -w -t "$win" @ccomp "$(js .trigger)" 2>/dev/null
            fase compactando "$(js .trigger)"; main "pensando" "$(tcolor think colour39)" ;;
  substart)
    f="$(agent_file)"; f="${f:-$reg/a-anon-$(date +%s%N)}"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(js .agent_type)" "$(now)" "starting" "$(now)" "$(aid)" > "$f"
    render ;;
  substop)
    f="$(agent_file)"
    [[ -z "$f" || ! -f "$f" ]] && f="$(find "$reg" -maxdepth 1 -name 'a-anon-*' -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d" " -f2-)"
    if [[ -n "$f" && -f "$f" ]]; then
      IFS=$'\t' read -r ty _ _ _ id < "$f"; rm -f "$f"
      printf '%s\t%s\t%s\t%s\n' "$(date +%H:%M)" "${ty:-agent}" "$(js .last_assistant_message | one 90)" "$id" >> "$reg/done.log"
      tail -n 10 "$reg/done.log" > "$reg/done.tmp" && mv "$reg/done.tmp" "$reg/done.log"
    fi
    render ;;
  end)      rm -rf "$reg"
            for o in @cs @csc @cmain @cmainc @csub @cctx @cctxc @cts @cstall @cfase @cdesde @cdet @cturno @cturno_txt @cultimo @cpane @ccomp; do tmux set -wu -t "$win" "$o" 2>/dev/null; done ;;
esac
exit 0
