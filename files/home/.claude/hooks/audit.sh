#!/usr/bin/env bash
#
# audit.sh <event> [reason] — local audit log for Claude Code (daily JSONL in
# ~/.claude/audit/). Stores metadata: who/where/which tool/which command. It does not store the
# prompt text or file contents (DLP); commands are stored with secrets redacted.
# Silent: writes nothing to stdout (on UserPromptSubmit that would be added to Claude's context).
#
# Tamper evidence (WS-SEC-011): every entry carries «prev», the sha256 of the line written before it (the previous
# line of the same day file, or the last line of the newest earlier day file for the first line of a day), so an
# edited, deleted or reordered line breaks the chain. On «end» the day's head hash is appended to an anchor file
# outside the agent's sandbox (%UserProfile%\ws-telemetry\audit-anchors.txt), so rewriting the whole chain shows too.
# Writers take a lock on the folder (flock). Check it with: ws-audit --verify-log
# Retention: 395 days (the same as telemetry). For MemPalace tools the sha256 of the tool input is kept (provenance of
# memory writes, WS-AI-013), never the input itself. For web and other MCP tools (WS-SEC-010): the URL without its
# query string, the first 200 characters of a search query and the first 500 of the redacted MCP input; all of them
# are part of the hashed record. «pane» is the tmux pane of the tab (for ws-anomaly, ws-stop-all).
# Usage: called by Claude Code hooks with the hook JSON on stdin · CLAUDE_AUDIT_DIR / CLAUDE_AUDIT_ANCHORS override
#        the folder and the anchor file (tests).
set -uo pipefail
input="$(cat)"
dir="${CLAUDE_AUDIT_DIR:-$HOME/.claude/audit}"
mkdir -p "$dir" && chmod 700 "$dir"
[ "${1:-}" = start ] && find "$dir" -name "*.jsonl" -mtime +395 -delete
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
repo="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)"; repo="${repo##*/}"
branch="$(git -C "${cwd:-.}" branch --show-current 2>/dev/null)"
tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
isha=""
[[ "$tool" == mcp__mempalace__* ]] && isha="$(jq -cS '.tool_input // {}' <<<"$input" 2>/dev/null | sha256sum | cut -c1-64)"
line="$(jq -c --arg ev "${1:-event}" --arg reason "${2:-}" --arg ts "$(date -Is)" --arg pane "${TMUX_PANE:-}" \
      --arg repo "$repo" --arg branch "$branch" --arg user "${USER:-}" --arg isha "$isha" '
  def redact:
    gsub("(?<k>password|passwd|secret|token|api[_-]?key|accountkey|client[_-]?secret|sig)(?<s>\\s*[=:]\\s*)[^\\s&;|\"'"'"']+"; "\(.k)\(.s)***"; "i")
    | gsub("(?<k>--(password|secret|token|client-secret|api-key|sas-token))(?<s>\\s+)[^\\s&;|\"'"'"']+"; "\(.k)\(.s)***"; "i")
    | gsub("(?<k>bearer\\s+)[A-Za-z0-9._~+/=-]+"; "\(.k)***"; "i")
    | gsub("(?<k>\"[A-Za-z_-]*(password|passwd|secret|token|api[_-]?key|accountkey|connection[_-]?string|sig)\"\\s*:\\s*)\"(\\\\.|[^\"\\\\])*\""; "\(.k)\"***\""; "i");
  {ts: $ts, ev: $ev, user: $user, session: .session_id, pane: $pane, repo: $repo, branch: $branch, cwd: .cwd,
   tool: .tool_name,
   cmd: (.tool_input.command // null | if . then redact else . end),
   file: (.tool_input.file_path // .tool_input.notebook_path // null),
   url: (.tool_input.url // null | if . then tostring | sub("[?#].*$"; "") else . end),
   query: (.tool_input.query // null | if . then tostring | .[0:200] else . end),
   mcp_input: (if ((.tool_name // "") | startswith("mcp__")) and (((.tool_name // "") | startswith("mcp__mempalace__")) | not)
               then (.tool_input // {} | tojson | redact | .[0:500]) else null end),
   input_sha: $isha,
   prompt_chars: (.prompt // null | if . then length else . end),
   reason: (if $reason == "" then null else $reason end)}
  | with_entries(select(.value != null and .value != ""))' <<<"$input" 2>/dev/null)" || exit 0
[[ -n "$line" ]] || exit 0

day="$dir/$(date +%F).jsonl"
# hash_of_last <file> — sha256 of its last line (without the newline); empty when the file is empty or missing.
hash_of_last() { [[ -s "$1" ]] && tail -n 1 "$1" | tr -d '\n' | sha256sum | cut -c1-64; }
{
  flock -w 3 9 || true   # never block Claude: after 3 s it writes anyway (the verifier reports a fork, if any)
  prev="$(hash_of_last "$day")"
  if [[ -z "$prev" ]]; then   # first line of the day: links to the newest earlier day file
    last="$(find "$dir" -maxdepth 1 -name '????-??-??.jsonl' 2>/dev/null | sort | awk -v d="$day" '$0 < d' | tail -1)"
    [[ -n "$last" ]] && prev="$(hash_of_last "$last")"
  fi
  printf '%s\n' "${line%\}},\"prev\":\"${prev:-genesis}\"}" >> "$day"
  chmod 600 "$day" 2>/dev/null
  if [[ "${1:-}" == end ]]; then
    anchors="${CLAUDE_AUDIT_ANCHORS:-}"
    if [[ -z "$anchors" ]]; then
      w="$(cat "$dir/.winhome" 2>/dev/null)"
      if [[ -z "$w" ]]; then   # cached: cmd.exe takes a moment and this runs on every session end
        w="$(wslpath -u "$(cmd.exe /c 'echo %UserProfile%' 2>/dev/null | tr -d '\r')" 2>/dev/null)"
        [[ -d "$w" ]] && printf '%s' "$w" > "$dir/.winhome"
      fi
      [[ -n "$w" && -d "$w" ]] && { mkdir -p "$w/ws-telemetry" 2>/dev/null; anchors="$w/ws-telemetry/audit-anchors.txt"; }
    fi
    # «<day> <sha256 of the last line> <lines in the file> <time>»: the verifier checks that line N still has that hash.
    [[ -n "$anchors" ]] && printf '%s %s %s %s\n' "$(date +%F)" "$(hash_of_last "$day")" "$(wc -l < "$day")" "$(date -Is)" \
      >> "$anchors" 2>/dev/null
  fi
} 9>>"$dir/.lock"
exit 0
