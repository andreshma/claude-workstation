#!/usr/bin/env bash
#
# tests/hooks-read-screen.sh — read-screen.sh, the PreToolUse screen of files before Claude reads them (WS-AI-022):
# a secret outside the project asks (and is audited), inside the project the read passes with a note (audited), a
# clean file, a binary, a missing file and a missing ws-redact pass silently; the hook is registered for Read.
#
# Usage: bash tests/hooks-read-screen.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }

export HOME="$T/home" CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt"
mkdir -p "$HOME/.claude/hooks" "$HOME/.local/bin" "$T/proj" "$T/elsewhere"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$ROOT/files/home/.claude/hooks/read-screen.sh" "$HOME/.claude/hooks/"
cp "$ROOT/files/home/.local/bin/ws-redact" "$HOME/.local/bin/"
chmod 755 "$HOME/.claude/hooks/"*.sh "$HOME/.local/bin/ws-redact"
H="$HOME/.claude/hooks/read-screen.sh"
tok="ghp_$(printf 'Z%.0s' {1..36})"
printf 'name=api\ntoken=%s\n' "$tok" > "$T/elsewhere/app.env"
printf 'token=%s\n' "$tok" > "$T/proj/config.txt"
printf 'nothing secret here\n' > "$T/elsewhere/notes.txt"
printf '\x00\x01\x02PNG' > "$T/elsewhere/img.bin"
ev() { jq -nc --arg f "$1" --arg c "$T/proj" '{hook_event_name: "PreToolUse", tool_name: "Read", tool_input: {file_path: $f}, cwd: $c, session_id: "s1"}'; }

out="$(ev "$T/elsewhere/app.env" | "$H")"
check "a secret outside the project asks" jq -e '.hookSpecificOutput.permissionDecision == "ask" and (.hookSpecificOutput.permissionDecisionReason | test("outside this project and 1 line"))' <<<"$out"
check "…and is audited (read-secret)" grep -rqs '"read-secret"' "$T/audit"
check "the reason never contains the secret" bash -c "! grep -q '$tok' <<<'$out'"
out="$(ev "$T/proj/config.txt" | "$H")"
check "a secret inside the project passes with a note" jq -e '(.hookSpecificOutput | has("permissionDecision") | not) and (.hookSpecificOutput.additionalContext | test("Do not repeat"))' <<<"$out"
check "…and is audited (read-secret-in-project)" grep -rqs 'read-secret-in-project' "$T/audit"
check "a clean file passes silently" test -z "$(ev "$T/elsewhere/notes.txt" | "$H")"
check "a binary passes silently" test -z "$(ev "$T/elsewhere/img.bin" | "$H")"
check "a missing file passes silently" test -z "$(ev "$T/elsewhere/none" | "$H")"
check "without ws-redact it passes (observing)" bash -c "mv '$HOME/.local/bin/ws-redact' '$T/'; out=\$(jq -nc --arg f '$T/elsewhere/app.env' '{tool_input:{file_path:\$f},cwd:\"/\"}' | '$H'); mv '$T/ws-redact' '$HOME/.local/bin/'; [[ -z \"\$out\" ]]"
check "registered for Read in settings.json, after read-convert" jq -e '[.hooks.PreToolUse[] | select(.matcher == "Read") | .hooks[].command] | index("~/.claude/hooks/read-screen.sh") == 1' "$ROOT/files/home/.claude/settings.json"
check "shellcheck clean" shellcheck -S warning "$ROOT/files/home/.claude/hooks/read-screen.sh"

echo
echo "Result: $PASS ok · $FAIL failed"
(( FAIL == 0 ))
