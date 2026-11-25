#!/usr/bin/env bash
#
# tests/audit-mcp.sh — ws-audit's MCP registration check (WS-AI-010) and managed-policy check (WS-AI-002), on a
# temporary HOME and a temporary policy folder (WS_MANAGED_DIR), calling the two checks directly:
#   registration  a user, local or approved project server that is not in files/mcp-servers.json fails, with the
#                 command that removes it; the kit's servers pass; an unapproved project server only warns
#   managed       no policy warns with the owner step; the kit's drop-in 50-ws-kit.json is read next to
#                 managed-settings.json; a drop-in without its floor, invalid JSON or a file not owned by root fails
#   mirrors       a Windows-side mirror last written in clear fails (WS-SEC-013)
#
# Usage: bash tests/audit-mcp.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
export HOME="$T/home" WS_KIT="$ROOT" WS_MANAGED_DIR="$T/etc"
mkdir -p "$HOME/.claude/hooks" "$T/etc" "$T/repo"
# run <function> — the ws-audit check alone; prints one «status<TAB>what<TAB>detail<TAB>reco» line per result.
run() {
  python3 -I - "$ROOT/files/home/.local/bin/ws-audit" "$1" <<'EOF'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ws_audit", sys.argv[1])
spec = importlib.util.spec_from_loader("ws_audit", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
getattr(m, sys.argv[2])()
for r in m.R:
    print("\t".join((r["status"], r["what"], r["detail"], r["reco"])))
EOF
}
cj() { printf '%s\n' "$1" > "$HOME/.claude.json"; }

echo "1) MCP servers against the allow list"
cj '{"mcpServers": {"azure": {}, "recall": {}, "microsoft-learn": {}}}'
check "the kit's servers pass" bash -c "$(declare -f run); ROOT='$ROOT'; run mcp_registration | grep -q '^ok.*0 outside'"
cj '{"mcpServers": {"azure": {}, "evil-tools": {"command": "/tmp/x"}}}'
run mcp_registration > "$T/out"
check "a user server outside the list fails" grep -q '^fail.*1 outside.*evil-tools (user' "$T/out"
check "  with the command that removes it" grep -q 'claude mcp remove evil-tools -s user' "$T/out"
check "  and how to add it on purpose (the kit's list and lock)" grep -q 'files/mcp-servers.json and its lock' "$T/out"
cj "{\"projects\": {\"$T/repo\": {\"mcpServers\": {\"local-one\": {}}}}}"
check "a local-scope server fails too" bash -c "$(declare -f run); ROOT='$ROOT'; run mcp_registration | grep -q '^fail.*local-one (local'"
printf '{"mcpServers": {"repo-srv": {"command": "node"}}}\n' > "$T/repo/.mcp.json"
cj "{\"projects\": {\"$T/repo\": {\"enabledMcpjsonServers\": []}}}"
run mcp_registration > "$T/out"
check "an unapproved project server only warns" bash -c "grep -q '^ok.*0 outside' '$T/out' && grep -q '^warn.*waiting for approval.*repo-srv' '$T/out'"
cj "{\"projects\": {\"$T/repo\": {\"enabledMcpjsonServers\": [\"repo-srv\"]}}}"
check "an approved project server outside the list fails" bash -c "$(declare -f run); ROOT='$ROOT'; run mcp_registration | grep -q '^fail.*repo-srv (project'"
mkdir -p "$HOME/.claude-personal"; printf '{"mcpServers": {"other": {}}}\n' > "$HOME/.claude-personal/.claude.json"; cj '{}'
check "the personal account's servers are checked too" bash -c "$(declare -f run); ROOT='$ROOT'; run mcp_registration | grep -q '^fail.*other (user'"
check "without the kit checkout it warns instead of passing" bash -c "$(declare -f run); ROOT='$ROOT'; WS_KIT='$T/none' run mcp_registration | grep -q '^warn.*not found'"

echo "2) the managed policy"
check "no policy warns with the owner step" bash -c "$(declare -f run); ROOT='$ROOT'; run managed_settings | grep -q '^warn.*install.sh --managed'"
mkdir -p "$T/etc/managed-settings.d" "$T/etc/hooks"
cp "$ROOT/files/etc/claude-code/managed-settings.json" "$T/etc/managed-settings.d/50-ws-kit.json"
cp "$ROOT/files/home/.claude/hooks/guard.sh" "$T/etc/hooks/guard.sh"; cp "$ROOT/files/home/.claude/hooks/guard.sh" "$HOME/.claude/hooks/"
sed -i "s#/etc/claude-code/hooks/guard.sh#$T/etc/hooks/guard.sh#" "$T/etc/managed-settings.d/50-ws-kit.json"
run managed_settings > "$T/out"
check "the kit's drop-in in managed-settings.d is read" grep -q 'managed policy file 50-ws-kit.json' "$T/out"
check "  its floor is recognised (bypass off, guard failing closed)" grep -q '^ok.*keeps its floor' "$T/out"
check "  a file not owned by root fails (the agent or you could change it)" grep -q '^fail.*50-ws-kit.json.*not root-owned' "$T/out"
check "  the managed guard.sh is compared with the kit's" grep -q '^ok.*managed guard.sh matches' "$T/out"
echo '{}' > "$T/etc/managed-settings.json"
check "managed-settings.json is read as well" bash -c "$(declare -f run); ROOT='$ROOT'; run managed_settings | grep -q 'managed policy file managed-settings.json'"
jq 'del(.permissions.disableBypassPermissionsMode)' "$T/etc/managed-settings.d/50-ws-kit.json" > "$T/x" && cat "$T/x" > "$T/etc/managed-settings.d/50-ws-kit.json"
check "a drop-in without its floor fails" bash -c "$(declare -f run); ROOT='$ROOT'; run managed_settings | grep -q '^fail.*keeps its floor'"
echo '{not json' > "$T/etc/managed-settings.d/60-broken.json"
check "an invalid drop-in fails" bash -c "$(declare -f run); ROOT='$ROOT'; run managed_settings | grep -q '^fail.*60-broken.json.*not valid JSON'"
echo "# changed" >> "$HOME/.claude/hooks/guard.sh"
check "a stale managed guard.sh warns" bash -c "$(declare -f run); ROOT='$ROOT'; run managed_settings | grep -q '^warn.*managed guard.sh'"

echo "3) the Windows-side mirrors"
mkdir -p "$HOME/.local/state"
printf '2026-01-01T00:00:00 /w/.claude-wsl-backup encrypted\n2026-01-01T00:00:00 /w/.tmux-resurrect-backup encrypted\n' \
  > "$HOME/.local/state/ws-backup-mirror.state"
check "encrypted mirrors pass" bash -c "$(declare -f run); ROOT='$ROOT'; run mirror_state | grep -q '^ok.*mirrors are encrypted'"
echo "2026-01-02T00:00:00 /w/.tmux-resurrect-backup UNENCRYPTED: no recipient" >> "$HOME/.local/state/ws-backup-mirror.state"
check "a mirror last written in clear fails" bash -c "$(declare -f run); ROOT='$ROOT'; run mirror_state | grep -q '^fail.*tmux-resurrect-backup: UNENCRYPTED'"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
