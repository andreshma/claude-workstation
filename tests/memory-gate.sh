#!/usr/bin/env bash
#
# tests/memory-gate.sh — memory write gate and provenance (WS-AI-012, WS-AI-013) and the <private> convention:
# memory-gate.sh asks for every MemPalace write, stamps provenance, blocks private text and allows only approved
# facts; memory-filter.sh strips private spans from what the lifecycle hooks hand to MemPalace; ws-memory builds the
# one-tool profile, saves approved facts (checked in the tool results) and lists facts due for review. Claude and
# MemPalace are simulated; temporary HOME only.
#
# Usage: bash tests/memory-gate.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

HK="$ROOT/files/home/.claude/hooks"; BIN="$ROOT/files/home/.local/bin"
export HOME="$T/home" CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors" WS_TELEMETRY_DIR="$T/tel" \
       WS_LEVELS_DIR="$T/levels" WS_MEMORY_CACHE="$T/cache"
unset WS_MEMORY_APPROVED WS_MEMORY_GATE WS_MEMORY_PRIVATE WS_MEMORY_SOURCE CLAUDE_CONFIG_DIR CLAUDECODE
mkdir -p "$HOME/.claude/hooks" "$T/bin"
cp "$HK/audit.sh" "$HOME/.claude/hooks/"
audit_has() { grep -h "\"ev\":\"$1\"" "$CLAUDE_AUDIT_DIR"/*.jsonl 2>/dev/null | grep -q -- "$2"; }
gate() { "$HK/memory-gate.sh"; }
pre() { jq -nc --arg t "mcp__mempalace__mempalace_$1" --argjson i "$2" \
  '{hook_event_name: "PreToolUse", session_id: "s1", cwd: "/repos/api", tool_name: $t, tool_input: $i}'; }

echo "1) memory-gate.sh"
check "a read (search) passes silently" test -z "$(pre search '{"query":"x"}' | gate)"
check "another MCP tool is not its business" test -z "$(pre x '{}' | jq -c '.tool_name = "mcp__azure__deploy"' | gate)"
out="$(pre kg_add '{"subject":"user","predicate":"prefers","object":"tabs"}' | gate)"
check "a kg_add asks, even after «don't ask again»" jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$out"
check "and its provenance is stamped by the hook" jq -e '.hookSpecificOutput.updatedInput.source_file | startswith("claude-code:session=s1;project=api;ts=")' <<<"$out"
check "the rest of the input is unchanged" jq -e '.hookSpecificOutput.updatedInput | .subject == "user" and .object == "tabs"' <<<"$out"
out="$(pre kg_add '{"subject":"a","predicate":"b","object":"c","source_file":"claude-code:session=fake"}' | gate)"
check "a source the model wrote stays after the real one, it cannot replace it" \
  jq -e '.hookSpecificOutput.updatedInput.source_file | test("^claude-code:session=s1;.* [|] claude-code:session=fake$")' <<<"$out"
out="$(pre add_drawer '{"wing":"w","room":"r","content":"x","added_by":"admin"}' | gate)"
check "add_drawer gets added_by from the hook" jq -e '.hookSpecificOutput.updatedInput.added_by | startswith("claude-code:session=s1")' <<<"$out"
check "diary_write, mine, sync and hook_settings ask too" bash -c "for t in diary_write mine sync hook_settings checkpoint; do
  jq -nc --arg t mcp__mempalace__mempalace_\$t '{hook_event_name:\"PreToolUse\",tool_name:\$t,tool_input:{}}' | '$HK/memory-gate.sh' | jq -e '.hookSpecificOutput.permissionDecision == \"ask\"' >/dev/null || exit 1; done"
check "the write is in the audit log with the input hash, not the content" \
  bash -c "grep -h '\"ev\":\"memory-write\"' '$CLAUDE_AUDIT_DIR'/*.jsonl | head -1 | jq -e '(.input_sha | length == 64) and (tostring | contains(\"tabs\") | not)'"
check "private text in a write is blocked" not bash -c "pre() { :; }; jq -nc '{hook_event_name:\"PreToolUse\",tool_name:\"mcp__mempalace__mempalace_add_drawer\",tool_input:{content:\"ok <private>pin 1234</private>\"}}' | '$HK/memory-gate.sh'"
check "and recorded as blocked" audit_has blocked 'memory write with <private> content'
check "a closing tag alone is caught too" not bash -c "jq -nc '{hook_event_name:\"PreToolUse\",tool_name:\"mcp__mempalace__mempalace_diary_write\",tool_input:{entry:\"x </PRIVATE>\"}}' | '$HK/memory-gate.sh'"
k="$(printf 'kg_add\x1fuser\x1fprefers\x1ftabs' | sha256sum | cut -c1-64)"
out="$(pre kg_add '{"subject":"user","predicate":"prefers","object":"tabs"}' | WS_MEMORY_APPROVED="x,$k" WS_MEMORY_SOURCE=ws-learn gate)"
check "an approved fact is allowed" jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<<"$out"
check "with the source of the approved path" jq -e '.hookSpecificOutput.updatedInput.source_file | startswith("ws-learn:session=s1")' <<<"$out"
out="$(pre kg_add '{"subject":"user","predicate":"prefers","object":"spaces"}' | WS_MEMORY_APPROVED="$k" gate)"
check "a different fact in the same run still asks" jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$out"
check "WS_MEMORY_GATE=warn does not ask but is audited" bash -c "[[ -z \"\$(jq -nc '{hook_event_name:\"PreToolUse\",tool_name:\"mcp__mempalace__mempalace_kg_add\",tool_input:{}}' | WS_MEMORY_GATE=warn '$HK/memory-gate.sh')\" ]]"
check "(the warn decision is in the audit log)" audit_has memory-write '^.*warn kg_add'
check "a memory write it cannot read is blocked (fails closed)" not bash -c "printf '%s' '{\"tool_name\":\"mcp__mempalace__mempalace_kg_add\",' | '$HK/memory-gate.sh'"
check "a non-memory input it cannot read passes" bash -c "printf '%s' 'not json' | '$HK/memory-gate.sh'"
out="$(jq -nc '{hook_event_name:"UserPromptSubmit",prompt:"use <private>my salary</private> for the plan"}' | gate)"
check "a prompt with <private> gets a note for Claude" jq -e '.hookSpecificOutput.additionalContext | test("do not store it")' <<<"$out"
check "a prompt without it gets nothing" test -z "$(jq -nc '{hook_event_name:"UserPromptSubmit",prompt:"hello"}' | gate)"

echo "2) memory-filter.sh"
printf '#!/bin/bash\ncat > "%s/got.json"\necho downstream-ran\n' "$T" > "$T/bin/sink"; chmod +x "$T/bin/sink"
tp="$T/proj/abc-123.jsonl"; mkdir -p "$T/proj"
printf '%s\n' '{"type":"user","message":{"content":"plan with <private>salary 90k</private> please"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}' > "$tp"
filt() { "$HK/memory-filter.sh" "$T/bin/sink" arg1; }
check "the command runs and its output comes back" bash -c "jq -nc --arg t '$tp' '{transcript_path:\$t,session_id:\"s1\"}' | '$HK/memory-filter.sh' '$T/bin/sink' | grep -qx downstream-ran"
copy="$(jq -r .transcript_path "$T/got.json")"
check "MemPalace gets a redacted copy, not the original" bash -c "[[ '$copy' != '$tp' && -f '$copy' ]]"
check "with the same file name (the session id)" test "$(basename "$copy")" = abc-123.jsonl
check "the copy has [private] and not the text" bash -c "grep -q '\[private\]' '$copy' && ! grep -q 'salary' '$copy'"
check "the original transcript is untouched" grep -q 'salary 90k' "$tp"
check "the copy is private" test "$(stat -c %a "$(dirname "$copy")")" = 700
check "the redaction is recorded" audit_has memory-redact 'transcript=1'
printf '%s\n' '{"type":"user","message":{"content":"nothing private"}}' > "$T/proj/clean.jsonl"
jq -nc --arg t "$T/proj/clean.jsonl" '{transcript_path: $t}' | filt >/dev/null
check "without a private tag the input goes through unchanged" test "$(jq -r .transcript_path "$T/got.json")" = "$T/proj/clean.jsonl"
jq -nc '{prompt: "a <private>secret\nline</private> b <private>open"}' | filt >/dev/null
check "private spans in .prompt are replaced, an unclosed one to the end" test "$(jq -r .prompt "$T/got.json")" = "a [private] b [private]"
rm -f "$T/got.json"
jq -nc --arg t "$tp" '{transcript_path: $t}' | WS_MEMORY_PRIVATE=skip "$HK/memory-filter.sh" "$T/bin/sink" >/dev/null
check "WS_MEMORY_PRIVATE=skip does not send that session at all" not test -e "$T/got.json"
check "and records why" audit_has memory-skip 'WS_MEMORY_PRIVATE=skip'
mkdir -p "$T/nopy"; for c in jq cat grep basename mktemp chmod mkdir find dirname; do ln -sf "$(command -v "$c")" "$T/nopy/$c"; done
jq -nc --arg t "$tp" '{transcript_path: $t}' | PATH="$T/nopy" /bin/bash "$HK/memory-filter.sh" "$T/bin/sink" >/dev/null
check "if the redaction fails, nothing is sent (fails closed for privacy) and the hook still exits 0" \
  bash -c "[[ ! -e '$T/got.json' ]] && jq -nc --arg t '$tp' '{transcript_path:\$t}' | PATH='$T/nopy' /bin/bash '$HK/memory-filter.sh' '$T/bin/sink'"

echo "3) ws-memory"
mkdir -p "$HOME/.claude"
jq -n '{permissions: {ask: ["mcp__mempalace__*add*", "mcp__mempalace__*delete*", "Bash(terraform apply*)"], deny: ["Read(~/.ssh/**)"]},
        hooks: {PreToolUse: [{matcher: "mcp__.*mempalace.*", hooks: [{type: "command", command: "~/.claude/hooks/memory-gate.sh"}]}]}}' \
  > "$HOME/.claude/settings.json"
prof="$(python3 "$BIN/ws-memory" profile kg_add)"
check "the profile drops only the ask rules that match kg_add" jq -e '.permissions.ask == ["mcp__mempalace__*delete*", "Bash(terraform apply*)"]' "$prof"
check "allows kg_add and keeps deny and the hooks" jq -e '(.permissions.allow | index("mcp__mempalace__mempalace_kg_add")) and (.permissions.deny | length == 1) and .hooks.PreToolUse' "$prof"
check "is private (0600)" test "$(stat -c %a "$prof")" = 600
check "only kg_add and kg_invalidate have an approved path" not python3 "$BIN/ws-memory" profile add_drawer
cat > "$T/bin/claude" <<'EOF'
#!/bin/bash
[[ "$1" == --help ]] && { echo "  --setting-sources <sources>"; exit 0; }
printf '%s\n' "$*" > "$FAKE/args"; printf '%s|%s\n' "${WS_MEMORY_APPROVED:-}" "${WS_MEMORY_SOURCE:-}" > "$FAKE/env"
tool="$(sed -n 's/.*--allowedTools \([^ ]*\).*/\1/p' "$FAKE/args")"
jq -c --arg t "$tool" --arg drop "${FAKE_DROP:-}" 'to_entries[] | select($drop == "" or .key == 0)
  | {type: "assistant", message: {content: [{type: "tool_use", id: "t\(.key)", name: $t, input: .value}]}},
    {type: "user", message: {content: [{type: "tool_result", tool_use_id: "t\(.key)", is_error: false}]}}'
EOF
chmod +x "$T/bin/claude"
facts='[{"subject":"user","predicate":"prefers","object":"tabs","evidence":"said so"},{"subject":"user","predicate":"uses","object":"WSL"},{"subject":"x","predicate":"y","object":"<private>z</private>"}]'
out="$(FAKE="$T" PATH="$T/bin:$PATH" python3 "$BIN/ws-memory" save-facts <<<"$facts")"; rc=$?
check "save-facts saves the facts and checks them in the tool results" bash -c "[[ $rc == 0 ]] && grep -q 'Saved 2 of 2' <<<'$out'"
check "a private fact is never sent" not grep -q private "$T/args"
check "the headless run loads only project/local sources plus the one-tool profile" grep -q -- '--setting-sources project,local --settings .*memory-kg_add.json --allowedTools mcp__mempalace__mempalace_kg_add' "$T/args"
check "the approved keys are the ones the gate computes, source ws-learn" bash -c "IFS='|' read -r keys src < '$T/env'; [[ \$src == ws-learn ]] &&
  jq -nc '{hook_event_name:\"PreToolUse\",tool_name:\"mcp__mempalace__mempalace_kg_add\",tool_input:{subject:\"user\",predicate:\"uses\",object:\"WSL\"}}' \
  | WS_MEMORY_APPROVED=\$keys '$HK/memory-gate.sh' | jq -e '.hookSpecificOutput.permissionDecision == \"allow\"'"
out="$(FAKE="$T" FAKE_DROP=1 PATH="$T/bin:$PATH" python3 "$BIN/ws-memory" save-facts <<<"$facts")"; rc=$?
check "a fact without a successful tool result is reported and the exit code says so" bash -c "[[ $rc == 1 ]] && grep -q 'Saved 1 of 2' <<<'$out' && grep -q 'not saved: user · uses · WSL' <<<'$out'"
check "inside a Claude session (CLAUDECODE) the approved path refuses" not env CLAUDECODE=1 FAKE="$T" PATH="$T/bin:$PATH" python3 "$BIN/ws-memory" save-facts <<<"$facts"
check "saves are logged with their keys" bash -c "grep -h '\"type\": \"facts-saved\"' '$WS_TELEMETRY_DIR'/learning/*.jsonl | head -1 | jq -e '.data.keys | length == 2'"
mkdir -p "$WS_TELEMETRY_DIR/learning"
printf '%s\n' '{"ts": "2026-01-02T10:00:00", "type": "facts", "data": [{"subject": "user", "predicate": "works_on", "object": "old project", "evidence": "e"}]}' \
  > "$WS_TELEMETRY_DIR/learning/2026-01-02.jsonl"
check "review --list shows facts older than 90 days" bash -c "python3 '$BIN/ws-memory' review --list | grep -q 'works_on · old project'"
check "and not the recent ones" bash -c "! python3 '$BIN/ws-memory' review --list | grep -q 'tabs'"
check "review --count" test "$(python3 "$BIN/ws-memory" review --count)" = 1
printf '%s\n' "{\"ts\": \"$(date +%FT%T)\", \"type\": \"kept\", \"data\": {\"facts\": [{\"subject\": \"user\", \"predicate\": \"works_on\", \"object\": \"old project\"}]}}" \
  >> "$WS_TELEMETRY_DIR/learning/2026-01-02.jsonl"
check "a fact kept today is not due again" test "$(python3 "$BIN/ws-memory" review --count)" = 0
check "ws-memory log lists the memory events" bash -c "python3 '$BIN/ws-memory' log | grep -q 'memory-write'"
if command -v shellcheck >/dev/null; then
  check "shellcheck memory-gate.sh and memory-filter.sh" shellcheck -S warning "$HK/memory-gate.sh" "$HK/memory-filter.sh"
fi
check "ws-memory compiles" python3 -c "import ast; ast.parse(open('$BIN/ws-memory').read())"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
