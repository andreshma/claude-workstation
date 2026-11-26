#!/usr/bin/env bash
#
# tests/spend-gate.sh — spend hard stop (WS-AI-019) and the emergency stop marker (WS-AI-025) in ws-runtime-gate.sh:
# ws-telemetry writes the over-budget flag only with hard=1, the hook holds prompts and tools in a project over budget
# (or every project when the total is over), an override or a stale flag lets work go on, and the stop marker holds
# everything except /exit. Temporary HOME only; Claude transcripts are fixtures.
#
# Usage: bash tests/spend-gate.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

TEL="$ROOT/files/home/.local/bin/ws-telemetry"
GATE="$ROOT/files/home/.claude/hooks/ws-runtime-gate.sh"
export HOME="$T/home" WS_STATE_DIR="$T/state" WS_TELEMETRY_DIR="$T/tel" WS_TELEMETRY_CLAUDE="$T/home/.claude" \
       WS_TELEMETRY_WIN="$T/win" CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors"
mkdir -p "$HOME/.config/ws-telemetry" "$HOME/.claude/hooks" "$HOME/.claude/projects/-repos-estimate"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"type":"user","sessionId":"s1","cwd":"/repos/estimate","timestamp":"%s","message":{"content":"x"}}\n{"type":"assistant","sessionId":"s1","cwd":"/repos/estimate","timestamp":"%s","message":{"id":"e1","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":1000,"output_tokens":100000}}}\n' \
  "$now" "$now" > "$HOME/.claude/projects/-repos-estimate/s1.jsonl"
gate() { jq -nc --arg e "$1" --arg c "$2" --arg p "${3:-}" '{hook_event_name: $e, cwd: $c, session_id: "s1", prompt: $p, tool_name: "Bash"}' | "$GATE"; }
FLAG="$WS_STATE_DIR/ws-budget-over"

echo "1) the flag"
printf 'estimate=1\nother=1000\n' > "$HOME/.config/ws-telemetry/budgets.conf"
python3 "$TEL" budgets >/dev/null 2>&1
check "without hard=1 no flag is written (alerts only)" not test -e "$FLAG"
check "the table says the hard limit is off" bash -c "python3 '$TEL' budgets | grep -q 'Hard limit: off'"
printf 'estimate=1\nother=1000\nhard=1\n' > "$HOME/.config/ws-telemetry/budgets.conf"
check "hard=1 is a switch, not a project" bash -c "! python3 '$TEL' budgets --alerts | grep -q '^hard'"
python3 "$TEL" budgets >/dev/null 2>&1
check "with hard=1 the flag lists the project over budget" jq -e '.over | map(.project) == ["estimate"]' "$FLAG"
check "the flag is private (0600)" test "$(stat -c %a "$FLAG")" = 600

echo "2) the gate"
check "a tool in the project over budget is held" not gate PreToolUse /repos/estimate
check "and so is a prompt" not gate UserPromptSubmit /repos/estimate hello
check "the reason names the project and the override" bash -c "jq -nc '{hook_event_name:\"PreToolUse\",cwd:\"/repos/estimate\"}' | '$GATE' 2>&1 | grep -q 'budgets --override estimate'"
check "the hold is recorded in the audit log as held" bash -c "grep -h '\"ev\":\"held\"' '$CLAUDE_AUDIT_DIR'/*.jsonl | grep -q 'budget estimate'"
check "another project is not held" gate PreToolUse /repos/other
touch -d '3 hours ago' "$FLAG"
check "a stale flag (dashboard not updating) lets work go on" gate PreToolUse /repos/estimate
touch "$FLAG"
python3 "$TEL" budgets --override estimate 2 >/dev/null
check "an override lets work go on" gate PreToolUse /repos/estimate
check "the override is in the audit log" bash -c "grep -h '\"ev\":\"budget-override\"' '$CLAUDE_AUDIT_DIR'/*.jsonl | grep -q 'estimate for 2 h'"
printf 'estimate %s\n' "$(( $(date +%s) - 10 ))" > "$WS_STATE_DIR/ws-budget-override"
check "an expired override holds again" not gate PreToolUse /repos/estimate
check "a bad override is refused" not python3 "$TEL" budgets --override 'x;rm' 2
printf '*=1\nhard=1\n' > "$HOME/.config/ws-telemetry/budgets.conf"; python3 "$TEL" budgets >/dev/null 2>&1
check "the total over budget holds every project" not gate PreToolUse /repos/anything
printf 'other=1000\nhard=1\n' > "$HOME/.config/ws-telemetry/budgets.conf"; python3 "$TEL" budgets >/dev/null 2>&1
check "with nothing over budget the flag is removed" not test -e "$FLAG"
check "and with no flag and no marker the gate passes" gate PreToolUse /repos/estimate
echo '{not json' > "$FLAG"
check "an unreadable flag fails open" gate PreToolUse /repos/estimate
rm -f "$FLAG"

echo "3) the emergency stop marker"
printf 'ts=2026-11-25T10:00:00\nreason=test\n' > "$WS_STATE_DIR/ws-stop-all"
check "every tool is held while the marker exists" not gate PreToolUse /repos/x
check "every prompt is held" not gate UserPromptSubmit /repos/x "do it"
check "/exit still passes, so the tabs can close" gate UserPromptSubmit /repos/x "/exit"
check "the marker holds even without jq" not bash -c "printf '{}' | PATH=/nonexistent /bin/bash '$GATE'"
rm -f "$WS_STATE_DIR/ws-stop-all"
command -v shellcheck >/dev/null && check "shellcheck ws-runtime-gate.sh" shellcheck -S warning "$GATE"
check "ws-telemetry compiles" python3 -c "import ast,sys; ast.parse(open('$TEL').read())"

echo "5) per-session cap"
printf 'hard=1\nother=1000\nper-session=1\n' > "$HOME/.config/ws-telemetry/budgets.conf"
python3 "$TEL" budgets >/dev/null 2>&1
check "per-session=USD: a session over the cap is in the flag with its id" jq -e '.over | any(.session == "s1" and (.project | startswith("(session s1")))' "$FLAG"
check "the session over the cap is held in any project" not gate PreToolUse /repos/elsewhere
gate2() { jq -nc '{hook_event_name: "PreToolUse", cwd: "/repos/elsewhere", session_id: "s2", tool_name: "Bash"}' | "$GATE"; }
check "another session is not held by it" gate2
check "per-session is a cap, not a project row" bash -c "! jq -e '.over | any(.project == \"per-session\")' '$FLAG'"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
