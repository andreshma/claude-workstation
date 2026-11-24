#!/usr/bin/env bash
#
# tmux-state.sh <event> — publishes the state of Claude Code on its tmux tab.
# Invoked by the hooks in ~/.claude/settings.json.
#
# Window options it writes:
#   @cmain/@cmainc  state of the main thread (text and colour)
#   @csub           active subagents (counted from the registry)
#   @cts            time (epoch) of the last event; tmux-watch uses it to detect inactivity
#   @cs/@csc        what the status bar shows; tmux-status paints it with its time (🧠 thinking 42s, 🔧 Bash 2m,
#                   ✋ approve Bash 5m, ✔ done 12m ago…). Without tmux-status: "needs you", "N agent(s)" or @cmain.
#   @cphase/@csince/@cdet  phase (thinking|tool|permission|question|yourturn|compacting|done|error), since when
#                   and what it is doing («Bash: npm test»); @cturn start of the turn; @clast last tool; @cpane
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
# WS_YOURTURN=0 turns it off. Silent and always exit 0: it never blocks Claude or adds context to it.

# asks <transcript> [last message] — 0 if Claude's last message leaves you something to do or answer.
# The verbs come from the language packs (keys state.asks and state.question; see ws-lang): English, plus Spanish
# with `ws-lang es`. The library is loaded here, not at the top: only the end of a turn needs it.
asks() {
  local txt="${2:-}" tail_txt last_line verbs="" question=""
  if [[ -z "$txt" && -f "${1:-}" ]]; then
    txt="$(tail -c 400000 "$1" | jq -rnR '[inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not))
            | [.message.content[]? | select(.type == "text") | .text] | join("\n") | select(length > 0)] | last // ""' 2>/dev/null)"
  fi
  [[ -n "$txt" ]] || return 1
  tail_txt="$(tail -c 900 <<<"$txt")"
  last_line="$(grep -v '^[[:space:]]*$' <<<"$tail_txt" | tail -1 | sed -E 's/[[:space:]*_`)"»]+$//')"
  [[ "$last_line" == *"?" ]] && return 0                                  # ends with a question
  # shellcheck source=/dev/null
  source "$HOME/.local/lib/ws-lang.sh" 2>/dev/null || return 1
  ws_lang_var question state.question && grep -Eq -- "$question" <<<"$tail_txt" && return 0   # a question in the closing lines
  ws_lang_var verbs state.asks || return 1
  grep -Eiq -- "(^|[^[:alpha:]])(${verbs})([^[:alpha:]]|\$)" <<<"$tail_txt"
}
# Test mode, without tmux: tmux-state.sh --asks <transcript>  → exits 0 if it is waiting for you.
[[ "${1:-}" == --asks ]] && { asks "${2:-}" "${3:-}"; exit $?; }
[[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null || exit 0
umask 077
input="$(cat)"
win="$TMUX_PANE"
reg="/tmp/claude-agents-$(id -u)/${win#%}"
mkdir -p "$reg" 2>/dev/null

opt() { tmux show -wv -t "$win" "$1" 2>/dev/null; }
# put <option> <value> — writes the option only if it changes. Every write makes tmux redraw the status bar, and
# with a menu or a popup open that redraw shows as flicker; a tool fires several events per second.
put() { [[ "$(opt "$1")" == "$2" ]] || tmux set -w -t "$win" "$1" "$2" 2>/dev/null; }
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
  if (( n > 0 )); then put @csub "$n"; elif [[ -n "$(opt @csub)" ]]; then tmux set -wu -t "$win" @csub 2>/dev/null; fi
  if [[ -x "$HOME/.local/bin/tmux-status" && -n "$(opt @cphase)" ]]; then
    "$HOME/.local/bin/tmux-status" --paint "$win"
  elif [[ "$m" == "needs you" || "$m" == "your turn" || "$m" == "API error" ]] || (( n == 0 )); then
    # Text shown when it differs from the stored @cmain value, as tmux-status paints it.
    case "$m" in
      "your turn") m="waiting for you" ;; "") m="done" ;;
    esac
    tmux set -w -t "$win" @cs "$m" \; set -w -t "$win" @csc "${c:-colour82}" 2>/dev/null
  else
    tmux set -w -t "$win" @cs "$n agent$( (( n == 1 )) || echo s)" \; set -w -t "$win" @csc "$(tcolor agent colour177)" 2>/dev/null
  fi
}

# main <text> <colour> — sets the state of the main thread and repaints.
main() { put @cmain "$1"; put @cmainc "$2"; render; }

# phase <code> [detail] — detailed phase (time since it changed). Called BEFORE main(), which repaints.
phase() {
  local before; before="$(opt @cphase)"
  put @cphase "$1"; put @cdet "${2:-}"; put @cpane "$win"
  [[ "$before" == "$1" && "$1" != tool ]] || tmux set -w -t "$win" @csince "$(now)" 2>/dev/null
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
              if [[ "$(opt @ccomp)" == auto ]]; then phase thinking "after compacting"; main "thinking" "$(tcolor think colour39)"
              else phase "done" "compacted"; main "done" "$(tcolor ok colour82)"; fi
            else rm -f "$reg"/a-* "$reg"/done.log; phase "done" ""; main "done" "$(tcolor ok colour82)"; fi
            # Which account this Claude started with (the project's, the tab's or the default one).
            if [[ "${CLAUDE_CONFIG_DIR:-}" == */.claude-personal ]]; then put @caccount personal; else put @caccount work; fi ;;
  prompt)   tmux set -w -t "$win" @cturn "$(now)" 2>/dev/null; tmux set -wu -t "$win" @cturn_txt 2>/dev/null
            phase thinking ""; main "thinking" "$(tcolor think colour39)" ;;
  tool|posttool)
    f="$(agent_file)"
    if [[ -n "$f" ]]; then
      [[ "$1" == tool && -f "$f" ]] && IFS=$'\t' read -r ty st _ _ id < "$f" &&
        printf '%s\t%s\t%s\t%s\t%s\n' "$ty" "$st" "$(activity)" "$(now)" "$id" > "$f"
      render
    elif [[ "$1" == tool ]]; then
      t="$(js .tool_name)"
      a="$(activity)"; put @clast "$a"; phase tool "$a"
      if [[ "$t" == Task || "$t" == Agent ]]; then main "launching agent" "$(tcolor agent colour177)"
      else main "$(sed -E 's/^mcp__([^_]+)__.*/mcp:\1/' <<<"${t:-tool}" | cut -c1-14)" "$(tcolor tool colour214)"; fi
    else phase thinking "after $(js .tool_name | sed -E 's/^mcp__([^_]+)__.*/mcp:\1/')"; main "thinking" "$(tcolor think colour39)"; fi ;;
  wait)     case "$(js .notification_type)" in
              idle_prompt) : ;;   # Claude finished and waits for your next message: stays «done»
              permission_prompt) phase permission "$(js .message | sed -nE 's/.*permission to use ([A-Za-z0-9_:.-]+).*/\1/p'): $(js .message | one 60)"
                                 main "needs you" "$(tcolor alert colour196)" ;;
              *) phase question "$(js .message | one 60)"; main "needs you" "$(tcolor alert colour196)" ;;
            esac ;;
  done)     t0="$(opt @cturn)"
            [[ -n "$t0" ]] && tmux set -w -t "$win" @cturn_txt "$("$HOME/.local/bin/tmux-status" --dur $(( $(now) - t0 )) 2>/dev/null)" 2>/dev/null
            tmux set -wu -t "$win" @cturn 2>/dev/null
            if [[ "${WS_YOURTURN:-1}" != 0 ]] && asks "$(js .transcript_path)" "$(js .last_assistant_message)"; then
              phase yourturn "left you something to do or answer"; main "your turn" "$(tcolor alert colour196)"
            else
              phase "done" "$(u="$(opt @clast)"; [[ -n "$u" ]] && echo "last: $u")"; main "done" "$(tcolor ok colour82)"
            fi ;;
  error)    phase error "$(js '.error // .error_type // .reason' | one 60)"; main "API error" "$(tcolor alert colour196)" ;;
  compact)  tmux set -w -t "$win" @ccomp "$(js .trigger)" 2>/dev/null
            phase compacting "$(js .trigger)"; main "thinking" "$(tcolor think colour39)" ;;
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
            for o in @cs @csc @cmain @cmainc @csub @cctx @cctxc @cts @cstall @cphase @csince @cdet @cturn @cturn_txt @clast @cpane @ccomp; do tmux set -wu -t "$win" "$o" 2>/dev/null; done ;;
esac
exit 0
