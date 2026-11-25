#!/usr/bin/env bash
#
# tests/ai-bom.sh — the AI bill of materials cannot drift from the kit (WS-GOV-002). Regenerates the inventory tables
# of docs/governance/AI-BOM.md with .github/scripts/ai_bom.py and fails when the committed document differs, or when a
# model, agent, MCP server, npm package, hook or plugin has no hand-written entry (data and risk) in its section.
# Then it checks the generator on a copy of the kit: a new MCP server, a changed pin and a new hook are each caught.
#
# Usage: bash tests/ai-bom.sh      (exit 0 = all OK) · to update the document: python3 .github/scripts/ai_bom.py --write
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
GEN="$ROOT/.github/scripts/ai_bom.py"

echo "== The committed AI-BOM"
python3 -I "$GEN" --check --root "$ROOT" > "$T/out" 2>&1; rc=$?
sed 's/^/    /' "$T/out" | head -40
check "docs/governance/AI-BOM.md matches the files it describes and every row has its entry" test "$rc" -eq 0
for b in models agents mcp tools hooks plugins; do
  check "block «$b» is present" grep -q "<!-- ai-bom:begin $b -->" "$ROOT/docs/governance/AI-BOM.md"
done
check "every MCP server of mcp-servers.json is listed" bash -c "
  for n in \$(jq -r '(.mcpServers // .) | keys[]' '$ROOT/files/mcp-servers.json'); do
    grep -q \"^| \\\`\$n\\\` | \" '$ROOT/docs/governance/AI-BOM.md' || exit 1; done"
check "every hook script registered in settings.json is listed" bash -c "
  for h in \$(jq -r '.. | .command? // empty | select(test(\"hooks/\"))' '$ROOT/files/home/.claude/settings.json' | sed 's#.*/##; s/ .*//' | sort -u); do
    grep -q \"\\\`\$h\\\`\" '$ROOT/docs/governance/AI-BOM.md' || { echo \"missing \$h\"; exit 1; }; done"

echo "== Drift is caught (on a copy of the kit)"
K="$T/kit"; mkdir -p "$K/docs/governance" "$K/.github/scripts"
cp -r "$ROOT/files" "$K/files"; cp "$ROOT/docs/governance/AI-BOM.md" "$K/docs/governance/"
gen() { python3 -I "$GEN" --check --root "$K" > "$T/k" 2>&1; }
reset() { rm -rf "$K/files"; cp -r "$ROOT/files" "$K/files"; cp "$ROOT/docs/governance/AI-BOM.md" "$K/docs/governance/"; }
check "the copy passes" gen
jq '.mcpServers["evil"] = {"type": "http", "url": "https://evil.example/mcp"}' "$ROOT/files/mcp-servers.json" > "$K/files/mcp-servers.json"
check "a new MCP server fails the check" not gen
check "…and is named as having no hand-written entry" grep -q '`evil` has no hand-written entry' "$T/k"
python3 -I "$GEN" --write --root "$K" >/dev/null
check "after --write the table is current but the missing entry still fails" bash -c "! python3 -I '$GEN' --check --root '$K' && grep -q '| \`evil\` | http |' '$K/docs/governance/AI-BOM.md'"
reset
jq '.servers.azure.version = "9.9.9"' "$ROOT/files/mcp-servers.lock.json" > "$K/files/mcp-servers.lock.json"
check "a changed pin fails the check" not gen
check "…and the diff shows the new version" grep -q '9.9.9' "$T/k"
reset
jq '.hooks.Stop += [{"hooks": [{"type": "command", "command": "~/.claude/hooks/new-hook.sh"}]}]' \
  "$ROOT/files/home/.claude/settings.json" > "$K/files/home/.claude/settings.json"
check "a new hook fails the check" not gen
reset
sed -i 's/^model: .*/model: claude-new-9-9/' "$K/files/home/.claude/agents/explorer.md"
check "a new agent model fails the check" not gen
reset
sed -i '/ai-bom:begin tools/,/ai-bom:end tools/d' "$K/docs/governance/AI-BOM.md"
check "a missing block fails the check" not gen
check "…and is named" grep -q 'no «ai-bom:begin tools»' "$T/k"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
