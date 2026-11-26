#!/usr/bin/env bash
#
# tests/supply-chain.sh — MCP lock and pinned npm packages (WS-AI-009), in temporary HOMEs:
# the lock agrees with mcp-servers.json and the committed package-lock.json files, nothing runs through npx or a
# moving tag, ws-pinned installs from the lock and notices a changed tree, local executables are pinned on first use,
# install.sh skips what the lock does not vouch for and migrates the old npx registration, and ws-update reports it.
# The ws-pinned install cases need the npm registry (or a warm npm cache); without it they are skipped, not failed.
#
# Usage: bash tests/supply-chain.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0 SKIP=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
skip()  { SKIP=$((SKIP+1)); echo "  skip $1"; }
not()   { ! "$@"; }
J="$ROOT/files/mcp-servers.json" L="$ROOT/files/mcp-servers.lock.json" N="$ROOT/files/home/.local/lib/ws-npm"
PIN="$ROOT/files/home/.local/bin/ws-pinned"

echo "1) lock format"
check "mcp-servers.lock.json is valid JSON, version 1" jq -e '.version == 1 and (.servers | type == "object")' "$L"
check "every server in mcp-servers.json has a lock entry" \
  jq -en --slurpfile j "$J" --slurpfile l "$L" '[$j[0] | keys[]] - [$l[0].servers | keys[]] | length == 0'
check "every lock source is npm, local or remote" jq -e '[.servers[], .tools[] | .source] | all(. == "npm" or . == "local" or . == "remote")' "$L"
check "no server runs through npx, npm exec or a bare package name" \
  jq -e '[.[] | .command // empty | select(test("(^|/)(npx|npm|pnpm|bunx|uvx)$"))] | length == 0' "$J"
check "no argument names a moving tag (@latest, @next, @beta)" jq -e '[.[] | .args // [] | .[] | select(test("@(latest|next|beta|canary)$"))] | length == 0' "$J"
check "npm entries pin an exact version and a sha512 integrity" \
  jq -e '[.servers[], .tools[] | select(.source == "npm")] | all((.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.]+)?$")) and (.integrity | test("^sha512-[A-Za-z0-9+/]+=*$")))' "$L"
check "a prerelease pin carries its reason" jq -e '[.servers[], .tools[] | select(.source == "npm" and (.version | test("-")))] | all(.prerelease == true and (.prereleaseReason | length > 20))' "$L"
lock_agrees() {   # every npm entry equals its package-lock.json (version, integrity, single dependency)
  local n npm pkg
  while IFS=$'\t' read -r n npm pkg; do
    [[ -f "$N/$npm/package-lock.json" ]] || return 1
    [[ "$(jq -r --arg p "$pkg" '.dependencies | keys == [$p]' "$N/$npm/package.json")" == true ]] || return 1
    [[ "$(jq -r --arg p "node_modules/$pkg" '"\(.packages[$p].version) \(.packages[$p].integrity)"' "$N/$npm/package-lock.json")" \
       == "$(jq -r --arg n "$n" '(.servers + .tools)[$n] | "\(.version) \(.integrity)"' "$L")" ]] || return 1
    [[ "$(jq -r --arg p "$pkg" '.dependencies[$p]' "$N/$npm/package.json")" == "$(jq -r --arg n "$n" '(.servers + .tools)[$n].version' "$L")" ]] || return 1
  done < <(jq -r '(.servers + .tools) | to_entries[] | select(.value.source == "npm") | "\(.key)\t\(.value.npm)\t\(.value.package)"' "$L")
}
check "the lock agrees with every committed package-lock.json" lock_agrees
check "npm-server commands point at the ws-pinned prefix" \
  jq -en --slurpfile j "$J" --slurpfile l "$L" '[$l[0].servers | to_entries[] | select(.value.source == "npm") | .key as $k | $j[0][$k].command
    | startswith("@HOME@/.local/share/ws-kit/npm/")] | all'
check "chrome-devtools: --isolated --no-usage-statistics --no-performance-crux and no update checks" \
  jq -e '.["chrome-devtools"] | (.args | index("--isolated") and index("--no-usage-statistics") and index("--no-performance-crux"))
         and .env.CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS == "1"' "$J"
check "chrome-devtools is opt-in in the lock" jq -e '.servers["chrome-devtools"].optIn == true' "$L"
check "remote entries match the URLs in mcp-servers.json" \
  jq -en --slurpfile j "$J" --slurpfile l "$L" '[$l[0].servers | to_entries[] | select(.value.source == "remote") | .value.url == $j[0][.key].url] | all'
check "agent-browser policy denies eval, download and upload" \
  jq -e '.default == "allow" and (.deny | index("eval") and index("download") and index("upload"))' "$ROOT/files/home/.config/agent-browser/policy.json"
check "agent-browser kit domains are local only" \
  bash -c "! grep -vE '^[[:space:]]*(#|\$)' '$ROOT/files/home/.config/agent-browser/allowed-domains.txt' | grep -vxE 'localhost|127\.0\.0\.1|\*\.localhost'"

echo "2) ws-pinned (needs the npm registry or cache)"
export WS_NPM_LOCKS="$N" WS_PINNED_ROOT="$T/npm" WS_MCP_TRUST="$T/trust.tsv"
check "ws-pinned list names every pinned package" bash -c "[[ \$(bash '$PIN' list | wc -l) -eq \$(ls -d '$N'/*/ | wc -l) ]]"
check "an unknown name is refused" not bash "$PIN" install '../etc'
if command -v npm >/dev/null && bash "$PIN" install chrome-devtools-mcp >"$T/pin.log" 2>&1; then
  check "install records the tree hash" test -s "$T/npm/chrome-devtools-mcp/.ws-tree.sha256"
  check "verify passes on a fresh install" bash "$PIN" verify chrome-devtools-mcp
  check "a second install changes nothing" grep -q '^  same' <(bash "$PIN" install chrome-devtools-mcp)
  check "bin prints the executable" test -x "$(bash "$PIN" bin chrome-devtools-mcp chrome-devtools-mcp)"
  echo '// changed' >> "$T/npm/chrome-devtools-mcp/node_modules/chrome-devtools-mcp/package.json.extra"
  check "verify fails when a file under node_modules changes" not bash "$PIN" verify chrome-devtools-mcp
  cp -r "$N" "$T/locks2"; jq '.packages["node_modules/chrome-devtools-mcp"].integrity = "sha512-AAAA"' \
    "$N/chrome-devtools-mcp/package-lock.json" > "$T/locks2/chrome-devtools-mcp/package-lock.json"
  check "a lock with a wrong integrity is refused by npm ci and the old tree stays" \
    bash -c "! WS_NPM_LOCKS='$T/locks2' bash '$PIN' install chrome-devtools-mcp && test -d '$T/npm/chrome-devtools-mcp/node_modules'"
else skip "npm registry unreachable: $(tail -1 "$T/pin.log" 2>/dev/null)"; fi
printf 'v1' > "$T/exe"
check "a local executable not pinned yet exits 3" bash -c "bash '$PIN' local-check m '$T/exe'; [[ \$? -eq 3 ]]"
check "local-pin records it" bash "$PIN" local-pin m "$T/exe"
check "the same file verifies" bash "$PIN" local-check m "$T/exe"
printf 'v2' > "$T/exe"
check "a changed file fails" not bash "$PIN" local-check m "$T/exe"

echo "3) install.sh: the lock decides what is registered"
K="$T/kit"; mkdir -p "$K"; cp -a "$ROOT"/{lib.sh,migrate.sh,renames.tsv,install.sh,manifest.txt,secrets-allow.txt,files} "$K/"
for p in .local/bin/ws-pinned .local/lib/ws-npm/chrome-devtools-mcp/; do grep -qxF "$p" "$K/manifest.txt" || echo "$p" >> "$K/manifest.txt"; done
# Only small servers in this copy: a local one (a temp file), the npm chrome-devtools (not opt-in here), a remote one.
LOC="$T/local-mcp"; printf '#!/bin/sh\n' > "$LOC"; chmod 755 "$LOC"
jq --arg c "$LOC" '{loc: {type: "stdio", command: $c, args: []}, "chrome-devtools": .["chrome-devtools"], "microsoft-learn": .["microsoft-learn"],
    rogue: {type: "http", url: "https://example.invalid/mcp"}}' "$J" > "$K/files/mcp-servers.json"
jq '.servers = {loc: {source: "local", trust: "first-use"}, "chrome-devtools": (.servers["chrome-devtools"] | del(.optIn)),
    "microsoft-learn": .servers["microsoft-learn"]}' "$L" > "$K/files/mcp-servers.lock.json"
FB="$T/fakebin"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 0\n' > "$FB/reg.exe"
cat > "$FB/claude" <<'EOF'
#!/usr/bin/env bash
f="$HOME/.claude.json"; [[ -f "$f" ]] || echo '{}' > "$f"
case "$1 $2" in
  "mcp get") jq -e --arg n "$3" '.mcpServers[$n]' "$f" >/dev/null ;;
  "mcp add-json") jq --arg n "$3" --argjson d "$4" '.mcpServers[$n] = $d' "$f" > "$f.t" && mv "$f.t" "$f" ;;
  "mcp remove") jq --arg n "$3" 'del(.mcpServers[$n])' "$f" > "$f.t" && mv "$f.t" "$f" ;;
esac
EOF
chmod 755 "$FB"/*
H="$T/home"; mkdir -p "$H"
inst() { HOME="$H" PATH="$FB:$PATH" WS_PINNED_ROOT="$H/.local/share/ws-kit/npm" WS_MCP_TRUST="$H/.local/share/ws-kit/mcp-trust.tsv" \
         bash "$K/install.sh" --no-plugins --no-git-hooks --win-user tester "$@" 2>&1; }
inst > "$T/i1.log"
reg() { jq -e --arg n "$1" '.mcpServers[$n]' "$H/.claude.json" >/dev/null 2>&1; }
check "a server missing from the lock is not registered" not reg rogue
check "  and the install says why" grep -q 'rogue is not in mcp-servers.lock.json' "$T/i1.log"
check "the local server is registered and pinned on first use" bash -c "jq -e '.mcpServers.loc' '$H/.claude.json' && grep -q '^loc' '$H/.local/share/ws-kit/mcp-trust.tsv'"
check "the remote server in the lock is registered" reg microsoft-learn
if grep -q 'new     chrome-devtools-mcp\|same    chrome-devtools-mcp' "$T/i1.log"; then
  check "the npm server is registered at the pinned path, through ws-mcp-jail (ADR-024)" \
    jq -e --arg h "$H" '.mcpServers["chrome-devtools"] | .command == ($h + "/.local/bin/ws-mcp-jail")
      and .args[(.args | index("--")) + 1] == ($h + "/.local/share/ws-kit/npm/chrome-devtools-mcp/node_modules/.bin/chrome-devtools-mcp")' \
    "$H/.claude.json"
else skip "npm server install (registry unreachable)"; fi
printf '#!/bin/sh\n# changed\n' > "$LOC"
jq 'del(.mcpServers.loc)' "$H/.claude.json" > "$H/c" && mv "$H/c" "$H/.claude.json"
inst > "$T/i2.log"
check "a changed local executable is skipped with a warning" bash -c "! jq -e '.mcpServers.loc' '$H/.claude.json' && grep -q 'changed since it was pinned' '$T/i2.log'"
inst --mcp-accept loc > "$T/i3.log"
check "--mcp-accept re-pins it after review" reg loc
jq '.mcpServers["microsoft-learn"] = {type: "stdio", command: "npx", args: ["-y", "something@1.0.0-beta.2"]}' "$H/.claude.json" > "$H/c" && mv "$H/c" "$H/.claude.json"
jq '.mcpServers.loc.args = ["--mine"]' "$H/.claude.json" > "$H/c" && mv "$H/c" "$H/.claude.json"
inst > "$T/i4.log"
check "an old npx registration is replaced by the kit's" bash -c "[[ \$(jq -r '.mcpServers[\"microsoft-learn\"].type' '$H/.claude.json') == http ]]"
check "a hand-made difference is reported, not overwritten" bash -c "grep -q 'differs loc' '$T/i4.log' && jq -e '.mcpServers.loc.args == [\"--mine\"]' '$H/.claude.json'"
inst --mcp-refresh > "$T/i5.log"
check "--mcp-refresh re-registers it" jq -e '.mcpServers.loc.args == []' "$H/.claude.json"
jq '.servers["microsoft-learn"].url = "https://elsewhere.invalid/mcp"' "$K/files/mcp-servers.lock.json" > "$T/l" && mv "$T/l" "$K/files/mcp-servers.lock.json"
jq 'del(.mcpServers["microsoft-learn"])' "$H/.claude.json" > "$H/c" && mv "$H/c" "$H/.claude.json"
inst > "$T/i6.log"
check "a remote URL that differs from the lock is not registered" not reg microsoft-learn
check "--dry-run writes no registration" bash -c "cp '$H/.claude.json' '$T/before'; HOME='$H' PATH='$FB:$PATH' bash '$K/install.sh' --dry-run --no-plugins --no-git-hooks --win-user tester --mcp-refresh >/dev/null 2>&1; cmp -s '$T/before' '$H/.claude.json'"
rm -f "$K/files/mcp-servers.lock.json"
check "without a lock file nothing is registered" bash -c "! HOME='$H' PATH='$FB:$PATH' bash '$K/install.sh' --no-plugins --no-git-hooks --win-user tester >/dev/null 2>&1"

echo "4) ws-update reports the pins"
U="$T/uhome"; mkdir -p "$U/.local/bin" "$U/.tmux/plugins/tpm/bin" "$T/ufb"
for c in claude sudo ws-sandbox-repos ws-check; do printf '#!/bin/sh\nexit 0\n' > "$T/ufb/$c"; done
printf '#!/bin/sh\nexit 0\n' > "$U/.tmux/plugins/tpm/bin/update_plugins"; chmod 755 "$T/ufb"/* "$U/.tmux/plugins/tpm/bin/update_plugins"
printf '#!/bin/sh\nexit 0\n' > "$T/ufb/npm"; chmod 755 "$T/ufb/npm"   # npm view answers nothing: no network needed
cp "$PIN" "$U/.local/bin/ws-pinned"; printf 'x' > "$T/u-exe"
jq -n --arg c "$T/u-exe" '{mcpServers: {azure: {type: "stdio", command: "npx", args: ["-y", "@azure/mcp@4.0.0-beta.7", "server", "start"]},
     mine: {type: "stdio", command: $c}}}' > "$U/.claude.json"
WS_MCP_TRUST="$U/trust.tsv" bash "$PIN" local-pin mine "$T/u-exe" >/dev/null; printf 'y' > "$T/u-exe"
out="$(HOME="$U" PATH="$T/ufb:$PATH" WS_MCP_TRUST="$U/trust.tsv" WS_PINNED_ROOT="$U/npm" bash "$ROOT/files/home/.local/bin/ws-update" 2>&1)"
check "the prerelease suffix of an npx registration is kept (4.0.0-beta.7, not 4.0.0)" grep -q '@azure/mcp@4.0.0-beta.7' <<<"$out"
check "an npx registration is flagged as unpinned" grep -q 'azure runs through npx' <<<"$out"
check "a changed local executable is flagged" grep -q 'mine changed since it was pinned' <<<"$out"

printf '\n%d ok, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
