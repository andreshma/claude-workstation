#!/usr/bin/env bash
#
# prompt-screen.sh — UserPromptSubmit hook: stops a prompt that seems to carry a secret before it is sent to the
# model (WS-AI-022). The prompt goes through ws-redact, the kit's one list of secret shapes (tokens, JWTs, keys,
# passwords in URLs, key=value secrets, private keys); if redaction changes it, the prompt is blocked and you see
# which line, already redacted. The prompt text is left out of the block message.
# Not counted as secrets (they are how people talk about code): a key=value whose value is a reference or a
# placeholder ($VAR, ${…}, <…>, {{…}}, %…%, os.environ…, process.env…, ***, xxx, changeme…), a plain word of up to
# 24 letters, or a value under 4 characters; and «Basic»/«Bearer» followed by an ordinary word.
# To send it anyway, start the prompt with #allow-secret: it passes and the audit log records that you did (never
# the prompt itself).
# Observing on failure: without jq or ws-redact it lets every prompt through and warns once per session.
# Usage: UserPromptSubmit hook (hook JSON on stdin; JSON decision on stdout). Tests: bash tests/hooks-prompt-screen.sh
set -uo pipefail
export LC_ALL=C.UTF-8
input="$(cat)"
REDACT="${WS_REDACT:-$HOME/.local/bin/ws-redact}"

# warn_once <text> — tells you (not Claude) once per session (per Claude process without jq) that the screen is off.
sid="$PPID"
warn_once() {
  local m="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ws-prompt-screen.${sid//[^A-Za-z0-9-]/}"
  [[ -e "$m" ]] && exit 0
  : > "$m" 2>/dev/null
  printf '{"systemMessage":"prompt-screen.sh: %s, so prompts are not screened for secrets in this session."}\n' "$1"
  exit 0
}
command -v jq >/dev/null 2>&1 || warn_once "jq is missing"
s="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)" && [[ -n "$s" ]] && sid="$s"
[[ -x "$REDACT" ]] || warn_once "ws-redact is missing"
prompt="$(jq -r '.prompt // ""' <<<"$input" 2>/dev/null)" || exit 0
[[ -n "$prompt" ]] || exit 0
if [[ "$prompt" == "#allow-secret"* ]]; then
  "$HOME/.claude/hooks/audit.sh" secret-allowed "prompt sent with #allow-secret" <<<"$input" >/dev/null 2>&1
  exit 0
fi

# Neutralise what only looks like a secret, then compare the redacted text with the input.
KEYS='password|passwd|pwd|secret|client_secret|token|api[_-]?key|access[_-]?key|accountkey|sharedaccesskey|connectionstring'
norm="$(sed -E \
  -e "s/(${KEYS})([\"']?[[:space:]]*)[:=]([[:space:]]*[\"']?)(\\\$|<|\\{|%|\\*\\*\\*|os\\.|process\\.|env\\b|getenv|secrets\\.|vault|xxx|changeme|example|placeholder|your[_-]|\\.\\.\\.)/\\1\\2 is \\3\\4/Ig" \
  -e "s/(${KEYS})([\"']?[[:space:]]*)[:=]([[:space:]]*[\"']?)([A-Za-z]{1,24}|[^[:space:]\"';,&]{1,3})([\"'[:space:];,&.)]|$)/\\1\\2 is \\3\\4\\5/Ig" \
  -e 's/(Bearer|Basic)([[:space:]]+[A-Za-z]+)([^A-Za-z0-9._~+\/=-]|$)/\1 word\3/Ig' <<<"$prompt")"
red="$("$REDACT" <<<"$norm" 2>/dev/null)" || exit 0
[[ "$red" == "$norm" ]] && exit 0

line="$(diff <(printf '%s\n' "$norm") <(printf '%s\n' "$red") 2>/dev/null | sed -n 's/^> //p' | head -1)"
n="$(diff <(printf '%s\n' "$norm") <(printf '%s\n' "$red") 2>/dev/null | grep -Eo '^[0-9]+' | head -1)"
"$HOME/.claude/hooks/audit.sh" secret-blocked "the prompt seemed to contain a secret (line ${n:-?})" <<<"$input" >/dev/null 2>&1
jq -nc --arg l "${line:0:160}" --arg n "${n:-?}" '{
  decision: "block",
  reason: ("The prompt seems to contain a secret (line \($n): \($l)). Remove it or use a reference (Key Vault, $VARIABLE); to send it anyway, start the prompt with #allow-secret (it is logged)."),
  hookSpecificOutput: {hookEventName: "UserPromptSubmit", suppressOriginalPrompt: true}}'
exit 0
