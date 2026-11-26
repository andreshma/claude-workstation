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
# The tab's profile comes first (ADR-021, WS_MEMORY or the profile of CLAUDE_CONFIG_DIR): memory=off BLOCKS every
# MemPalace tool, reads too (the palace holds the other clients' work); memory=wing:W forces wing W on the tools that
# take one (search, list_drawers, list_rooms, diary_read, diary_write, add_drawer) and blocks the rest, which cannot
# be limited to one wing. The opt-out above never lifts either.
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

mode="${WS_MEMORY:-on}"
if [[ -r "$HOME/.local/lib/ws-profile.sh" ]]; then
  # shellcheck source=../../.local/lib/ws-profile.sh
  . "$HOME/.local/lib/ws-profile.sh" && wsp_memory && mode="$REPLY"
elif [[ "$mode" != on && "$mode" != wing:* ]]; then mode=off; fi
case "$mode" in
  on) ;;
  wing:*)
    wing="${mode#wing:}"
    if [[ ! "$short" =~ ^(search|list_drawers|list_rooms|diary_read|diary_write|add_drawer)$ ]]; then
      audit blocked "memory scoped to wing $wing: $short cannot be limited to it"
      printf 'BLOCKED by policy (memory-gate.sh): this tab'"'"'s profile limits MemPalace to the wing «%s», and %s cannot be limited to one wing.\n' "$wing" "$short" >&2
      exit 2
    fi
    input="$(jq -c --arg w "$wing" '.tool_input = ((.tool_input // {}) | .wing = $w)' <<<"$input")" || exit 2
    if [[ ! "$short" =~ $WRITE ]]; then
      jq -nc --argjson u "$(jq -c '.tool_input' <<<"$input")" --arg w "$wing" '{hookSpecificOutput: {hookEventName: "PreToolUse",
        permissionDecision: "allow", updatedInput: $u, permissionDecisionReason: "MemPalace read limited to the wing \($w) (this tab'"'"'s profile)"}}'
      exit 0
    fi ;;
  *)
    audit blocked "memory off (profile ${WS_PROFILE:-?}): $short"
    printf 'BLOCKED by policy (memory-gate.sh): this tab runs with the profile «%s», whose memory is off: MemPalace is not used here (neither read nor written), so other clients'"'"' work stays out of this organisation. Work from the conversation and the repository.\n' "${WS_PROFILE:-?}" >&2
    exit 2 ;;
esac
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
