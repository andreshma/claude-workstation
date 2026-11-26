#!/usr/bin/env bash
#
# bump-pinned.sh — moves the pin of an npm package the kit installs with ws-pinned (files/home/.local/lib/ws-npm/<name>)
# and brings every file that must agree with it into step, in one command (WS-AI-009, WS-SEC-018, WS-GOV-002):
#   1. with a version: sets it in package.json and regenerates package-lock.json (npm install --package-lock-only
#      --ignore-scripts; nothing is installed or run); without one: takes package.json and package-lock.json as they
#      are (a Dependabot branch already changed both)
#   2. files/mcp-servers.lock.json: version, integrity (from package-lock.json) and the prerelease flag
#   3. docs/governance/AI-BOM.md: the generated tables (.github/scripts/ai_bom.py --write)
#   4. runs tests/supply-chain.sh, tests/ai-bom.sh and tests/compliance.sh and says what to commit
# A prerelease needs a prereleaseReason in the lock: an existing reason is kept (review it), a missing one fails.
#
# Usage: bash .github/scripts/bump-pinned.sh <name> [version]     e.g. bump-pinned.sh azure-mcp 4.0.0-beta.9
#        bash .github/scripts/bump-pinned.sh --list
# On a Dependabot branch: git checkout <branch> && bash .github/scripts/bump-pinned.sh <name> && git commit -a … && push
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
NPMD="$ROOT/files/home/.local/lib/ws-npm"
LOCK="$ROOT/files/mcp-servers.lock.json"
die() { echo "✖ $*" >&2; exit 1; }

if [[ "${1:-}" == --list || -z "${1:-}" ]]; then
  for d in "$NPMD"/*/; do
    n="$(basename "$d")"; p="$(jq -r '.dependencies | keys[0]' "$d/package.json")"
    printf '%-22s %s@%s\n' "$n" "$p" "$(jq -r --arg p "node_modules/$p" '.packages[$p].version' "$d/package-lock.json")"
  done
  [[ -n "${1:-}" ]] || { echo; sed -n '15,17p' "$0"; }
  exit 0
fi
name="$1" ver="${2:-}"
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ && -f "$NPMD/$name/package.json" ]] || die "no pinned package $name ($0 --list)"
[[ -z "$ver" || "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "not an exact version: $ver"
command -v jq >/dev/null || die "jq is missing"
dir="$NPMD/$name"; pkg="$(jq -r '.dependencies | keys[0]' "$dir/package.json")"

if [[ -n "$ver" ]]; then
  command -v npm >/dev/null || die "npm is missing"
  jq --arg p "$pkg" --arg v "$ver" '.dependencies[$p] = $v' "$dir/package.json" > "$dir/package.json.tmp" \
    && mv "$dir/package.json.tmp" "$dir/package.json"
  # --ignore-scripts and --package-lock-only: the registry metadata is resolved, nothing is installed or run.
  (cd "$dir" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund --loglevel=error) \
    || die "npm could not resolve $pkg@$ver (package.json was changed: git checkout -- $dir to undo)"
fi

v="$(jq -r --arg p "node_modules/$pkg" '.packages[$p].version // empty' "$dir/package-lock.json")"
i="$(jq -r --arg p "node_modules/$pkg" '.packages[$p].integrity // empty' "$dir/package-lock.json")"
want="$(jq -r --arg p "$pkg" '.dependencies[$p]' "$dir/package.json")"
[[ -n "$v" && -n "$i" ]] || die "package-lock.json has no version or integrity for $pkg"
[[ "$v" == "$want" ]] || die "package.json asks for $want but package-lock.json pins $v: regenerate the lock"

# Every entry of the lock (servers and tools) installed from this folder.
keys="$(jq -r --arg n "$name" '[(.servers, .tools) | to_entries[] | select(.value.npm == $n) | .key] | join(" ")' \
         "$LOCK")"
[[ -n "$keys" ]] || die "no entry of files/mcp-servers.lock.json has npm: \"$name\""
pre=false; [[ "$v" == *-* ]] && pre=true
jq --arg n "$name" --arg v "$v" --arg i "$i" --argjson pre "$pre" '
  def bump: if .npm == $n then .version = $v | .integrity = $i
    | (if $pre then .prerelease = true else del(.prerelease, .prereleaseReason) end) else . end;
  .servers |= map_values(bump) | .tools |= map_values(bump)' "$LOCK" > "$LOCK.tmp" && mv "$LOCK.tmp" "$LOCK"
if [[ "$pre" == true ]] && ! jq -e --arg n "$name" \
     '[(.servers, .tools)[] | select(.npm == $n)] | all((.prereleaseReason // "") | length > 20)' \
     "$LOCK" >/dev/null; then
  die "$v is a prerelease: write its prereleaseReason in files/mcp-servers.lock.json, then run this again"
fi
echo "✔ $name: $pkg@$v (integrity ${i:0:20}…) in package.json, package-lock.json and mcp-servers.lock.json ($keys)"
[[ "$pre" == true ]] && echo "! prerelease: review prereleaseReason in files/mcp-servers.lock.json (kept as it was)"

python3 -I "$ROOT/.github/scripts/ai_bom.py" --write --root "$ROOT" >/dev/null || die "ai_bom.py --write failed"
echo "✔ docs/governance/AI-BOM.md regenerated"

rc=0
[[ -n "${BUMP_NO_TESTS:-}" ]] && exit 0   # tests/supply-tools.sh: only the file updates
for t in supply-chain ai-bom compliance; do
  if bash "$ROOT/tests/$t.sh" > "${TMPDIR:-/tmp}/bump-$t.log" 2>&1; then echo "✔ tests/$t.sh"
  else echo "✖ tests/$t.sh (log: ${TMPDIR:-/tmp}/bump-$t.log)"; rc=1; fi
done
if (( rc == 0 )); then
  echo
  echo "Review and commit: git -C $ROOT diff --stat"
  echo "  git commit -am 'build(deps): bump $pkg to $v'  (and a CHANGELOG line under Unreleased)"
  echo "After merging and installing: ws-pinned install $name && ws-pinned verify --online"
fi
exit "$rc"
