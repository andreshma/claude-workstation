#!/usr/bin/env bash
#
# read-screen.sh — PreToolUse hook (Read): screens a text file for secrets BEFORE Claude reads it (WS-AI-022). What
# Claude reads goes to the model provider and into the transcript; the deny rules keep the credential stores out,
# this catches a secret in an ordinary file (a .env copied to Downloads, a token in a log, a connection string in
# another repository's config).
#   · outside the session's working directory: a file with what ws-redact recognises as a secret ASKS you first
#     (permissionDecision ask, with how many lines matched), also in auto (solo) mode; audited as read-secret
#   · inside the working directory (the project you opened Claude on): it reads, with a note telling Claude not to
#     repeat, store or send the values; audited as read-secret-in-project
# Only the first 2 MiB of a regular text file are screened; binaries, missing files and the kit's own converted
# Markdown pass. Detection is pattern-based (ws-redact), not a guarantee. Observing on error: without jq or
# ws-redact, or on anything it cannot read, it lets the read through (the deny rules still apply).
# Usage: called by Claude Code (PreToolUse, matcher Read).
set -uo pipefail
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
R="$HOME/.local/bin/ws-redact"; [[ -x "$R" ]] || exit 0
IFS=$'\x1f' read -r f cwd < <(jq -r '[.tool_input.file_path // "", .cwd // ""] | join("\u001f")' <<<"$input" 2>/dev/null)
[[ -n "${f:-}" && -f "$f" && -r "$f" ]] || exit 0
grep -Iq . <(head -c 65536 -- "$f") 2>/dev/null || exit 0            # binary or empty
n="$(diff <(head -c 2097152 -- "$f") <(head -c 2097152 -- "$f" | "$R" 2>/dev/null) 2>/dev/null | grep -c "^>")" || true
[[ "${n:-0}" =~ ^[0-9]+$ ]] && (( n > 0 )) || exit 0
rp="$(realpath -m -- "$f")"; rc="$(realpath -m -- "${cwd:-/nonexistent}")"
audit() { "$HOME/.claude/hooks/audit.sh" "$1" "$2" <<<"$input" >/dev/null 2>&1; }
if [[ -n "$cwd" && ( "$rp" == "$rc" || "$rp" == "$rc"/* ) ]]; then
  audit read-secret-in-project "$n line(s) of ${rp##*/} look like a secret"
  jq -nc --arg n "$n" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext:
    ("This file has " + $n + " line(s) that look like a secret (token, key, password or connection string). Do not repeat, quote, store, commit or send those values; refer to them by name, and suggest moving them to a secret store (Key Vault, ws-secret) if they are real.")}}'
  exit 0
fi
audit read-secret "$n line(s) of $rp look like a secret (outside the project)"
jq -nc --arg n "$n" --arg p "$rp" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask",
  permissionDecisionReason: ("read-screen: " + $p + " is outside this project and " + $n + " line(s) look like a secret. Reading it sends them to the model provider and keeps them in the transcript. Allow only if you are sure.")}}'
exit 0
