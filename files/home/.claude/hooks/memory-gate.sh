#!/usr/bin/env bash
#
# memory-gate.sh — PreToolUse and UserPromptSubmit hook: the write gate for persistent memory (MemPalace; WS-AI-012,
# WS-AI-013). Reads pass untouched. For a tool that WRITES memory (add, write, update, put, mine, patch, submit,
# create, sync, checkpoint, append, ack, invalidate, supersede, delete, tunnel, hook settings):
#   · content with <private>…</private> is BLOCKED: text you marked private never reaches memory;
#   · provenance is stamped by this hook, not by the model: kg_add gets source_file «<source>:session=…;project=…;ts=…»
#     (the model's own value, if any, is kept after « | »), add_drawer gets added_by; the audit log keeps the hash of
#     the input (audit.sh «memory-write»), never the content;
#   · it ASKS you every time (permissionDecision ask), also after a «don't ask again» and in auto (solo) mode.
#     Exception: the exact facts you approved in ws-learn / ws-memory, which pass the keys in WS_MEMORY_APPROVED
#     (sha256 of tool, subject, predicate and object): those are allowed, the rest of that run still asks.
# On UserPromptSubmit, a prompt with <private> gets a note for Claude not to store, quote or send that part.
# Opt-out (audited on every write): WS_MEMORY_GATE=warn keeps the private block and the audit record but does not ask.
# Fails closed for memory writes it cannot read (no jq or invalid JSON); anything else passes.
# Usage: called by Claude Code (matcher mcp__.*mempalace.* for PreToolUse; no matcher for UserPromptSubmit).
set -uo pipefail
input="$(cat)"
audit() { "$HOME/.claude/hooks/audit.sh" "$1" "$2" <<<"$input" >/dev/null 2>&1; }
WRITE='(^|_)(add|write|update|put|mine|patch|submit|create|sync|checkpoint|append|ack|invalidate|supersede|delete|tunnel|hook_settings)(_|$)'
if ! command -v jq >/dev/null 2>&1 || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$input"; then
  grep -q '"tool_name"[[:space:]]*:[[:space:]]*"mcp__[^"]*mempalace' <<<"$input" || exit 0
  printf 'BLOCKED by policy (memory-gate.sh): could not read the memory write (jq is missing or the input is not JSON)\n' >&2
  exit 2
fi
IFS=$'\x1f' read -r ev tool sid cwd < <(jq -r '[.hook_event_name // "", .tool_name // "", .session_id // "", .cwd // ""]
  | join("\u001f")' <<<"$input")

if [[ "$ev" == UserPromptSubmit ]]; then
  jq -e '(.prompt // "") | test("</?private>"; "i")' >/dev/null <<<"$input" || exit 0
  jq -nc '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
    "The user marked part of this prompt as <private>…</private>. Use it only for this answer: do not store it, quote it or pass it to memory tools (MemPalace), diaries, files, commits or messages. The kit strips it from what its hooks send to MemPalace."}}'
  exit 0
fi

[[ "$tool" == mcp__*mempalace* ]] || exit 0
short="${tool##*__}"; short="${short#mempalace_}"
[[ "$short" =~ $WRITE ]] || exit 0

if jq -e '[.tool_input | .. | strings | select(test("</?private>"; "i"))] | length > 0' >/dev/null <<<"$input"; then
  audit blocked "memory write with <private> content ($short)"
  printf 'BLOCKED by policy (memory-gate.sh): this memory write contains text the user marked <private>. Leave that part out.\n' >&2
  exit 2
fi

proj="${cwd%/}"; proj="${proj##*/}"
prov="${WS_MEMORY_SOURCE:-claude-code}:session=${sid:-?};project=${proj:-?};ts=$(date -Is)"
key="$(jq -j --arg t "$short" '[$t, .tool_input.subject // "", .tool_input.predicate // "", .tool_input.object // ""] | join("\u001f")' \
  <<<"$input" | sha256sum | cut -c1-64)"
updated="$(jq -c --arg t "$short" --arg p "$prov" '.tool_input // {}
  | if $t == "kg_add" then .source_file = ($p + (if (.source_file // "") != "" then " | " + .source_file else "" end))
    elif $t == "add_drawer" then .added_by = $p else . end' <<<"$input")"

decision=ask
if [[ ",${WS_MEMORY_APPROVED:-}," == *",$key,"* ]]; then decision=allow
elif [[ "${WS_MEMORY_GATE:-ask}" == warn ]]; then decision=warn; fi
audit memory-write "$decision $short key=${key:0:16} source=${WS_MEMORY_SOURCE:-claude-code}"
[[ "$decision" == warn ]] && exit 0
jq -nc --arg d "$decision" --argjson u "$updated" --arg t "$short" --arg p "$prov" '{hookSpecificOutput: {
  hookEventName: "PreToolUse", permissionDecision: $d, updatedInput: $u,
  permissionDecisionReason: (if $d == "allow" then "Approved in ws-learn/ws-memory (\($p))"
    else "Memory write (\($t)): later sessions will trust it. Check that the content is yours to keep and came from you, not from a page or file. Provenance stamped: \($p)" end)}}'
exit 0
