#!/usr/bin/env bash
#
# tests/audit-round4.sh — the ws-audit checks added in round 4, each called on its own with fake tools in a temporary
# HOME (nothing reaches the network or the owner's machine):
#   1) branch_protection (WS-AI-021): a GitHub repository whose default branch requires a pull request (ruleset or
#      classic protection) passes, one that does not warns, offline mode is reported, never a failure
#   2) secret_rotation (WS-GOV-010): a secret older than its period warns, an unknown age is said, values never read
#   3) level_network (WS-SEC-003): the base denies, the full profile's strict allow list, the Claude Code version
#   4) restore_drill (WS-GOV-013): never timed warns; ws-restore-lite --drill records a line; a passing recent drill
#      under 30 min passes, a failed one warns
#   5) mcp_filter (WS-AI-031): a server registered without the filter warns; a pending tool-definition change fails
#
# Usage: bash tests/audit-round4.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
export HOME="$T/home"; unset WS_AUDIT_OFFLINE CLAUDECODE
mkdir -p "$HOME/.claude" "$HOME/.config/ws-secret" "$T/bin" "$T/code"
export REPOS="$T/code" WS_TELEMETRY_DIR="$T/tel"
B="$T/bin"
fake() { printf '#!/bin/bash\n%s\n' "$2" > "$B/$1"; chmod 755 "$B/$1"; }
# Two repositories with GitHub origins: «good» requires a pull request (ruleset), «bad» does not.
for r in good bad; do
  git init -q "$T/code/$r" && git -C "$T/code/$r" remote add origin "https://github.com/acme/$r.git"
done
fake gh 'case "$*" in *repos/acme/good/rules/*) echo "[\"pull_request\",\"deletion\"]" ;; *repos/acme/bad/rules/*) echo "[]" ;;
  *repos/acme/bad/branches/*/protection*) exit 1 ;; *) exit 1 ;; esac'
fake ws-secret 'case "$1" in ages) printf "telegram-bot-token\t400\t365\ntelegram-pin\t-1\t365\nother\t10\t90\n" ;; *) exit 1 ;; esac'
: > "$HOME/.config/ws-secret/rotation.conf"
fake claude 'echo "2.1.332 (Claude Code)"'
fake tmux-level 'echo "{\"sandbox\":{\"network\":{\"strictAllowlist\":true,\"deniedDomains\":[\"api.github.com\"]}}}"'
cp "$ROOT/files/home/.claude/settings.json" "$HOME/.claude/settings.json"
run() {
  env PATH="$B:$PATH" "$@" python3 -I - "$ROOT/files/home/.local/bin/ws-audit" "$FN" <<'EOF'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ws_audit", sys.argv[1])
spec = importlib.util.spec_from_loader("ws_audit", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
for fn in sys.argv[2].split(","):
    getattr(m, fn)()
for r in m.R:
    print("\t".join((r["status"], r["what"], r["detail"], r["reco"])))
EOF
}

echo "== 1. branch protection"
FN=branch_protection run > "$T/out"
check "one of two default branches requires a pull request: warns with the other" grep -q $'^warn\tdefault branches that require a pull request: 1 of 2\tacme/bad:main' "$T/out"
FN=branch_protection run env WS_AUDIT_OFFLINE=1 > "$T/out"
check "offline: reported as not checked, never failed" grep -q $'^info\tbranch protection of the repositories agents push to: not checked' "$T/out"

echo "== 2. secret rotation"
FN=secret_rotation run > "$T/out"
check "a secret past its period warns, with its age" grep -q $'^warn\tsecrets within their rotation period: 2 of 3\ttelegram-bot-token (400 d > 365 d); telegram-pin (age unknown)' "$T/out"

echo "== 3. network per level"
FN=level_network run > "$T/out"
check "the base denies the gist and upload hosts" grep -q $'^ok\tsandbox denies the gist and upload hosts at every level' "$T/out"
check "the full profile has the strict allow list" grep -q $'^ok\tfull level: strict network allow list' "$T/out"
check "Claude Code is new enough for strictAllowlist" grep -q $'^ok\tClaude Code 2.1.332 honours sandbox.network.strictAllowlist' "$T/out"
fake claude 'echo "2.1.100 (Claude Code)"'
FN=level_network run > "$T/out"
check "an older Claude Code warns" grep -q $'^warn\tClaude Code 2.1.100' "$T/out"

echo "== 4. restore drill"
FN=restore_drill run > "$T/out"
check "never timed: warns" grep -q $'^warn\trestore drill: never timed' "$T/out"
bash "$ROOT/files/home/.local/bin/ws-restore-lite" --drill "$T/no-such-backup.tar.gz" >/dev/null 2>&1
check "ws-restore-lite --drill records date, seconds, result and backup (0600)" bash -c "grep -qE \$'\tfailed\t$T/no-such-backup.tar.gz\$' '$T/tel/restore-drills.tsv' && [[ \$(stat -c %a '$T/tel/restore-drills.tsv') == 600 ]]"
FN=restore_drill run > "$T/out"
check "a failed drill warns" grep -q $'^warn\tlast restore drill: failed' "$T/out"
printf '%s\t420\tok\tlatest\n' "$(date -Is)" >> "$T/tel/restore-drills.tsv"
FN=restore_drill run > "$T/out"
check "a recent drill that passed in 7 min passes" grep -q $'^ok\tlast restore drill: ok in 420 s, 0 days ago' "$T/out"

echo "== 5. MCP filter"
jq -n --arg k "$HOME/.local/bin/ws-mcp-keepalive" --arg f "$HOME/.local/bin/ws-mcp-filter" '{mcpServers: {
  a: {type: "stdio", command: $k, args: ["--name", "a", "--", $f, "--name", "a", "--", "/x/a"]},
  b: {type: "stdio", command: "/x/b", args: []}}}' > "$HOME/.claude.json"
mkdir -p "$HOME/.local/state/ws-mcp/tools-pending"
fake ws-mcp-tools 'echo "a   3 tools  first-use  2026  npm:x  ⚠ CHANGE PENDING since 2026: +1 ~0 -0 → ws-mcp-tools diff a"; exit 1'
python3 -I - "$ROOT/files/home/.local/bin/ws-audit" > "$T/out" <<EOF
import importlib.machinery, importlib.util, os, sys
os.environ["PATH"] = "$B:" + os.environ["PATH"]; os.environ["WS_AUDIT_OFFLINE"] = "1"
loader = importlib.machinery.SourceFileLoader("ws_audit", sys.argv[1])
spec = importlib.util.spec_from_loader("ws_audit", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
m.mcp_filter({}, m.jload(m.H / ".claude.json")["mcpServers"])
for r in m.R:
    print("\t".join((r["status"], r["what"], r["detail"], r["reco"])))
EOF
check "a server registered without the filter warns" grep -q $'^warn\tlocal MCP servers behind ws-mcp-filter: 1, not: 1\tb' "$T/out"
check "a pending tool-definition change fails" grep -q $'^fail\tMCP tool definitions: a change is waiting for your review' "$T/out"

echo
echo "Result: $PASS ok · $FAIL failed"
(( FAIL == 0 ))
