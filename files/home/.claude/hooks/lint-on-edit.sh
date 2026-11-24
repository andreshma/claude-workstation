#!/usr/bin/env bash
#
# lint-on-edit.sh — PostToolUse hook (Edit|Write|MultiEdit): checks with ws-gate the file
# Claude has just written and, if there are findings, passes them as context so it fixes
# them right away. Never blocks; 20 s at most.
input="$(cat)"
f="$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)"
[[ -n "$f" && -f "$f" ]] || exit 0
gate="$HOME/.local/bin/ws-gate"; [[ -x "$gate" ]] || exit 0
# WS_GATE_SIN_CODIGO_REPO: hooks run outside the sandbox, so linters that load code or configuration from the repo
# (eslint and prettier from node_modules) are not run here; those are left for pre-commit.
out="$(cd "$(dirname "$f")" && WS_GATE_SIN_CODIGO_REPO=1 timeout 20 "$gate" file "$f" 2>&1)" && exit 0
out="$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out" | head -40)"
[[ -n "$out" ]] || exit 0
jq -n --arg c "Lint of ${f##*/} (ws-gate) found this; fix it before continuing:
$out" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
