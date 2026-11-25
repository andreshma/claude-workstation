#!/usr/bin/env bash
#
# tests/audit-prompts.sh — approval fatigue metrics (WS-AI-006): «ws-telemetry prompts» counts the permission prompts
# you answered, how fast, and the permanent allow rules in settings.local.json files, and --alerts reports a high
# approval rate, rubber-stamping (answers under 2 s) and new or broad permanent rules. OpenTelemetry rows are fixtures.
#
# Usage: bash tests/audit-prompts.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

TEL="$ROOT/files/home/.local/bin/ws-telemetry"
export HOME="$T/home" WS_TELEMETRY_DIR="$T/tel" WS_TELEMETRY_CLAUDE="$T/home/.claude" WS_TELEMETRY_WIN="$T/win" WS_STATE_DIR="$T/state"
mkdir -p "$HOME/.claude" "$WS_TELEMETRY_DIR/otel" "$T/proj/.claude"
o="$WS_TELEMETRY_DIR/otel/$(date +%F).jsonl"
for i in $(seq 1 35); do
  printf '{"ts":"%s","signal":"event","name":"tool_decision","source":"user_temporary","decision":"accept","tool_name":"Bash"}\n' \
    "$(date -u -d "-$i minutes" +%FT%TZ)"
done > "$o"
printf '{"ts":"%s","signal":"event","name":"tool_decision","source":"user_permanent","decision":"accept","tool_name":"Edit"}\n' "$(date -u +%FT%TZ)" >> "$o"
printf '{"ts":"%s","signal":"event","name":"tool_decision","source":"user_reject","decision":"reject","tool_name":"Bash"}\n' "$(date -u +%FT%TZ)" >> "$o"
printf '{"ts":"%s","signal":"event","name":"tool_decision","source":"config","decision":"accept","tool_name":"Read"}\n' "$(date -u +%FT%TZ)" >> "$o"
for i in $(seq 1 20); do printf '{"ts":"%s","signal":"span","name":"claude_code.tool.blocked_on_user","dur_ms":%d}\n' "$(date -u +%FT%TZ)" $(( i <= 15 ? 800 : 9000 )); done >> "$o"
echo '{"permissions":{"allow":["Bash(npm test:*)","Bash(curl:*)"]}}' > "$HOME/.claude/settings.local.json"
echo '{"permissions":{"allow":["WebFetch"]}}' > "$T/proj/.claude/settings.local.json"
jq -n --arg p "$T/proj" '{projects: {($p): {}}}' > "$HOME/.claude.json"

j="$(python3 "$TEL" prompts --json)"
check "counts only the prompts you answered (not config decisions)" jq -e '.answered == 37 and .approvals == 36 and .rejections == 1' <<<"$j"
check "counts «don't ask again» grants" jq -e '.permanent_grants == 1' <<<"$j"
check "approvals in the last hour" jq -e '.last_hour == 36' <<<"$j"
check "share of prompts answered in under 2 s" jq -e '.wait_n == 20 and .quick_pct == 75' <<<"$j"
check "finds permanent rules in the user and project settings.local.json" jq -e '.rules == 3' <<<"$j"
check "flags the broad ones (curl, WebFetch), not npm test" jq -e '[.broad_rules[].rule] | sort == ["Bash(curl:*)", "WebFetch"]' <<<"$j"
a="$(python3 "$TEL" prompts --alerts)"
check "--alerts: approval rate over the threshold" grep -qP '^rate\t36\t' <<<"$a"
check "--alerts: rubber-stamping" grep -qP '^quick\t75\t' <<<"$a"
check "--alerts: new permanent rules in 24 h" grep -qP '^permanent\t3\t' <<<"$a"
check "--alerts: broad rules" grep -qP '^broad\t2\t' <<<"$a"
check "--rate raises the threshold" not grep -q '^rate' <<<"$(python3 "$TEL" prompts --alerts --rate 100)"
check "a rule seen before is not new the next day" bash -c "python3 - '$WS_TELEMETRY_DIR/cache/allow-rules.json' <<'EOF'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); json.dump({k: '2026-01-01T00:00:00' for k in d}, open(f, 'w'))
EOF
! python3 '$TEL' prompts --alerts | grep -q '^permanent'"
check "the terminal summary prints" bash -c "python3 '$TEL' prompts | grep -q 'Permission prompts in 7 days: 37 answered'"
check "without OpenTelemetry data it still reports the rules" bash -c "WS_TELEMETRY_DIR='$T/empty' python3 '$TEL' prompts --json | jq -e '.answered == 0 and .rules == 3'"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
