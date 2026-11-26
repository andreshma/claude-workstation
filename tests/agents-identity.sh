#!/usr/bin/env bash
#
# tests/agents-identity.sh — least privilege of the kit's subagents (WS-AI-016) and the per-identity SSH key
# (WS-AI-026), in a temporary HOME:
#   1) every agent file declares tools or disallowedTools; the read-only agents cannot write; the debugger has no web
#      tools; sql-quick has an explicit tool list without MCP or web tools, and the database clients it would run ask
#   2) an agent identity or a custom profile with ~/.config/ws-agent/NAME/ssh/id_ed25519 gets GIT_SSH_COMMAND with
#      only that key (no agent, no other identity); without the key nothing changes; the guard keeps it in place
#
# Usage: bash tests/agents-identity.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
A="$ROOT/files/home/.claude/agents"
fm() { sed -n '2,/^---$/p' "$1" | sed '$d'; }

echo "== 1. subagents"
for f in "$A"/*.md; do
  check "${f##*/} declares tools or disallowedTools" bash -c "sed -n '2,/^---\$/p' '$f' | grep -qE '^(tools|disallowedTools):'"
done
for f in architect explorer; do
  check "$f cannot write (Edit, Write, NotebookEdit disallowed)" bash -c "sed -n '2,/^---\$/p' '$A/$f.md' | grep -E '^disallowedTools:' | grep -q 'Edit' && sed -n '2,/^---\$/p' '$A/$f.md' | grep -E '^disallowedTools:' | grep -q 'Write'"
done
check "debugger has no web tools" bash -c "fm() { sed -n '2,/^---\$/p' \"\$1\"; }; fm '$A/debugger.md' | grep -E '^disallowedTools:' | grep -q WebFetch && fm '$A/debugger.md' | grep -E '^disallowedTools:' | grep -q WebSearch"
check "sql-quick: an explicit tool list, no MCP, no web" bash -c "l=\$(sed -n '2,/^---\$/p' '$A/sql-quick.md' | sed -n 's/^tools: //p'); [[ -n \$l && \$l != *mcp__* && \$l != *Web* ]]"
check "the database clients sql-quick would run always ask" jq -e '.permissions.ask | index("Bash(psql *)") and index("Bash(sqlcmd *)") and index("Bash(mysql *)")' "$ROOT/files/home/.claude/settings.json"

echo "== 2. SSH key per identity"
export HOME="$T/home"; mkdir -p "$HOME/.config/ws-agent/ops/ssh" "$HOME/.config/ws-agent/plain"
: > "$HOME/.config/ws-agent/ops/ssh/id_ed25519"
printf '#!/bin/sh\n[ "$1" = --help ] && echo "  --setting-sources <s>"\nexit 0\n' > "$T/claude"; chmod 755 "$T/claude"
L="$ROOT/files/home/.local/bin/tmux-level"
out="$(PATH="$T:/usr/bin:/bin" WS_LEVELS_DIR="$T/levels" bash "$L" --command normal --agent ops 2>/dev/null)"
printf '%s\n' "$out" > "$T/cmd.out"
check "an identity with a key: git over SSH uses only that key" grep -qF "GIT_SSH_COMMAND='ssh -i $HOME/.config/ws-agent/ops/ssh/id_ed25519 -o IdentitiesOnly=yes -o IdentityAgent=none'" "$T/cmd.out"
out="$(PATH="$T:/usr/bin:/bin" WS_LEVELS_DIR="$T/levels" bash "$L" --command normal --agent plain 2>/dev/null)"
check "an identity without a key: unchanged" bash -c "[[ '$out' != *GIT_SSH_COMMAND* && '$out' == *WS_AGENT=plain* ]]"
check "a custom profile exports its key too (ws-profile.sh)" grep -q 'GIT_SSH_COMMAND=%q' "$ROOT/files/home/.local/lib/ws-profile.sh"
G="$ROOT/files/home/.claude/hooks/guard.sh"
check "in an identity tab, Claude cannot switch GIT_SSH_COMMAND" bash -c "jq -nc '{tool_name:\"Bash\",tool_input:{command:\"GIT_SSH_COMMAND=ssh git push origin x\"},cwd:\"/tmp\"}' | WS_AGENT=ops bash '$G'; [[ \$? == 2 ]]"
check "…nor SSH_AUTH_SOCK" bash -c "jq -nc '{tool_name:\"Bash\",tool_input:{command:\"export SSH_AUTH_SOCK=/tmp/a\"},cwd:\"/tmp\"}' | WS_AGENT=ops bash '$G'; [[ \$? == 2 ]]"

echo
echo "Result: $PASS ok · $FAIL failed"
(( FAIL == 0 ))
