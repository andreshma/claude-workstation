#!/usr/bin/env bash
#
# memory-filter.sh <command> [args...] — wrapper for the hooks that hand your conversation to MemPalace (Stop,
# PreCompact, SessionEnd; WS-AI-012): text between <private> and </private> never reaches it.
#   · .prompt in the hook JSON: each private span becomes «[private]» (an unclosed tag runs to the end of the text);
#   · .transcript_path: if the transcript contains a private tag, MemPalace gets a redacted copy with the same file
#     name in ~/.cache/ws-memory/ (0700, copies older than 2 days removed) instead of the original;
#   · WS_MEMORY_PRIVATE=skip: a session with any private tag is not sent to MemPalace at all (also hides what Claude
#     paraphrased from it, which redaction cannot recognise).
# Fails closed for privacy and open for Claude: if the redaction fails, the command is NOT run (audit «memory-skip»)
# and the hook still exits 0. Without a private tag, the input goes through unchanged. Then it runs the command with
# the filtered JSON on stdin, returning its output and exit code (in settings.json: memory-filter.sh win-hook.sh …).
set -uo pipefail
(( $# )) || { echo "usage: memory-filter.sh <command> [args...]" >&2; exit 2; }
input="$(cat)"
CACHE="${WS_MEMORY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ws-memory}"
skip() { "$HOME/.claude/hooks/audit.sh" memory-skip "$1" <<<"$input" >/dev/null 2>&1; exit 0; }
command -v jq >/dev/null || skip "no jq: cannot redact"
TAG='</?private>|\\u003c/?private\\u003e'
tp="$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)"
has_prompt=0; has_tp=0
jq -e '(.prompt // "") | test("</?private>"; "i")' >/dev/null 2>&1 <<<"$input" && has_prompt=1
[[ -n "$tp" && -f "$tp" ]] && grep -qiE "$TAG" "$tp" 2>/dev/null && has_tp=1
(( has_prompt || has_tp )) || { exec "$@" <<<"$input"; }
[[ "${WS_MEMORY_PRIVATE:-redact}" == skip ]] && skip "private content: session not sent (WS_MEMORY_PRIVATE=skip)"

# shellcheck disable=SC2016  # Python source, not shell
REDACT='
import json, re, sys
PAT = re.compile(r"<private>.*?(?:</private>|\Z)|</private>", re.I | re.S)
def red(x):
    if isinstance(x, str): return PAT.sub("[private]", x)
    if isinstance(x, list): return [red(v) for v in x]
    if isinstance(x, dict): return {k: red(v) for k, v in x.items()}
    return x
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8", errors="replace") as fi, open(dst, "w", encoding="utf-8") as fo:
    for line in fi:
        try:
            fo.write(json.dumps(red(json.loads(line)), ensure_ascii=False) + "\n")
        except ValueError:
            fo.write(PAT.sub("[private]", line.replace("\\u003c", "<").replace("\\u003e", ">")))
'
if (( has_tp )); then
  mkdir -p "$CACHE" && chmod 700 "$CACHE" || skip "cannot create $CACHE"
  find "$CACHE" -mindepth 1 -maxdepth 1 -type d -mmin +2880 -exec rm -rf {} + 2>/dev/null
  d="$(mktemp -d "$CACHE/r.XXXXXX")" || skip "cannot create a copy folder"
  copy="$d/$(basename "$tp")"
  ( umask 077; python3 -c "$REDACT" "$tp" "$copy" ) 2>/dev/null || skip "redaction of the transcript failed"
  grep -qiE '<private>' "$copy" && skip "redaction left a private tag"
  input="$(jq -c --arg c "$copy" '.transcript_path = $c' <<<"$input")" || skip "cannot rewrite transcript_path"
fi
if (( has_prompt )); then
  input="$(jq -c '.prompt |= gsub("<private>[\\s\\S]*?(</private>|\\z)|</private>"; "[private]"; "gi")' <<<"$input")" || skip "prompt redaction failed"
fi
"$HOME/.claude/hooks/audit.sh" memory-redact "prompt=$has_prompt transcript=$has_tp" <<<"$input" >/dev/null 2>&1
exec "$@" <<<"$input"
