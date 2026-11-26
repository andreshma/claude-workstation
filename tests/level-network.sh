#!/usr/bin/env bash
#
# tests/level-network.sh — network egress per protection level (ADR-028, WS-SEC-003) and the level marker the MCP
# filter reads (WS_LEVEL), from the generated profiles of tmux-level in a temporary HOME (no tmux, no Claude):
#   1) base settings.json: the gist and upload hosts are denied at every level, the allow list has no broad TLD
#   2) full: strictAllowlist, the GitHub API and github.com denied on top of the base denies, nothing excluded
#   3) solo, solo-net: strictAllowlist and the GitHub API denied; solo-unsandboxed: no sandbox, so no network rules
#   4) normal adds nothing to the network; a missing or broken network.json leaves the base as it is
#   5) every start command carries WS_LEVEL; the default level of new tabs (full or normal, never bare), refused
#      inside Claude, audited; --new-tab-command follows it
#
# Usage: bash tests/level-network.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }

export HOME="$T/home"; unset CLAUDECODE WS_PROFILE WS_LEVEL
export CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt" WS_WINHOME="$T/nowin"
mkdir -p "$HOME/.claude/hooks" "$HOME/.config/claude-levels" "$HOME/.config/claude-solo" "$T/bin"
cp "$ROOT/files/home/.claude/settings.json" "$HOME/.claude/settings.json"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"; chmod 755 "$HOME/.claude/hooks/audit.sh"
cp "$ROOT/files/home/.config/claude-levels/"*.json "$HOME/.config/claude-levels/"
cp "$ROOT/files/home/.config/claude-solo/settings.json" "$HOME/.config/claude-solo/"
printf '#!/bin/sh\n[ "$1" = --help ] && echo "  --setting-sources <s>"\nexit 0\n' > "$T/bin/claude"; chmod 755 "$T/bin/claude"
export PATH="$T/bin:/usr/bin:/bin"
L="$ROOT/files/home/.local/bin/tmux-level"
net() { bash "$L" --profile "$1" 2>/dev/null | jq -c '.sandbox.network // {}'; }

echo "== 1. base"
check "the base denies gist.github.com, gist.githubusercontent.com and uploads.github.com" \
  jq -e '.sandbox.network.deniedDomains | index("gist.github.com") and index("gist.githubusercontent.com") and index("uploads.github.com")' "$ROOT/files/home/.claude/settings.json"
check "the base has no broad TLD wildcard" jq -e '.sandbox.network.allowedDomains | all(test("^[*][.]?(com|net|org|io)$") | not)' "$ROOT/files/home/.claude/settings.json"

echo "== 2. full"
f="$(net full)"
check "full: strictAllowlist" jq -e '.strictAllowlist == true' <<<"$f"
check "full: github.com and the GitHub API denied, base denies kept" jq -e '.deniedDomains | index("github.com") and index("api.github.com") and index("gist.github.com")' <<<"$f"
check "full: no excluded commands" bash -c "bash '$L' --profile full | jq -e '.sandbox | has(\"excludedCommands\") | not'"

echo "== 3. solo"
for v in solo solo-net; do
  check "$v: strictAllowlist and the GitHub API denied" jq -e '.strictAllowlist == true and (.deniedDomains | index("api.github.com"))' <<<"$(net "$v")"
done
check "solo-unsandboxed: the sandbox is off (no network rule can apply)" bash -c "bash '$L' --profile solo-unsandboxed | jq -e '.sandbox.enabled == false'"

echo "== 4. normal and a missing file"
check "normal adds no network rule (the base applies)" bash -c "bash '$L' --profile normal | jq -e '.sandbox.network == null'"
mv "$HOME/.config/claude-levels/network.json" "$T/"
check "without network.json, full keeps only the base denies" jq -e '(.strictAllowlist // false) == false and (.deniedDomains | index("api.github.com")) == null and (.deniedDomains | index("gist.github.com"))' <<<"$(net full)"
echo '{broken' > "$HOME/.config/claude-levels/network.json"
check "a broken network.json is ignored, not half-read" jq -e '(.strictAllowlist // false) == false' <<<"$(net full)"
mv "$T/network.json" "$HOME/.config/claude-levels/network.json"

echo "== 5. WS_LEVEL and the default level"
export WS_LEVELS_DIR="$T/levels"
check "normal starts with WS_LEVEL=normal" bash -c "bash '$L' --command normal | grep -q '^WS_LEVEL=normal claude-resume --settings '"
check "full starts with WS_LEVEL=full" bash -c "bash '$L' --command full | grep -q '^WS_LEVEL=full claude-resume --setting-sources project,local'"
check "bare starts with WS_LEVEL=bare" bash -c "bash '$L' --command bare | grep -q '^WS_LEVEL=bare '"
check "solo starts with WS_LEVEL=solo" grep -q 'CMD_SOLO="WS_LEVEL=solo claude' "$ROOT/files/home/.local/bin/tmux-solo"
check "the default level is normal" test "$(bash "$L" default)" == normal
check "setting it inside Claude is refused" bash -c "CLAUDECODE=1 bash '$L' default full; [[ \$? == 2 ]]"
check "bare is never a default" bash -c "bash '$L' default bare; [[ \$? == 2 ]]"
bash "$L" default full >/dev/null
check "default full is stored (0600) and audited" bash -c "[[ \$(cat '$T/levels/default') == full && \$(stat -c %a '$T/levels/default') == 600 ]] && grep -rqs level-default '$T/audit'"
check "a new tab then starts at full" bash -c "bash '$L' --new-tab-command '$T' | grep -q '^WS_LEVEL=full '"
check "functions.sh starts new tabs with --new-tab-command and marks full tabs" bash -c "grep -q -- '--new-tab-command' '$ROOT/files/home/.config/tmux-claude/functions.sh' && grep -q '_claude_mark' '$ROOT/files/home/.config/tmux-claude/functions.sh'"
check "shellcheck tmux-level" shellcheck -S warning "$L"

echo
echo "Result: $PASS ok · $FAIL failed"
(( FAIL == 0 ))
