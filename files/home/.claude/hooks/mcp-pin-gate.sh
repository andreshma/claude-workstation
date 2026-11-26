#!/usr/bin/env bash
#
# mcp-pin-gate.sh — PreToolUse hook (mcp__.*) and SessionStart hook: MCP tool-definition pins for every server, local
# and remote (ADR-027, WS-AI-031). ws-mcp-filter already withholds a changed tool of a LOCAL server in the stdio path;
# remote (HTTP) servers talk to Claude Code directly, so for them the check is:
#   · SessionStart (argument «start»): ws-mcp-tools check-remote runs in the background (it never delays the session):
#     it lists each remote server's tools over MCP and compares them with their pins; a change is stored as pending
#   · PreToolUse: a call to a tool of a server with a pending, unapproved definition change is DENIED, with the
#     review command, until the owner runs «ws-mcp-tools approve NAME» in a terminal (Menu → Settings)
# The fast path (no pending change at all) starts no process. Fails open: without jq, or on anything it cannot read,
# it lets the call through (the filter and the always-ask rules still apply).
# Usage: called by Claude Code (PreToolUse matcher mcp__.*; SessionStart with «start»).
set -uo pipefail
P="${XDG_STATE_HOME:-$HOME/.local/state}/ws-mcp/tools-pending"
if [[ "${1:-}" == start ]]; then
  IFS= read -r -d '' _ || true
  if [[ -x "$HOME/.local/bin/ws-mcp-tools" ]]; then
    setsid timeout 120 "$HOME/.local/bin/ws-mcp-tools" check-remote </dev/null >/dev/null 2>&1 &
  fi
  exit 0
fi
compgen -G "$P/*.json" >/dev/null || { IFS= read -r -d '' _ || true; exit 0; }
input="$(cat)"
command -v jq >/dev/null || exit 0
tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
[[ "$tool" =~ ^mcp__([A-Za-z0-9_.-]+)__(.+)$ ]] || exit 0
srv="${BASH_REMATCH[1],,}" name="${BASH_REMATCH[2]}"
f="$P/$srv.json"; [[ -f "$f" ]] || exit 0
pins="$HOME/.local/share/ws-kit/mcp-tools.lock.json"
# Pending and not yet approved: the pending digest differs from the pinned one.
pd="$(jq -r '.digest // empty' "$f" 2>/dev/null)"; [[ -n "$pd" ]] || exit 0
[[ "$(jq -r --arg s "$srv" '.servers[$s].digest // empty' "$pins" 2>/dev/null)" == "$pd" ]] && exit 0
# Only the tools that are new or changed are held; a removed tool cannot be called anyway.
jq -e --arg t "$name" '(.diff.added + .diff.changed) | index($t)' "$f" >/dev/null 2>&1 || exit 0
"$HOME/.claude/hooks/audit.sh" blocked "mcp tool definition changed: $srv/$name" <<<"$input" >/dev/null 2>&1
jq -nc --arg s "$srv" --arg t "$name" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("BLOCKED by mcp-pin-gate: the definition of " + $s + "/" + $t + " changed since it was pinned and the owner has not approved it (a rug-pull check). Do not use this tool; tell the user to review it with «ws-mcp-tools diff " + $s + "» and approve it with «ws-mcp-tools approve " + $s + "» in a terminal.")}}'
exit 0
