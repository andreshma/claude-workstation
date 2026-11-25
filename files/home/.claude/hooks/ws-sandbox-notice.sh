#!/usr/bin/env bash
#
# ws-sandbox-notice.sh — PostToolUse / PostToolUseFailure hook (Bash): tells you when the sandbox stopped something.
# The sandbox blocks silently: the command just «fails». This hook makes it visible: it records the hit and shows
# a message in tmux, to tell a legitimate block (a missing domain, another level is needed) from an odd attempt
# (reading credentials, reaching a site nobody asked for).
#   network    the output carries «deny network-outbound host:port» or the proxy answered 403
#   read       the command names a credentials path and the output says it does not exist or permission is denied
#   write      «Read-only file system» (writing outside the project, or to .git/hooks and .git/config)
# Claude Code does not document a «sandbox violation» event: this goes by the text of the result, so it is
# an approximate detection. It never blocks or fails (exits 0).
# Log: ~/.local/share/ws-telemetry/raw/sandbox-YYYY-MM.jsonl (type, detail, program, project; without the full
# command or the output). Message in tmux at most every 5 min per detail. WS_SANDBOX_NOTICE=0 turns the message off.
# Usage: called by Claude Code · ws-sandbox-notice.sh --summary [days]   hits by type and detail (30 days)
set -uo pipefail
DIR="${WS_TELEMETRY_DIR:-$HOME/.local/share/ws-telemetry}/raw"

if [[ "${1:-}" == --summary ]]; then
  days="${2:-30}"; since="$(date -d "-$days days" +%Y-%m-%d)"
  # Lines written before the rename carry tipo/detalle and the values red|lectura|escritura: both are read.
  cat "$DIR"/sandbox-*.jsonl 2>/dev/null | jq -r --arg d "$since" 'select(.ts >= $d) | (.type // .tipo) as $t
    | "\({red: "network", lectura: "read", escritura: "write"}[$t] // $t)\t\(.detail // .detalle)"' 2>/dev/null \
    | sort | uniq -c | sort -rn | awk 'BEGIN { n = 0 } { n++; print } END { if (!n) print "No sandbox hits in the period." }'
  exit 0
fi

command -v jq >/dev/null || exit 0
input="$(cat)"
[[ "$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null)" == Bash ]] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
# Everything that is not the command: the tool response or the error, whichever field it comes in.
rest="$(jq -r 'del(.tool_input) | tostring' <<<"$input" 2>/dev/null)"
kind=""; detail=""
SECRETS='\.ssh|\.aws|\.azure|\.kube|\.gnupg|\.git-credentials|\.netrc|\.npmrc|\.pypirc|\.docker/config|\.credentials\.json|GitHub CLI|User Data|ws-telemetry/otel'
if host="$(grep -oE 'deny network-outbound [^ \\"]+' <<<"$rest" | head -1 | awk '{ print $3 }')" && [[ -n "$host" ]]; then
  kind="network"; detail="$host"
elif grep -qE 'CONNECT tunnel failed, response 403|blocked by (the )?sandbox' <<<"$rest"; then
  kind="network"; detail="$(grep -oE 'https?://[^/ \\"'"'"']+' <<<"$cmd" | head -1 | sed -E 's#https?://##')"; detail="${detail:-destination not allowed}"
elif path="$(grep -oE "$SECRETS" <<<"$cmd" | head -1)" && [[ -n "$path" ]] && grep -qE 'No such file or directory|Permission denied|Operation not permitted' <<<"$rest"; then
  kind="read"; detail="$path"
elif grep -q 'Read-only file system' <<<"$rest"; then
  kind="write"; detail="$(grep -oE '[^ :\\"]+: Read-only file system' <<<"$rest" | head -1 | sed -E 's/: Read-only file system//; s#.*/(\.git/[^/]+).*#\1#; s#^/.*/##')"; detail="${detail:-outside the project}"
fi
[[ -n "$kind" ]] || exit 0

mkdir -p "$DIR" 2>/dev/null && chmod 700 "$DIR" 2>/dev/null
f="$DIR/sandbox-$(date +%Y-%m).jsonl"
prog="$(awk '{ print $1; exit }' <<<"$cmd")"; prog="${prog##*/}"
jq -nc --arg ts "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg kind "$kind" --arg d "${detail:0:120}" --arg p "${prog:0:40}" \
   --arg proj "$(basename "$(jq -r '.cwd // ""' <<<"$input")")" --arg s "$(jq -r '.session_id // ""' <<<"$input")" \
   '{ts: $ts, type: $kind, detail: $d, program: $p, project: $proj, session: $s}' >> "$f" 2>/dev/null
chmod 600 "$f" 2>/dev/null

[[ "${WS_SANDBOX_NOTICE:-1}" != 0 && -n "${TMUX_PANE:-}" ]] || exit 0
stamp="${XDG_RUNTIME_DIR:-/tmp}/ws-sandbox-$(id -u)-$(printf '%s' "$kind$detail" | md5sum | cut -c1-10)"
if [[ ! -f "$stamp" || $(( $(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) )) -ge 300 ]]; then
  : > "$stamp" 2>/dev/null
  case "$kind" in
    network) m="🛡 The sandbox blocked the connection to $detail" ;;
    read) m="🛡 The sandbox blocked a credentials read ($detail)" ;;
    *) m="🛡 The sandbox blocked a write ($detail)" ;;
  esac
  tmux display-message -d 6000 -t "$TMUX_PANE" "$m · $(tmux display -p -t "$TMUX_PANE" '#W' 2>/dev/null)" 2>/dev/null
fi
exit 0
