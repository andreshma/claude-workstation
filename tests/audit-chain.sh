#!/usr/bin/env bash
#
# tests/audit-chain.sh — tamper-evident audit log (WS-SEC-011): audit.sh chains every line to the previous one with
# sha256 and anchors the day's head on session end; ws-audit --verify-log detects an edited, deleted or reordered
# line, a deleted day file and a truncated tail. Temporary folders only.
#
# Usage: bash tests/audit-chain.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

AUDIT="$ROOT/files/home/.claude/hooks/audit.sh"
VERIFY="$ROOT/files/home/.local/bin/ws-audit"
export CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt" HOME="$T/home"
mkdir -p "$HOME"
ev() { printf '{"session_id":"s1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s"}}' "$T" "$2" | "$AUDIT" "$1"; }
day="$CLAUDE_AUDIT_DIR/$(date +%F).jsonl"
verify() { python3 "$VERIFY" --verify-log "$CLAUDE_AUDIT_DIR"; }

echo "1) the chain"
ev start a; ev tool b; ev tool c; ev end d
check "four entries are written" test "$(wc -l < "$day")" = 4
check "each entry carries prev" test "$(jq -r 'select(.prev | test("^([0-9a-f]{64}|genesis)$")) | 1' "$day" | wc -l)" = 4
check "the second prev is the sha256 of the first line" \
  test "$(sed -n 2p "$day" | jq -r .prev)" = "$(sed -n 1p "$day" | tr -d '\n' | sha256sum | cut -c1-64)"
check "the file is private (0600)" test "$(stat -c %a "$day")" = 600
check "session end appends an anchor with the head hash and the line count" \
  bash -c "read -r d h n _ < '$CLAUDE_AUDIT_ANCHORS'; [[ \$d == $(date +%F) && \$n == 4 && \$h == \$(tail -1 '$day' | tr -d '\n' | sha256sum | cut -c1-64) ]]"
check "an intact log verifies" verify
check "secrets in commands are still redacted" bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"x --token abc123\"}}' | '$AUDIT' tool; tail -1 '$day' | grep -q -- '--token \*\*\*'"
check "and the chain still verifies after more writes" verify
check "MemPalace tools keep only the hash of their input" bash -c "printf '%s' '{\"tool_name\":\"mcp__mempalace__mempalace_kg_add\",\"tool_input\":{\"subject\":\"x\"}}' | '$AUDIT' tool; tail -1 '$day' | jq -e '(.input_sha | test(\"^[0-9a-f]{64}$\")) and (tostring | contains(\"subject\") | not)'"
check "the tmux pane is recorded" bash -c "printf '{}' | TMUX_PANE=%42 '$AUDIT' tool; tail -1 '$day' | jq -e '.pane == \"%42\"'"
# WS-SEC-010: what web and MCP tools reached, inside the hashed record.
check "WebFetch keeps the URL without its query string" bash -c "printf '%s' '{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://x.test/p?sig=abc#f\"}}' | '$AUDIT' tool; tail -1 '$day' | jq -e '.url == \"https://x.test/p\"'"
check "WebSearch keeps the query (200 characters at most)" bash -c "jq -nc '{tool_name: \"WebSearch\", tool_input: {query: (\"q\" * 300)}}' | '$AUDIT' tool; tail -1 '$day' | jq -e '(.query | length) == 200'"
check "other MCP tools keep their input, redacted" bash -c "printf '%s' '{\"tool_name\":\"mcp__azure__storage\",\"tool_input\":{\"command\":\"list\",\"password\":\"hunter2\"}}' | '$AUDIT' tool; tail -1 '$day' | jq -e '(.mcp_input | contains(\"storage\") or contains(\"list\")) and (.mcp_input | contains(\"hunter2\") | not)'"
check "the new fields are covered by the chain" verify

echo "2) tampering is detected"
cp "$day" "$T/good"
sed -i '2s/"ev":"tool"/"ev":"toolx"/' "$day"
check "an edited line fails" not verify
check "and the report names the line after it" bash -c "python3 '$VERIFY' --verify-log '$CLAUDE_AUDIT_DIR' | grep -q ':3 prev does not match line 2'"
cp "$T/good" "$day"; sed -i '2d' "$day"
check "a deleted line fails" not verify
cp "$T/good" "$day"; { sed -n 1p "$T/good"; sed -n 3p "$T/good"; sed -n 2p "$T/good"; sed -n '4,$p' "$T/good"; } > "$day"
check "reordered lines fail" not verify
cp "$T/good" "$day"; head -n 3 "$T/good" > "$day"
check "a truncated tail fails against the anchor" bash -c "python3 '$VERIFY' --verify-log '$CLAUDE_AUDIT_DIR' | grep -q 'had 4 lines at session end'"
cp "$T/good" "$day"
check "restoring the original verifies again" verify
# Rewriting the whole file with a recomputed chain passes the chain but not the anchor.
python3 - "$day" <<'EOF'
import hashlib, json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
rows[0]["ev"] = "forged"; prev = "genesis"; out = []
for r in rows:
    r["prev"] = prev; line = json.dumps(r, separators=(",", ":")); out.append(line); prev = hashlib.sha256(line.encode()).hexdigest()
open(sys.argv[1], "w").write("\n".join(out) + "\n")
EOF
check "a rewritten chain is caught by the anchor" bash -c "python3 '$VERIFY' --verify-log '$CLAUDE_AUDIT_DIR' | grep -q 'changed after the session ended'"
cp "$T/good" "$day"

echo "3) across days and legacy lines"
D2="$T/audit2"; mkdir -p "$D2"; export CLAUDE_AUDIT_ANCHORS="$T/a2"
printf '{"ts":"old","ev":"tool"}\n' > "$D2/2026-01-01.jsonl"     # from before the chain (no prev)
check "legacy lines before the chain are accepted" python3 "$VERIFY" --verify-log "$D2"
printf '{}' | CLAUDE_AUDIT_DIR="$D2" CLAUDE_AUDIT_ANCHORS="$T/a2" "$AUDIT" tool
check "the first line of a new day links to the last line of the previous day file" \
  test "$(jq -r .prev "$D2/$(date +%F).jsonl")" = "$(tr -d '\n' < "$D2/2026-01-01.jsonl" | sha256sum | cut -c1-64)"
check "and verifies" python3 "$VERIFY" --verify-log "$D2"
printf '{"ts":"x","ev":"tool","prev":"genesis"}\n' > "$D2/2026-01-02.jsonl"
check "a day file whose link does not match fails" not python3 "$VERIFY" --verify-log "$D2"
rm -f "$D2/2026-01-02.jsonl"
echo "$(date +%F) deadbeef 1 x" > "$T/a3"; echo "2026-01-01 $(tr -d '\n' < "$D2/2026-01-01.jsonl" | sha256sum | cut -c1-64) 1 x" >> "$T/a3"
rm -f "$D2/$(date +%F).jsonl"
check "an anchored day file that was deleted fails" bash -c "CLAUDE_AUDIT_ANCHORS='$T/a3' python3 '$VERIFY' --verify-log '$D2' | grep -q 'is missing (deleted)'"

echo "4) retention and hygiene"
check "retention is 395 days" grep -q -- '-mtime +395 -delete' "$AUDIT"
check "audit.sh writes nothing to stdout" test -z "$(printf '{"prompt":"hi"}' | "$AUDIT" prompt)"
command -v shellcheck >/dev/null && check "shellcheck audit.sh" shellcheck -S warning "$AUDIT"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
